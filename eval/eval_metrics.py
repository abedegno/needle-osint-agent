#!/usr/bin/env python3
"""eval_metrics.py — deterministic run-evaluation metrics for osint_investigator runs.

Runs ON THE RUNNER (reads the transcripts + reaches omnigent:8000). Stdlib only.
Emits a metrics JSON (stdout + --out). See docs/superpowers/specs/2026-06-21-bl8-run-evaluator-design.md.
"""
import argparse, json, os, re, glob, subprocess, sys, urllib.request, collections

OMNIGENT = os.environ.get("OMNIGENT_URL", "http://omnigent:8000")
# CLAUDE_PROJECTS_DIR env override always wins. Otherwise PROJECTS is DERIVED (in main(), once
# --repo is known) from the actual workspace path -- never hardcoded to any one deployment's
# identity. Left unset here; main() fills it in before the first jsonl_files() call.
PROJECTS = os.environ.get("CLAUDE_PROJECTS_DIR")

def munged_workspace_dir(abs_path):
    # Claude Code's own transcript-directory naming scheme: the absolute workspace path with
    # every non-alphanumeric character replaced by '-' (e.g. a workspace checked out at
    # /data/some_project reads as -data-some-project). This mirrors how Claude Code derives
    # each session's ~/.claude/projects/<dir>, so deriving it from the real --repo path
    # (instead of a hardcoded literal) is correct for any deployment, not just one.
    return re.sub(r"[^a-zA-Z0-9]", "-", abs_path)
BANNED = ("mcp__crawl4ai__screenshot", "mcp__crawl4ai__pdf")
TOOLING_GLOB = ("omnigent/bin/", "omnigent/skills/", "omnigent/tests/", "omnigent/eval/")
WARN = []
# run_base() records an unresolvable evaluation base here; main() maps a non-empty
# list to a hard_fail -> verdict FAIL, so metrics computed against a bad base can
# never read as an authoritative PASS.
BASE_UNRESOLVED = []

def warn(msg): WARN.append(msg)

def http_json(path):
    try:
        with urllib.request.urlopen(OMNIGENT + path, timeout=20) as r:
            return json.loads(r.read().decode())
    except Exception as e:
        warn(f"http {path}: {e}"); return None

def git(repo, *args):
    try:
        return subprocess.run(["git", "-C", repo, *args], capture_output=True,
                              text=True, timeout=60).stdout
    except Exception as e:
        warn(f"git {args}: {e}"); return ""

def find_conv(run_id):
    d = http_json("/v1/sessions?limit=50") or {}
    for s in d.get("data", []):
        # NEVER self-match the evaluator's own session: its dispatch prompt (the title) contains the
        # run_id, so without this skip find_conv returns the evaluator session and coordinator metrics
        # are wrong (dispatch_count=0). Pass --conv-id for accurate coordinator metrics.
        if s.get("agent_name") == "run_evaluator":
            continue
        if run_id in (s.get("title") or ""):
            return s.get("id"), s.get("created_at"), s.get("updated_at")
    warn(f"no coordinator session matched {run_id} (pass --conv-id for coordinator metrics)")
    return None, None, None

def fetch_items(conv_id):
    # The omnigent API caps ?limit at 1000 (limit=2000 -> HTTP 422) and IGNORES ?offset,
    # so there is no pagination — one clamped page is the most we can read. 1000 covers any
    # real run (a 6-lead drain coordinator is ~290 items); warn if we actually hit the cap.
    if not conv_id: return []
    d = http_json(f"/v1/sessions/{conv_id}/items?limit=1000&order=asc") or {}
    items = [it for it in d.get("data", []) if isinstance(it, dict)]
    if len(items) >= 1000:
        warn(f"items for {conv_id} hit the 1000 cap — transcript may be truncated")
    return items

def coordinator_metrics(conv_id):
    out = {"tool_histogram": {}, "dispatch_count": 0, "errors": []}
    if not conv_id: return out, None, None
    sess = http_json(f"/v1/sessions/{conv_id}") or {}
    created, updated = sess.get("created_at"), sess.get("updated_at")
    hist = collections.Counter()
    for it in fetch_items(conv_id):
        if it.get("type") == "function_call" and it.get("name"):
            hist[it["name"]] += 1
            if it["name"] == "sys_session_send": out["dispatch_count"] += 1
        if it.get("type") == "error":
            out["errors"].append({"code": it.get("code"), "message": it.get("message")})
    out["tool_histogram"] = dict(hist)
    return out, created, updated

def jsonl_files(run_id, created, updated):
    files = []
    for f in glob.glob(os.path.join(PROJECTS, "*.jsonl")):
        try:
            mt = os.path.getmtime(f); txt = None
            in_window = created and updated and (created - 120) <= mt <= (updated + 1800)
            if not in_window:
                txt = open(f, errors="ignore").read()
                if run_id not in txt: continue
            files.append(f)
        except Exception as e:
            warn(f"stat {f}: {e}")
    return files

# AUTH failures are recognised ONLY from a tool call's error/status envelope — narrow,
# error-specific phrases that do not occur in ordinary fetched page text. (BL-23: bare
# "unauthorized" collided with California-State-Bar "Unauthorized Practice of Law" page
# boilerplate and mis-escalated a clean run to verification_integrity FAIL_CANDIDATE.)
AUTH_FAIL_PATS = ("is empty in this shell", "no api key", "has no api key",
                  "invalid api key", "401 unauthorized", "http 401", "403 forbidden",
                  "http 403", "authorization failed", "authentication failed")
SEARCH_FAIL_PATS = ("no results found", "search engines are working")

# Tool tags that denote a network/API/auth-bearing call. AUTH/SEARCH/capture signals are
# scanned ONLY for these — a `cat`/`grep` of a script, or a fetched page body, cannot flag (BL-23).
NETWORK_TOOL_HINTS = ("crawl4ai", "searxng", "web_url_read", "web_search", "curl",
                      "capture-evidence", "capture-stealth", "companies-house", "companies_house",
                      "gazette", "courtlistener", "gleif", "uspto", "wipo", "tsdr")

# ULID id-schema: collision-safe lead ids. Match ULID form (lead-01J8ZQK7W2QF3M8B4R9YT6X0AD)
# or legacy digits (lead-123). Used to parse lead citations from blobs.
ULID_RE = r"[0-7][0-9A-HJKMNP-TV-Z]{25}"
LEAD_TOKEN = re.compile(r"lead-(?:" + ULID_RE + r"|[0-9]+)")

def _lead_from_text(s):
    """Extract lead token (ULID or legacy digits) from text substring."""
    m = LEAD_TOKEN.search(s or "")
    return m.group(0) if m else None

def is_network_tool(tool):
    if not tool: return False
    t = str(tool).lower()
    return any(h in t for h in NETWORK_TOOL_HINTS)

def invoked_binary(cmd):
    # The actually-executed binary of a shell command, skipping interpreters/wrappers, so that
    # `cat omnigent/bin/capture-evidence.sh` reads as `cat` (not a network call) while
    # `omnigent/bin/capture-evidence.sh ...` reads as the network script itself.
    toks = str(cmd).split()
    i = 0
    while i < len(toks) and toks[i] in ("bash", "sh", "sudo", "env", "time", "nice"):
        i += 1
    return toks[i] if i < len(toks) else ""

def scan_output(s, tool=None):
    sig = {"command_not_found": [], "read_before_edit": 0, "input_validation_errors": 0,
           "tool_auth_failures": 0, "search_fail": 0, "capture_failures": 0}
    low = s.lower()
    # Tool-agnostic signals — any tool result can legitimately show these.
    sig["command_not_found"] = re.findall(r"([\w./-]+): command not found", s)
    if "File has not been read yet" in s: sig["read_before_edit"] += 1
    if "InputValidationError" in s: sig["input_validation_errors"] += 1
    # AUTH/SEARCH/capture are meaningful only from a network/API tool's own output, NOT from a
    # fetched page body or a read-only file inspection whose text happens to match (BL-23).
    if is_network_tool(tool):
        if any(p in low for p in AUTH_FAIL_PATS): sig["tool_auth_failures"] += 1
        if any(p in low for p in SEARCH_FAIL_PATS): sig["search_fail"] += 1
        if "capture-evidence" in low and ("error" in low or "exit code: 1" in low):
            sig["capture_failures"] += 1
    return sig

def subagent_metrics(path):
    m = {"file": os.path.basename(path), "role": "?", "turns": 0, "tool_histogram": {},
         "banned_capture_calls": 0, "capture_evidence_calls": 0, "command_not_found": [],
         "read_before_edit": 0, "input_validation_errors": 0, "tool_auth_failures": 0,
         "search_fail": 0, "capture_failures": 0, "title": "", "lead": None}
    hist = collections.Counter(); first_user = ""; tool_tag_by_id = {}
    for line in open(path, errors="ignore"):
        line = line.strip()
        if not line: continue
        try: e = json.loads(line)
        except Exception: continue
        t = e.get("type"); msg = e.get("message") or {}; content = msg.get("content")
        if t == "assistant": m["turns"] += 1
        if t == "user" and not first_user and isinstance(content, list):
            for c in content:
                if isinstance(c, dict) and c.get("type") == "text":
                    first_user = c.get("text", "")[:400]; break
        if isinstance(content, list):
            for c in content:
                if not isinstance(c, dict): continue
                if c.get("type") == "tool_use":
                    name = c.get("name", "?"); hist[name] += 1
                    if name in BANNED: m["banned_capture_calls"] += 1
                    cmd = str((c.get("input") or {}).get("command", ""))
                    if "capture-evidence.sh" in cmd: m["capture_evidence_calls"] += 1
                    # remember what this call was so its result can be scoped (BL-23): the
                    # invoked binary for a shell tool, else the MCP tool name.
                    if c.get("id"):
                        tool_tag_by_id[c["id"]] = invoked_binary(cmd) if cmd else name
                if c.get("type") == "tool_result":
                    rc = c.get("content"); s = rc if isinstance(rc, str) else json.dumps(rc)
                    sig = scan_output(s, tool=tool_tag_by_id.get(c.get("tool_use_id")))
                    m["command_not_found"] += sig["command_not_found"]
                    for k in ("read_before_edit", "input_validation_errors",
                              "tool_auth_failures", "search_fail", "capture_failures"):
                        m[k] += sig[k]
    blob = first_user
    m["role"] = ("analyst" if ("synthesize" in blob or "analyst" in blob)
                 else "verifier" if "verif" in blob
                 else "researcher" if ("research" in blob or "explore" in blob) else "?")
    m["title"] = ""  # local jsonl has no omnigent title
    m["lead"] = _lead_from_text(blob)
    m["tool_histogram"] = dict(hist)
    m["command_not_found"] = sorted(set(m["command_not_found"]))
    return m

def api_subagent_metrics(conv_id, role, title):
    # Same shape as subagent_metrics(), computed from omnigent conversation-store items
    # (function_call / function_call_output) instead of an on-disk claude-native .jsonl.
    m = {"file": f"api:{conv_id}", "role": role or "?", "turns": 0, "tool_histogram": {},
         "banned_capture_calls": 0, "capture_evidence_calls": 0, "command_not_found": [],
         "read_before_edit": 0, "input_validation_errors": 0, "tool_auth_failures": 0,
         "search_fail": 0, "capture_failures": 0, "title": title, "lead": None}
    hist = collections.Counter(); tool_tag_by_id = {}
    for it in fetch_items(conv_id):
        t = it.get("type")
        if t in ("message", "reasoning"): m["turns"] += 1
        if t == "function_call" and it.get("name"):
            name = it["name"]; hist[name] += 1
            if name in BANNED: m["banned_capture_calls"] += 1
            args = it.get("arguments") or ""
            if "capture-evidence.sh" in args:
                m["capture_evidence_calls"] += 1
            cmd = ""
            try:
                parsed = json.loads(args) if isinstance(args, str) else (args or {})
                cmd = str(parsed.get("command", "")) if isinstance(parsed, dict) else ""
            except Exception:
                cmd = ""
            cid = it.get("call_id") or it.get("id")
            if cid:
                tool_tag_by_id[cid] = invoked_binary(cmd) if cmd else name
        if t == "function_call_output":
            out = it.get("output"); s = out if isinstance(out, str) else json.dumps(out)
            sig = scan_output(s, tool=tool_tag_by_id.get(it.get("call_id") or it.get("id")))
            m["command_not_found"] += sig["command_not_found"]
            for k in ("read_before_edit", "input_validation_errors",
                      "tool_auth_failures", "search_fail", "capture_failures"):
                m[k] += sig[k]
    m["lead"] = _lead_from_text(title)
    m["tool_histogram"] = dict(hist)
    m["command_not_found"] = sorted(set(m["command_not_found"]))
    return m

def api_subagents(conv_id):
    # Fallback when no local .jsonl matched: the run's sub-agents are omnigent SUB-SESSIONS
    # (not on-disk Task transcripts), so discover each child conv from the coordinator's
    # sys_session_send outputs (output.conversation_id) and read it from the API.
    subs, seen = [], set()
    for it in fetch_items(conv_id):
        if it.get("type") != "function_call_output": continue
        out = it.get("output")
        try: out = json.loads(out) if isinstance(out, str) else out
        except Exception: continue
        if not isinstance(out, dict): continue
        child = out.get("conversation_id")
        if isinstance(child, str) and child.startswith("conv_") and child not in seen:
            seen.add(child)
            subs.append(api_subagent_metrics(child, out.get("agent", ""), out.get("title", "")))
    return subs

_DELIVERED_PATS = (
    r"sub-agent\s+\S+?/(\S+?)\s+finished\s+\(completed\)",   # single-item proactive delivery
    r"sub-agent task \S+ completed [—-] \S+?:(\S+?) returned",  # bundled-drain (≥2 completed at once)
)

def titles_from_items(items):
    # Titles the coordinator confirmed received, across both delivery-message formats.
    # ensure_ascii=False keeps the em-dash literal (default escaping would hide it as —).
    titles = set()
    for it in items:
        blob = json.dumps(it, ensure_ascii=False)
        for pat in _DELIVERED_PATS:
            for m in re.finditer(pat, blob):
                titles.add(m.group(1))
    return titles

def delivered_titles(conv_id):
    return titles_from_items(fetch_items(conv_id))

def run_base(repo, branch, run_id, base_ref=None):
    # base_ref is the merge-base FALLBACK, used only when no commit subject matches run_id.
    # Default derives from this deployment's OSINT_BRANCH (NOT a hardcoded origin/main —
    # a master-only deployment has no origin/main, and git() swallows the failed
    # merge-base, so an unresolvable fallback silently empties every downstream diff).
    if not base_ref:
        base_ref = "origin/" + os.environ.get("OSINT_BRANCH", "master")
    # The run's branch point = parent of the EARLIEST commit whose subject contains run_id.
    # Robust whether or not the run has already been merged into master (merge-base breaks then).
    first = git(repo, "log", f"origin/{branch}", f"--grep={run_id}",
                "--format=%H", "--reverse").splitlines()
    if first:
        parent = git(repo, "rev-parse", f"{first[0]}^").strip()
        if parent:
            return parent
    mb = git(repo, "merge-base", base_ref, f"origin/{branch}").strip()
    if mb:
        return mb
    # No subject match AND no merge-base => there is NO valid common base: the fallback
    # ref is either MISSING or from UNRELATED history (an existing-but-orphan ref has no
    # merge-base with the run branch). Diffing against it is an invalid comparison whose
    # empty diffs would silently read as an authoritative PASS. Ref EXISTENCE is NOT
    # sufficient -- the absence of a merge-base is itself the failure. Record a HARD
    # failure (main() forces verdict FAIL) rather than return a bogus base.
    BASE_UNRESOLVED.append(base_ref)
    warn(f"run_base: no valid evaluation base for run '{run_id}' on branch '{branch}' -- no "
         f"commit subject matched the run id and '{base_ref}' shares no history with it "
         f"(missing or unrelated). Verdict forced to FAIL. Pass --base-ref "
         f"\"origin/$OSINT_BRANCH\" for this deployment's base branch.")
    return base_ref

def branch_metrics(repo, branch, base):
    names = git(repo, "diff", "--name-only", f"{base}..origin/{branch}").splitlines()
    tooling = [n for n in names if any(n.startswith(p) for p in TOOLING_GLOB)]
    evidence = [n for n in names if n.startswith(("dossier/sources/evidence", "evidence/"))]
    return {"files_changed": len([n for n in names if n]), "evidence_added": len(evidence),
            "run_modified_tooling": tooling}

def gate_metrics(repo, branch):
    wt = f"/tmp/eval-wt-{os.getpid()}"
    added = False
    try:
        add = subprocess.run(["git", "-C", repo, "worktree", "add", "-q", "--detach", wt,
                              f"origin/{branch}"], capture_output=True, text=True, timeout=60)
        added = add.returncode == 0
        if not added:
            warn(f"gate: worktree add failed: {add.stderr.strip()}")
            return {"exit": None, "paths_checked": None}
        p = subprocess.run(["bash", "omnigent/tests/verify-register.sh", "."],
                           cwd=wt, capture_output=True, text=True, timeout=120)
        m = re.search(r"(\d+)\s+evidence path", p.stdout + p.stderr)
        return {"exit": p.returncode, "paths_checked": int(m.group(1)) if m else None}
    except Exception as e:
        warn(f"gate: {e}"); return {"exit": None, "paths_checked": None}
    finally:
        if added:
            git(repo, "worktree", "remove", "--force", wt)

def grade_of(blob):
    grades = re.findall(r"^confidence:\s*([ABCD])\b", blob, re.MULTILINE)
    grades += re.findall(r"^verifier_grade:\s*([ABCD])\b", blob, re.MULTILINE)
    # verifier_grades: map — inline flow ({F-1: B, F-2: A}) or an indented block;
    # capture the rest of that line plus any following indented lines, then pull grades.
    mv = re.search(r"^verifier_grades:(.*(?:\n[ \t]+.*)*)", blob, re.MULTILINE)
    if mv:
        grades += re.findall(r":\s*([ABCD])\b", mv.group(1))
    # body header / parenthetical, e.g. "## F-087-01 — Acme Ltd (Grade C)"
    grades += re.findall(r"\(Grade[:\s]*([ABCD])\b", blob)
    grades = [g for g in grades if g in "ABCD"]
    return min(grades, key=lambda g: "ABCD".index(g)) if grades else None

def lead_of(blob):
    m = re.search(r"^lead:\s*(lead-(?:" + ULID_RE + r"|[0-9]+))", blob, re.MULTILINE)
    if m:
        return m.group(1)
    m = re.search(r"\*\*Lead:\*\*\s*(lead-(?:" + ULID_RE + r"|[0-9]+))", blob, re.IGNORECASE)
    return m.group(1) if m else None

def grade_tally(blobs):
    t = {"A": 0, "B": 0, "C": 0, "D": 0}
    for b in blobs:
        g = grade_of(b)
        if g:
            t[g] += 1
    return t

def map_verdict(hard_fail, flags):
    if any(hard_fail.values()): return "FAIL"
    if any(flags.values()): return "PASS_WITH_FLAGS"
    return "PASS"

def findings_metrics(repo, branch, base):
    # A(dded) AND M(odified): a lead that APPENDS to an existing finding doc must still have its
    # grade counted (BL-23 part 2); the strongest grade is read from the post-run blob below.
    changed = git(repo, "diff", "--name-only", "--diff-filter=AM",
                  f"{base}..origin/{branch}").splitlines()
    blobs, lead_grades = [], {}
    for path in changed:
        if path.startswith("dossier/findings/") and path.endswith(".md"):
            blob = git(repo, "show", f"origin/{branch}:{path}")
            blobs.append(blob)
            ld, gr = lead_of(blob), grade_of(blob)
            if ld and gr:
                prev = lead_grades.get(ld)
                # keep the STRONGEST grade per lead (A strongest → lowest index)
                if prev is None or "ABCD".index(gr) < "ABCD".index(prev):
                    lead_grades[ld] = gr
    leads_yaml = git(repo, "show", f"origin/{branch}:dossier/leads.yaml")
    done = len(re.findall(r"status:\s*done", leads_yaml))
    blocked = len(re.findall(r"status:\s*blocked", leads_yaml))
    return {"leads_done": done, "leads_blocked": blocked,
            "grade_tally": grade_tally(blobs), "lead_grades": lead_grades}

def regression(result, prev_path):
    if not prev_path or not os.path.exists(prev_path):
        return {"vs": None, "deltas": {}}
    try: prev = json.load(open(prev_path))
    except Exception as e:
        warn(f"prev-metrics: {e}"); return {"vs": None, "deltas": {}}
    pt = prev.get("totals", {}); ct = result["totals"]
    deltas = {}
    for k in ("banned_capture_calls", "capture_evidence_calls", "read_before_edit",
              "input_validation_errors"):
        deltas[k] = ct.get(k, 0) - pt.get(k, 0)
    deltas["gate_exit"] = [prev.get("gate", {}).get("exit"), result["gate"]["exit"]]
    new_cnf = sorted(set(ct.get("command_not_found", [])) - set(pt.get("command_not_found", [])))
    deltas["new_command_not_found"] = new_cnf
    # promote flags off the baseline
    result["flags"]["new_command_not_found"] = bool(new_cnf)
    result["flags"]["validation_error_spike"] = ct["input_validation_errors"] > pt.get("input_validation_errors", 0)
    result["flags"]["read_before_edit_spike"] = ct["read_before_edit"] > pt.get("read_before_edit", 0)
    return {"vs": prev.get("run_id"), "deltas": deltas}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--conv-id")
    ap.add_argument("--branch", required=True)
    ap.add_argument("--repo", default=".")
    ap.add_argument("--out")
    ap.add_argument("--prev-metrics")
    ap.add_argument("--base-ref", default=None,
                    help="merge-base fallback ref used by run_base() when no commit subject "
                         "matches --run-id. Default fallback is origin/<$OSINT_BRANCH>; "
                         "OSINT_BRANCH itself defaults to the value used by run.sh. "
                         "Pass it explicitly to match your deployment's base branch.")
    a = ap.parse_args()
    repo = os.path.abspath(a.repo)

    global PROJECTS
    if not PROJECTS:
        PROJECTS = os.path.join("/root/.claude/projects", munged_workspace_dir(repo))

    conv_id, created, updated = (a.conv_id, None, None)
    if conv_id:
        sess = http_json(f"/v1/sessions/{conv_id}") or {}
        created, updated = sess.get("created_at"), sess.get("updated_at")
    else:
        conv_id, created, updated = find_conv(a.run_id)

    coord, c2, u2 = coordinator_metrics(conv_id)
    created = created or c2; updated = updated or u2
    files = jsonl_files(a.run_id, created, updated)
    subs = api_subagents(conv_id)            # API = complete child set (ground truth)
    if not subs and files:                    # API unreachable → local fallback
        subs = [subagent_metrics(f) for f in files]
        warn(f"sub-agent metrics via local .jsonl fallback ({len(subs)}); API returned none")
    if not subs:
        warn("no sub-agent transcripts found (neither API sub-sessions nor local .jsonl)")
    delivered = delivered_titles(conv_id)
    totals = {
        "banned_capture_calls": sum(s["banned_capture_calls"] for s in subs),
        "capture_evidence_calls": sum(s["capture_evidence_calls"] for s in subs),
        "command_not_found": sorted({c for s in subs for c in s["command_not_found"]}),
        "read_before_edit": sum(s["read_before_edit"] for s in subs),
        "input_validation_errors": sum(s["input_validation_errors"] for s in subs),
        "tool_auth_failures": sum(s.get("tool_auth_failures", 0) for s in subs),
        "search_fail": sum(s.get("search_fail", 0) for s in subs),
        "capture_failures": sum(s.get("capture_failures", 0) for s in subs),
    }
    git(repo, "fetch", "origin", a.branch, "-q")
    base = run_base(repo, a.branch, a.run_id, a.base_ref)
    br = branch_metrics(repo, a.branch, base)
    gate = gate_metrics(repo, a.branch)
    finds = findings_metrics(repo, a.branch, base)
    for s in subs:
        s["finding_grade"] = finds["lead_grades"].get(s.get("lead"))
        s["delivered"] = bool(s.get("title") and s["title"] in delivered)

    def searxng_calls(ag):
        return sum(v for k, v in ag.get("tool_histogram", {}).items() if "searxng" in k.lower())
    core = lambda ag: ag.get("role") in ("researcher", "verifier")
    degraded_tooling = any(core(ag) and ag.get("tool_auth_failures", 0) > 0 for ag in subs)
    # search_fail is now scoped to actual searxng-call outputs (BL-23), so judge it as a RATE of a
    # lead's searxng calls — a raw count threshold false-fired on high-volume-but-healthy searching
    # (INV-SYNTH-01 had 39 benign zero-hit results, over the old raw >20 threshold).
    degraded_search = any(
        searxng_calls(ag) and ag.get("search_fail", 0) > 0.5 * searxng_calls(ag)
        for ag in subs)
    verification_integrity = any(
        core(ag) and ag.get("tool_auth_failures", 0) > 0
        and finds["lead_grades"].get(ag.get("lead")) in ("A", "B")
        for ag in subs)
    coord_status = (http_json(f"/v1/sessions/{conv_id}") or {}).get("status") if conv_id else None
    reaped_after_completion = bool(gate["exit"] == 0 and coord_status == "failed")

    hard_fail = {"banned_capture": totals["banned_capture_calls"] > 0,
                 "gate_fail": gate["exit"] not in (0,),
                 "unresolved_eval_base": bool(BASE_UNRESOLVED)}
    flags = {"run_modified_tooling": bool(br["run_modified_tooling"]),
             "command_not_found": bool(totals["command_not_found"]),
             "degraded_tooling": degraded_tooling,
             "degraded_search": degraded_search,
             "new_command_not_found": False,
             "validation_error_spike": False,
             "read_before_edit_spike": False}
    verdict = map_verdict(hard_fail, flags)

    result = {"run_id": a.run_id, "conv_id": conv_id, "branch_name": a.branch,
              "coordinator": coord, "agents": subs, "totals": totals,
              "branch": br, "gate": gate, "findings": finds,
              "hard_fail": hard_fail, "flags": flags, "verdict": verdict,
              "verification_integrity": "FAIL_CANDIDATE" if verification_integrity else None,
              "reaped_after_completion": reaped_after_completion,
              "regression": {"vs": None, "deltas": {}}}
    prev = a.prev_metrics
    if not prev:
        cands = sorted(glob.glob(os.path.join(repo, "dossier/runs/INV-*-eval.metrics.json")),
                       key=os.path.getmtime, reverse=True)
        cands = [c for c in cands if a.run_id not in os.path.basename(c)]
        prev = cands[0] if cands else None
    result["regression"] = regression(result, prev)
    # re-evaluate verdict now that regression may have set flags
    result["verdict"] = map_verdict(result["hard_fail"], result["flags"])
    if WARN: result["_warnings"] = WARN
    out = a.out or os.path.join(repo, "dossier/runs", f"{a.run_id}-eval.metrics.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w").write(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()

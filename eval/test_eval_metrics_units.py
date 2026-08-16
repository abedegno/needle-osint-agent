import importlib.util, os
_spec = importlib.util.spec_from_file_location(
    "eval_metrics", os.path.join(os.path.dirname(__file__), "eval_metrics.py"))
em = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(em)

FIND_B = "---\nid: x\nconfidence: B   # registry facts B; nexus D\nstatus: verified\nlead: lead-120\n---\n## Claim\n"
FIND_A = "---\nid: y\nconfidence: A\nlead: lead-121\n---\nbody"
FIND_NONE = "---\nid: z\nstatus: open\n---\nno grade"

# --- BL-19.1: multi-format grade/lead fixtures ---
FIND_VG_SCALAR = "---\nid: a\nverifier_grade: A\nlead: lead-200\n---\nbody"
FIND_VG_MAP = "---\nid: b\nverifier_grades: {F-1: B, F-2: A}\n---\nbody"
FIND_HEADER = "**Lead:** lead-087\n\n## F-087-01 — Acme Ltd (Grade C)\n\nSome prose.\n"
FIND_MIXED = "---\nconfidence: C\n---\n## F-9 — x (Grade A)\nbody"

def test_grade_of_reads_letter_ignoring_trailing_comment():
    assert em.grade_of(FIND_B) == "B"
    assert em.grade_of(FIND_A) == "A"
    assert em.grade_of(FIND_NONE) is None

def test_lead_of():
    assert em.lead_of(FIND_B) == "lead-120"
    assert em.lead_of(FIND_NONE) is None

def test_grade_of_reads_verifier_grade_scalar():
    assert em.grade_of(FIND_VG_SCALAR) == "A"

def test_grade_of_reads_verifier_grades_map_strongest():
    assert em.grade_of(FIND_VG_MAP) == "A"

def test_grade_of_reads_header_parenthetical():
    assert em.grade_of(FIND_HEADER) == "C"

def test_grade_of_returns_strongest_across_formats():
    assert em.grade_of(FIND_MIXED) == "A"

def test_lead_of_reads_bold_markdown():
    assert em.lead_of(FIND_HEADER) == "lead-087"

def test_grade_tally_counts_and_ignores_ungraded():
    assert em.grade_tally([FIND_B, FIND_A, FIND_NONE]) == {"A": 1, "B": 1, "C": 0, "D": 0}

def test_scan_output_detects_token_empty_as_auth_failure():
    s = '{"output": "capture-evidence: ERROR: CRAWL4AI_API_TOKEN is empty in this shell  [exit code: 1]"}'
    sig = em.scan_output(s, tool="capture-evidence.sh")
    assert sig["tool_auth_failures"] >= 1
    assert sig["capture_failures"] >= 1

def test_scan_output_token_present_is_not_auth_failure():
    # "✅ CRAWL4AI_API_TOKEN present" is a success line, not a failure.
    assert em.scan_output("✅ CRAWL4AI_API_TOKEN present", tool="crawl4ai__md")["tool_auth_failures"] == 0

def test_scan_output_detects_no_api_key_and_searxng_fail():
    assert em.scan_output("this shell has no API key, falling back", tool="companies-house.sh")["tool_auth_failures"] >= 1
    assert em.scan_output("No results found for 'x'. check if SearXNG search engines are working", tool="searxng__web_search")["search_fail"] == 1

def test_scan_output_keeps_existing_signals():
    sig = em.scan_output("bash: dig: command not found\nFile has not been read yet")
    assert sig["command_not_found"] == ["dig"]
    assert sig["read_before_edit"] == 1

def test_scan_output_clean_is_all_zero():
    sig = em.scan_output('{"items":[{"name":"PAPADOPOULOS"}]}')
    assert sig == {"command_not_found": [], "read_before_edit": 0, "input_validation_errors": 0,
                   "tool_auth_failures": 0, "search_fail": 0, "capture_failures": 0}

def test_map_verdict_precedence():
    assert em.map_verdict({"gate_fail": True}, {"degraded_tooling": False}) == "FAIL"
    assert em.map_verdict({"gate_fail": False}, {"degraded_tooling": True}) == "PASS_WITH_FLAGS"
    assert em.map_verdict({"gate_fail": False}, {"degraded_tooling": False}) == "PASS"

def test_titles_from_items_reads_both_delivery_formats():
    items = [
        {"content": "sub-agent research-lead/research-lead-139 finished (completed)"},
        {"content": "sub-agent task conv_abc123 completed — researcher:preflight-researcher returned: ok"},
    ]
    titles = em.titles_from_items(items)
    assert titles == {"research-lead-139", "preflight-researcher"}

# --- BL-23 part 1: AUTH/SEARCH scoped to the network tool's error envelope ---

CALBAR_PAGE = ("State Bar of California attorney search results. Menu: Unauthorized Practice "
               "of Law | Unauthorized Practice of Law Violations | Rule 1-300 Unauthorized "
               "Practice of Law Complaint. Attorney: Heidi Wells, active, no discipline.")

def test_scan_output_calbar_page_text_is_not_auth_failure():
    # A successfully-fetched CalBar page whose nav says "Unauthorized Practice of Law" is NOT an
    # auth failure — bare "unauthorized" must no longer match, even for a network tool.
    assert em.scan_output(CALBAR_PAGE, tool="crawl4ai__md")["tool_auth_failures"] == 0

def test_scan_output_auth_only_for_network_tools():
    # A real HTTP 401 from a network fetch IS an auth failure...
    assert em.scan_output("crawl4ai fetch failed: HTTP 401 Unauthorized", tool="crawl4ai__md")["tool_auth_failures"] == 1
    # ...but the same error string inside a CAT of a script is not (cat is not a network tool).
    assert em.scan_output("die 'HTTP 401 Unauthorized'  # invalid api key template", tool="cat")["tool_auth_failures"] == 0
    # ...and with no tool context, AUTH is not scanned (tool-agnostic default).
    assert em.scan_output("invalid api key")["tool_auth_failures"] == 0

def test_scan_output_capture_failure_only_for_capture_tool():
    err = "capture-evidence: ERROR: CRAWL4AI_API_TOKEN is empty in this shell  [exit code: 1]"
    assert em.scan_output(err, tool="capture-evidence.sh")["capture_failures"] == 1
    # cat-ing the capture-evidence source must NOT count as a capture failure.
    assert em.scan_output(err, tool="cat")["capture_failures"] == 0

def test_scan_output_search_fail_only_for_searxng():
    txt = "No results found for 'x'. check if SearXNG search engines are working"
    assert em.scan_output(txt, tool="searxng__web_search")["search_fail"] == 1
    assert em.scan_output(txt, tool="cat")["search_fail"] == 0

def test_scan_output_tool_agnostic_signals_always_scanned():
    # command_not_found / read_before_edit / validation are NOT tool-scoped.
    sig = em.scan_output("bash: dig: command not found\nFile has not been read yet\nInputValidationError", tool="cat")
    assert sig["command_not_found"] == ["dig"]
    assert sig["read_before_edit"] == 1
    assert sig["input_validation_errors"] == 1

def test_is_network_tool():
    for t in ("crawl4ai__md", "searxng__web_search", "web_url_read",
              "omnigent/bin/capture-evidence.sh", "companies-house.sh", "curl", "gazette.sh"):
        assert em.is_network_tool(t), t
    for t in ("cat", "grep", "sed", "head", "sys_os_edit", "", None):
        assert not em.is_network_tool(t), t

def test_invoked_binary_strips_interpreters():
    assert em.invoked_binary("cat omnigent/bin/capture-evidence.sh") == "cat"
    assert em.invoked_binary("bash omnigent/bin/capture-evidence.sh --stealth u o") == "omnigent/bin/capture-evidence.sh"
    assert em.invoked_binary("sudo curl https://x") == "curl"
    assert em.invoked_binary("") == ""

def test_subagent_metrics_scopes_auth_to_network_tool(tmp_path):
    import json as _j
    lines = [
      {"type":"user","message":{"content":[{"type":"text","text":"research lead-999: do x"}]}},
      {"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu1","name":"sys_os_shell","input":{"command":"cat omnigent/bin/capture-evidence.sh"}}]}},
      {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu1","content":"... die 'invalid api key' ..."}]}},
      {"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu2","name":"crawl4ai__md","input":{"url":"https://x"}}]}},
      {"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu2","content":"crawl4ai: HTTP 401 Unauthorized"}]}},
    ]
    p = tmp_path / "a.jsonl"; p.write_text("\n".join(_j.dumps(x) for x in lines))
    m = em.subagent_metrics(str(p))
    assert m["tool_auth_failures"] == 1  # only the crawl4ai 401, not the cat of the script

# --- BL-23 part 2: findings_metrics counts grades in MODIFIED finding docs, not only ADDED ---

def test_findings_metrics_counts_modified_docs(tmp_path):
    import subprocess
    repo = tmp_path / "r"; repo.mkdir()
    def g(*a): subprocess.run(["git", "-C", str(repo), *a], check=True, capture_output=True)
    g("init", "-q"); g("config", "user.email", "t@t"); g("config", "user.name", "t")
    (repo / "dossier" / "findings").mkdir(parents=True)
    (repo / "dossier" / "findings" / "old.md").write_text("---\nlead: lead-1\nconfidence: C\n---\nx")
    (repo / "dossier" / "leads.yaml").write_text("- id: lead-1\n  status: done\n")
    g("add", "-A"); g("commit", "-qm", "base")
    base = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    g("checkout", "-qb", "run/x")
    (repo / "dossier" / "findings" / "new.md").write_text("---\nlead: lead-2\nconfidence: A\n---\ny")   # ADDED
    (repo / "dossier" / "findings" / "old.md").write_text("---\nlead: lead-1\nconfidence: B\n---\nx+")  # MODIFIED
    g("add", "-A"); g("commit", "-qm", "run")
    g("remote", "add", "origin", str(repo)); g("fetch", "-q", "origin")
    fm = em.findings_metrics(str(repo), "run/x", base)
    assert fm["lead_grades"].get("lead-2") == "A"  # added doc (existing behaviour)
    assert fm["lead_grades"].get("lead-1") == "B"  # MODIFIED doc — the BL-23 part-2 fix

# --- Task 3: ULID lead ids + doc-local F-NN ---

ULID_A = "lead-01J8ZQK7W2QF3M8B4R9YT6X0AD"
FIND_ULID = f"---\nlead: {ULID_A}\nverifier_grades: {{F-01: A, F-02: C}}\n---\nbody"

def test_lead_of_reads_ulid_lead_field():
    assert em.lead_of(FIND_ULID) == ULID_A

def test_grade_of_reads_ulid_finding_docs():
    assert em.grade_of(FIND_ULID) == "A"

def test_lead_from_text_reads_ulid_title_substring():
    assert em._lead_from_text("research-" + ULID_A) == ULID_A

def test_lead_from_text_still_reads_legacy():
    assert em._lead_from_text("research-lead-167") == "lead-167"   # no pre-migration regression

#!/usr/bin/env python3
# id_integrity.py — dossier id-integrity checker. check(ws) -> list of violation strings.
# Surface: tracked files under dossier/ + evidence/ path names. Excludes docs/tools/tests/.superpowers.
#
# Scope (F-id amendment v7, BL-22): src/lead ONLY. F-<lead>-<seq> ids are FROZEN opaque identifiers —
# the gate ACCEPTS any `F-<n>-<n>` token as valid without inspecting it: no legacy-F flagging, no
# def/ref resolution, no allowlist entry required. The corpus uses 3+ incompatible F-definition
# conventions (verifier_grades map, `## F-NN — title` headings, single-finding frontmatter) that
# cannot be reliably distinguished, and F-references are NOT doc-local (237 cross-doc citations, 8
# strings defined verbatim in 2-3 docs) — attempting cross-convention resolution produces false
# positives across the corpus. See docs/superpowers/specs/2026-07-16-id-schema-ulid-design.md,
# "F-id scope amendment (v7)".
import glob, os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(__file__))
from ulid import is_canonical

ULID = r"[0-7][0-9A-HJKMNP-TV-Z]{25}"
# Broad candidate: src/lead + any id-ish run, at token boundaries. Each candidate is classified as
# legacy (all digits), canonical ULID (is_canonical), or MALFORMED (neither — a violation). This
# catches lowercase/wrong-length ULID-shaped refs that a strict 26-upper regex would miss.
# Leading boundary excludes alnum/hyphen (not underscore): evidence filenames routinely join id
# tokens to a PRECEDING segment with `_` (e.g. `verify_lead-092_snapshot.html`) and those
# underscore-joined segments must not block the match.
# Trailing boundary excludes alnum ONLY (not hyphen) — the real dossier also joins id tokens to a
# DESCRIPTIVE SUFFIX with a bare hyphen, not underscore (e.g.
# `evidence/snapshots/lead-092-example-homepage.png`); excluding trailing hyphen served no purpose
# (the value group's own charset already stops at a hyphen; the alnum exclusion alone is what
# stops a legacy-shaped prefix inside a canonical ULID from being misread) but silently made this
# hyphen-joined filename convention invisible to the gate — found running the full-repo e2e (F-id
# scope amendment v7 rework); fixed here in lockstep with apply.rewrite_text and mapper.LEGACY.
# Deliberately src|lead only — F-ids are frozen and out of scope (see module docstring).
# re.I: the design spec requires the "no legacy id anywhere" surface to be matched "case-
# insensitively (LEAD-024)" — the real dossier has uppercase-prefixed evidence filenames
# (`LEAD-024_...`, `infra_analytics_LEAD-028_...`). Without re.I, CAND's literal `src|lead`
# alternation only matched exact-lowercase prefixes, so an uppercase legacy/dangling/malformed
# token would be entirely invisible to the gate (a defined `LEAD-024` gets correctly renamed by
# apply.rename_manifest's/rewrite_text's own re.I passes during migration, so this rarely bites in
# the common case — but an unresolved, allowlisted, or otherwise-surviving uppercase token would
# silently escape detection). `_classify_candidates` already lower()s the captured kind/value
# defensively, so this only widens which literal prefixes are recognized as candidates at all; the
# legacy/canonical/malformed classification logic is unchanged.
CAND = re.compile(r"(?<![A-Za-z0-9-])(src|lead)-([0-9A-Za-z]+)(?![A-Za-z0-9])", re.I)

def doc_slugs(ws):
    # Basenames (no extension) of every SLUG-NAMED, NEVER-RENAMED dossier doc — findings/entities/
    # people. A finding/entity/person filename can coincidentally START with a legacy
    # `(?:src|lead)-[0-9]+-` prefix as part of its own descriptive slug (e.g. a doc named
    # `lead-012-example-registered-office-cross-check.md` or
    # `lead-034-example-trademark-ownership-confirmed.md`). That prefix
    # is the file's own permanent name, not a legacy citation — its own (never-renamed) path, and
    # any exact citation of the same slug elsewhere (a `[[wikilink]]`, an inline-code mention),
    # must NOT be flagged as a legacy/dangling id. Mirrors tools/migrate_ids/mapper.doc_slugs.
    #
    # Only slugs of the form `(?:src|lead)-[0-9]+-<more>` are admitted (id prefix + a real
    # descriptive suffix) — a hypothetical BARE-id-named doc (`lead-054.md`, no suffix) is
    # deliberately excluded, since admitting it would guard on "lead-054" alone and silently
    # suppress every unrelated "lead-054" legacy citation in the corpus. No-op on today's data
    # (every real slug already has a descriptive suffix); closes a latent gap.
    _bare_id_prefix=re.compile(r"^(?:src|lead)-[0-9]+-", re.I)
    slugs=set()
    for sub in ("findings","entities","people"):
        for fp in glob.glob(os.path.join(ws,"dossier",sub,"*.md")):
            slug=os.path.splitext(os.path.basename(fp))[0]
            if _bare_id_prefix.match(slug): slugs.add(slug)
    return slugs

def _cand_pattern(protect):
    if not protect: return CAND
    guard="(?:"+"|".join(re.escape(s) for s in sorted(protect, key=len, reverse=True))+")"
    return re.compile(r"(?<![A-Za-z0-9-])(?!"+guard+r")(src|lead)-([0-9A-Za-z]+)(?![A-Za-z0-9])", re.I)

INCLUDE_PREFIXES = ("dossier/", "evidence/")
EXCLUDE_PREFIXES = ("docs/", "tools/", "omnigent/tests/", ".superpowers/")

def tracked(ws):
    r = subprocess.run(["git","-C",ws,"ls-files","-z"], capture_output=True, text=True)
    return [p for p in r.stdout.split("\0") if p]

def in_surface(rel):
    if any(rel.startswith(p) for p in EXCLUDE_PREFIXES): return False
    return any(rel.startswith(p) for p in INCLUDE_PREFIXES)

def is_text(path):
    try:
        with open(path,"rb") as fh: return b"\0" not in fh.read(4096)
    except OSError: return False

def load_allow(ws):
    p = os.path.join(ws,"dossier","id-allowlist.txt")
    if not os.path.isfile(p): return set()
    out=set()
    for ln in open(p, errors="ignore"):
        s=ln.split("#",1)[0].strip()
        if s: out.add(s.lower())
    return out

def defined_ids(ws):
    src, lead = set(), set()
    reg=os.path.join(ws,"dossier/sources/register.yaml")
    if os.path.isfile(reg):
        for ln in open(reg, errors="ignore"):
            m=re.match(r"- id:\s*(src-"+ULID+r")\s*$", ln.strip())
            if m: src.add(m.group(1))
    lp=os.path.join(ws,"dossier/leads.yaml")
    if os.path.isfile(lp):
        for ln in open(lp, errors="ignore"):
            m=re.match(r"- id:\s*(lead-"+ULID+r")\s*$", ln.strip())
            if m: lead.add(m.group(1))
    return src, lead

def _dup_defs(ws, path, prefix):
    seen, dups = set(), []
    fp=os.path.join(ws,path)
    if os.path.isfile(fp):
        for ln in open(fp, errors="ignore"):
            m=re.match(r"- id:\s*("+prefix+r"-"+ULID+r")\s*$", ln.strip())
            if m:
                if m.group(1) in seen: dups.append(m.group(1))
                seen.add(m.group(1))
    return dups

def _classify_candidates(where, text, src_def, lead_def, allow, v, rel, pattern=CAND):
    # classify every src/lead candidate as legacy | canonical-resolved | violation.
    for m in pattern.finditer(text):
        full, kind, val = m.group(0), m.group(1).lower(), m.group(2)
        low = full.lower()
        if val.isdigit():                                   # legacy (e.g. src-042)
            if low not in allow: v.append(f"legacy id token in {where} {rel}: {full}")
        elif is_canonical(val):                             # canonical ULID → must resolve
            pool = src_def if kind == "src" else lead_def
            if full not in pool and low not in allow:
                v.append(f"dangling reference in {where} {rel}: {full}")
        elif any(c.isdigit() for c in val) or len(val) >= 20:   # non-canonical but ID-shaped → malformed
            # A candidate is ID-shaped if it contains a digit (catches truncated `lead-01J8ZQK7W2QF3M8B4R9`
            # and lowercase attempts, any length) OR is ULID-length-ish (catches a 26-char ALL-ALPHABETIC
            # malformed value that lost its leading digit). Only SHORT pure-alphabetic compounds like
            # `lead-attached` (no digit, len<20) fall through as ordinary prose.
            if low not in allow: v.append(f"malformed id in {where} {rel}: {full}")

def check(ws):
    v=[]; allow=load_allow(ws); src_def, lead_def = defined_ids(ws)
    pattern=_cand_pattern(doc_slugs(ws))
    for i in _dup_defs(ws,"dossier/sources/register.yaml","src"): v.append(f"duplicate src id: {i}")
    for i in _dup_defs(ws,"dossier/leads.yaml","lead"): v.append(f"duplicate lead id: {i}")
    for rel in tracked(ws):
        if not in_surface(rel): continue
        ap=os.path.join(ws,rel)
        _classify_candidates("path", rel, src_def, lead_def, allow, v, rel, pattern)
        if rel.startswith("evidence/"): continue          # evidence blobs are binary; path handled above
        if not is_text(ap): continue
        text=open(ap, errors="ignore").read()
        _classify_candidates("body", text, src_def, lead_def, allow, v, rel, pattern)
    return v

def main():
    ws=sys.argv[1] if len(sys.argv)>1 else "."
    v=check(ws)
    if v:
        print("verify-id-integrity: FAIL")
        for x in v: print("   ", x)
        sys.exit(1)
    print("verify-id-integrity: OK (dossier surface: refs resolve, no legacy ids, ids unique in scope)")

if __name__=="__main__": main()

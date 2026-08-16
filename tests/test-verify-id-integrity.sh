#!/usr/bin/env bash
# Test for verify-id-integrity.sh — the dossier id-integrity gate.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; GATE="$HERE/verify-id-integrity.sh"
fail=0
ok(){ printf '  \033[32m✅\033[0m %s\n' "$1"; }
no(){ printf '  \033[31m❌\033[0m %s\n' "$1"; fail=1; }
skip(){ printf '  \033[33m⏭\033[0m  SKIP: %s — sandbox off\n' "$1"; exit 77; }
for t in mktemp python3 git; do command -v "$t" >/dev/null 2>&1 || skip "missing $t"; done
WS="$(mktemp -d 2>/dev/null)" || skip "mktemp blocked"; trap 'rm -rf "$WS"' EXIT
git -C "$WS" init -q; git -C "$WS" config user.email t@t; git -C "$WS" config user.name t
mkdir -p "$WS/dossier/sources" "$WS/dossier/findings" "$WS/evidence/snapshots"
U1=01J8ZQK7W2QF3M8B4R9YT6X0AD; U2=01J8ZQK7W3AAAAAAAAAAAAAAAA
cat > "$WS/dossier/sources/register.yaml" <<YAML
- id: src-$U1
  archive_url: evidence/snapshots/src-${U1}_shot.png
YAML
printf -- "- id: lead-%s\n  status: done\n" "$U2" > "$WS/dossier/leads.yaml"
cat > "$WS/dossier/findings/f.md" <<MD
---
lead: lead-$U2
verifier_grades: {F-01: A}
sources: [src-$U1]
---
F-01 cites src-$U1.
MD
printf x > "$WS/evidence/snapshots/src-${U1}_shot.png"
git -C "$WS" add -A
# Baseline commit: subsequent `checkout HEAD -- <path>` reverts read from THIS commit
# (a bare `git checkout -- <path>` reads from the INDEX, not HEAD, and would replay
# whatever was last staged — including an accidentally-staged dirty edit within the
# same case block — instead of restoring the pristine fixture).
git -C "$WS" commit -q -m init

# (a) clean → pass
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? = 0 ]; } && ok "clean dossier passes" || no "clean failed: $out"
# (b) dangling lead ULID reference → fail
printf '\nsee lead-01J8ZQK7W4BBBBBBBBBBBBBBBB\n' >> "$WS/dossier/findings/f.md"
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? != 0 ] && printf '%s' "$out" | grep -q BBBBBBBB; } \
  && ok "dangling lead ref fails" || no "dangling not caught: $out"
git -C "$WS" checkout HEAD -- dossier/findings/f.md
# (d) legacy token → fail; same token allowlisted → pass
printf '\nlegacy src-042 here\n' >> "$WS/dossier/findings/f.md"
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? != 0 ] && printf '%s' "$out" | grep -qi "src-042"; } \
  && ok "legacy token fails" || no "legacy not caught: $out"
echo "src-042" > "$WS/dossier/id-allowlist.txt"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? = 0 ]; } && ok "allowlisted legacy passes" || no "allowlist ignored: $out"
rm "$WS/dossier/id-allowlist.txt"; git -C "$WS" checkout HEAD -- dossier/findings/f.md; git -C "$WS" add -A
# (e) legacy token in an EVIDENCE PATH → fail; allowlisted path token → pass
git -C "$WS" mv "evidence/snapshots/src-${U1}_shot.png" "evidence/snapshots/lead-099_orphan.png"
python3 - "$WS/dossier/sources/register.yaml" "$U1" <<'PY'
import sys; p=sys.argv[1]; t=open(p).read().replace(f"src-{sys.argv[2]}_shot.png","lead-099_orphan.png"); open(p,"w").write(t)
PY
git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? != 0 ] && printf '%s' "$out" | grep -qi "lead-099"; } \
  && ok "legacy token in evidence path fails" || no "path legacy not caught: $out"
echo "lead-099" > "$WS/dossier/id-allowlist.txt"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? = 0 ]; } && ok "allowlisted path token passes" || no "path allowlist ignored: $out"
rm "$WS/dossier/id-allowlist.txt"; git -C "$WS" add -A
git -C "$WS" mv "evidence/snapshots/lead-099_orphan.png" "evidence/snapshots/src-${U1}_shot.png"
python3 - "$WS/dossier/sources/register.yaml" "$U1" <<'PY'
import sys; p=sys.argv[1]; t=open(p).read().replace("lead-099_orphan.png",f"src-{sys.argv[2]}_shot.png"); open(p,"w").write(t)
PY
git -C "$WS" add -A
# (f) non-canonical ULID reference → fail (over-range 8…)
printf '\nsee lead-8ZZZZZZZZZZZZZZZZZZZZZZZZZZ\n' >> "$WS/dossier/findings/f.md"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? != 0 ]; } && ok "non-canonical ULID ref fails" || no "non-canonical passed: $out"
git -C "$WS" checkout HEAD -- dossier/findings/f.md
# (g) duplicate global src id → fail
printf -- "- id: src-%s\n  archive_url: null\n" "$U1" >> "$WS/dossier/sources/register.yaml"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? != 0 ] && printf '%s' "$out" | grep -qi duplicate; } \
  && ok "duplicate src fails" || no "dup not caught: $out"
git -C "$WS" checkout HEAD -- dossier/sources/register.yaml
# (h) F-ids are FROZEN and out of gate scope (F-id scope amendment v7): an `F-146-01` token defined
# in a findings doc, PLUS a cross-doc citation of that exact string from another doc, are both
# ACCEPTED with no allowlist entry — the gate does not inspect F-ids at all (no def/ref resolution,
# no legacy-F flagging, no duplicate-F detection). Even a wholly-undefined F-string (F-999-99) and a
# doc-local-style F-01 both pass, proving the gate genuinely never looks.
printf -- "---\nlead: lead-%s\nverifier_grades: {F-146-01: A}\n---\nF-146-01 here.\n" "$U2" > "$WS/dossier/findings/g.md"
printf -- "---\nlead: lead-%s\n---\ncited elsewhere: F-146-01 and also F-999-99 and F-01, none defined in THIS doc.\n" "$U2" > "$WS/dossier/findings/h.md"
git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? = 0 ]; } \
  && ok "F-146-01 in findings doc + cross-doc/undefined F citations all accepted (frozen, unscanned)" || no "F-id wrongly flagged: $out"
git -C "$WS" rm -qf dossier/findings/g.md dossier/findings/h.md
# (i) example ULID in a DOCS/ file is NOT treated as a dossier reference (surface scoping)
mkdir -p "$WS/docs"; printf 'example id lead-01J8ZQK7W9CCCCCCCCCCCCCCCC in prose\n' > "$WS/docs/note.md"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? = 0 ]; } && ok "docs/ example id ignored (surface scoped to dossier)" || no "docs falsely scanned: $out"
# (k) MALFORMED ULID-shaped ref (lowercase) in the dossier → fail (neither legacy nor canonical)
printf '\nsee lead-01j8zqk7w2qf3m8b4r9yt6x0ad lowercased\n' >> "$WS/dossier/findings/f.md"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? != 0 ] && printf '%s' "$out" | grep -qi malformed; } && ok "lowercase malformed ULID ref fails" || no "malformed not caught: $out"
git -C "$WS" checkout HEAD -- dossier/findings/f.md
# (l) short English compound (lead-attached, no digit) is NOT an id → must NOT flag (precision guard)
printf '\nthe lead-attached document was reviewed\n' >> "$WS/dossier/findings/f.md"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? = 0 ]; } && ok "short compound lead-attached not flagged" || no "false positive on lead-attached: $out"
git -C "$WS" checkout HEAD -- dossier/findings/f.md
# (m) TRUNCATED ULID (<20 chars, has digits) → must fail (the length-guard blind spot)
printf '\ntruncated lead-01J8ZQK7W2QF3M8B4R9 here\n' >> "$WS/dossier/findings/f.md"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? != 0 ] && printf '%s' "$out" | grep -qi malformed; } && ok "truncated (<20) ULID ref fails" || no "truncated not caught: $out"
git -C "$WS" checkout HEAD -- dossier/findings/f.md
# (n) OVERLONG ULID (27 chars, has digits) → must fail
printf '\noverlong lead-01J8ZQK7W2QF3M8B4R9YT6X0ADX here\n' >> "$WS/dossier/findings/f.md"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? != 0 ] && printf '%s' "$out" | grep -qi malformed; } && ok "overlong (27) ULID ref fails" || no "overlong not caught: $out"
git -C "$WS" checkout HEAD -- dossier/findings/f.md
# (o) 26-char ALL-ALPHABETIC malformed candidate (no digit, but ULID-length) → must fail (length guard)
printf '\nall-alpha lead-ABCDEFGHJKMNPQRSTVWXYZK here\n' >> "$WS/dossier/findings/f.md"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? != 0 ] && printf '%s' "$out" | grep -qi malformed; } && ok "26-char all-alpha candidate fails (length guard)" || no "all-alpha not caught: $out"
git -C "$WS" checkout HEAD -- dossier/findings/f.md
# (p) legacy token PRECEDED BY `_` in an EVIDENCE PATH (leading-underscore boundary) → fail
git -C "$WS" mv "evidence/snapshots/src-${U1}_shot.png" "evidence/snapshots/foo_lead-099_orphan.png"
python3 - "$WS/dossier/sources/register.yaml" "$U1" <<'PY'
import sys; p=sys.argv[1]; t=open(p).read().replace(f"src-{sys.argv[2]}_shot.png","foo_lead-099_orphan.png"); open(p,"w").write(t)
PY
git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? != 0 ] && printf '%s' "$out" | grep -qi "lead-099"; } \
  && ok "underscore-prefixed legacy token in evidence path fails" || no "leading-_ path legacy not caught: $out"
git -C "$WS" mv "evidence/snapshots/foo_lead-099_orphan.png" "evidence/snapshots/src-${U1}_shot.png"
python3 - "$WS/dossier/sources/register.yaml" "$U1" <<'PY'
import sys; p=sys.argv[1]; t=open(p).read().replace("foo_lead-099_orphan.png",f"src-{sys.argv[2]}_shot.png"); open(p,"w").write(t)
PY
git -C "$WS" add -A
# (q) legacy token PRECEDED BY `_` in a finding BODY (leading-underscore boundary) → fail
printf '\nverify_lead-042_thing here\n' >> "$WS/dossier/findings/f.md"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? != 0 ] && printf '%s' "$out" | grep -qi "lead-042"; } \
  && ok "underscore-prefixed legacy token in body fails" || no "leading-_ body legacy not caught: $out"
git -C "$WS" checkout HEAD -- dossier/findings/f.md
# (r) underscore-preceded tokens still resolve/allowlist correctly (not just "always fail")
# (r1) underscore-prefixed CANONICAL lead reference resolves normally → pass
printf '\nverify_lead-%s_snapshot done\n' "$U2" >> "$WS/dossier/findings/f.md"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? = 0 ]; } && ok "underscore-prefixed canonical lead ref resolves" || no "leading-_ canonical ref broken: $out"
git -C "$WS" checkout HEAD -- dossier/findings/f.md
# (r1b) underscore-prefixed DANGLING canonical-shaped lead reference still fails — proves the
# scanner actually SEES underscore-prefixed tokens (a leading-boundary bug would silently drop
# the candidate entirely, making it invisible and thus pass vacuously, not resolve deliberately)
printf '\nverify_lead-01J8ZQK7W4BBBBBBBBBBBBBBBB_snapshot done\n' >> "$WS/dossier/findings/f.md"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? != 0 ] && printf '%s' "$out" | grep -q BBBBBBBB; } \
  && ok "underscore-prefixed dangling canonical ref still fails" || no "leading-_ dangling ref invisible: $out"
git -C "$WS" checkout HEAD -- dossier/findings/f.md
# (r2) underscore-prefixed legacy token, allowlisted → pass
printf '\nverify_lead-042_thing here\n' >> "$WS/dossier/findings/f.md"
echo "lead-042" > "$WS/dossier/id-allowlist.txt"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? = 0 ]; } && ok "underscore-prefixed legacy token allowlisted passes" || no "leading-_ allowlist ignored: $out"
rm "$WS/dossier/id-allowlist.txt"; git -C "$WS" checkout HEAD -- dossier/findings/f.md; git -C "$WS" add -A
# (r3) legacy token followed by a bare HYPHEN descriptive suffix (the real dossier's OTHER evidence
# filename convention alongside underscore-joining, e.g. `lead-092-example-homepage.png`) must still
# fail as a legacy token — a trailing (?![A-Za-z0-9-]) boundary would silently drop this candidate
# entirely (found running the full-repo e2e, F-id scope amendment v7 rework).
printf '\nlegacy src-042-suffix here\n' >> "$WS/dossier/findings/f.md"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? != 0 ] && printf '%s' "$out" | grep -qi "src-042"; } \
  && ok "hyphen-suffixed legacy token fails" || no "hyphen-suffixed legacy not caught: $out"
git -C "$WS" checkout HEAD -- dossier/findings/f.md
# (r4) a findings-doc FILENAME that coincidentally starts with a legacy id prefix as its own
# descriptive slug (e.g. lead-012-example-registered-office-cross-check.md;
# findings/entities/people are slug-named and NEVER renamed) is NOT flagged as a legacy path token
# for its own path, and a cross-doc wikilink citing the exact same slug elsewhere is not flagged
# either — found running the full-repo e2e (F-id scope amendment v7 rework).
slugfile="$WS/dossier/findings/lead-055-some-descriptive-finding-slug.md"
printf -- "---\nlead: lead-%s\n---\nbody text.\n" "$U2" > "$slugfile"
printf '\nsee [[lead-055-some-descriptive-finding-slug]] for detail.\n' >> "$WS/dossier/findings/f.md"
git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? = 0 ]; } \
  && ok "findings-doc slug prefix (own path + cross-doc citation) not flagged as legacy" || no "slug prefix wrongly flagged: $out"
git -C "$WS" rm -qf "$slugfile"; git -C "$WS" checkout HEAD -- dossier/findings/f.md; git -C "$WS" add -A
# (r5) a BARE-id-named doc (no descriptive suffix, e.g. `lead-999.md`) must NOT be admitted into the
# slug-protection guard — admitting it would guard on the bare string "lead-999" and silently
# suppress every OTHER, unrelated "lead-999" legacy citation in the dossier. A genuine legacy
# citation of the same digits elsewhere must still fail normally.
barefile="$WS/dossier/findings/lead-999.md"
printf -- "---\nlead: lead-%s\n---\nbody text.\n" "$U2" > "$barefile"
printf '\na genuine, unrelated legacy lead-999 citation here\n' >> "$WS/dossier/findings/f.md"
git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? != 0 ] && printf '%s' "$out" | grep -qi "lead-999"; } \
  && ok "bare-id-named doc does not over-suppress an unrelated legacy citation" || no "bare-id doc over-suppressed: $out"
git -C "$WS" rm -qf "$barefile"; git -C "$WS" checkout HEAD -- dossier/findings/f.md; git -C "$WS" add -A
# (r6) UPPERCASE-prefixed legacy/dangling/malformed tokens must be caught too (the spec requires
# case-insensitive matching, e.g. real evidence paths like `LEAD-024_...`); CAND was compiled
# without re.I, so an exact-case "LEAD"/"SRC" prefix was entirely invisible to the gate.
printf '\nsee LEAD-042 uppercase legacy here\n' >> "$WS/dossier/findings/f.md"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? != 0 ] && printf '%s' "$out" | grep -qi "LEAD-042"; } \
  && ok "uppercase legacy token fails" || no "uppercase legacy not caught: $out"
git -C "$WS" checkout HEAD -- dossier/findings/f.md; git -C "$WS" add -A
# (s) a legacy-F-shaped token (`F-146-01`), `_`-adjacent on BOTH sides, in an EVIDENCE PATH NAME →
# still passes (F-ids are frozen/unscanned even path-embedded and even underscore-adjacent).
printf x > "$WS/evidence/snapshots/foo_F-146-01_bar.png"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? = 0 ]; } \
  && ok "underscore-adjacent F token in evidence path accepted (frozen, unscanned)" || no "F token in path wrongly flagged: $out"
git -C "$WS" rm -qf evidence/snapshots/foo_F-146-01_bar.png
# (t) an F-NN-shaped reference, `_`-adjacent on BOTH sides, in a finding-doc BODY → still passes.
printf '\nverify_F-77_thing here\n' >> "$WS/dossier/findings/f.md"; git -C "$WS" add -A
out="$(bash "$GATE" "$WS" 2>&1)"; { [ $? = 0 ]; } \
  && ok "underscore-adjacent F reference in body accepted (frozen, unscanned)" || no "F reference in body wrongly flagged: $out"
git -C "$WS" checkout HEAD -- dossier/findings/f.md

exit "$fail"

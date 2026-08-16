#!/usr/bin/env bash
# Test for capture-filing-images.sh — offline via a PATH-shimmed curl + a CAPTURE_CLAUDE_BIN stub.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SCRIPT="$HERE/../bin/capture-filing-images.sh"
fail=0
ok(){ printf '  \033[32m✅\033[0m %s\n' "$1"; }
no(){ printf '  \033[31m❌\033[0m %s\n' "$1"; fail=1; }
skip(){ printf '  \033[33m⏭\033[0m  SKIP: %s — run with the sandbox disabled\n' "$1"; exit 77; }
for t in mktemp file sha256sum python3; do command -v "$t" >/dev/null 2>&1 || skip "missing '$t'"; done
WS="$(mktemp -d 2>/dev/null)" || true
{ [ -n "$WS" ] && [ -d "$WS" ]; } || skip "cannot create a temp workspace"
trap 'rm -rf "$WS"' EXIT
mkdir -p "$WS/bin"

# Fake curl: serves post HTML on a no -o / no -w call; writes a minimal PNG (>1KB) to -o for image
# URLs and prints the http code when -w is present. $FAKE_PAGE selects the HTML body/status:
# "with" (default) = normal post w/ one embedded image, "none" = post w/ no images, "walled" =
# post fetch returns a non-2xx status (login-wall / moved / blocked simulation).
cat > "$WS/bin/curl" <<'CURL'
#!/usr/bin/env bash
url=""; out=""; wantcode=""; prev=""
for a in "$@"; do
  case "$prev" in -o) out="$a" ;; esac
  [ "$a" = "-w" ] && wantcode=1
  case "$a" in http*) url="$a" ;; esac
  prev="$a"
done
case "${FAKE_PAGE:-with}" in
  none)   body='<p>no pictures here</p>' ;;
  walled) body='Access Denied' ;;
  *)      body='<div class="post-body"><a href="https://1.bp.blogspot.com/-x/AAA/BBB/s1600/filing.jpg"><img src="https://1.bp.blogspot.com/-x/AAA/BBB/s640/filing.jpg"></a></div>' ;;
esac
case "$url" in
  *post.html)
    if [ "${FAKE_PAGE:-with}" = "walled" ]; then
      [ -n "$out" ] && printf '%s' "$body" > "$out"
      [ -n "$wantcode" ] && printf '403'
    else
      if [ -n "$out" ]; then printf '%s' "$body" > "$out"; else [ -z "$wantcode" ] && printf '%s' "$body"; fi
      [ -n "$wantcode" ] && printf '200'
    fi ;;
  *filing.jpg*|*/s0/*)
    if [ -n "$out" ]; then { printf '\211PNG\r\n\032\n\000\000\000\015IHDR\000\000\000\001\000\000\000\001\010\000\000\000\000\000\000\000\000'; head -c 1300 /dev/zero; } > "$out"; fi
    [ -n "$wantcode" ] && printf '200' ;;
  *) [ -n "$wantcode" ] && printf '404' ;;
esac
exit 0
CURL
chmod +x "$WS/bin/curl"

# Transcriber stubs: -ok echoes canned text; -fail exits non-zero. Both answer --version.
cat > "$WS/bin/fakeclaude-ok" <<'FC'
#!/usr/bin/env bash
[ "$1" = "--version" ] && { echo "fakeclaude 9.9 (stub)"; exit 0; }
echo "IN THE SUPERIOR COURT OF CALIFORNIA -- CANNED TRANSCRIPTION"
FC
cat > "$WS/bin/fakeclaude-fail" <<'FC'
#!/usr/bin/env bash
[ "$1" = "--version" ] && { echo "fakeclaude 9.9 (stub)"; exit 0; }
exit 3
FC
chmod +x "$WS/bin/fakeclaude-ok" "$WS/bin/fakeclaude-fail"

export PATH="$WS/bin:$PATH"
cd "$WS"

# (a) success -> image + transcription .md (with header) + register block referencing both
out="$(FAKE_PAGE=with CAPTURE_CLAUDE_BIN="$WS/bin/fakeclaude-ok" \
        bash "$SCRIPT" "https://example.com/post.html" testslug 2>"$WS/err")"; rc=$?
{ [ "$rc" = 0 ] \
  && [ -f "$WS/evidence/snapshots/testslug/filing-01.png" ] \
  && file "$WS/evidence/snapshots/testslug/filing-01.png" | grep -qi 'PNG image' \
  && [ -f "$WS/evidence/snapshots/testslug/filing-01.md" ] \
  && grep -q 'AI-ASSISTED TRANSCRIPTION' "$WS/evidence/snapshots/testslug/filing-01.md" \
  && grep -q 'CANNED TRANSCRIPTION' "$WS/evidence/snapshots/testslug/filing-01.md" \
  && printf '%s' "$out" | grep -q 'archive_url: evidence/snapshots/testslug/filing-01.png' \
  && printf '%s' "$out" | grep -q 'companion_transcription: evidence/snapshots/testslug/filing-01.md' \
  && printf '%s' "$out" | grep -Eq 'sha256: [0-9a-f]{64}'; } \
  && ok "success -> image + transcription + register block" \
  || no "success (rc=$rc): out='$out' err='$(cat "$WS/err")'"

# (b) non-fatal: transcriber fails -> image kept, no .md, block marks failed, exit 0
rm -rf "$WS/evidence"
out="$(FAKE_PAGE=with CAPTURE_CLAUDE_BIN="$WS/bin/fakeclaude-fail" \
        bash "$SCRIPT" "https://example.com/post.html" s2 2>/dev/null)"; rc=$?
{ [ "$rc" = 0 ] \
  && [ -f "$WS/evidence/snapshots/s2/filing-01.png" ] \
  && [ ! -f "$WS/evidence/snapshots/s2/filing-01.md" ] \
  && printf '%s' "$out" | grep -q 'companion_transcription: (transcription failed)'; } \
  && ok "transcriber fail -> image kept, block marks failed" \
  || no "non-fatal (rc=$rc): $out"

# (c) no images on the page -> exit 0 with a notice, nothing written
rm -rf "$WS/evidence"
out="$(FAKE_PAGE=none CAPTURE_CLAUDE_BIN="$WS/bin/fakeclaude-ok" \
        bash "$SCRIPT" "https://example.com/post.html" s3 2>"$WS/err")"; rc=$?
{ [ "$rc" = 0 ] && grep -qi "no embedded filing images" "$WS/err" \
  && [ ! -d "$WS/evidence/snapshots/s3" -o -z "$(ls -A "$WS/evidence/snapshots/s3" 2>/dev/null)" ]; } \
  && ok "no images -> exit 0 + notice, nothing written" \
  || no "no-images (rc=$rc): err='$(cat "$WS/err")'"

# (d) bad slug (contains a slash) -> validation error
FAKE_PAGE=with bash "$SCRIPT" "https://example.com/post.html" "bad/slug" 2>"$WS/err"; rc=$?
{ [ "$rc" != 0 ] && grep -qi "slug must be" "$WS/err"; } \
  && ok "bad slug -> validation error" || no "bad-slug (rc=$rc): $(cat "$WS/err")"

# (e) post fetch returns a non-2xx (login-wall / moved / blocked) -> die loudly, not a silent
# "no embedded filing images" false-success. Nothing should be written.
rm -rf "$WS/evidence"
out="$(FAKE_PAGE=walled CAPTURE_CLAUDE_BIN="$WS/bin/fakeclaude-ok" \
        bash "$SCRIPT" "https://example.com/post.html" s4 2>"$WS/err")"; rc=$?
{ [ "$rc" != 0 ] && grep -qi "http 403" "$WS/err" \
  && [ ! -d "$WS/evidence/snapshots/s4" -o -z "$(ls -A "$WS/evidence/snapshots/s4" 2>/dev/null)" ]; } \
  && ok "post fetch http 403 -> die, no silent false-success" \
  || no "walled post (rc=$rc): out='$out' err='$(cat "$WS/err")'"

exit "$fail"

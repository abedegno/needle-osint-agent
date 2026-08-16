#!/usr/bin/env bash
# Test for capture-evidence.sh — the crawl4ai default track must report WHY a capture
# failed (curl exit / HTTP status / response-body snippet), not one opaque message.
# Drives the script with a `curl` PATH shim; no network. Run with the sandbox disabled
# (needs a writable temp dir).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SCRIPT="$HERE/../bin/capture-evidence.sh"
fail=0
ok(){ printf '  \033[32m✅\033[0m %s\n' "$1"; }
no(){ printf '  \033[31m❌\033[0m %s\n' "$1"; fail=1; }
skip(){ printf '  \033[33m⏭\033[0m  SKIP: %s — run with the sandbox disabled\n' "$1"; exit 77; }

for t in mktemp jq file sha256sum wc python3; do command -v "$t" >/dev/null 2>&1 || skip "missing '$t'"; done
WS="$(mktemp -d 2>/dev/null)" || true
{ [ -n "$WS" ] && [ -d "$WS" ]; } || skip "cannot create a temp workspace (mktemp blocked)"
trap 'rm -rf "$WS"' EXIT

# A fake `curl` whose behaviour is selected by $FAKE_CURL_MODE. Parses -o <file> and
# detects the POST (the arg literally "POST" appears with -X POST).
mkdir -p "$WS/bin"
cat > "$WS/bin/curl" <<'CURL'
#!/usr/bin/env bash
out=""; is_post=0; prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] && out="$a"
  [ "$a" = "POST" ] && is_post=1
  prev="$a"
done
case "$FAKE_CURL_MODE" in
  transport_fail) exit 7 ;;
  post_500)   [ "$is_post" = 1 ] && { [ -n "$out" ] && printf '%s' '{"error":"render failed: boom"}' > "$out"; printf '500'; } ;;
  no_artifact)[ "$is_post" = 1 ] && { [ -n "$out" ] && printf '%s' '{"error":"page blank"}' > "$out"; printf '200'; } ;;
  success)
    if [ "$is_post" = 1 ]; then
      [ -n "$out" ] && printf '%s' '{"artifact_id":"abc"}' > "$out"; printf '200'
    else
      python3 -c "import base64,sys; sys.stdout.buffer.write(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='))" > "$out"
      head -c 1100 /dev/zero >> "$out"; printf '200'
    fi ;;
esac
CURL
chmod +x "$WS/bin/curl"
export PATH="$WS/bin:$PATH"
export CRAWL4AI_API_TOKEN=test CRAWL4AI_HOST=http://fake.invalid

run(){ FAKE_CURL_MODE="$1" bash "$SCRIPT" "https://example.com/x" "$WS/out.png" 2>"$WS/err"; echo $?; }

# (a) transport failure → names the curl exit code
rc="$(run transport_fail)"; err="$(cat "$WS/err")"
{ [ "$rc" != 0 ] && printf '%s' "$err" | grep -qi "curl exit 7"; } \
  && ok "transport failure → reports curl exit code" || no "transport case (rc=$rc): $err"

# (b) POST HTTP 500 → names the status AND a body snippet
rc="$(run post_500)"; err="$(cat "$WS/err")"
{ [ "$rc" != 0 ] && printf '%s' "$err" | grep -qi "http 500" && printf '%s' "$err" | grep -qi "render failed"; } \
  && ok "POST 500 → reports http status + body snippet" || no "post_500 case (rc=$rc): $err"

# (c) 200 but no artifact_id → says so AND includes the error field
rc="$(run no_artifact)"; err="$(cat "$WS/err")"
{ [ "$rc" != 0 ] && printf '%s' "$err" | grep -qi "no artifact" && printf '%s' "$err" | grep -qi "page blank"; } \
  && ok "200/no-artifact → reports body snippet" || no "no_artifact case (rc=$rc): $err"

# (d) success → unchanged stdout contract: "<out.png> <size> <sha256>"
out="$(FAKE_CURL_MODE=success bash "$SCRIPT" "https://example.com/x" "$WS/out.png" 2>"$WS/err")"; rc=$?
{ [ "$rc" = 0 ] && printf '%s' "$out" | grep -Eq "out\.png [0-9]+ [0-9a-f]{64}"; } \
  && ok "success → unchanged <out> <size> <sha256> contract" || no "success case (rc=$rc): out='$out' err='$(cat "$WS/err")'"

# (e) bad extension → validated before any curl
FAKE_CURL_MODE=success bash "$SCRIPT" "https://example.com/x" "$WS/out.txt" 2>"$WS/err"; rc=$?
{ [ "$rc" != 0 ] && grep -qi "must end in .png or .pdf" "$WS/err"; } \
  && ok "bad extension → validation error" || no "bad-ext case (rc=$rc): $(cat "$WS/err")"

exit "$fail"

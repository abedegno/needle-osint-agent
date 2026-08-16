#!/usr/bin/env bash
# Test for extract-filing-image-urls.py — pure HTML->full-res-URL extraction (offline).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; EXTRACT="$HERE/../bin/lib/extract-filing-image-urls.py"
fail=0
ok(){ printf '  \033[32m✅\033[0m %s\n' "$1"; }
no(){ printf '  \033[31m❌\033[0m %s\n' "$1"; fail=1; }
skip(){ printf '  \033[33m⏭\033[0m  SKIP: %s\n' "$1"; exit 77; }
command -v python3 >/dev/null 2>&1 || skip "python3 missing"

run(){ printf '%s' "$1" | python3 "$EXTRACT" "https://example.blogspot.com/post.html"; }

# (a) in-post image: s640 thumbnail wrapped in an <a href> to s1600 -> full-res /s0/
html='<div class="post-body"><a href="https://1.bp.blogspot.com/-x/AAA/BBB/s1600/filing.jpg"><img src="https://1.bp.blogspot.com/-x/AAA/BBB/s640/filing.jpg"></a></div>'
out="$(run "$html")"
printf '%s\n' "$out" | grep -q '/s0/filing.jpg' \
  && ok "path-form thumbnail -> /s0/ full-res" || no "path-form: '$out'"

# (b) suffix-form googleusercontent =s400 -> =s0
out="$(run '<img src="https://blogger.googleusercontent.com/img/a/ZZZ=s400">')"
printf '%s\n' "$out" | grep -q '=s0' \
  && ok "suffix-form =s400 -> =s0" || no "suffix-form: '$out'"

# (c) small avatar/icon (s72) -> skipped (chrome, not a filing)
out="$(run '<img src="https://1.bp.blogspot.com/-y/CCC/DDD/s72/avatar.jpg">')"
[ -z "$out" ] && ok "small s72 avatar skipped" || no "avatar not skipped: '$out'"

# (d) generic non-Blogger .png -> passthrough
out="$(run '<img src="https://example.com/photos/document.png">')"
printf '%s\n' "$out" | grep -q 'example.com/photos/document.png' \
  && ok "generic .png passthrough" || no "generic: '$out'"

# (e) no images -> empty output
out="$(run '<p>no pictures here</p>')"
[ -z "$out" ] && ok "no images -> empty output" || no "no-images: '$out'"

# --- SSRF / local-file-read guard: only public http(s) URLs may be emitted ---

# (f) file:// scheme (local file read) -> rejected
out="$(run '<img src="file:///etc/hosts.png">')"
[ -z "$out" ] && ok "file:// scheme rejected" || no "file:// not rejected: '$out'"

# (g) link-local / cloud-metadata IP -> rejected
out="$(run '<img src="http://169.254.169.254/x.png">')"
[ -z "$out" ] && ok "link-local 169.254.169.254 rejected" || no "link-local not rejected: '$out'"

# (h) RFC1918 private IP -> rejected
out="$(run '<img src="http://192.168.0.1:11235/x.png">')"
[ -z "$out" ] && ok "RFC1918 192.168.0.1 rejected" || no "RFC1918 not rejected: '$out'"

# (i) localhost hostname -> rejected
out="$(run '<img src="http://localhost:8080/x.jpg">')"
[ -z "$out" ] && ok "localhost hostname rejected" || no "localhost not rejected: '$out'"

# (i2) non-canonical numeric IPv4 forms that the OS resolver maps to 127.0.0.1 -> rejected
# (ipaddress.ip_address only accepts canonical dotted-quad, so these must be caught separately).
out="$(run '<img src="http://2130706433/x.png">')"
[ -z "$out" ] && ok "decimal-int host 2130706433 rejected" || no "decimal-int not rejected: '$out'"
out="$(run '<img src="http://0x7f000001/x.png">')"
[ -z "$out" ] && ok "hex host 0x7f000001 rejected" || no "hex host not rejected: '$out'"
out="$(run '<img src="http://127.1/x.png">')"
[ -z "$out" ] && ok "short-form host 127.1 rejected" || no "short-form not rejected: '$out'"

# (j) normal Blogger URL -> still emitted (guard doesn't over-block safe hosts)
out="$(run '<img src="https://blogger.googleusercontent.com/img/a/ZZZ=s600">')"
printf '%s\n' "$out" | grep -q 'blogger.googleusercontent.com' \
  && ok "safe blogger URL still emitted" || no "safe blogger URL missing: '$out'"

# (k) public generic https URL -> still emitted (guard doesn't over-block safe hosts)
out="$(run '<img src="https://example.com/photos/x.png">')"
printf '%s\n' "$out" | grep -q 'example.com/photos/x.png' \
  && ok "safe public URL still emitted" || no "safe public URL missing: '$out'"

# --- size decision must follow the resolved full-res href, not the thumbnail src (the 0-for-61 bug) ---

# (l) a real blog filing: s320 thumbnail <img src> wrapped in a full-res <a href> (s2028) -> emitted.
#     Sizing the s320 thumbnail wrongly drops the filing; the size must come from the full-res href.
html='<a href="https://blogger.googleusercontent.com/img/b/R29vZ2xl/AAA/s2028/20260121_105332.jpg"><img src="https://blogger.googleusercontent.com/img/b/R29vZ2xl/AAA/s320/20260121_105332.jpg"></a>'
out="$(run "$html")"
printf '%s\n' "$out" | grep -q '/s0/20260121_105332.jpg' \
  && ok "filing with s320 thumbnail + full-res href -> emitted" || no "filing dropped: '$out'"

# (m) 72px multi-suffix avatar token (w72-h72-p-k-no-nu, no full-res href) -> skipped as chrome.
#     inline_size must parse the multi-suffix token (else it returns None and the avatar leaks through).
out="$(run '<img src="https://blogger.googleusercontent.com/img/b/R29vZ2xl/AAA/w72-h72-p-k-no-nu/20200906_110817.jpg">')"
[ -z "$out" ] && ok "72px multi-suffix avatar skipped" || no "avatar leaked: '$out'"

exit "$fail"

#!/usr/bin/env python3
# extract-filing-image-urls.py — read an HTML page on stdin and print the full-resolution URL
# of each embedded content image, one per line. Blogger serves a downscaled thumbnail inline
# and links (or size-encodes) the original larger; resolve to full-res (s0). Skip small chrome
# (avatars/icons) by inline size. Pure function of (html, base-url) -> URL list; no network.
# Usage:  curl -sSL <post-url> | extract-filing-image-urls.py [base-url]
import sys, re, ipaddress
from html.parser import HTMLParser
from urllib.parse import urljoin, urlsplit

BLOGGER_HOSTS = ("bp.blogspot.com", "blogger.googleusercontent.com", "googleusercontent.com")
MIN_SIZE = 400  # inline thumbnails below this are chrome (avatars, icons), not filings

def is_blogger(url):
    return any(h in url for h in BLOGGER_HOSTS)

def is_safe_url(url):
    # Only harvest public http(s) URLs. Reject file:// (LFI) and anything that resolves to
    # loopback/link-local/RFC1918/0.0.0.0 (SSRF against localhost or cloud metadata endpoints).
    # DNS-rebinding via a non-IP-literal hostname is out of scope for this threat model.
    try:
        parts = urlsplit(url)
    except ValueError:
        return False
    if parts.scheme not in ("http", "https"):
        return False
    host = parts.hostname
    if not host:
        return False
    host_l = host.lower()
    if host_l == "localhost" or host_l.endswith(".localhost"):
        return False
    try:
        ip = ipaddress.ip_address(host_l)
    except ValueError:
        # Not a canonical dotted-quad/IPv6 literal. But the OS resolver still maps non-canonical
        # numeric forms (decimal 2130706433, hex 0x7f000001, octal 017700000001, short 127.1) to
        # internal IPs — a full SSRF bypass. Reject any purely-numeric/hex host; no real hostname
        # is numeric-only, so this never over-blocks a legitimate DNS name.
        if re.fullmatch(r'(0[xX][0-9a-fA-F]+|[0-9]+)(\.(0[xX][0-9a-fA-F]+|[0-9]+)){0,3}', host_l):
            return False
        return True  # not an IP literal; treat as an ordinary public hostname
    if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_unspecified or ip.is_reserved:
        return False
    return True

def inline_size(url):
    # Size segments carry zero or more trailing option flags, e.g. `/s320/`, `/s1600-c/`,
    # `/w72-h72-p-k-no-nu/`. Allow MULTIPLE `-flag` suffixes — a single-optional-suffix regex
    # fails to parse `w72-h72-p-k-no-nu`, returns None, and lets 72px chrome through.
    m = re.search(r'/(?:s(\d+)|w(\d+)-h(\d+))(?:-[a-z0-9]+)*/', url)
    if not m:
        m = re.search(r'=(?:s(\d+)|w(\d+)-h(\d+))', url)
    if not m:
        return None
    nums = [int(x) for x in m.groups() if x]
    return max(nums) if nums else None

def to_fullres(url):
    url = re.sub(r'/(?:s\d+|w\d+-h\d+)(?:-[a-z0-9]+)*/', '/s0/', url)
    url = re.sub(r'=(?:s\d+|w\d+-h\d+)(?:-[a-z0-9]+)*$', '=s0', url)
    return url

class ImgParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.href = None
        self.urls = []
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "a":
            self.href = a.get("href")
        elif tag == "img":
            src = a.get("src") or a.get("data-src")
            if not src:
                return
            # Prefer the enclosing <a href> when it points to the same image host: Blogger wraps
            # a downscaled thumbnail (<img src>, e.g. /s320/) in a link to the FULL-RESOLUTION
            # image (<a href>, e.g. /s2028/). Size the CANDIDATE we will actually emit, not the
            # thumbnail — sizing the /s320/ thumbnail wrongly drops real filings whose full-res
            # href is large (this was the 0-for-61-filings bug).
            cand = self.href if (self.href and is_blogger(self.href)) else src
            sz = inline_size(cand)
            if sz is not None and sz < MIN_SIZE:
                return
            self.urls.append(cand)
    def handle_endtag(self, tag):
        if tag == "a":
            self.href = None

def main():
    base = sys.argv[1] if len(sys.argv) > 1 else ""
    parser = ImgParser()
    parser.feed(sys.stdin.read())
    seen, out = set(), []
    for u in parser.urls:
        if base:
            u = urljoin(base, u)
        if is_blogger(u):
            u = to_fullres(u)
        elif not re.search(r'\.(?:jpe?g|png|webp|tiff?)(?:\?|$)', u, re.I):
            continue  # non-Blogger, not an obvious image file -> skip
        if not is_safe_url(u):
            continue  # not a public http(s) URL -> skip (SSRF/LFI guard)
        if u not in seen:
            seen.add(u)
            out.append(u)
    for u in out:
        print(u)

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""capture-stealth.py — screenshot a URL via the CloakBrowser (anti-detect Chrome) over CDP,
bypassing crawl4ai. For fingerprint/webdriver-walled pages. Writes a full-page PNG to <output>.
Exits non-zero with a clear stderr message on any failure (caller validates the file bytes)."""
import os, sys
CLOAK_CDP = os.environ.get("CLOAK_CDP_URL", "http://localhost:9222")

def die(msg):
    print(f"capture-stealth: ERROR: {msg}", file=sys.stderr); sys.exit(1)

if len(sys.argv) != 3:
    die("usage: capture-stealth.py <url> <output.png>")
url, out = sys.argv[1], sys.argv[2]
if not out.endswith(".png"):
    die("output must be .png")
try:
    from playwright.sync_api import sync_playwright
except ImportError:
    die("playwright not installed on the runner")
try:
    with sync_playwright() as p:
        browser = p.chromium.connect_over_cdp(CLOAK_CDP)
        ctx = browser.contexts[0] if browser.contexts else browser.new_context()
        page = ctx.new_page()
        try:
            page.goto(url, wait_until="domcontentloaded", timeout=45000)
            page.wait_for_timeout(3000)
            page.screenshot(path=out, full_page=True)
        finally:
            page.close()
        browser.close()
except Exception as e:
    die(f"{type(e).__name__}: {str(e)[:160]}")

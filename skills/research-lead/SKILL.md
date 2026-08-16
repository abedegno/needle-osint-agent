---
name: research-lead
description: Researcher procedure — discover sources with SearXNG, fetch and snapshot them (text via crawl4ai MCP, screenshots/PDF via shell), extract PDF text, and return a sourced report for one lead. Collect, don't conclude.
---

# research-lead

For ONE lead (entity + question). Methodology source of truth:
`omnigent/skills/osint-investigation`.

1. **Discover.** `searxng_web_search` for the entity/question. Prefer registries
   (ASIC/ABN Lookup, KvK, Companies House, US SoS), official sites, press, court
   records. Collect candidate URLs.
2. **Fetch + snapshot.** For each source you rely on, save the capture under
   `evidence/snapshots/` (the ONLY path you may write); record the retrieval date.
   - **Text is the DEFAULT snapshot — do NOT screenshot routine pages.** The crawl4ai `md` capture below
     IS the citeable snapshot for almost every source. Reserve a screenshot/PDF (via the helper) ONLY when
     the *rendered page itself* is the evidence — a register record, a listing, a filing image, or to
     evidence a visible wall/absence. A screenshot is the exception, not a per-source step.
   - **Text:** crawl4ai `md` (and `html` where DOM fidelity matters) via the MCP tool.
   - **Evidence capture (screenshots & page-PDFs) — use the helper, never the MCP tool.**

         omnigent/bin/capture-evidence.sh <url> evidence/snapshots/<src-ULID>_<name>.png    # screenshot
         omnigent/bin/capture-evidence.sh <url> evidence/snapshots/<src-ULID>_<name>.pdf    # page as PDF

     Evidence filenames embed the source id (ULID). It captures via crawl4ai, lands the real bytes in 
     `evidence/snapshots/`, validates them, and EXITS NON-ZERO with a clear error on failure (so a failed 
     capture cannot pass unnoticed). On success it prints `<path> <bytes> <sha256>` — record that path + 
     sha256 in `dossier/sources/register.yaml` (`archive_url:` = the captured file path).

     **NEVER use `mcp__crawl4ai__screenshot` or `mcp__crawl4ai__pdf`.** They run inside the crawl4ai container,
     write to a path the runner cannot read, and return `success:true` anyway. Use
     `mcp__crawl4ai__md`/`html`/`crawl` for page TEXT only.

     **Fingerprint/bot-walled page?** Add `--stealth` —
     `omnigent/bin/capture-evidence.sh --stealth <url> evidence/snapshots/<src-ULID>_<name>.png` — it captures via the
     CloakBrowser (undetected browser). Use it when a page shows a captcha/Cloudflare/`webdriver` block.
     (Stealth defeats fingerprint detection only — not SPA form-interaction or captchas.)

   - **Photographed court filings embedded in a page — capture + transcribe them.** When a
     source post embeds *photos/scans of court documents* (e.g. an investigative blog post), run:

         omnigent/bin/capture-filing-images.sh <post-url> <slug>    # e.g. slug example-blog_2026-01-21_filings

     It saves each filing image to `evidence/snapshots/<slug>/filing-NN.<ext>`, writes an
     AI-assisted transcription companion `filing-NN.md`, and prints a `register.yaml` block per
     image. **The image is the citeable evidence; the transcription is AI-assisted — cite it as
     such and verify against the image.** Paste the emitted block(s) into the register; treat
     `[illegible]`/`[uncertain]` spans as non-load-bearing. Not for routine pages — only pages
     whose embedded photographed filings ARE the evidence.

3. **Stealth fallback (bot walls).** If a fetch is blocked/empty/CAPTCHA/Cloudflare/truncated
   (common on CIPO, IP Australia, some registries), capture a `--stealth` PNG snapshot:
   `omnigent/bin/capture-evidence.sh --stealth <url> evidence/snapshots/<src-ULID>_<name>.png` — the only
   sanctioned stealth path (crawl4ai rejects caller `cdp_url`). The PNG counts as a real source.
   Note in your report that it was a stealth fetch. Only when a normal fetch fails — don't
   route everything through it.
4. **Extract PDF text.** For every PDF you saved under `evidence/snapshots/`:
   - `pdftotext evidence/snapshots/<name>.pdf evidence/snapshots/<name>.txt` — the `.txt` is the
     citeable snapshot (cite its text, not a hand-summary).
   - If the `.txt` is empty/negligible (image-only/scanned), OCR it:
     `pdftoppm -png -r 200 evidence/snapshots/<name>.pdf /tmp/<name>` then
     `tesseract /tmp/<name>-1.png evidence/snapshots/<name> -l eng` (repeat per page as needed).
   - `sha256sum evidence/snapshots/<name>.pdf` — report the `.txt` path + this SHA256.
5. **Report.** Per claim: claim text, source URL, retrieval date, snapshot path (the `.md`/`.png`/
   `.txt`), primary/secondary, and whether a stealth fetch was used. For PDFs, give the `.txt` path
   + the binary SHA256. List what you could not find. Do not grade or conclude.

## Structured registry/court APIs (preferred over scraping)

For these sources, call the API helper FIRST — it returns structured JSON, archives a citeable
snapshot, and never silently fails. Only fall back to crawl4ai/searxng/`capture-evidence.sh` if the
API can't answer.

- **UK companies** (officers, PSC/ownership, filing history): `omnigent/bin/companies-house.sh
  <search|profile|officers|psc|filings> <arg>` — e.g. `companies-house.sh psc 01234567`.
- **US trademarks** (status, owner of record): `omnigent/bin/uspto-tsdr.sh status <serial|registration>`.
- **US court dockets / RECAP**: `omnigent/bin/courtlistener.sh <search|docket|recap> <arg>`.
- **Global corporate hierarchy (LEI / who-owns-whom)**: `omnigent/bin/gleif.sh
  <search|record|parent|children> <arg>` — `search "<legal name>"` → LEI; `record <LEI>`,
  `parent <LEI>`, `children <LEI>` give the official parent↔child structure. Free, no key.
  `parent`/`children` print "no direct parent/children on record" (and still archive) when none.
- **UK insolvency / disqualification / strike-off (The Gazette)**: `omnigent/bin/gazette.sh
  search "<text>"` — official UK public-record notice search. Free, no key. **Default stdout (after the
  `path sha summary` line) is a tidy `{total, notices:[{code,title,name,date,link}]}` view — read that
  directly.** Pass `--jq FILTER` only to query the raw archived Atom body (where `.["f:total"]` is a JSON
  **string** — `|tonumber` to compare numerically).

Each prints `<evidence-path> <sha256> <summary>`. Record that source in `register.yaml` (endpoint +
evidence path + SHA256 + retrieval date) and cite the archived JSON. Use `--jq '<filter>'` to pull
specific fields. A non-zero exit is a real failure (bad key, 404, rate-limit) — read the message.

---
name: verify-finding
description: Verifier procedure — SIFT each finding, try to refute it, require an independent second source (text via crawl4ai MCP, screenshots/PDF via shell), and assign confidence A/B/C/D. Return verdicts; record nothing.
---

# verify-finding

For each claimed finding. Methodology source of truth:
`omnigent/skills/osint-investigation`.

1. **SIFT.** Who publishes the source? Primary or secondary? What incentive?
2. **Refute.** Actively search for contradicting evidence.
3. **Corroborate.** Find an INDEPENDENT second source (`searxng_web_search`), fetch/snapshot it
   into `evidence/snapshots/`:
   - **Independence is provenance-tiered — required for any source you will grade ≥ B:**
     - *High-trust API archive* (`companies-house.sh` / `courtlistener.sh` / `uspto-tsdr.sh` output —
       content-addressed, endpoint + sha256 + date recorded): **accept it.** It is self-authenticating;
       no re-fetch needed (a cheap re-call as a spot-check is optional).
     - *Web scrape / snapshot* (`crawl4ai` / `searxng` of an arbitrary page): perform **your own live
       fetch** (the source URL, or a distinct corroborating URL) and snapshot it — **re-reading the
       researcher's snapshot does NOT count** as independent confirmation.
     - *Binary-only primary* (a filed PDF / iXBRL with no distinct second source): the minimum
       independent step is a live `companies-house.sh` existence/metadata check confirming the filing
       exists.
   - **Text:** crawl4ai `md`/`html` via the MCP tool.
   - **Corroborating-evidence capture:** screenshot/page-PDF only via
     `omnigent/bin/capture-evidence.sh <url> evidence/snapshots/<src-ULID>_<name>.(png|pdf)` (record the printed path +
     sha256 in `register.yaml`). Evidence filenames embed the source id (ULID). Never use `mcp__crawl4ai__screenshot`/`pdf` — inaccessible container path + false success.

     **Fingerprint/bot-walled page?** Add `--stealth` —
     `omnigent/bin/capture-evidence.sh --stealth <url> evidence/snapshots/<src-ULID>_<name>.png` — it captures via the
     CloakBrowser (undetected browser). Use it when a page shows a captcha/Cloudflare/`webdriver` block.
     (Stealth defeats fingerprint detection only — not SPA form-interaction or captchas.)
   - If the source is **bot-walled** (captcha / Cloudflare / `webdriver`), capture a `--stealth` PNG:
     `omnigent/bin/capture-evidence.sh --stealth <url> evidence/snapshots/<src-ULID>_<name>.png` — the only sanctioned
     stealth path (crawl4ai rejects caller `cdp_url`). The PNG counts as a real corroborating source; note it.
4. **Grade.** A = 2+ independent primary/authoritative; B = 1 solid primary or 2 weak/secondary;
   C = single uncorroborated; D = inference/rumour. Never A/B on a single source. Do not assign A/B
   unless each load-bearing source is independently established per step 3's tiers; a ≥B resting only
   on an unconfirmed low-trust scrape caps at **C**.
5. **Return** per finding: grade, one-line justification, corroborating source URL + snapshot path
   (`.md`/`.png`/`.txt`; + PDF SHA256). Flag fabrication or anything uncorroborated.

## Structured registry/court APIs (preferred over scraping)

For these sources, call the API helper FIRST — it returns structured JSON, archives a citeable
snapshot, and never silently fails. Only fall back to crawl4ai/searxng/`capture-evidence.sh` if the
API can't answer.

- **UK companies** (officers, PSC/ownership, filing history): `omnigent/bin/companies-house.sh
  <search|profile|officers|psc|filings> <arg>` — e.g. `companies-house.sh psc 01234567`.
- **US trademarks** (status, owner of record): `omnigent/bin/uspto-tsdr.sh status <serial|registration>`.
- **Trademarks by OWNER or brand name (worldwide)**: `omnigent/bin/wipo-trademark.sh <owner|brand|mark> <query>`
  — WIPO Global Brand DB (UK national + Madrid + many offices); e.g. `wipo-trademark.sh owner "Example Holdings"` lists
  that owner's whole mark portfolio. The way to enumerate a person/company's trademarks by name.
- **US court dockets / RECAP**: `omnigent/bin/courtlistener.sh <search|docket|recap> <arg>`.

Each prints `<evidence-path> <sha256> <summary>`. Record that source in `register.yaml` (endpoint +
evidence path + SHA256 + retrieval date) and cite the archived JSON. Use `--jq '<filter>'` to pull
specific fields. A non-zero exit is a real failure (bad key, 404, rate-limit) — read the message.

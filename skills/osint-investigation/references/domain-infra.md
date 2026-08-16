# Domain & infrastructure OSINT

Goal: link entities through shared digital infrastructure and recover content that may
be taken down.

## WHOIS / RDAP
- Registrant, registrar, creation/expiry/update dates, name servers. Many registrants
  are privacy-shielded — record the registrar and dates regardless; historical WHOIS
  (e.g. via archived records) may predate privacy shielding.

## DNS
- A/AAAA, MX, NS, TXT (SPF/DKIM hint at the mail provider). Shared name servers or mail
  hosts across domains are weak-to-moderate links.

## Reverse IP / hosting
- Other domains on the same IP/host can reveal sibling sites (note: shared hosting is
  weak evidence — grade accordingly).

## Certificate transparency
- crt.sh — historical certs reveal subdomains and sometimes sibling domains sharing a
  SAN list.

## Shared identifiers (strong links)
- Google Analytics / AdSense / Tag Manager IDs, Facebook pixel IDs reused across sites
  are strong evidence of common operators. Find them in page source or archived pages.

## Archived content (recover the vanished)
- **Wayback Machine** (web.archive.org) — historical snapshots; `web.archive.org/save/`
  to create a fresh snapshot.
- **archive.today** — independent snapshots.
- **crawl4ai** — capture current pages into `evidence/snapshots/` as primary evidence.

## Applying this to the current case
- Compare registrants, analytics IDs, and hosting across the target's known
  domains (e.g. example.com, example.co.uk, example-group.com) to test whether
  one operator runs all of them.

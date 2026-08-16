# Corporate registries — per-jurisdiction how-to

Goal: for each company, capture **directors, owners/shareholders, incorporation date,
registered address, current status**, and any prior names. Cross-check officers and
addresses against other entities to find links.

## Australia (AU)
- **ASIC Connect** (asic.gov.au) — company/business name search by ACN/ABN. Free
  search; extracts (officers, addresses) are paid.
- **ABN Lookup** (abr.business.gov.au) — validate ABN/ACN, entity name, GST status,
  registration dates. Free. Note: a valid ABN is 11 digits; mismatches are a flag.
- A **TFN (Tax File Number)** is confidential and must never appear publicly — its
  presence on a public document is itself a finding.

## Netherlands (NL)
- **KvK (Kamer van Koophandel)** (kvk.nl) — Dutch business register. Search by name;
  extracts (uittreksel) list directors, registered address, SBI activity codes.

## United Kingdom (UK)
- **Companies House** (find-and-update.company-information.service.gov.uk) — free, rich:
  officers, persons with significant control (PSC/beneficial owners), filing history,
  registered address, dissolution. A future MCP candidate.

## United States (US)
- State **Secretary of State** business search (incorporation is state-level): e.g.
  Florida (Sunbiz), California (bizfileOnline), New York (apps.dos.ny.gov). Capture
  registered agent + officers; registered agents often link shells.

## Cross-jurisdiction
- **OpenCorporates** (opencorporates.com) — aggregates many registries; good for
  finding the same officer/name across countries.
- **GLEIF** (search.gleif.org) — Legal Entity Identifiers, parent/child relationships.

## Red flags to record as findings
- Virtual-office / mass-registration registered addresses shared by many companies.
- Mobile-only or no phone for a "head office".
- Officer appearing across multiple entities/jurisdictions.
- Malformed/contradictory identifiers (e.g. ABN with wrong digit count).

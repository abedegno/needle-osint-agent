# Source verification, archiving & grading

## SIFT (apply to every source)
1. **Stop** — note your purpose and the claim before trusting the page.
2. **Investigate the source** — who publishes it? Primary (registry, the company itself,
   a court) or secondary (press, forum)? What is their incentive?
3. **Find better/other coverage** — seek independent corroboration of the claim.
4. **Trace** — follow quotes/data to the original. Don't cite the aggregator; cite the
   origin.

## Archive BEFORE you rely
For every web source, before recording a claim from it:
1. Capture with crawl4ai into `evidence/snapshots/` (markdown + screenshot where useful).
2. Submit to Wayback: `https://web.archive.org/save/<URL>` and record the resulting
   snapshot URL as `archive_url` in the register.
3. Record a `sha256` of the captured artifact.

## Grading (assign on every claim/record/edge)
- **A** confirmed — 2+ independent primary/authoritative sources agree.
- **B** probable — 1 solid primary source, or 2 weak/secondary.
- **C** unverified — single uncorroborated source.
- **D** inference — analyst reasoning, not directly evidenced.
Downgrade when corroboration fails; upgrade only when new independent sources confirm.

## Fact vs inference vs allegation
- **Fact** — directly supported by a cited source.
- **Inference** — your reasoning from facts; label it, grade it D until evidenced.
- **Allegation** — a claim of wrongdoing. Attribute it precisely ("records indicate",
  "X alleges in [filing]") and don't record it as *established* guilt — that's accuracy,
  not defamation caution. Name the individuals plainly; this is private research, not a
  publication.

## Correction protocol
If a recorded finding is later disproven: keep it, strike it through, and add a dated
correction note explaining what changed and why. Never silently delete.

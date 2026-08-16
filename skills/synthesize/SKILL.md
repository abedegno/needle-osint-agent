---
name: synthesize
description: Analyst procedure — read verified findings + relationships and propose new edges and new leads. Read-only; conservative grading.
---

# synthesize

Read-only over the run's VERIFIED findings + `dossier/relationships.yaml` + entity
records. Do not fetch or edit.

1. **New nodes + edges.** Propose **person nodes** (`dossier/people/<id>.md`) for named
   individuals surfaced across the findings, plus edges — shared address/phone/email/
   officer/director/domain/infra — between entities AND people (person↔entity,
   person↔person, entity↔entity). Per edge: from-id, to-id, type, confidence (A/B/C/D),
   supporting source ids.
2. **New leads.** Per lead: target (or null), concrete question, type
   (registry/infra/corroboration/osint/social), priority 1–5, one-line rationale.
3. Be conservative — only what the verified evidence supports; weak inferences are
   C/D. Return both lists for the coordinator to merge (leads are for the NEXT run).

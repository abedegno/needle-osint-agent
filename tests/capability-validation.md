# osint_investigator — capability-track validation suite

Acceptance tests for the 2026-06-19 capability track (BL-2…BL-5 + the methodology/PII
reframe). These bundle skills are **markdown, not code** — there are no unit tests; validation
is a **supervised run** plus **scripted artifact checks**.

Each test has two halves:

1. **Driver prompt** — paste into a launched `osint_investigator` session (pick the
   `<your-workspace>` workspace folder). Keep them small; they are smoke tests, not a drain.
2. **Verification** — run the scripted checks against the session's workspace on the runner.
   The transcript claiming success is **not** enough — the artifact must exist on disk.

## Running the verification

Run the whole gate at once: `./omnigent.sh exec "cd /workspaces/<your-workspace> && bash omnigent/tests/run-capability-suite.sh"` (rolls up harness-selftest + verify-register + crawl4ai-auth + companies-house).

After a validation session, on the runner (which sees `/workspaces` and `CRAWL4AI_API_TOKEN`):

```bash
# filesystem artifacts (VT-1..VT-3) — point at the session's workspace root:
./omnigent.sh exec "cd /workspaces/<your-workspace> && \
  omnigent/tests/verify-artifacts.sh ."

# crawl4ai auth wiring (VT-4) — infrastructure, needs no session:
./omnigent.sh exec "cd /workspaces/<your-workspace> && \
  omnigent/tests/verify-crawl4ai-auth.sh"
```

`verify-artifacts.sh` exits non-zero if any structural check fails. The real-name / no-pseudonym
judgement (VT-3) is a **manual** review — the script flags it; it cannot assert it.

---

## VT-1 — Screenshot capture (BL-3: authed crawl4ai REST shell, no base64 in context)

**Driver prompt:**

> Capture a screenshot of https://example.com to `evidence/snapshots/` and tell me the file path
> and its size in bytes. Do not paste any base64.

**Pass:** a real `evidence/snapshots/*.png` on disk (valid PNG magic, > 1 KB); **no base64 blob in
the transcript**. The bytes flowed `curl → jq → base64 -d → file`, bypassing the agent context.

**Verify:** `verify-artifacts.sh` VT-1 (PNG magic + size). The "no base64 in transcript" half is a
manual transcript scan.

## VT-2 — PDF→text pipeline (BL-5: pdftotext/OCR + register.yaml pointer)

**Driver prompt:**

> Download https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf into
> `evidence/snapshots/`, extract its text to a `.txt` snapshot, and record the text path + the
> binary's SHA256 in `dossier/sources/register.yaml`. Show me the `.txt` contents and the register
> entry.

**Pass:** `dummy.txt` present and non-empty (readable text); `register.yaml` carries a SHA256 + the
text-snapshot path; the binary is kept. (Image-only PDFs should fall back to `tesseract` OCR.)

**Verify:** `verify-artifacts.sh` VT-2 (`.txt` beside each `.pdf`, `register.yaml` has a sha256).

## VT-3 — People are first-class + real names (methodology/PII reframe)

**Driver prompt:**

> Take one named individual already in this case's dossier, create `dossier/people/<id>.md` for them
> using their real name (no pseudonym), and link the findings that mention them under
> `dossier/findings/`. Show me the files you created.

**Pass:** a `dossier/people/<id>.md` recording the **real name** (not corporate-only, not
pseudonymised), a `dossier/findings/<slug>.md`, cross-linked. Confirms "publication-grade caution
applies only to what is published, not the research."

**Verify:** `verify-artifacts.sh` VT-3 asserts `people/` and `findings/` are non-empty. The
**real-name / no-pseudonym** judgement is a **manual** review of the `people/` files.

## VT-4 — Verifier reaches crawl4ai authed (crawl4ai 0.9.0 bearer header, the 401 fix)

**Driver prompt (optional — VT-4 is mostly infra):**

> Have the verifier corroborate one existing finding by fetching its primary source via crawl4ai.
> Report the HTTP status of the crawl4ai call.

**Pass:** the fetch succeeds, **no 401** — the codex/verifier bearer header is wired through on 0.9.0.

**Verify:** `verify-crawl4ai-auth.sh` — unauthenticated request → `401` (auth is on), authenticated
request → `success: true` with an inline base64 screenshot.

---

## Combined smoke (one run instead of four)

> Research the person `<name>`: fetch their primary source page, screenshot it to
> `evidence/snapshots/`, create their `dossier/people/` entry with their real name, and link one
> finding. Summarise what you wrote to disk.

Then run both verify scripts. This exercises VT-1, VT-2 (if the source is a PDF), VT-3, and VT-4 in
a single pass.

## Caveat

The concurrency design is **unexecuted** — a validation run still uses the as-is 6-wide fan-out.
Keep these prompts narrow so they don't trigger a full drain.

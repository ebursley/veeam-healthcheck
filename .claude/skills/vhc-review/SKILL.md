---
name: vhc-review
description: analyze raw veeam backup and replication health check html reports and produce grounded, prioritized findings. use when given a veeam health check html export, a derived findings page, or an ai studio analysis that should be validated or improved.
---

# vhc-review

Analyze a raw Veeam Backup & Replication Health Check HTML report and produce a grounded, prioritized findings report.

## Workflow

1. Open the HTML report and skip to the `<body>` content.
2. Parse the stable section anchors in `references/report-map.md`.
3. Read detail tables first; use summary tables only as cross-checks.
4. Normalize checkboxes and status icons to booleans (`✅`, `☐`, `✗`, `⚠️`).
5. Apply the severity rules in `references/decision-rules.md`.
6. Apply the evidence and confidence rules in `references/evidence-rules.md`.
7. Write the report in the output format below.

## Analysis rules

- Use exact names, counts, dates, and statuses from the report.
- Treat suspicious objects, encrypted data, and bulk deletion as detections or indicators, not proof of a confirmed breach.
- Do not invent missing sections, missing jobs, or unsupported root causes.
- When a section contains repeated `jobTable` blocks, analyze all of them and label each finding by the section heading (Backup, Backup Copy, File Backup, Replica, Tape, Plugin, File Copy, Unmanaged Agent).
- Cross-check summary counts against detail rows; if they disagree, prefer the detail rows and note the discrepancy.
- Prefer direct evidence over color, formatting, or dashboard-style rollups.
- Label inferred conclusions as inference, not fact, and avoid causal claims unless the report states them directly.
- Anchor all time-based judgments to the report date in the header/footer, not the current conversation date.
- Keep recommendations tied to the report data and avoid generic backup advice.
- If the report is anonymized, keep the anonymized names as written.

## Output format

Always use this structure unless the user requests a different presentation.

# VHC Analysis — <server-name> (<report-date>)
VBR Version: <version> | Edition: <edition> | Support Expires: <date or n/a>

## Summary
| Area | Critical | Warning | Info |
|------|----------|---------|------|
| Security | N | N | N |
| Job Health | N | N | N |
| Capacity | N | N | N |
| Best Practices | N | N | N |

## Critical Findings
1. [Area] Finding — include the exact object, job, proxy, repository, or server name, the report evidence, why it matters, and confidence.

## Warnings
1. [Area] Finding — include the exact object, job, proxy, repository, or server name, the report evidence, why it matters, and confidence.

## Informational
- [Area] Useful context or a passed control.

## Recommendations
1. Most urgent actionable item.
2. Next priority item.
3. Additional action item.

## Resource files

- `references/report-map.md`: stable section anchors, tables, and what each one contains.
- `references/decision-rules.md`: thresholds and prioritization rules for security, job health, capacity, and best practices.
- `references/evidence-rules.md`: fact versus inference rules, confidence labeling, and date handling.

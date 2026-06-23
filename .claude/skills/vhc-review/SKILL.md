---
name: vhc-review
description: analyze raw veeam backup and replication health check html reports and produce a fixed-format executive html report with grounded findings, evidence, and recommendations. use when given a veeam health check html export, a derived findings page, or an ai studio analysis that should be validated, improved, or normalized to the standard report template.
---

## release 1.0.6

Analyze a raw Veeam Backup & Replication Health Check HTML report and produce one canonical executive report format.

## Workflow

1. Open the HTML report and skip to the `<body>` content.
2. Parse the stable section anchors in `references/report-map.md`.
3. Read detail tables first; use summary tables only as cross-checks.
4. Normalize checkboxes and status icons to booleans (`✅`, `☐`, `✗`, `⚠️`).
5. Apply the severity rules in `references/decision-rules.md`.
6. Apply the evidence and confidence rules in `references/evidence-rules.md`.
7. Render the report using the exact structure in `references/output-pattern.md`.

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
- Preserve the report's polished executive tone, but do not change the canonical section order or rename sections.

## Canonical output rules

- Always produce a single self-contained executive HTML report.
- Always use the same section order and labels from `references/output-pattern.md`.
- Always include the top score cards, the findings-by-area summary, the three finding sections, the infrastructure overview, repository/SOBR capacity, job session summary, security compliance highlights, and the prioritized recommendations.
- If a section has no entries, keep the section and show `—` or `n/a`; do not remove the section or invent a different layout.
- Use numbered findings with stable prefixes: `C1`, `C2`, `W1`, `W2`, `I1`, etc.
- Each finding must include exact evidence and a confidence label (`high`, `medium`, or `low`).
- Keep the recommendation count and order stable unless the report data truly does not support a slot; in that case, keep the slot and mark it as `n/a` rather than reshaping the report.

## Resource files

- `references/output-pattern.md`: the required report skeleton and section order.
- `references/report-map.md`: stable section anchors, tables, and what each one contains.
- `references/decision-rules.md`: thresholds and prioritization rules for security, job health, capacity, and best practices.
- `references/evidence-rules.md`: fact versus inference rules, confidence labeling, and date handling.

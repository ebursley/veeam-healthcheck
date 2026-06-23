# Veeam Health Check executive report pattern

Use this exact order and keep the same section names.

## 1. Header
- Product title: `Veeam Health Check`
- Subtitle: `Executive Analysis Report · 7-Day Window`
- Server name
- Report date
- Analyzed date
- VBR version and edition badge

## 2. Score cards
Include four cards only:
- Critical
- Warnings
- Informational
- Compliance Passed

## 3. Findings by Area
Use one summary table with the rows:
- Security & Malware
- Job Health
- Capacity
- Best Practices

Include columns for:
- Critical
- Warning
- Info
- Overall

## 4. Critical Findings
Create a numbered list of finding cards.
Use stable IDs like `C1`, `C2`, etc.
Each card must include:
- area label
- title with exact object name
- short body with exact evidence
- one evidence block or evidence table snippet
- confidence label

## 5. Warnings
Create a numbered list of finding cards.
Use stable IDs like `W1`, `W2`, etc.
Use the same card structure as critical findings.

## 6. Informational
Create a numbered list of passed controls or useful context cards.
Use stable IDs like `I1`, `I2`, etc.

## 7. Infrastructure Overview
Show fixed-count tiles for the key environment totals.
Use the same tile order every time.

## 8. Repository & SOBR Capacity Status
Use a single table with repository type, free space, total space, free %, immutability, job count, and status.

## 9. Job Session Summary (7-Day Window)
Use a single table with job name, type, items, sessions, failures, retries, success %, average duration, average change %, and status.

## 10. Security Compliance Highlights
Use a fixed grid of pass/fail/warn items.
Do not regroup these by prompt preference.

## 11. Prioritized Recommendations
Use exactly 10 recommendation cards when the data supports it.
Keep the order stable:
1. highest-risk security item
2. second security item or malware response
3. TLS / registry / encryption issue
4. tape / offline recovery issue
5. unprotected workloads / coverage gap
6. capacity pressure
7. job failure investigation
8. GFS / retention improvement
9. chain type / backup mode fix
10. hardening / optimization / remaining controls

If fewer than 10 are justified, keep the same list length and mark unsupported slots as `n/a`.

## 12. Footer
Include report metadata and a short validation note that malware detections are indicators, not confirmed breaches.

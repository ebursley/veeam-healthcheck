# vhc-review — Veeam Health Check Report Analyzer

Analyze a Veeam Health Check HTML report and return prioritized findings across security, job health, capacity, and best-practice alignment.

## Usage

```
/vhc-review <path-to-report.html> [--focus security|jobs|capacity|bestpractice]
```

Omit `--focus` to get a full analysis across all four areas.

## How to Execute This Skill

1. **Read the file** using the Read tool on the path provided in args.
2. **Extract sections** by locating HTML elements with the IDs listed below. The report is a single HTML file — scan for `id="<section>"` anchors. Each section is a collapsed `<div>` containing one or more `<table>` elements.
3. **Analyze** each section per the rules below.
4. **Output** a structured findings report in the format specified at the bottom.

If no path is provided, ask the user for the path to the HTML report.

---

## Report Section Map

These are the stable `id=` anchors in VHC reports. Use them to locate data without parsing CSS/JS.

| ID | Contents |
|----|----------|
| `license` | Edition, version, support expiry, used/total instances |
| `vbrserver` | Backup Server hostname, OS, RAM, cores, SQL server, DB type, Veeam version |
| `secsummary` | MFA enabled, config backup encrypted/enabled, last CB result, Cloud Connect, WAN accelerator |
| `serversummary` | Count of each managed server type |
| `jobsummary` | Count of each job type |
| `missingjobs` | Job types that exist 0 instances of |
| `protectedworkloads` | HV total/protected/not-protected, Physical total/protected/not-protected, NAS |
| `managedServerInfo` | All servers: name, type, role, OS, cores, RAM |
| `regkeys` | Non-default registry keys: name, value, best practice note |
| `proxies` | Proxy: name, type, role, cores, RAM, transport mode, failover-to-NBD |
| `repos` | Repository: name, path, free space %, total space (TB), immutability, rotation drives, size limit |
| `sobr` | SOBR name, extents, capacity tier, archive tier |
| `extents` | SOBR extent detail: name, free space %, dedup, compression |
| `jobs` | Per-job: name, type, compression, block size, active full, synthetic full, GFS, per-VM/per-machine, encryption, traffic encryption, retention, WAN acc, next run |
| `jobsesssum` | Per-job session stats: total sessions, success rate %, avg/min/max time (min), avg/max backup size (TB), avg/max data size (TB), avg/max wait |
| `jobTable` | Raw concurrency data table (job-level overlap) |
| `jobcon` | Job concurrency heat map (hour × day-of-week grid) |
| `taskcon` | Task concurrency heat map (hour × day-of-week grid) |
| `ComplianceSummary` | BCDR compliance summary counts |
| `ComplianceTable` | Per-item compliance status: object, severity, event info |

---

## Analysis Rules

### Security Posture

Flag **Critical** if any of:
- MFA not enabled on the Backup Server
- Config Backup not enabled or last result is not Success/Warning
- Config Backup encryption is disabled
- Any repository has `Use Immutability = No` AND is not a tape/cloud repo
- Any job has `Backup File Encryption = No` (flag if customer has sensitive workloads — note as advisory)
- Support contract expired or within 30 days of expiry

Flag **Warning** if any of:
- Traffic Encryption disabled on any job
- WAN Accelerator not in use but remote sites are present (inferred from managed server count > 1 site)
- Cloud Connect enabled but no redundant gateway pools

Flag **Info**:
- Number of user roles / credentials configured
- Whether MFA is noted as enabled

### Job Health

Flag **Critical** if any of:
- Any job's Success Rate % < 80%
- Any job type listed in `missingjobs` that is relevant: "Agent Backup" if physical servers exist, "VM Backup" if HV exists, "File Share Backup" if NAS workloads present
- Unprotected workloads: `Not Protected VMs > 0` or `Phys Not Prot > 0`

Flag **Warning** if any of:
- Success Rate % between 80–95% for any job
- Any job has `Next Run = Never` (disabled jobs)
- Wait for Resources count is high (> 5 for any job)
- Avg wait time > 30 minutes for any job

Flag **Info**:
- Total job count breakdown by type
- Session count summary
- Jobs with retries enabled/disabled

### Capacity & Sizing

Flag **Critical** if any of:
- Any repository Free Space % < 10%
- Any SOBR extent Free Space % < 10%

Flag **Warning** if any of:
- Any repository Free Space % between 10–20%
- Any proxy has only 1 core or ≤ 4 GB RAM
- `Failover to NBD = Yes` on any proxy (indicates transport mode fallback)
- No SOBR configured (single-repo without capacity tier for large environments)

Flag **Info**:
- Total raw repository capacity and free space
- Proxy count and combined task capacity
- Any object storage / capacity tier configured

### Best-Practice Gaps

Flag **Warning** if any job:
- `Compression Level` is set to `None` or `Extreme` (both suboptimal for most cases)
- `Block Size` is not `Local Target (256KB)` or `LAN Target (512KB)` — flag `Auto` or very small values
- `Synthetic Full Enabled = No` AND `Active Full Enabled = No` (no full recovery point strategy)
- `GFS Enabled = No` for jobs that are primary/production backups
- `Per-VM Backup Files = No` for large VMware jobs (>20 VMs implied by workload counts)
- `Backup Chain Type = Forever Incremental` without GFS

Flag **Warning** for infrastructure:
- Non-default registry keys present (list them; each may indicate a workaround or known issue)
- SQL Express used for the VBR database (`DataBase Type = SQL Express`) on large environments (>50 jobs or high session count)
- Veeam version is not the latest (compare against known latest: v12.3 = 12.3.x, v13 = 13.x)

Flag **Info**:
- Config backup target type and schedule

---

## Output Format

Always produce output in this structure. Use severity badges: `🔴 Critical`, `🟡 Warning`, `🔵 Info`.

```
# VHC Analysis — <server-name> (<report-date>)
VBR Version: <version>  |  Edition: <edition>  |  Support Expires: <date>

## Summary
| Area | Critical | Warning | Info |
|------|----------|---------|------|
| Security | N | N | N |
| Job Health | N | N | N |
| Capacity | N | N | N |
| Best Practices | N | N | N |

---

## 🔴 Critical Findings
<!-- Numbered list. One finding per line. Include the section it came from. -->
1. [Security] Config Backup encryption is disabled — if the configuration database is lost, credentials cannot be recovered.
2. [Job Health] Job "Daily VMware" has a 71% success rate over the last 30 days (threshold: 80%).

## 🟡 Warnings
<!-- Numbered list. -->
1. [Capacity] Repository "Repo-01" is at 18% free space — approaching the 10% critical threshold.

## 🔵 Informational
<!-- Bulleted list, grouped by area. -->
- [Security] MFA is enabled on the Backup Server.
- [Job Health] 14 jobs configured: 8 VM Backup, 3 Agent, 2 File Share, 1 Tape.

---

## Recommendations
<!-- Top 3–5 actionable items, in priority order. Link to Veeam Best Practices guide where relevant. -->
1. **Enable Config Backup encryption** — navigate to Home > Backup Infrastructure > Backup Repositories, then Home > Configuration Backup and enable encryption.
2. **Investigate "Daily VMware" job failures** — review job sessions for the last 7 days to identify recurring task-level errors.
3. **Add a second datastore to Repository "Repo-01"** — current free space trajectory suggests exhaustion within 30 days.
```

---

## Notes for the Analyst (Claude)

- The HTML contains embedded CSS and JavaScript before the body content. Skip to the `<body>` tag to find the data tables.
- Table rows with green background = healthy/good; yellow = warning; red = critical — but read the cell values directly, don't rely on color.
- The `jobsesssum` section contains per-job session statistics. Success Rate % and Avg Time are the most important columns.
- The `regkeys` section lists registry keys that differ from a vanilla VBR install — treat each as potentially masking a known issue.
- Scrubbed reports will have anonymized hostnames (e.g., `Server-1`, `10.x.x.x`) — still analyze values, just note that names are anonymized.
- If a section is missing from the report (not all environments have tape, SOBR, Cloud Connect, etc.), skip those rules silently.
- Be specific: always include the job name, server name, or repo name when flagging an issue.
- Do not fabricate data — if a value is not in the report, say so.

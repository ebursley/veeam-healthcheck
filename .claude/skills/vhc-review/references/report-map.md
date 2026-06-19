# Veeam Health Check report map

Use these stable section anchors when reading a raw Veeam Health Check HTML report.

| ID | What to read |
|----|--------------|
| `license` | license edition, used/total instances, expiration dates, cloud connect status |
| `vbrserver` | backup server name, Veeam version, cores, RAM, configuration backup target/result/encryption |
| `secsummary` | immutability, traffic encryption, backup file encryption, config backup encryption, MFA, malware detections |
| `serversummary` | infrastructure counts by type |
| `jobsummary` | job counts by type |
| `missingjobs` | job types that are absent |
| `protectedworkloads` | protected vs. unprotected VM counts and potential duplicates |
| `managedServerInfo` | all managed servers, OS details, protected totals, and unavailable state |
| `regkeys` | non-default registry keys and values |
| `proxies` | proxy resources, transport mode, and failover-to-NBD |
| `sobr` | SOBR topology, capacity tier, archive tier, and immutability |
| `extents` | SOBR extent details and repository free space |
| `repos` | repository type, free space, immutability, and size limits |
| `jobcon` | job concurrency heat map |
| `taskcon` | task concurrency heat map and per-job session stats |
| `jobsesssum` | per-job session totals, success rate, duration, waits, change rate |
| `jobs` | per-job configuration, chain type, block size, compression, GFS, encryption |
| `ComplianceSummary` | passed / not implemented / unable to detect / suppressed counts |
| `ComplianceTable` | best-practice rows and their status |

Notes:
- Some reports repeat `jobTable` blocks for each job family. Read every one.
- Use the table headers to identify the family when the HTML section does not make it obvious.
- Prefer the row text over visual badges.

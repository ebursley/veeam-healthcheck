# ADR 0020: Align JobInfo Type Resolution with JobSessionSummary

* **Status:** Accepted
* **Date:** 2026-05-28
* **Decider:** Ben Thomas (@comnam90)
* **Consulted:** Claude Code (architecture review)

## Context and Problem Statement

The VBR healthcheck report builds two job-centric tables from the same underlying `_Jobs.csv`
data:

| Section | Builder | Type resolution |
|---|---|---|
| `jobSessionSummaryByJob` | `CJobSessSummary` | `CJobTypesParser.GetJobType` then overridden by `_Jobs.csv` `TypeToString` |
| `jobInfo` | `CJobInfoTable` | Agent rows → `AgentJobRecord.FriendlyType`; all others → `CJobTypesParser.GetJobType` only |

For jobs backed by the Veeam plug-in system (`VmbApiPolicyTempJob` — Proxmox VE, Nutanix AHV,
HPE Morpheus VME, VMware Cloud Director, etc.), `CJobTypesParser.GetJobType` has no matching
`case` and falls through to `default: return jobType`, emitting the raw enum string.

Confirmed in `After-Veeam Health Check Report_VBR_vbr-04.usdemo.veeam.local_2026.05.27.132935.json`:
- `Sections.jobInfo.Rows`: `"VmbApiPolicyTempJob"` for Proxmox / AHV / HPE Morpheus jobs.
- `Sections.jobSessionSummaryByJob.Rows`: same jobs shown as `"Proxmox Backup"` / `"Nutanix AHV Backup"` / `"HPE Morpheus VME Backup"`.

`TypeToString` is written by `Get-VhcJob.ps1` directly from the Veeam API
(`$Job.TypeToString`) and is the authoritative, Veeam-supplied friendly label for any job
type, including third-party plug-in types. The session-summary table already uses it
(introduced in ADR 0019). The job-info table did not.

## Decision

Introduce a shared static helper `CJobTypesParser.ResolveJobFriendlyType` that encodes the
three-level precedence in one place:

```csharp
// Precedence: agent FriendlyType (already resolved by AgentJobAggregator)
//             → TypeToString (Veeam API authoritative label)
//             → GetJobType (enum switch fallback)
public static string ResolveJobFriendlyType(CJobCsvInfos row, string agentFriendlyType = null)
{
    if (!string.IsNullOrEmpty(agentFriendlyType))
        return agentFriendlyType;

    if (row != null && !string.IsNullOrEmpty(row.TypeToString))
        return row.TypeToString;

    return GetJobType(row?.JobType);
}
```

Note: the caller passes `agentRecord?.FriendlyType` rather than the `AgentJobRecord` object
to avoid a namespace cycle — `AgentJobAggregator` (in `DataFormers.AgentJobs`) already
imports `CJobTypesParser` (in `Html.DataFormers`).

**`CJobInfoTable`:** section grouping is generalized so every `JobType` (not only agent
enums) is split by `ResolveJobFriendlyType`. This means raw types like `Backup` (which
contains both VMware and Hyper-V jobs when `TypeToString` differs) fragment into separate
sub-sections (e.g., "VMware Backup Jobs", "Hyper-V Backup Jobs") with their own anchor
slugs (`jobTable-backup-vmware-backup`, `jobTable-backup-hyper-v-backup`). The two
per-row resolution sites (HTML + JSON) are updated to use the same helper.

**`CJobSessSummary`:** the existing two-step override (`GetJobType` then `TypeToString`
if present at lines 123 / 138-140) is collapsed into a single `ResolveJobFriendlyType`
call. No semantic change — this is a simplification to prevent the two sites from drifting
independently in future.

## Rationale

- **Single source of truth.** The precedence ladder (`FriendlyType` → `TypeToString` →
  `GetJobType`) is encoded once; callers cannot independently drift.
- **No new enum cases needed.** Plug-in job types are fully described by `TypeToString`
  from the Veeam API. Adding them to the switch would require updating the switch every
  time Veeam ships a new plug-in.
- **Section fragmentation is intentional.** Grouping "Backup" rows by friendly type
  produces per-platform sections that are more readable than one monolithic "Backup Jobs"
  section mixing VMware and Hyper-V rows. The HTML anchor slugs change
  (`jobTable-backup` → `jobTable-backup-vmware-backup`); verified that no external JS,
  TOC, or sidebar references these slugs — they are generated and consumed internally.

## Consequences

### Positive

- `Sections.jobInfo.Rows[*].JobType` shows `"Proxmox Backup"`, `"Nutanix AHV Backup"`, etc.
  for plug-in jobs, matching the session-summary output.
- One section per friendly type in the HTML report for every job category, not only agents.
- Single code path for type resolution; future plug-in types require no code changes.

### Neutral

- HTML anchor IDs change for non-agent `Backup` and `Replica` sub-sections.
  No external references exist; internal TOC is rebuilt from the generated section list.

### Negative

- Reports generated before and after this change are not structurally identical in the
  `jobInfo` section — `VmbApiPolicyTempJob` values become friendly names.

## Related

- **ADR 0019** — policy-link session rollup; introduced the `TypeToString` override in
  `CJobSessSummary`. This ADR extends the same precedence to `CJobInfoTable`.
- **ADR 0015** — hybrid friendly-type rule; established the agent `FriendlyType` resolution
  (standalone vs managed).

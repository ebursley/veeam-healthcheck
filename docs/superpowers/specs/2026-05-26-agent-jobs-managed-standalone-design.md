# Agent Jobs — Managed and Standalone — Design

**Status:** Draft for review
**Date:** 2026-05-26
**Scope:** VBR reporting only (no VB365 impact)

## Problem

The current report mishandles Veeam Agent jobs in three ways:

1. **`jobInfo` is missing all standalone (unmanaged) agent jobs.** The renderer iterates `_Jobs.csv` (from `Get-VBRJob`), which does not include standalone jobs. Information visible elsewhere — source size, on-disk GB, retention, encryption flags — never appears for standalone agents in `jobInfo`.
2. **`jobSummary` double-counts managed agent jobs and uses raw enum names.** It sums `_AgentBackupJob.csv` (from `Get-VBRComputerBackupJob`) into an "Agent Backup" bucket *and* the same jobs again from `_Jobs.csv` under their raw `JobType` enum names (`EpAgentBackup`, `EpAgentPolicy`). Verified on the live VBR server: both cmdlets return identical job IDs, so the buckets overlap fully.
3. **`jobSessionSummaryByJob` collapses every agent session to `JobTypes = "Endpoint Backup"`.** `CJobTypesParser.GetJobType()` maps `EEndPoint` → "Endpoint Backup" and has no cases for `EpAgentBackup` / `EpAgentPolicy`, so all managed agent types fall through to default and either show as raw enum names or get lumped under the same display label as standalone sessions.

Users cannot distinguish "Windows Agent Backup" (managed individual/group), "Windows Agent Policy" (managed protection group), and "Windows Agent Standalone" (unmanaged) in the report — even though Veeam Console clearly labels them differently.

## Goals

- `jobInfo` contains one row per agent job, managed or standalone, with source/on-disk sizes populated.
- `jobSummary` shows distinct buckets per friendly type (e.g. "Windows Agent Backup: 2", "Windows Agent Policy: 1", "Windows Agent Standalone: 1") with no double-counting.
- `jobSessionSummaryByJob` shows the correct friendly type per session row (e.g. each session's `JobTypes` column reflects its job's actual type — "Windows Agent Policy", not a generic "Endpoint Backup").
- Generic across agent platforms (Windows, Linux, Mac) via `TypeToString` from VBR.
- The `FriendlyType` column carries the managed/standalone distinction; no separate table or visual badge is needed.

## Out of Scope

- `missingJobs` section.
- VB365 report.
- Migrating away from `Get-VBRJob` for agent and backup-copy types (Veeam has deprecated it for these — `Get-VBRComputerBackupJob` is the future path — but the warning is already silenced and the cmdlet still returns the data we need; tracked as future work).
- Removing `Get-VBRComputerBackupJob` / `Get-VBREPJob` collection from `Get-VhciAgentJob.ps1`. Both keep running as a side channel; nothing live consumes the resulting CSVs after this change, but they stay to avoid scope creep on unrelated callers.

## Architecture

Two new pieces under `vHC/HC_Reporting/Functions/Reporting/DataFormers/AgentJobs/`:

### `AgentJobRecord`

POCO holding the normalized fields for one agent job:

| Field | Notes |
|---|---|
| `JobName` | string |
| `JobType` | raw enum string from CSV (`EpAgentBackup`, `EpAgentPolicy`, `EpAgentManagement`, `ELinuxPhysical`, `EndpointBackup`) |
| `FriendlyType` | resolved display label (`"Windows Agent Backup"`, `"Linux Agent Policy"`, `"Mac Agent Standalone"`, …) |
| `RepoName` | string |
| `SourceSizeGB` | decimal |
| `OnDiskGB` | decimal |
| `RetentionScheme` | string |
| `RetainDays` | int |
| `Encrypted` | bool |
| `CompressionLevel` | string |
| `BlockSize` | string |
| `GfsEnabled` | bool |
| `GfsDetails` | string |
| `ActiveFullEnabled` | bool |
| `SyntheticFullEnabled` | bool |
| `BackupChainType` | string |
| `IndexingEnabled` | bool |
| `AAIPEnabled` | bool |
| `VSSEnabled` | bool |
| `VSSIgnoreErrors` | bool |
| `GuestFSIndexing` | string |
| `Platform` | string (Windows / Linux / Mac / blank) |

Standalone jobs flow through the same `CBackupJob` projection as managed jobs (via `Get-VBRBackup | ?{IsAgentStandaloneJob} | .GetJob()`), so `Options.BackupStorageOptions`, `Options.GfsPolicy`, and `VssOptions` are populated identically. Fields that genuinely don't apply (or that VBR leaves unset for a specific job) keep their default/empty value so renderers emit blanks.

`BackupChainType` is derived in the existing renderer code from `Algorithm` / `TransformFullToSyntethic` / related fields; `AgentJobRecord` carries the raw inputs and lets the same derivation run.

### `AgentJobAggregator`

Static class with one public entry point that takes the parsed rows directly so the aggregator stays a pure function (easy to unit-test with synthetic `CJobCsvInfos` instances without touching disk):

```csharp
public static IReadOnlyList<AgentJobRecord> Build(IEnumerable<CJobCsvInfos> rows);
```

Callers (`CDataFormer.AgentJobs`) materialize the rows via `new CCsvParser().JobCsvParser()` before invoking `Build`.

Behavior:

1. Receive the parsed `_Jobs.csv` rows from the caller (typically `CCsvParser.JobCsvParser()` output).
2. Filter rows whose raw `JobType` is in the agent set (`AgentJobAggregator.AgentJobTypes`): `EpAgentBackup`, `EpAgentPolicy`, `EpAgentManagement`, `ELinuxPhysical`, `EndpointBackup`. This `IReadOnlySet<string>` is exposed as a public static so other components (e.g. `CJobSummaryTable`) can reuse it without duplicating the list.
3. Map each row to an `AgentJobRecord`, resolving `FriendlyType` per the rule below.
4. Return the list.

The aggregator does **not** read `_AgentBackupJob.csv` or `_EndpointJob.csv`. All agent jobs (managed and standalone) flow through `_Jobs.csv` via the collection changes in the next section.

### `CDataFormer` integration

`CDataFormer` calls `AgentJobAggregator.Build(csvParser)` once during processing and caches the result on a new property:

```csharp
public IReadOnlyList<AgentJobRecord> AgentJobs { get; private set; }
```

Renderers read `CDataFormer.AgentJobs` instead of touching the agent-related CSVs directly.

### Friendly-type resolution rule

Single resolution function inside `AgentJobAggregator`:

1. If row has `TypeToString` and it is non-empty:
   - If `JobType == "EndpointBackup"`: take `TypeToString` and substitute the trailing word "Backup" with "Standalone" (e.g. `"Windows Agent Backup"` → `"Windows Agent Standalone"`). If the string doesn't end in "Backup", append " Standalone" as a defensive fallback.
   - Otherwise: use `TypeToString` as-is.
2. If `TypeToString` is blank or absent: fall back to `CJobTypesParser.GetJobType(JobType)` with newly-added cases for `EpAgentBackup` (`"Windows Agent Backup"`) and `EpAgentPolicy` (`"Windows Agent Policy"`) so the fallback path produces sensible labels for any legacy CSVs predating the `TypeToString` column.

## Data flow / collection changes

### `Get-VhcJob.ps1`

Two changes:

1. **Add standalone jobs to the iteration set.** After `Get-VBRJob`, also collect standalone agent jobs and append them to `$Jobs`:

```powershell
$StandaloneJobs = Get-VBRBackup |
    Where-Object { $_.IsAgentStandaloneJob -eq $true } |
    ForEach-Object { $_.GetJob() }
$Jobs = @($Jobs) + @($StandaloneJobs)
```

Verified on the live VBR server: `.GetJob()` on a standalone backup returns a `Veeam.Backup.Core.CBackupJob` with the same shape as `Get-VBRJob` output. `GetLastBackup()` works on it; `Options.BackupStorageOptions`, `Options.GfsPolicy`, and `VssOptions` are fully populated (compression, block size, retention type/count, encryption flag, GFS weekly/monthly/yearly, AAIP/VSS, indexing — all present). `TypeToString` returns `"Windows Agent Backup"` (the substitution rule above converts this to `"Windows Agent Standalone"` in C#). `JobType` is the enum value `EndpointBackup`.

2. **Add `TypeToString` to the projection.** One new entry in the `Select-Object` chain at line 109:

```powershell
@{n = 'TypeToString'; e = { $Job.TypeToString } }
```

The existing restore-point sizing logic (`GetLastBackup()` → `Get-VBRRestorePoint` → `ApproxSize`-by-`ObjectId` summation, `GetStorage().Stats.BackupSize / 1GB` for on-disk) works uniformly for managed and standalone jobs once they're in the same `$Jobs` array.

### `Get-VhciAgentJob.ps1`

No functional change. `_AgentBackupJob.csv` and `_EndpointJob.csv` continue to be collected; nothing live consumes them after this change.

### `CCsvParser.cs`

The existing dynamic CSV reader picks up the new `TypeToString` column automatically; no parser changes required.

## Renderer changes

### `CJobInfoTable`

Currently reads `_Jobs.csv` directly and renders one row per job, with non-agent and agent jobs interleaved. After this change, agent rows source from `CDataFormer.AgentJobs`:

- For each non-agent job (existing path): unchanged.
- For each `AgentJobRecord`: render a row with `FriendlyType` in the `JobType` column and populate the rest from the record. Because standalone jobs flow through `.GetJob()` (full `CBackupJob`), their rows are populated as completely as managed-agent rows — the distinguishing signal is the `FriendlyType` value (`"… Standalone"`), not blank cells.

The JSON section name (`jobInfo`) and column headers do not change.

### `CJobSummaryTable`

Currently builds counts from `_Jobs.csv` (using `CJobTypesParser`) plus `_AgentBackupJob.csv` (labeled "Agent Backup") plus `_EndpointJob.csv` (labeled "Unmanaged Agent"). After this change:

- Drop the `_AgentBackupJob.csv` and `_EndpointJob.csv` contributions.
- For agent buckets: `CDataFormer.AgentJobs.GroupBy(x => x.FriendlyType).Select(g => new { Type = g.Key, Count = g.Count() })`.
- Non-agent buckets continue using their existing paths.

This eliminates the double-count and produces buckets like `"Windows Agent Backup: 2"`, `"Windows Agent Policy: 1"`, `"Windows Agent Standalone: 1"`.

### `CJobSessionSummaryTable`

Per-session metrics (durations, change rate, dedup, success rate, sizes, retries) continue to come from `CGlobals.DtParser.JobSessions` (the SQL database). **Not affected by this change.** The only modification is the `JobType` column lookup:

- Today: `CJobTypesParser.GetJobType(stu.JobType)` (line 68 and line 117 of `CJobSessionSummaryTable.cs`).
- After: look up the session's `JobName` in `CDataFormer.AgentJobs` (case-insensitive). If matched, use that record's `FriendlyType`. If no match (e.g. non-agent session, session for a deleted job, or session whose job name has since been renamed), fall back to `CJobTypesParser.GetJobType(stu.JobType)` — which now produces sensible labels for the managed agent enums thanks to the new parser cases.

`RenderByJob` (which groups by job type for sub-section headings) consumes the same lookup so each section heading shows the resolved friendly type rather than the default "Endpoint Backup".

### `CJobTypesParser`

Add explicit cases for the agent enum values, used as the fallback when `TypeToString` is absent:

- `EpAgentBackup` → `"Windows Agent Backup"`
- `EpAgentPolicy` → `"Windows Agent Policy"`
- (Existing cases stay: `EpAgentManagement` → "Agent Backup", `ELinuxPhysical` → "Agent Backup", `EEndPoint` → "Endpoint Backup".)

These are only hit when `TypeToString` is blank — i.e. legacy CSVs collected before the projection change, or jobs where VBR returns empty for the property.

## Testing

### Unit tests (`vHC/VhcXTests/`)

New test class `AgentJobAggregatorTests` covering:

- `Build_NonAgentJobType_FiltersOut` — rows whose `JobType` is e.g. `Backup` are excluded.
- `Build_EpAgentBackupWithTypeToString_UsesTypeToString` — managed agent backup row with `TypeToString="Windows Agent Backup"` → `FriendlyType="Windows Agent Backup"`.
- `Build_EpAgentBackupWithoutTypeToString_FallsBackToParser` — blank `TypeToString` → `FriendlyType="Windows Agent Backup"` via parser.
- `Build_StandaloneRow_ReplacesBackupWithStandalone` — `JobType="EndpointBackup"`, `TypeToString="Windows Agent Backup"` → `FriendlyType="Windows Agent Standalone"`.
- `Build_StandaloneLinux_ReplacesBackupWithStandalone` — `TypeToString="Linux Agent Backup"` → `FriendlyType="Linux Agent Standalone"`.
- `Build_StandaloneTypeToStringNotEndingInBackup_AppendsStandalone` — defensive fallback for unexpected strings.
- `Build_SizesParsedCorrectly` — decimal parsing for `SourceSizeGB`/`OnDiskGB` round-trips through the dynamic CSV.

New cases in `CJobTypesParserTests` (or equivalent) for the two new enum mappings.

### Manual end-to-end verification

Run the report against the live VBR server and confirm:

- `jobInfo` contains one row per agent job, including the standalone agent, with non-zero `SourceSizeGB` / `OnDiskGB`.
- `jobSummary` shows distinct friendly buckets per type; the sum across agent buckets matches the count of agent rows in `jobInfo`.
- `jobSessionSummaryByJob` rows show their correct `FriendlyType` in the `JobTypes` column; no session row collapses to a generic "Endpoint Backup".
- Existing non-agent sections (`backupServer`, `serverSummary`, `managedServers`, `repos`, etc.) are unchanged.

## Future work (not in this change)

- Migrate collection off `Get-VBRJob` for agent types, switching to `Get-VBRComputerBackupJob` for managed agents (Veeam-recommended) and keeping the `Get-VBRBackup | ?{IsAgentStandaloneJob} | .GetJob()` path for standalone. The deprecation warning is already suppressed via `-WarningAction SilentlyContinue`, so this is a hygiene/future-proofing improvement, not a functional fix.
- Stop collecting `_AgentBackupJob.csv` and `_EndpointJob.csv` once no callers remain.
- Apply the same friendly-type treatment to the `missingJobs` section if users want "Windows Agent Standalone" etc. to appear in the "no jobs of this type" list.

# ADR 0014: Source Standalone Agent Jobs via Get-VBRBackup + .GetJob() Instead of Get-VBREPJob

* **Status:** Accepted
* **Date:** 2026-05-26
* **Decider:** Ben Thomas (@comnam90)
* **Consulted:** Claude Code (architecture review)

## Context and Problem Statement

`Get-VBRJob` does not return standalone (unmanaged) Veeam Agent jobs. Before this work, the report had no per-job detail row in `jobInfo` for these jobs — their session data appeared in `jobSessionSummaryByJob` but the actual job configuration (source size, on-disk GB, retention, encryption, compression, GFS, indexing) was absent. To close the gap we needed a way to enumerate standalone jobs and project them through the same `_Jobs.csv` pipeline as managed jobs.

The Veeam SDK offers two candidates:

### Option A — `Get-VBREPJob`

The obvious first choice. Already collected by `Get-VhciAgentJob.ps1` into `_EndpointJob.csv`. Live inspection of the cmdlet's output for a real standalone job:

```
RepositoryId : fddf7a1e-708f-46f0-be18-cfb8df621a09
ObjectsCount : 1
IsEnabled    : True
NextRun      : 27/05/2026 12:30:00 am
Target       : BackupRepo1
Type         : EndpointBackup
LastResult   : Success
LastState    : Stopped
Id           : 54bc3629-5304-47cb-bb0d-9c9aede2e72c
Name         : Unmanaged-WindowsAgents-VTESTVM03
Description  : Veeam Agent for Windows backup job
```

The output is a stripped-down wrapper. It exposes only the fields above — no retention scheme, no encryption flag, no compression level, no block size, no GFS settings, no AAIP/VSS, no indexing options, no source/on-disk size. To consume it for the existing `_Jobs.csv` projection (40+ columns of `CJobCsvInfos`), we would have needed:

- A parallel projection path emitting blank cells for everything `Get-VBREPJob` does not expose.
- A separate sizing pipeline (the `Get-VBRBackup` → `Get-VBRRestorePoint` → `GetStorage().Stats.BackupSize` chain that `Get-VhcJob.ps1` already runs for managed jobs).
- Synthesized `TypeToString` from the `Description` field's platform substring (`"Veeam Agent for Windows"` → `"Windows Agent ..."`), since the wrapper does not carry `TypeToString`.

### Option B — `Get-VBRBackup | ?{IsAgentStandaloneJob} | .GetJob()`

`Get-VBRBackup` returns the backup repository's view of each backup. Filter on `IsAgentStandaloneJob` to select standalone-agent backups, then call `.GetJob()` on each. Live inspection:

```
PS> $standalone = Get-VBRBackup | Where-Object { $_.IsAgentStandaloneJob -eq $true }
PS> $standalone[0].GetJob().GetType().FullName
Veeam.Backup.Core.CBackupJob
PS> $standalone[0].GetJob() | Select-Object Name, JobType, TypeToString | Format-List
Name         : Unmanaged-WindowsAgents-VTESTVM03
JobType      : EndpointBackup
TypeToString : Windows Agent Backup
```

`.GetJob()` returns a `Veeam.Backup.Core.CBackupJob` — the exact same .NET type that `Get-VBRJob` returns for managed jobs. `GetLastBackup()` works on it. `Options.BackupStorageOptions` is fully populated (`CompressionLevel = 5`, `StgBlockSize = KbBlockSize1024`, `RetentionType = Days`, `RetainCycles = 7`, `StorageEncryptionEnabled = True`). `Options.GfsPolicy` and `VssOptions` are fully populated.

## Decision

Source standalone agent jobs via:

```powershell
$standaloneJobs = @(Get-VBRBackup -WarningAction SilentlyContinue |
    Where-Object { $_.IsAgentStandaloneJob -eq $true } |
    ForEach-Object { $_.GetJob() } |
    Where-Object { $_ })
$Jobs = @($Jobs) + $standaloneJobs
```

inside `Get-VhcJob.ps1`, immediately after the existing `Get-VBRJob` call. Standalone jobs are appended to the same `$Jobs` array and flow through the existing projection foreach unchanged.

`Get-VBREPJob` continues to be collected by `Get-VhciAgentJob.ps1` for now, but is not consumed by `AgentJobAggregator` or any downstream renderer. Removing the collection entirely is tracked as future work.

## Rationale

- **Shape parity:** `.GetJob()` returns a `CBackupJob` identical in shape to `Get-VBRJob` output. The existing `Select-Object` projection (sizing math via `GetLastBackup()` + `Get-VBRRestorePoint`, options paths under `Options.BackupStorageOptions` / `Options.GfsPolicy` / `VssOptions`) works for standalone jobs without modification.
- **Single projection path:** No parallel column-by-column logic. No synthesized fields except `FriendlyType` (handled in C# per [ADR 0015](0015-hybrid-friendly-type-rule.md)).
- **Future-proof:** When Veeam adds new properties to `CBackupJob`, standalone jobs pick them up for free. With `Get-VBREPJob` we would have to hand-maintain a column-translation table.
- **Sizing already works:** `GetLastBackup()` returns a valid backup on a standalone `CBackupJob`. Live test confirmed sum-of-restore-point sizes equal the standalone session's `BackupSize`.

## Consequences

### Positive
- Standalone agent jobs appear in `jobInfo` with full configuration (retention, encryption, compression, block size, GFS, indexing, AAIP/VSS).
- Sizing is accurate (live verification: source 30.05 GB, on-disk 17.34 GB).
- Future agent-related options on `CBackupJob` flow through automatically.

### Neutral
- The order of operations matters: `Get-VBRBackup | Where-Object | ForEach-Object | Where-Object { $_ }` — the trailing `Where-Object { $_ }` filters out any null returns from `.GetJob()` (defensive; we have not observed null in practice).
- `@(...)` around the pipeline forces an array even when zero results match, so downstream `$standaloneJobs.Count` is always safe.

### Negative
- The standalone path requires a live `Connect-VBRServer` session (so does `Get-VBREPJob` — neither cmdlet works against SDK-only contexts, so no regression).
- A subtle trap for future maintainers: `Get-VBREPJob` is the more discoverable cmdlet (its name implies "endpoint job"), but using it would silently truncate the data we need. This ADR exists to prevent that regression.

## Validation

Live testing on VBR v13 with one known standalone job (`Unmanaged-WindowsAgents-VTESTVM03`) confirmed:

- `Get-VBRBackup | ?{IsAgentStandaloneJob}` returns exactly one backup (the expected one).
- `.GetJob()` on that backup returns a `Veeam.Backup.Core.CBackupJob`.
- `TypeToString` = `"Windows Agent Backup"`.
- `JobType` enum string = `"EndpointBackup"`.
- `GetLastBackup()` returns a valid `Veeam.Backup.Core.CBackup` named `Unmanaged-WindowsAgents-VTESTVM03`.
- `Options.BackupStorageOptions`, `Options.GfsPolicy`, and `VssOptions` are fully populated.
- The end-to-end report produces a `jobInfo` row with `JobName=Unmanaged-WindowsAgents-VTESTVM03`, `JobType=Windows Agent Standalone`, `SourceSizeGB=30.05`, `OnDiskGB=17.34`.

Related: [ADR 0015](0015-hybrid-friendly-type-rule.md) explains how `TypeToString="Windows Agent Backup"` is transformed into the displayed `"Windows Agent Standalone"` label.

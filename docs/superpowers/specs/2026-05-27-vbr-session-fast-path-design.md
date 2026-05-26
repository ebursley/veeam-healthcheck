# VBR Session Collection Fast Path — Design

**Date:** 2026-05-27
**Closes:** veeamhub/veeam-healthcheck#147
**Status:** Proposed

## Problem

Commit `59e2621` rewrote `Get-VhcBackupSessions.ps1` to iterate per-job using
`Get-VBRBackupSession -Job $job`, aiming to bound each SQL query to a single
job's session history and avoid the Veeam SDK's ~600 s internal command timeout
on large environments.

The `-Job` parameter does not exist on `Get-VBRBackupSession` in any released
VBR version — neither v12 nor v13. On every supported environment, every loop
iteration throws `A parameter cannot be found that matches parameter name 'Job'`,
the `try/catch` swallows it as a WARNING, and `$sessions` is empty when
`Get-VhcSessionReport` runs. The pre-`59e2621` implementation worked but used a
single unfiltered `Get-VBRBackupSession` call that hits the SDK timeout on large
environments. We need both: a fast path that filters at the database, and a
safe fallback for environments where the fast path is not available.

## Solution

Use the internal `Veeam.Backup.Core.CBackupSession.GetByJobAndTimeRangeWithLog(Guid, DateTime)`
static method as a fast path. This method exists on every supported VBR version
that ships `Veeam.Backup.Core.dll` and queries the indexed
`backup.model.jobsessions` table directly (verified manually against a VBR 13.0.1
lab: 2 sessions for a 7-day window returned in 312 ms).

Fall back to the original unfiltered `Get-VBRBackupSession | Where-Object` shape
when the fast-path type or method is not available, preserving v12 compatibility
and matching the established `[Veeam.Backup.Core.CNasBackup]` and
`[Veeam.Backup.Core.SBackupOptions]` direct-access pattern already used
elsewhere in the module.

Path selection is detected once per helper call and the choice is logged. There
is no mode-switching mid-run — if the fast path is chosen, every job uses it; a
per-job exception inside the fast path logs a WARNING and continues to the next
job (matching today's partial-failure tolerance) but does not demote that job to
the slow path.

## Architecture

```
Get-VhcBackupSessions (Public)
    │
    ├─ Get-VBRJob                        → $jobs       (VM + Backup Copy)
    ├─ Get-VBRComputerBackupJob          → $agentJobs  (Agent)
    │
    ├─ Get-VhciJobSessions (Private)   --- called once for VM/BackupCopy
    │       │
    │       ├─ Test-VhciCBackupSessionFastPath  (Private)
    │       │       reflection: type + method binding check
    │       │
    │       ├─ fast: foreach job → Invoke-VhciCBackupSessionFetch (Private)
    │       │       wraps the static .NET call (Mock seam)
    │       │
    │       └─ slow: & $SlowPathCommand once → Where-Object cutoff
    │
    └─ Get-VhciJobSessions             --- called once for Agent
            (same logic, different SlowPathCommand)
```

The helper is a single private function with one explicit seam — the
`SlowPathCommand` scriptblock the caller passes in. The seam keeps the helper
ignorant of which VBR cmdlet to fall back to, so phase 2 (NAS, tape, replica,
SureBackup) can reuse it by passing different scriptblocks and job lists.

## Components

### 1. `Private/Get-VhciJobSessions.ps1` (new)

```powershell
function Get-VhciJobSessions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Jobs,
        [Parameter(Mandatory)] [DateTime]    $Since,
        [Parameter(Mandatory)] [scriptblock] $SlowPathCommand,
        [Parameter(Mandatory)] [string]      $PathLabel
    )
    # 1. probe = Test-VhciCBackupSessionFastPath
    # 2. log "Using fast path" or "Using slow path" once
    # 3. fast: iterate $Jobs, call Invoke-VhciCBackupSessionFetch per job in try/catch
    # 4. slow: invoke $SlowPathCommand once in try/catch, filter CreationTime > $Since
    # 5. log final count
    # 6. return array
}
```

`PathLabel` is used for log prefixing only (e.g. `[VM/BackupCopy]`,
`[Agent]`) — not for behavior selection.

### 2. `Private/Test-VhciCBackupSessionFastPath.ps1` (new)

Returns `[bool]`. Uses `'Veeam.Backup.Core.CBackupSession' -as [type]` for type
existence, then `GetMethod('GetByJobAndTimeRangeWithLog', [type[]]@([guid],[datetime]))`
for method existence. Wrapped in `try/catch` returning `$false` on any
reflection failure — never throws to caller.

### 3. `Private/Invoke-VhciCBackupSessionFetch.ps1` (new)

Single-line wrapper around the static call. Exists solely as a Pester `Mock`
target so unit tests don't need a live VBR connection.

```powershell
function Invoke-VhciCBackupSessionFetch {
    param([Parameter(Mandatory)] [Guid] $JobId, [Parameter(Mandatory)] [DateTime] $Since)
    return [Veeam.Backup.Core.CBackupSession]::GetByJobAndTimeRangeWithLog($JobId, $Since)
}
```

### 4. `Public/Get-VhcBackupSessions.ps1` (modified)

Lines 37–58 (the broken `-Job` loop plus the agent block) collapse to:

```powershell
$jobs       = @(Get-VBRJob                   -ErrorAction SilentlyContinue)
$agentJobs  = @(Get-VBRComputerBackupJob     -ErrorAction SilentlyContinue)

$vmSessions    = @(Get-VhciJobSessions -Jobs $jobs      -Since $cutoff `
                       -SlowPathCommand { Get-VBRBackupSession } `
                       -PathLabel 'VM/BackupCopy')

$agentSessions = @(Get-VhciJobSessions -Jobs $agentJobs -Since $cutoff `
                       -SlowPathCommand { Get-VBRComputerBackupJobSession } `
                       -PathLabel 'Agent')

return $vmSessions + $agentSessions
```

The `Get-VBRComputerBackupJob` call is new — the pre-existing code did not need
an agent job list because the slow-path cmdlet is called unfiltered. The fast
path requires a job-id list, so the caller now fetches one. In the slow-path
branch the job list is unused — that is fine.

### 5. `Private/Get-VhciJobSessions.Tests.ps1` (new)

Pester v5 unit tests for the helper (see Testing).

### 6. `Public/Get-VhcBackupSessions.Tests.ps1` (rewritten)

Existing ISC-1…ISC-7 tests assert the broken `-Job` shape and must be replaced.

### 7. `vHC-VbrConfig.Manifest.Tests.ps1` (possibly modified)

If the manifest test enumerates private functions, add the three new ones. To
be confirmed during implementation.

## Data Flow

1. `Get-VhcBackupSessions -ReportInterval 7` computes `$cutoff = Now - 7d`.
2. Fetches both job families (`Get-VBRJob`, `Get-VBRComputerBackupJob`).
3. Calls `Get-VhciJobSessions` twice — once per family.
4. Inside each helper call:
   - Probe runs once. Result logged at INFO.
   - Fast path: iterate jobs, call `Invoke-VhciCBackupSessionFetch` per job. Per-job
     `catch` logs WARNING with job name + exception message, continues.
   - Slow path: invoke scriptblock once. `catch` logs WARNING and returns `@()`.
     Apply `Where-Object { $_.CreationTime -gt $Since }` to the result.
5. Caller concatenates both arrays and returns.

## Error Handling

| Failure | Behavior |
|---|---|
| Probe reflection throws unexpectedly | `Test-VhciCBackupSessionFastPath` returns `$false`; caller goes to slow path; logged once as INFO ("Using slow path") |
| Per-job exception in fast path | WARNING with job name + exception message; continue to next job (matches today's ISC-3 behavior); **no demote to slow path** |
| Slow-path scriptblock throws | WARNING with exception message; helper returns `@()`; other path family may still succeed |
| Empty `$Jobs` + fast path | Zero iterations; returns `@()`; INFO log "No jobs to query" |
| Empty `$Jobs` + slow path | Scriptblock still invoked (slow path does not consume `$Jobs`); empty result possible if nothing in window |
| Probe says yes but type loads partially | Reflection check on both type and method binding; either null → returns `$false`; silent degrade to slow path. Loud-fail on method-shape mismatch was rejected because it would break the very upgrade-resilience this design exists for. |

**Logging per helper call:**

- 1 × INFO: chosen path
- 0–N × WARNING: per-job failures (fast) or scriptblock failure (slow)
- 1 × INFO: result count

## Testing

All Veeam cmdlets are stubbed as global no-ops in `BeforeAll` so the suite
runs cross-platform. `Write-LogFile` is mocked with a script-scope warn
collector. `Invoke-VhciCBackupSessionFetch` and
`Test-VhciCBackupSessionFastPath` are pure PowerShell functions and act as
`Mock` targets — no `Add-Type` required.

### `Get-VhciJobSessions.Tests.ps1`

| ID | Scenario |
|---|---|
| GJS-1 | Probe `$true` → fast branch chosen; `Invoke-VhciCBackupSessionFetch` invoked, scriptblock never invoked |
| GJS-2 | Probe `$false` → slow branch chosen; scriptblock invoked once, `Invoke-VhciCBackupSessionFetch` never invoked |
| GJS-3 | Fast, 3 jobs → `Invoke-VhciCBackupSessionFetch` invoked 3× with each job's Id and `$Since` |
| GJS-4 | Fast, mid-iteration throw → WARNING with job name + message; other jobs still processed |
| GJS-5 | Slow, mixed-age results → cutoff filter excludes older |
| GJS-6 | Slow, scriptblock throws → WARNING logged; helper returns `@()`, does not throw |
| GJS-7 | Empty `$Jobs` + fast → zero `Invoke-VhciCBackupSessionFetch` calls; returns `@()` |

### `Get-VhcBackupSessions.Tests.ps1` (rewritten)

| ID | Scenario |
|---|---|
| ISC-1 | Smoke: function exists; empty job lists → no throw, returns array |
| ISC-2 | `Get-VhciJobSessions` invoked twice with `-PathLabel 'VM/BackupCopy'` and `-PathLabel 'Agent'` |
| ISC-3 | Slow-path scriptblock contents match expected cmdlet (`[scriptblock]::ToString()` filter) |
| ISC-4 | `-Since` propagation equals `(Get-Date).AddDays(-ReportInterval)` within ~1 s tolerance |
| ISC-5 | Result is concatenation of both helper calls (sentinel-array technique) |
| ISC-6 | One helper throws → other still runs; function returns partial results |
| ISC-7 | Return shape: flat `[object[]]`, not nested ArrayList |

### Manual verification (not CI)

Performed during implementation against the local lab VBR (13.0.1) used during
brainstorming:

1. `Veeam.Backup.Core.CBackupSession.GetByJobAndTimeRangeWithLog($jobId, $since)`
   returns `CBackupSession` objects for VM/BackupCopy and Agent jobs alike
   (confirmed during design: `Managed-WindowsAgents-Job` returned 2 sessions).
2. End-to-end run of `Get-VhcSessionReport` over the helper's output — the
   downstream code path that calls `Get-VBRTaskSession` accepts `CBackupSession`
   objects originating from agent jobs. If this fails, a small adapter is
   needed at the agent slow-path return site; this is implementation risk, not
   design risk.

## Out of Scope

- NAS / file-share, replica, tape, SureBackup session collection. Phase 2 work
  per scope decision. The helper signature is designed to accommodate them
  later without refactor.
- Caching the probe result across calls — re-probing twice per run is
  acceptable; caching would add script-scope state for negligible benefit.
- Per-job fallback from fast to slow path within a single run — rejected per
  the "detect once + fall back globally" choice. Mode is decided once per
  helper call and remains fixed.
- Loud failure on `Veeam.Backup.Core.CBackupSession` method shape changes — the
  design intentionally silent-degrades to slow path so future VBR upgrades do
  not break us.

## Risks

- **Agent return-type compatibility.** `Get-VBRTaskSession` accepts both
  `CBackupSession` and `VBRSession` per the existing doc comment in
  `Get-VhcBackupSessions.ps1`. The fast path returns `CBackupSession` for
  agent jobs. Other downstream code in `Get-VhcSessionReport` may rely on
  `VBRSession`-specific properties when handling agent sessions; this is the
  one real risk in the design and will be confirmed by a manual end-to-end run
  against the lab before merge.
- **Internal type stability.** `Veeam.Backup.Core.CBackupSession` is not part
  of the supported PowerShell surface. A future VBR release could rename the
  method or change its signature. The probe specifically validates the
  `(Guid, DateTime)` overload exists; signature drift cleanly degrades to slow
  path. Risk accepted.

## References

- Issue: <https://github.com/veeamhub/veeam-healthcheck/issues/147>
- Commit that introduced the bug: `59e2621` (`fix(diagnostics): three fixes from
  v3.0.1.131 customer log analysis`)
- Existing precedent for `[Veeam.Backup.Core.*]` direct access:
  `Private/Get-VhciNasJob.ps1` (`CNasBackup`, `CNasBackupPoint`),
  `Public/Get-VhcVbrInfo.ps1` (`SBackupOptions`)
- Database table backing the fast path: `public."backup.model.jobsessions"`
  (PostgreSQL config DB; 33 columns, indexed on `(job_id, creation_time)` among
  others)

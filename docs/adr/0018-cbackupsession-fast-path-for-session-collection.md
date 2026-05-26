# ADR 0018: VBR Session Collection via Veeam.Backup.Core.CBackupSession Fast Path

* **Status:** Accepted
* **Date:** 2026-05-27
* **Decider:** Ben Thomas (@comnam90)
* **Consulted:** Claude Code (architecture review)

## Context and Problem Statement

`Get-VhcBackupSessions` needs to return all VBR backup sessions created within a
reporting window (default 7 days) so the downstream session-report code path can
process them. Two competing constraints drive this:

1. **Filtering must happen at the database, not in PowerShell**, because large
   environments hold tens of thousands of sessions and the supported cmdlet's
   internal SQL command timeout (~600 s) trips on the unfiltered call.
2. **The collector must work on every supported VBR version**, currently v12 and
   v13. Solutions that depend on cmdlet shape changes between versions are
   fragile.

The commit history shows the difficulty:

- **Pre-`59e2621`** — single unfiltered `Get-VBRBackupSession | Where-Object {...}`
  call. Worked on v12 and small v13 environments. Timed out on large v13
  environments.
- **`59e2621`** — switched to `Get-VBRBackupSession -Job $job` per job. The
  `-Job` parameter does not exist on `Get-VBRBackupSession` in any released VBR
  version. Every iteration threw, all sessions were caught as WARNINGs, and the
  collector returned an empty array on every environment. See
  veeamhub/veeam-healthcheck#147 for the customer log evidence.

We need a path that filters at the database layer and works on both v12 and
v13. No supported PowerShell cmdlet provides this today.

### What the database actually exposes

Live inspection of the VBR 13.0.1 configuration database (PostgreSQL) shows
the `public."backup.model.jobsessions"` table holds 33 columns and 14
indexes, including a composite `(job_id, creation_time)` btree. The indexed
shape is exactly what we need — given a job id and a cutoff date, the query
plan is a bounded index scan, not a full table read. This index has existed
on the SQL/PostgreSQL schemas across v11+.

### What VBR exposes for accessing that index

`Veeam.Backup.Core.dll` ships with `Veeam.Backup.Core.CBackupSession`, a
static-method class with over 40 query methods. Several map directly to the
index:

| Method | Filters by |
|---|---|
| `GetByJob(Guid jobId)` | job id (full history) |
| `GetByJobAndTimeRangeWithLog(Guid, DateTime)` | job id + start date |
| `GetByTypeAndTimeInterval(EDbJobType, DateTime, DateTime)` | type + window |
| `FindLastByJob(Guid)` | most recent for job |

These are the methods the supported cmdlets (`Get-VBRBackupSession`,
`Get-VBRComputerBackupJobSession`) call internally. We confirmed by lab test
that `GetByJobAndTimeRangeWithLog` returns sessions for VM, Backup Copy, and
agent jobs alike — including the `Managed-WindowsAgents-Job` from a managed
agent — in 312 ms over a 7-day window.

### The supportability question

`Veeam.Backup.Core.*` types are not part of Veeam's documented PowerShell
surface. The standard Veeam guidance is to use cmdlets only. However:

1. **There is no supported cmdlet that does what we need.** The cmdlet's
   `-Job` parameter does not exist; there is no `-Since`/`-After` filter
   either.
2. **The module already uses several `Veeam.Backup.Core.*` types** for
   similar "no supported cmdlet exists" cases:
   - `[Veeam.Backup.Core.CNasBackup]::GetByNasPointId` in
     `Private/Get-VhciNasJob.ps1`
   - `[Veeam.Backup.Core.CNasBackupPoint]::Get` in the same file
   - `[Veeam.Backup.Core.SBackupOptions]::get_GlobalMFA` in
     `Public/Get-VhcVbrInfo.ps1`
3. **The internal API surface has been stable.** `CBackupSession` static
   query methods have not been renamed across the v11/v12/v13 transitions
   based on a comparison of `Veeam.Backup.Core.dll` reflection output across
   versions (verified for v13.0.1; v11 and v12 dlls show the same method
   shapes in customer logs from prior support cases).

The risk is real but bounded. The mitigation (next section) makes the
coupling automatic to recover from.

## Decision

1. **Primary path: internal .NET method.** Call
   `[Veeam.Backup.Core.CBackupSession]::GetByJobAndTimeRangeWithLog($jobId, $since)`
   per job to fetch sessions filtered at the database layer.

2. **Fallback path: supported unfiltered cmdlet.** When the type or the
   specific `(Guid, DateTime)` method overload is not available, fall back
   to a single unfiltered cmdlet call (`Get-VBRBackupSession` for VM/Backup
   Copy, `Get-VBRComputerBackupJobSession` for agents) with client-side
   `CreationTime > $since` filtering. This is the pre-`59e2621` shape and
   is known to work on v12 and small v13 environments.

3. **Reflection-based probe.** A `Test-VhciCBackupSessionFastPath` helper
   uses reflection (`'Veeam.Backup.Core.CBackupSession' -as [type]` +
   `GetMethod('GetByJobAndTimeRangeWithLog', [type[]]@([guid],[datetime]))`)
   to determine availability. Probe failures degrade silently to the slow
   path with an INFO log line.

4. **Detect once per helper call; no mid-run switching.** If the probe says
   yes, every job uses the fast path. A per-job exception in the fast path
   logs a WARNING and continues to the next job — it does not demote that
   job to the slow path.

5. **Wrap the static call in a mockable PS function.**
   `Invoke-VhciCBackupSessionFetch` is a one-line wrapper around the static
   call, exposed solely so Pester can `Mock` it without `Add-Type`.

The full helper design is documented in
`docs/superpowers/specs/2026-05-27-vbr-session-fast-path-design.md`.

## Rationale

- **Performance.** The fast path is an indexed query and returns in hundreds of
  milliseconds even on databases with millions of session rows. The supported
  cmdlet does not expose any equivalent filter, so this is the only known path
  to the indexed query short of opening a direct PostgreSQL connection from
  the script (rejected: more brittle, requires credentials, bypasses VBR's
  caching layer).

- **Compatibility.** The reflection probe means the fast path is opt-in based
  on environment: present and exercised on v13, automatically degraded on v12
  or any future VBR build that changes the method shape. The slow path is the
  pre-`59e2621` code that we know worked on v12.

- **Precedent.** The module already accepts the supportability tradeoff for
  three other `Veeam.Backup.Core.*` types where no supported equivalent
  exists. This decision is consistent with the existing pattern, not a new
  exception.

- **Failure isolation.** A per-job throw in the fast path logs a WARNING and
  continues, the same partial-failure tolerance the collector has today.
  Mid-run switching to slow path was considered and rejected — it would mask
  real per-job data problems by silently retrying through a different code
  path and producing different result shapes.

- **Testability.** Wrapping the static call in `Invoke-VhciCBackupSessionFetch`
  costs one extra function but means the helper is testable on macOS and
  Linux CI without any Veeam runtime. This matches the existing pattern (the
  test file already stubs `Get-VBRBackupSession` and friends).

## Consequences

### Positive

- VBR Health Check Reports are usable on large v13 environments — the
  SDK-timeout failure mode is gone.
- Per-job filtering at the database scales linearly with active job count
  rather than total session-history size.
- Issue veeamhub/veeam-healthcheck#147 is resolved on both v12 (slow path
  works as it always did) and v13 (fast path works and is bounded).
- The module gains a reusable session-collection helper that NAS, tape,
  replica, and SureBackup collectors can adopt in a follow-up phase by
  passing different `SlowPathCommand` scriptblocks.

### Neutral

- The internal `Veeam.Backup.Core.CBackupSession` type is now a documented
  dependency of the module. The probe makes the dependency soft (degrades on
  removal/rename) rather than hard.
- The fast path returns `CBackupSession` objects for agent jobs, where the
  slow path returns `VBRSession` (PowerShell wrapper) objects. Downstream
  `Get-VBRTaskSession` accepts both per ADR 0012, so this is expected to be
  transparent — but it is the one risk surface that needs manual end-to-end
  verification before merge.

### Negative

- Coupling to an unsupported internal API. Mitigated by the reflection
  probe; nonetheless, if Veeam renames or removes
  `GetByJobAndTimeRangeWithLog` in a future major version, the slow path
  becomes the only path on that version. Acceptable, since "slow but
  working" is the current pre-`59e2621` baseline.
- One extra `Get-VBRComputerBackupJob` call in `Get-VhcBackupSessions` to
  produce the agent-job list the fast path iterates. Cheap (returns a small
  metadata list, not session data) and only paid once per run.

## Relationship to other ADRs

- **ADR 0012 (Agent Backup Session Collection)** — the operative cmdlet for
  agent sessions when the fast path is unavailable. Its downstream
  `Get-VBRTaskSession` per-session loop and `IsEpAgentPlatform` detection
  are unchanged by this ADR. ADR 0012 now carries a "See also" pointer to
  this ADR for the updated collection mechanism.

## Validation

The fast path was validated against a VBR 13.0.1 lab during the design
phase:

- `[Veeam.Backup.Core.CBackupSession]::GetByJobAndTimeRangeWithLog($jobId, $since)`
  returned 2 sessions for `Managed-WindowsAgents-Job` over a 7-day window
  in 312 ms.
- The same call against a VM/BackupCopy job (`Backup Copy Job 1`) returned
  the expected sessions with `CBackupSession` shape.
- `psql` direct inspection of `public."backup.model.jobsessions"` confirmed
  the index plan and that the result set matches the cmdlet output
  one-for-one.

Implementation will add:

- Pester unit tests in `Private/Get-VhciJobSessions.Tests.ps1` (GJS-1
  through GJS-7) covering both branches without a live VBR runtime.
- Rewritten `Public/Get-VhcBackupSessions.Tests.ps1` (ISC-1 through ISC-7)
  asserting the new call shape.
- A manual end-to-end run of `Get-VhcSessionReport` against the lab to
  confirm `CBackupSession` agent-session objects flow through
  `Get-VBRTaskSession` correctly. If they do not, an adapter layer is added
  at the agent fast-path return site; this is implementation risk, not
  design risk.

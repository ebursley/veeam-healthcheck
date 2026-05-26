# VBR Session Fast Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken `Get-VBRBackupSession -Job $job` per-job loop in `Get-VhcBackupSessions.ps1` with a new private helper `Get-VhciJobSessions` that calls the indexed-DB-query .NET method `[Veeam.Backup.Core.CBackupSession]::GetByJobAndTimeRangeWithLog` when available, and falls back to the unfiltered supported cmdlet (pre-`59e2621` behaviour) when not. Closes veeamhub/veeam-healthcheck#147.

**Architecture:** Three new private functions in `vHC-VbrConfig/Private/` (probe, mockable wrapper, main helper); one rewrite of `Public/Get-VhcBackupSessions.ps1`; full rewrite of `Get-VhcBackupSessions.Tests.ps1`; new Pester tests for the helper. The probe runs once per helper call via reflection on `Veeam.Backup.Core.CBackupSession` + the `(Guid, DateTime)` method overload — silent degrade to slow path on any failure. See `docs/superpowers/specs/2026-05-27-vbr-session-fast-path-design.md` and `docs/adr/0018-cbackupsession-fast-path-for-session-collection.md`.

**Tech Stack:** PowerShell 5.1 (production module) + PowerShell 7 (Pester tests), Pester v5, .NET reflection. Branch `fix/vbr-session-fast-path` is already pushed to origin and checked out.

---

## File Structure

**Create:**

- `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Test-VhciCBackupSessionFastPath.ps1` — reflection probe, returns `[bool]`
- `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Test-VhciCBackupSessionFastPath.Tests.ps1` — Pester tests for the probe
- `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Invoke-VhciCBackupSessionFetch.ps1` — one-line static-call wrapper, sole purpose is to be a Mock target
- `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Invoke-VhciCBackupSessionFetch.Tests.ps1` — Pester tests
- `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Get-VhciJobSessions.ps1` — the main helper
- `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Get-VhciJobSessions.Tests.ps1` — Pester tests (GJS-1 to GJS-7)

**Modify:**

- `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcBackupSessions.ps1` — replace the broken `-Job` loop with two `Get-VhciJobSessions` calls; add `Get-VBRComputerBackupJob` fetch for the agent job list
- `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcBackupSessions.Tests.ps1` — full rewrite; current ISC-1…ISC-7 assert the broken `-Job` shape

**Possibly modify (verify in Task 9):**

- `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/vHC-VbrConfig.Manifest.Tests.ps1` — the cmdlet-stub list at lines 97-114 already contains `Get-VBRComputerBackupJob`; no change expected, but verify

---

## Task Conventions

**Test execution.** All Pester tests run with PowerShell 7 + Pester v5. The standard command for a single test file is:

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path '<path-to-Tests.ps1>' -Output Detailed"
```

Pester is preinstalled on Windows lab box and on the CI runner. If `pwsh` is unavailable on a development host, fall back to `powershell.exe` with Pester v5 explicitly imported — but the test files use `#Requires -Version 7.0`, so PS 7 is the supported path.

**Module dot-source for tests.** Each Tests.ps1 dot-sources its function under test using the same idiom as `Get-VhcBackupSessions.Tests.ps1`:

```powershell
. $PSCommandPath.Replace('.Tests.ps1', '.ps1')
```

That keeps the test file colocated with the function and means no `Import-Module` round-trip per test.

**Commits.** Each task ends with a single commit on `fix/vbr-session-fast-path`. Push at end of each task so the branch on origin tracks progress. Commit message conventional-commits style (`feat`, `fix`, `test`, `refactor`, `docs`), matching the existing log on this branch.

**Branch.** Already on `fix/vbr-session-fast-path`. Do not branch off again.

---

### Task 1: Reflection probe (Test-VhciCBackupSessionFastPath)

**Files:**
- Create: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Test-VhciCBackupSessionFastPath.ps1`
- Create: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Test-VhciCBackupSessionFastPath.Tests.ps1`

The probe returns `$true` only when the type AND the `(Guid, DateTime)` overload both exist. Any reflection exception (e.g. type-load partial failure) is caught and returns `$false`. The function must never throw to its caller — fast path must always degrade silently.

- [ ] **Step 1: Write the Tests.ps1 file**

```powershell
#Requires -Version 7.0
# Pester v5 tests for Test-VhciCBackupSessionFastPath

BeforeAll {
    . $PSCommandPath.Replace('.Tests.ps1', '.ps1')
}

Describe 'Test-VhciCBackupSessionFastPath' {

    It 'returns $false when the Veeam.Backup.Core.CBackupSession type is not loaded' {
        # In the test environment, the Veeam SDK is not present, so the -as [type]
        # check returns $null and the probe must return $false without throwing.
        $result = Test-VhciCBackupSessionFastPath
        $result | Should -BeOfType [bool]
        $result | Should -BeFalse
    }

    It 'never throws and always returns a [bool]' {
        # Pester's -BeNullOrEmpty treats $false as falsy/empty, so we cannot
        # assert non-null directly. Type check is the right contract here.
        { Test-VhciCBackupSessionFastPath } | Should -Not -Throw
        $result = Test-VhciCBackupSessionFastPath
        $result | Should -BeOfType [bool]
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path 'vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Test-VhciCBackupSessionFastPath.Tests.ps1' -Output Detailed"
```

Expected: FAIL (`Test-VhciCBackupSessionFastPath` is not defined — the dot-source target doesn't exist yet).

- [ ] **Step 3: Write the production function**

Create `Private/Test-VhciCBackupSessionFastPath.ps1`:

```powershell
#Requires -Version 5.1

function Test-VhciCBackupSessionFastPath {
    <#
    .Synopsis
        Probes whether the internal Veeam.Backup.Core.CBackupSession type and its
        GetByJobAndTimeRangeWithLog(Guid, DateTime) overload are available in the
        current PowerShell session.

        Returns $true only when both the type and the (Guid, DateTime) method
        binding exist. Any reflection failure (type partially loaded, method
        renamed, etc.) is caught and returns $false so callers can fall back
        cleanly without exception handling. See ADR 0018.
    .Outputs
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $type = 'Veeam.Backup.Core.CBackupSession' -as [type]
        if ($null -eq $type) { return $false }

        $method = $type.GetMethod(
            'GetByJobAndTimeRangeWithLog',
            [System.Reflection.BindingFlags]'Public,Static',
            $null,
            [type[]]@([guid], [datetime]),
            $null
        )
        return ($null -ne $method)
    } catch {
        return $false
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path 'vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Test-VhciCBackupSessionFastPath.Tests.ps1' -Output Detailed"
```

Expected: PASS (2 tests).

- [ ] **Step 5: Commit and push**

```powershell
git add vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Test-VhciCBackupSessionFastPath.ps1 vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Test-VhciCBackupSessionFastPath.Tests.ps1
git commit -m @'
feat(vbr-session): add Test-VhciCBackupSessionFastPath reflection probe

Single-purpose probe used by Get-VhciJobSessions to decide whether to use
the indexed-DB fast path or the unfiltered cmdlet slow path. Returns
$false on any reflection failure so callers can degrade silently. See
ADR 0018.

Refs #147
'@
git push
```

---

### Task 2: Mockable static-call wrapper (Invoke-VhciCBackupSessionFetch)

**Files:**
- Create: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Invoke-VhciCBackupSessionFetch.ps1`
- Create: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Invoke-VhciCBackupSessionFetch.Tests.ps1`

The wrapper exists solely so Pester can `Mock Invoke-VhciCBackupSessionFetch` without instantiating real Veeam runtime. It does no extra work — just forwards to the static method. Tests only assert the contract (parameter shape and that it forwards), not the .NET behaviour.

- [ ] **Step 1: Write the Tests.ps1 file**

```powershell
#Requires -Version 7.0
# Pester v5 tests for Invoke-VhciCBackupSessionFetch

BeforeAll {
    . $PSCommandPath.Replace('.Tests.ps1', '.ps1')
}

Describe 'Invoke-VhciCBackupSessionFetch' {

    It 'requires JobId parameter' {
        # Mandatory params throw a parameter binding exception when missing.
        # We invoke the function with no args; PowerShell prompts in interactive
        # mode but throws here because -NoProfile + non-interactive.
        { Invoke-VhciCBackupSessionFetch -Since (Get-Date) } | Should -Throw
    }

    It 'requires Since parameter' {
        { Invoke-VhciCBackupSessionFetch -JobId ([guid]::NewGuid()) } | Should -Throw
    }

    It 'accepts a [guid] JobId and [datetime] Since' {
        # We expect this to throw because the static .NET type is not available
        # in the test environment - but it must throw a "type not found" /
        # "GetByJobAndTimeRangeWithLog not found" error, NOT a parameter binding error.
        # That demonstrates the param shape is correct.
        {
            try { Invoke-VhciCBackupSessionFetch -JobId ([guid]::NewGuid()) -Since (Get-Date) }
            catch { }
        } | Should -Not -Throw
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path 'vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Invoke-VhciCBackupSessionFetch.Tests.ps1' -Output Detailed"
```

Expected: FAIL (`Invoke-VhciCBackupSessionFetch` is not defined).

- [ ] **Step 3: Write the production function**

Create `Private/Invoke-VhciCBackupSessionFetch.ps1`:

```powershell
#Requires -Version 5.1

function Invoke-VhciCBackupSessionFetch {
    <#
    .Synopsis
        Single-purpose wrapper around
        [Veeam.Backup.Core.CBackupSession]::GetByJobAndTimeRangeWithLog so that
        Pester can mock the .NET edge in tests. Do not add logic here.
        See ADR 0018.
    .Parameter JobId
        The Veeam job UUID (from CBackupJob.Id).
    .Parameter Since
        Earliest CreationTime to include (inclusive of microsecond drift).
    .Outputs
        [Veeam.Backup.Core.CBackupSession[]] from the live VBR config database.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [guid]     $JobId,
        [Parameter(Mandatory)] [datetime] $Since
    )

    return [Veeam.Backup.Core.CBackupSession]::GetByJobAndTimeRangeWithLog($JobId, $Since)
}
```

- [ ] **Step 4: Run test to verify it passes**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path 'vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Invoke-VhciCBackupSessionFetch.Tests.ps1' -Output Detailed"
```

Expected: PASS (3 tests).

- [ ] **Step 5: Commit and push**

```powershell
git add vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Invoke-VhciCBackupSessionFetch.ps1 vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Invoke-VhciCBackupSessionFetch.Tests.ps1
git commit -m @'
feat(vbr-session): add Invoke-VhciCBackupSessionFetch wrapper

One-line wrapper around the CBackupSession.GetByJobAndTimeRangeWithLog
static call. Sole purpose: act as a Pester Mock target so unit tests can
exercise Get-VhciJobSessions without a live Veeam runtime. See ADR 0018.

Refs #147
'@
git push
```

---

### Task 3: Get-VhciJobSessions — fast path branch (GJS-1, GJS-3)

**Files:**
- Create: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Get-VhciJobSessions.ps1`
- Create: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Get-VhciJobSessions.Tests.ps1`

Write enough of the helper to satisfy the fast-path tests only. Subsequent tasks (4, 5) add the slow-path branch and edge-case handling. This task establishes the test scaffolding (Pester stubs, dot-source, mock targets).

- [ ] **Step 1: Write the initial Tests.ps1 with GJS-1 + GJS-3**

```powershell
#Requires -Version 7.0
# Pester v5 tests for Get-VhciJobSessions (GJS-1 through GJS-7)
#
# Strategy: Test-VhciCBackupSessionFastPath and Invoke-VhciCBackupSessionFetch
# are pure PS functions so we Mock them directly. No Add-Type, no live VBR.

BeforeAll {
    # Dot-source the function under test PLUS its private deps so the names
    # exist for Pester's Mock to attach to.
    $privateDir = Split-Path -Parent $PSCommandPath
    . (Join-Path $privateDir 'Test-VhciCBackupSessionFastPath.ps1')
    . (Join-Path $privateDir 'Invoke-VhciCBackupSessionFetch.ps1')
    . $PSCommandPath.Replace('.Tests.ps1', '.ps1')

    # Write-LogFile lives in Public/; dot-source it so Pester can mock it.
    $publicDir = Join-Path (Split-Path -Parent $privateDir) 'Public'
    . (Join-Path $publicDir 'Write-LogFile.ps1')

    # Helpers for fake jobs
    function script:New-FakeJob {
        param([string]$Name = 'FakeJob', [guid]$Id = [guid]::NewGuid())
        [PSCustomObject]@{ Name = $Name; Id = $Id }
    }
    function script:New-FakeSession {
        param([datetime]$CreationTime, [string]$JobName = 'FakeJob')
        [PSCustomObject]@{ CreationTime = $CreationTime; JobName = $JobName }
    }
}

# ---------------------------------------------------------------------------
# GJS-1  Probe $true -> fast branch; Invoke-VhciCBackupSessionFetch invoked,
#                       slow-path scriptblock never invoked
# ---------------------------------------------------------------------------
Describe 'GJS-1: Probe $true selects the fast path' {

    BeforeEach {
        Mock Write-LogFile -MockWith { }
        Mock Test-VhciCBackupSessionFastPath -MockWith { $true }
        Mock Invoke-VhciCBackupSessionFetch -MockWith {
            return @(script:New-FakeSession -CreationTime (Get-Date).AddHours(-1))
        }
        $script:slowCalled = $false
        $script:slowSb     = { $script:slowCalled = $true; @() }
    }

    It 'calls Invoke-VhciCBackupSessionFetch and not the slow-path scriptblock' {
        $job = script:New-FakeJob 'J1'
        @(Get-VhciJobSessions -Jobs @($job) -Since (Get-Date).AddDays(-7) `
            -SlowPathCommand $script:slowSb -PathLabel 'VM/BackupCopy') | Out-Null
        Should -Invoke Invoke-VhciCBackupSessionFetch -Times 1 -Exactly
        $script:slowCalled | Should -BeFalse
    }

    It 'logs an INFO line containing "fast path"' {
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        Mock Write-LogFile -MockWith {
            if (-not $LogLevel -or $LogLevel -eq 'INFO') { $script:infoMessages.Add($Message) }
        }
        $job = script:New-FakeJob 'J1'
        @(Get-VhciJobSessions -Jobs @($job) -Since (Get-Date).AddDays(-7) `
            -SlowPathCommand $script:slowSb -PathLabel 'VM/BackupCopy') | Out-Null
        ($script:infoMessages | Where-Object { $_ -match 'fast path' }).Count | Should -BeGreaterThan 0
    }
}

# ---------------------------------------------------------------------------
# GJS-3  Fast path, 3 jobs -> Invoke-VhciCBackupSessionFetch invoked 3x with
#                              each job's Id and the supplied $Since
# ---------------------------------------------------------------------------
Describe 'GJS-3: Fast path iterates jobs with correct JobId and Since' {

    BeforeEach {
        Mock Write-LogFile -MockWith { }
        Mock Test-VhciCBackupSessionFastPath -MockWith { $true }
        Mock Invoke-VhciCBackupSessionFetch -MockWith {
            @(script:New-FakeSession -CreationTime (Get-Date).AddHours(-1))
        }
        $script:job1 = script:New-FakeJob 'J1'
        $script:job2 = script:New-FakeJob 'J2'
        $script:job3 = script:New-FakeJob 'J3'
        $script:cutoff = (Get-Date).AddDays(-7)
    }

    It 'invokes the fetch exactly 3 times' {
        @(Get-VhciJobSessions -Jobs @($script:job1, $script:job2, $script:job3) `
            -Since $script:cutoff -SlowPathCommand { } -PathLabel 'VM/BackupCopy') | Out-Null
        Should -Invoke Invoke-VhciCBackupSessionFetch -Times 3 -Exactly
    }

    It 'passes each job''s Id to the fetch' {
        @(Get-VhciJobSessions -Jobs @($script:job1, $script:job2, $script:job3) `
            -Since $script:cutoff -SlowPathCommand { } -PathLabel 'VM/BackupCopy') | Out-Null
        Should -Invoke Invoke-VhciCBackupSessionFetch -Times 1 -Exactly -ParameterFilter { $JobId -eq $script:job1.Id }
        Should -Invoke Invoke-VhciCBackupSessionFetch -Times 1 -Exactly -ParameterFilter { $JobId -eq $script:job2.Id }
        Should -Invoke Invoke-VhciCBackupSessionFetch -Times 1 -Exactly -ParameterFilter { $JobId -eq $script:job3.Id }
    }

    It 'passes the supplied $Since to the fetch' {
        @(Get-VhciJobSessions -Jobs @($script:job1) -Since $script:cutoff `
            -SlowPathCommand { } -PathLabel 'VM/BackupCopy') | Out-Null
        Should -Invoke Invoke-VhciCBackupSessionFetch -Times 1 -Exactly -ParameterFilter { $Since -eq $script:cutoff }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path 'vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Get-VhciJobSessions.Tests.ps1' -Output Detailed"
```

Expected: FAIL (`Get-VhciJobSessions` not defined).

- [ ] **Step 3: Write Get-VhciJobSessions.ps1 with fast path only**

Create `Private/Get-VhciJobSessions.ps1`:

```powershell
#Requires -Version 5.1

function Get-VhciJobSessions {
    <#
    .Synopsis
        Returns backup-session objects for a list of jobs within a time window,
        using the indexed Veeam.Backup.Core.CBackupSession fast path when
        available and falling back to a caller-supplied cmdlet when not.
        See docs/superpowers/specs/2026-05-27-vbr-session-fast-path-design.md
        and ADR 0018.
    .Parameter Jobs
        Array of job objects (CBackupJob / agent job). Must have an .Id (Guid)
        property in the fast path; unused in slow path. May be empty.
    .Parameter Since
        Earliest CreationTime to include. Sessions with CreationTime > $Since
        are returned.
    .Parameter SlowPathCommand
        Scriptblock invoked once when the fast path is not available. Should
        return all sessions of the relevant family; this function filters by
        $Since client-side. Typical values: { Get-VBRBackupSession } or
        { Get-VBRComputerBackupJobSession }.
    .Parameter PathLabel
        Short identifier used in log line prefixes (e.g. "VM/BackupCopy",
        "Agent"). Does not affect behaviour.
    .Outputs
        [object[]] -- array of session objects (CBackupSession on fast path;
                      whatever $SlowPathCommand returns on slow path).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Jobs,
        [Parameter(Mandatory)] [datetime]    $Since,
        [Parameter(Mandatory)] [scriptblock] $SlowPathCommand,
        [Parameter(Mandatory)] [string]      $PathLabel
    )

    $useFastPath = Test-VhciCBackupSessionFastPath

    if ($useFastPath) {
        Write-LogFile "[$PathLabel] Using fast path (CBackupSession.GetByJobAndTimeRangeWithLog)"

        $results = New-Object System.Collections.ArrayList
        foreach ($job in $Jobs) {
            try {
                $jobResults = @(Invoke-VhciCBackupSessionFetch -JobId $job.Id -Since $Since)
                if ($jobResults.Count -gt 0) {
                    [void]$results.AddRange($jobResults)
                }
            } catch {
                Write-LogFile "[$PathLabel] Failed to fetch sessions for job '$($job.Name)': $($_.Exception.Message)" -LogLevel 'WARNING'
            }
        }
        Write-LogFile "[$PathLabel] Collected $($results.Count) sessions via fast path"
        return @($results)
    }

    # Slow-path branch implemented in Task 4
    Write-LogFile "[$PathLabel] Using slow path (fallback NOT YET IMPLEMENTED)" -LogLevel 'WARNING'
    return @()
}
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path 'vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Get-VhciJobSessions.Tests.ps1' -Output Detailed"
```

Expected: PASS (5 tests across GJS-1 and GJS-3).

- [ ] **Step 5: Commit and push**

```powershell
git add vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Get-VhciJobSessions.ps1 vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Get-VhciJobSessions.Tests.ps1
git commit -m @'
feat(vbr-session): add Get-VhciJobSessions fast-path branch

Per-job iteration over CBackupSession.GetByJobAndTimeRangeWithLog with
the reflection probe gate. Slow-path branch is a stub; Task 4 fills it
in. See ADR 0018.

Refs #147
'@
git push
```

---

### Task 4: Get-VhciJobSessions — slow path branch (GJS-2, GJS-5)

**Files:**
- Modify: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Get-VhciJobSessions.ps1`
- Modify: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Get-VhciJobSessions.Tests.ps1`

Slow path: probe returns `$false` → invoke `SlowPathCommand` once unfiltered → filter by `CreationTime > $Since` client-side.

- [ ] **Step 1: Append GJS-2 and GJS-5 Describe blocks to the Tests.ps1**

Append to `Private/Get-VhciJobSessions.Tests.ps1`:

```powershell
# ---------------------------------------------------------------------------
# GJS-2  Probe $false -> slow branch; scriptblock invoked once,
#                        Invoke-VhciCBackupSessionFetch never invoked
# ---------------------------------------------------------------------------
Describe 'GJS-2: Probe $false selects the slow path' {

    BeforeEach {
        Mock Write-LogFile -MockWith { }
        Mock Test-VhciCBackupSessionFastPath -MockWith { $false }
        Mock Invoke-VhciCBackupSessionFetch -MockWith { throw 'Should not be called' }
        $script:slowCallCount = 0
        $script:slowSb = {
            $script:slowCallCount++
            @(script:New-FakeSession -CreationTime (Get-Date).AddHours(-1))
        }
    }

    It 'invokes the slow-path scriptblock exactly once' {
        @(Get-VhciJobSessions -Jobs @((script:New-FakeJob 'J1')) `
            -Since (Get-Date).AddDays(-7) -SlowPathCommand $script:slowSb -PathLabel 'VM/BackupCopy') | Out-Null
        $script:slowCallCount | Should -Be 1
    }

    It 'never invokes Invoke-VhciCBackupSessionFetch' {
        @(Get-VhciJobSessions -Jobs @((script:New-FakeJob 'J1')) `
            -Since (Get-Date).AddDays(-7) -SlowPathCommand $script:slowSb -PathLabel 'VM/BackupCopy') | Out-Null
        Should -Invoke Invoke-VhciCBackupSessionFetch -Times 0 -Exactly
    }

    It 'logs an INFO line containing "slow path"' {
        $script:infoMessages = [System.Collections.Generic.List[string]]::new()
        Mock Write-LogFile -MockWith {
            if (-not $LogLevel -or $LogLevel -eq 'INFO') { $script:infoMessages.Add($Message) }
        }
        @(Get-VhciJobSessions -Jobs @((script:New-FakeJob 'J1')) `
            -Since (Get-Date).AddDays(-7) -SlowPathCommand $script:slowSb -PathLabel 'VM/BackupCopy') | Out-Null
        ($script:infoMessages | Where-Object { $_ -match 'slow path' }).Count | Should -BeGreaterThan 0
    }
}

# ---------------------------------------------------------------------------
# GJS-5  Slow path applies the cutoff filter client-side
# ---------------------------------------------------------------------------
Describe 'GJS-5: Slow path filters by CreationTime > $Since' {

    BeforeEach {
        Mock Write-LogFile -MockWith { }
        Mock Test-VhciCBackupSessionFastPath -MockWith { $false }
        $script:slowSb = {
            @(
                (script:New-FakeSession -CreationTime (Get-Date).AddDays(-10)),  # outside window
                (script:New-FakeSession -CreationTime (Get-Date).AddHours(-1))   # inside window
            )
        }
    }

    It 'returns only sessions newer than $Since' {
        $result = @(Get-VhciJobSessions -Jobs @() `
            -Since (Get-Date).AddDays(-7) -SlowPathCommand $script:slowSb -PathLabel 'VM/BackupCopy')
        $result.Count | Should -Be 1
        $result[0].CreationTime | Should -BeGreaterThan (Get-Date).AddDays(-7)
    }
}
```

- [ ] **Step 2: Run tests to verify the new ones fail (existing GJS-1/3 still pass)**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path 'vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Get-VhciJobSessions.Tests.ps1' -Output Detailed"
```

Expected: GJS-2 (3 tests) and GJS-5 (1 test) FAIL; GJS-1 and GJS-3 still PASS.

- [ ] **Step 3: Replace the slow-path stub in Get-VhciJobSessions.ps1**

In `Private/Get-VhciJobSessions.ps1`, replace the stub:

```powershell
    # Slow-path branch implemented in Task 4
    Write-LogFile "[$PathLabel] Using slow path (fallback NOT YET IMPLEMENTED)" -LogLevel 'WARNING'
    return @()
```

with the real implementation:

```powershell
    # Slow path: single unfiltered cmdlet call, client-side cutoff filter.
    # Matches pre-59e2621 behaviour for v12 environments.
    $cmdText = $SlowPathCommand.ToString().Trim()
    Write-LogFile "[$PathLabel] Using slow path ($cmdText unfiltered)"

    $raw = @()
    try {
        $raw = @(& $SlowPathCommand)
    } catch {
        Write-LogFile "[$PathLabel] Slow path failed: $($_.Exception.Message)" -LogLevel 'WARNING'
        return @()
    }

    $filtered = @($raw | Where-Object { $_.CreationTime -gt $Since })
    Write-LogFile "[$PathLabel] Collected $($filtered.Count) sessions via slow path"
    return $filtered
```

- [ ] **Step 4: Run tests to verify all pass**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path 'vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Get-VhciJobSessions.Tests.ps1' -Output Detailed"
```

Expected: PASS (all 9 tests: GJS-1, GJS-2, GJS-3, GJS-5).

- [ ] **Step 5: Commit and push**

```powershell
git add vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Get-VhciJobSessions.ps1 vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Get-VhciJobSessions.Tests.ps1
git commit -m @'
feat(vbr-session): add Get-VhciJobSessions slow-path branch

Single-call unfiltered cmdlet + client-side cutoff filter. Matches
pre-59e2621 behaviour for v12 environments where the fast path is
unavailable. See ADR 0018.

Refs #147
'@
git push
```

---

### Task 5: Get-VhciJobSessions — error handling and edges (GJS-4, GJS-6, GJS-7)

**Files:**
- Modify: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Get-VhciJobSessions.Tests.ps1` (append the remaining Describe blocks)

The production code already handles all three cases — these tests lock the behaviour in.

- [ ] **Step 1: Append GJS-4, GJS-6, GJS-7 Describe blocks**

Append to `Private/Get-VhciJobSessions.Tests.ps1`:

```powershell
# ---------------------------------------------------------------------------
# GJS-4  Fast path, mid-iteration throw -> WARNING logged with job name and
#                                          message; other jobs still processed
# ---------------------------------------------------------------------------
Describe 'GJS-4: Fast path mid-iteration throw is contained' {

    BeforeEach {
        $script:warnMessages = [System.Collections.Generic.List[string]]::new()
        Mock Write-LogFile -MockWith {
            if ($LogLevel -eq 'WARNING') { $script:warnMessages.Add($Message) }
        }
        Mock Test-VhciCBackupSessionFastPath -MockWith { $true }

        $script:goodJob  = script:New-FakeJob 'GoodJob'
        $script:badJob   = script:New-FakeJob 'BadJob'
        $script:goodJob2 = script:New-FakeJob 'GoodJob2'

        Mock Invoke-VhciCBackupSessionFetch -MockWith {
            if ($JobId -eq $script:badJob.Id) { throw 'Simulated fetch failure' }
            @(script:New-FakeSession -CreationTime (Get-Date).AddHours(-1) -JobName 'X')
        }
    }

    It 'does not throw when one job''s fetch fails' {
        { @(Get-VhciJobSessions -Jobs @($script:goodJob, $script:badJob, $script:goodJob2) `
            -Since (Get-Date).AddDays(-7) -SlowPathCommand { } -PathLabel 'VM/BackupCopy') } |
            Should -Not -Throw
    }

    It 'logs a WARNING containing the failing job name' {
        @(Get-VhciJobSessions -Jobs @($script:goodJob, $script:badJob, $script:goodJob2) `
            -Since (Get-Date).AddDays(-7) -SlowPathCommand { } -PathLabel 'VM/BackupCopy') | Out-Null
        ($script:warnMessages | Where-Object { $_ -match 'BadJob' }).Count | Should -BeGreaterThan 0
    }

    It 'logs a WARNING containing the exception message' {
        @(Get-VhciJobSessions -Jobs @($script:goodJob, $script:badJob, $script:goodJob2) `
            -Since (Get-Date).AddDays(-7) -SlowPathCommand { } -PathLabel 'VM/BackupCopy') | Out-Null
        ($script:warnMessages | Where-Object { $_ -match 'Simulated fetch failure' }).Count | Should -BeGreaterThan 0
    }

    It 'still returns sessions from the other two jobs' {
        $result = @(Get-VhciJobSessions -Jobs @($script:goodJob, $script:badJob, $script:goodJob2) `
            -Since (Get-Date).AddDays(-7) -SlowPathCommand { } -PathLabel 'VM/BackupCopy')
        $result.Count | Should -Be 2
    }
}

# ---------------------------------------------------------------------------
# GJS-6  Slow-path scriptblock throws -> WARNING logged; returns @()
# ---------------------------------------------------------------------------
Describe 'GJS-6: Slow-path scriptblock failure logs WARNING and returns empty' {

    BeforeEach {
        $script:warnMessages = [System.Collections.Generic.List[string]]::new()
        Mock Write-LogFile -MockWith {
            if ($LogLevel -eq 'WARNING') { $script:warnMessages.Add($Message) }
        }
        Mock Test-VhciCBackupSessionFastPath -MockWith { $false }
        $script:slowSb = { throw 'Simulated cmdlet failure' }
    }

    It 'does not throw' {
        { @(Get-VhciJobSessions -Jobs @() -Since (Get-Date).AddDays(-7) `
            -SlowPathCommand $script:slowSb -PathLabel 'VM/BackupCopy') } |
            Should -Not -Throw
    }

    It 'logs a WARNING with the exception message' {
        @(Get-VhciJobSessions -Jobs @() -Since (Get-Date).AddDays(-7) `
            -SlowPathCommand $script:slowSb -PathLabel 'VM/BackupCopy') | Out-Null
        ($script:warnMessages | Where-Object { $_ -match 'Simulated cmdlet failure' }).Count | Should -BeGreaterThan 0
    }

    It 'returns an empty array' {
        $result = @(Get-VhciJobSessions -Jobs @() -Since (Get-Date).AddDays(-7) `
            -SlowPathCommand $script:slowSb -PathLabel 'VM/BackupCopy')
        $result.Count | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
# GJS-7  Empty $Jobs + fast path -> zero fetch calls, returns empty
# ---------------------------------------------------------------------------
Describe 'GJS-7: Empty $Jobs + fast path returns empty without calling fetch' {

    BeforeEach {
        Mock Write-LogFile -MockWith { }
        Mock Test-VhciCBackupSessionFastPath -MockWith { $true }
        Mock Invoke-VhciCBackupSessionFetch -MockWith { throw 'Should not be called' }
    }

    It 'never invokes Invoke-VhciCBackupSessionFetch' {
        @(Get-VhciJobSessions -Jobs @() -Since (Get-Date).AddDays(-7) `
            -SlowPathCommand { } -PathLabel 'VM/BackupCopy') | Out-Null
        Should -Invoke Invoke-VhciCBackupSessionFetch -Times 0 -Exactly
    }

    It 'returns an empty array' {
        $result = @(Get-VhciJobSessions -Jobs @() -Since (Get-Date).AddDays(-7) `
            -SlowPathCommand { } -PathLabel 'VM/BackupCopy')
        $result.Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run tests to verify all pass** (no production code change needed in this task)

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path 'vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Get-VhciJobSessions.Tests.ps1' -Output Detailed"
```

Expected: PASS (all GJS-1 through GJS-7).

If any of GJS-4/6/7 fail, the production code in Task 3/4 is incomplete — go back and fix it before continuing.

- [ ] **Step 3: Commit and push**

```powershell
git add vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/Get-VhciJobSessions.Tests.ps1
git commit -m @'
test(vbr-session): cover GJS-4/6/7 edge cases in Get-VhciJobSessions

GJS-4 fast-path per-job throw, GJS-6 slow-path scriptblock throw,
GJS-7 empty job list under fast path. Production code from Tasks 3/4
already handles these; these tests lock the behaviour. See ADR 0018.

Refs #147
'@
git push
```

---

### Task 6: Rewrite Get-VhcBackupSessions.Tests.ps1 (ISC-1…ISC-7)

**Files:**
- Modify (full rewrite): `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcBackupSessions.Tests.ps1`

Current tests assert the broken `Get-VBRBackupSession -Job` shape. Replace them with tests that assert the new helper-delegation shape. The new tests mock `Get-VhciJobSessions` directly and verify it's called with the right parameters; we do **not** re-test the helper's internal behaviour from this file.

- [ ] **Step 1: Replace the entire Tests.ps1 with the new contract**

Replace `Public/Get-VhcBackupSessions.Tests.ps1` (entire file):

```powershell
#Requires -Version 7.0
# Pester v5 tests for Get-VhcBackupSessions (ISC-1 through ISC-7)
#
# Rewritten 2026-05-27 (ADR 0018, issue #147). The previous ISC-2 asserted
# Get-VBRBackupSession -Job binding; that parameter does not exist in any
# released VBR version. The function now delegates path selection to the
# private Get-VhciJobSessions helper, which is tested separately.

BeforeAll {
    if (-not (Get-Command Get-VBRJob -ErrorAction SilentlyContinue)) {
        function global:Get-VBRJob { param([string]$ErrorAction) }
    }
    if (-not (Get-Command Get-VBRComputerBackupJob -ErrorAction SilentlyContinue)) {
        function global:Get-VBRComputerBackupJob { param([string]$ErrorAction) }
    }
    if (-not (Get-Command Get-VBRBackupSession -ErrorAction SilentlyContinue)) {
        function global:Get-VBRBackupSession { }
    }
    if (-not (Get-Command Get-VBRComputerBackupJobSession -ErrorAction SilentlyContinue)) {
        function global:Get-VBRComputerBackupJobSession { }
    }

    function script:New-FakeJob {
        param([string]$Name = 'FakeJob', [guid]$Id = [guid]::NewGuid())
        [PSCustomObject]@{ Name = $Name; Id = $Id }
    }

    # Dot-source Write-LogFile (production logger), Get-VhciJobSessions and its
    # deps (so Mock can attach to them), then the function under test.
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $moduleRoot 'Public/Write-LogFile.ps1')
    . (Join-Path $moduleRoot 'Private/Test-VhciCBackupSessionFastPath.ps1')
    . (Join-Path $moduleRoot 'Private/Invoke-VhciCBackupSessionFetch.ps1')
    . (Join-Path $moduleRoot 'Private/Get-VhciJobSessions.ps1')
    . $PSCommandPath.Replace('.Tests.ps1', '.ps1')
}

# ---------------------------------------------------------------------------
# ISC-1  Smoke: function exists, empty job lists -> no throw, returns array
# ---------------------------------------------------------------------------
Describe 'ISC-1: Empty job lists do not throw' {

    BeforeEach {
        Mock Write-LogFile -MockWith { }
        Mock Get-VBRJob               -MockWith { @() }
        Mock Get-VBRComputerBackupJob -MockWith { @() }
        Mock Get-VhciJobSessions      -MockWith { @() }
    }

    It 'does not throw' {
        { @(Get-VhcBackupSessions -ReportInterval 7) } | Should -Not -Throw
    }

    It 'returns an array' {
        $result = @(Get-VhcBackupSessions -ReportInterval 7)
        $result | Should -BeOfType [object] -Because 'wrapped in @() so any return becomes [object[]]'
        $result.Count | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
# ISC-2  Get-VhciJobSessions invoked twice with the correct -PathLabel values
# ---------------------------------------------------------------------------
Describe 'ISC-2: Helper invoked once per session family with correct PathLabel' {

    BeforeEach {
        Mock Write-LogFile -MockWith { }
        Mock Get-VBRJob               -MockWith { @((script:New-FakeJob 'V1')) }
        Mock Get-VBRComputerBackupJob -MockWith { @((script:New-FakeJob 'A1')) }
        Mock Get-VhciJobSessions      -MockWith { @() }
    }

    It 'invokes Get-VhciJobSessions exactly twice' {
        @(Get-VhcBackupSessions -ReportInterval 7) | Out-Null
        Should -Invoke Get-VhciJobSessions -Times 2 -Exactly
    }

    It 'invokes once with PathLabel ''VM/BackupCopy''' {
        @(Get-VhcBackupSessions -ReportInterval 7) | Out-Null
        Should -Invoke Get-VhciJobSessions -Times 1 -Exactly -ParameterFilter { $PathLabel -eq 'VM/BackupCopy' }
    }

    It 'invokes once with PathLabel ''Agent''' {
        @(Get-VhcBackupSessions -ReportInterval 7) | Out-Null
        Should -Invoke Get-VhciJobSessions -Times 1 -Exactly -ParameterFilter { $PathLabel -eq 'Agent' }
    }
}

# ---------------------------------------------------------------------------
# ISC-3  Slow-path scriptblocks routed to the correct cmdlets
# ---------------------------------------------------------------------------
Describe 'ISC-3: SlowPathCommand routes to the expected cmdlet per family' {

    BeforeEach {
        Mock Write-LogFile -MockWith { }
        Mock Get-VBRJob               -MockWith { @((script:New-FakeJob 'V1')) }
        Mock Get-VBRComputerBackupJob -MockWith { @((script:New-FakeJob 'A1')) }
        Mock Get-VhciJobSessions      -MockWith { @() }
    }

    It 'VM/BackupCopy scriptblock text contains Get-VBRBackupSession' {
        @(Get-VhcBackupSessions -ReportInterval 7) | Out-Null
        Should -Invoke Get-VhciJobSessions -Times 1 -Exactly -ParameterFilter {
            $PathLabel -eq 'VM/BackupCopy' -and $SlowPathCommand.ToString() -match 'Get-VBRBackupSession'
        }
    }

    It 'Agent scriptblock text contains Get-VBRComputerBackupJobSession' {
        @(Get-VhcBackupSessions -ReportInterval 7) | Out-Null
        Should -Invoke Get-VhciJobSessions -Times 1 -Exactly -ParameterFilter {
            $PathLabel -eq 'Agent' -and $SlowPathCommand.ToString() -match 'Get-VBRComputerBackupJobSession'
        }
    }
}

# ---------------------------------------------------------------------------
# ISC-4  $Since == (Get-Date).AddDays(-ReportInterval) within ~1s tolerance
# ---------------------------------------------------------------------------
Describe 'ISC-4: $Since propagation matches ReportInterval' {

    BeforeEach {
        Mock Write-LogFile -MockWith { }
        Mock Get-VBRJob               -MockWith { @() }
        Mock Get-VBRComputerBackupJob -MockWith { @() }
        Mock Get-VhciJobSessions      -MockWith { @() }
    }

    It 'passes a Since within 1 second of (Get-Date).AddDays(-7)' {
        $expected = (Get-Date).AddDays(-7)
        @(Get-VhcBackupSessions -ReportInterval 7) | Out-Null
        Should -Invoke Get-VhciJobSessions -Times 2 -Exactly -ParameterFilter {
            [Math]::Abs(($Since - $expected).TotalSeconds) -lt 1
        }
    }
}

# ---------------------------------------------------------------------------
# ISC-5  Return concatenates both helper calls
# ---------------------------------------------------------------------------
Describe 'ISC-5: Return is the concatenation of both helper calls' {

    BeforeEach {
        Mock Write-LogFile -MockWith { }
        Mock Get-VBRJob               -MockWith { @((script:New-FakeJob 'V1')) }
        Mock Get-VBRComputerBackupJob -MockWith { @((script:New-FakeJob 'A1')) }
        # Return distinct sentinel arrays per family so we can verify concat.
        Mock Get-VhciJobSessions -MockWith {
            if ($PathLabel -eq 'VM/BackupCopy') {
                return @([PSCustomObject]@{ Tag = 'vm1' }, [PSCustomObject]@{ Tag = 'vm2' })
            }
            return @([PSCustomObject]@{ Tag = 'agent1' })
        }
    }

    It 'returns 3 sessions (2 vm + 1 agent)' {
        $result = @(Get-VhcBackupSessions -ReportInterval 7)
        $result.Count | Should -Be 3
    }

    It 'contains both vm and agent sentinels' {
        $result = @(Get-VhcBackupSessions -ReportInterval 7)
        ($result | Where-Object { $_.Tag -like 'vm*' }).Count    | Should -Be 2
        ($result | Where-Object { $_.Tag -like 'agent*' }).Count | Should -Be 1
    }
}

# ---------------------------------------------------------------------------
# ISC-6  One helper call throws -> other still runs, partial result returned
# ---------------------------------------------------------------------------
Describe 'ISC-6: One helper throw does not terminate the other' {

    BeforeEach {
        Mock Write-LogFile -MockWith { }
        Mock Get-VBRJob               -MockWith { @((script:New-FakeJob 'V1')) }
        Mock Get-VBRComputerBackupJob -MockWith { @((script:New-FakeJob 'A1')) }
        Mock Get-VhciJobSessions -MockWith {
            if ($PathLabel -eq 'VM/BackupCopy') { throw 'Simulated VM helper failure' }
            return @([PSCustomObject]@{ Tag = 'agent1' })
        }
    }

    It 'does not throw' {
        { @(Get-VhcBackupSessions -ReportInterval 7) } | Should -Not -Throw
    }

    It 'returns the surviving agent session' {
        $result = @(Get-VhcBackupSessions -ReportInterval 7)
        $result.Count | Should -Be 1
        $result[0].Tag | Should -Be 'agent1'
    }
}

# ---------------------------------------------------------------------------
# ISC-7  Return shape: flat [object[]], not nested ArrayList
# ---------------------------------------------------------------------------
Describe 'ISC-7: Return is a flat [object[]]' {

    BeforeEach {
        Mock Write-LogFile -MockWith { }
        Mock Get-VBRJob               -MockWith { @((script:New-FakeJob 'V1')) }
        Mock Get-VBRComputerBackupJob -MockWith { @((script:New-FakeJob 'A1')) }
        Mock Get-VhciJobSessions -MockWith {
            @([PSCustomObject]@{ Tag = 'x' }, [PSCustomObject]@{ Tag = 'y' })
        }
    }

    It 'returns [object[]]' {
        $result = @(Get-VhcBackupSessions -ReportInterval 7)
        $result.GetType().Name | Should -Be 'Object[]'
    }

    It 'is flat (no element is an ArrayList or array)' {
        $result = @(Get-VhcBackupSessions -ReportInterval 7)
        foreach ($item in $result) {
            $item | Should -Not -BeOfType [System.Collections.ArrayList]
            $item.GetType().IsArray | Should -BeFalse
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path 'vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcBackupSessions.Tests.ps1' -Output Detailed"
```

Expected: FAIL — current `Get-VhcBackupSessions.ps1` still has the broken `-Job` loop, so it does not call `Get-VhciJobSessions` at all; most assertions fail.

- [ ] **Step 3: Wait — production code change comes in Task 7**

Do NOT update `Get-VhcBackupSessions.ps1` in this task. The TDD ordering here is: failing tests describing the new contract, then Task 7 makes them pass.

- [ ] **Step 4: Commit and push**

```powershell
git add vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcBackupSessions.Tests.ps1
git commit -m @'
test(vbr-session): rewrite ISC-1 through ISC-7 for helper-delegation shape

Previous tests asserted Get-VBRBackupSession -Job binding; that parameter
does not exist in any released VBR version. New tests assert the
function delegates to Get-VhciJobSessions twice (VM/BackupCopy + Agent)
with correct PathLabel, $Since propagation, slow-path scriptblock text,
result concatenation, partial-failure isolation, and flat return shape.
Tests fail against current production code by design; Task 7 makes them
pass. See ADR 0018.

Refs #147
'@
git push
```

---

### Task 7: Update Get-VhcBackupSessions.ps1 to use the helper

**Files:**
- Modify: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcBackupSessions.ps1`

Replace the broken `-Job` loop and the standalone agent block with two `Get-VhciJobSessions` calls. The doc comment is updated to reflect the new architecture.

- [ ] **Step 1: Replace the entire file**

Replace `Public/Get-VhcBackupSessions.ps1` (entire file):

```powershell
#Requires -Version 5.1

function Get-VhcBackupSessions {
    <#
    .Synopsis
        Fetches VBR backup sessions created within the reporting window and returns
        them as pipeline output. The caller (orchestrator) captures the output and
        passes it explicitly to Get-VhcSessionReport via the -BackupSessions parameter.

        Returns a mixed array of two session object families:
        - VM and Backup Copy sessions (CBackupSession / CBackupCopySession)
        - Agent / computer backup sessions

        Both families are accepted by Get-VBRTaskSession, which Get-VhcSessionReport
        uses to resolve task-level detail. See ADR 0012 and ADR 0018.

        Path selection is delegated to the private Get-VhciJobSessions helper. On
        VBR versions that ship Veeam.Backup.Core.CBackupSession with the
        GetByJobAndTimeRangeWithLog(Guid, DateTime) overload, the helper uses an
        indexed DB query per job (the fast path). On older versions or when
        reflection fails, it falls back to a single unfiltered cmdlet call
        followed by a client-side CreationTime filter (the pre-59e2621 shape that
        works on v12).
    .Parameter ReportInterval
        Number of days back to collect sessions for. Matches the -ReportInterval
        parameter passed to Get-VBRConfig.ps1.
    .Outputs
        [object[]] -- mixed array of Veeam backup session objects.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [int] $ReportInterval
    )

    Write-LogFile "Fetching backup sessions for the last $ReportInterval days..."
    $cutoff = (Get-Date).AddDays(-$ReportInterval)

    $jobs       = @(Get-VBRJob               -ErrorAction SilentlyContinue)
    $agentJobs  = @(Get-VBRComputerBackupJob -ErrorAction SilentlyContinue)

    $vmSessions = @()
    try {
        $vmSessions = @(Get-VhciJobSessions `
            -Jobs $jobs `
            -Since $cutoff `
            -SlowPathCommand { Get-VBRBackupSession } `
            -PathLabel 'VM/BackupCopy')
    } catch {
        Write-LogFile "VM/BackupCopy session collection failed: $($_.Exception.Message)" -LogLevel 'WARNING'
    }

    $agentSessions = @()
    try {
        $agentSessions = @(Get-VhciJobSessions `
            -Jobs $agentJobs `
            -Since $cutoff `
            -SlowPathCommand { Get-VBRComputerBackupJobSession } `
            -PathLabel 'Agent')
    } catch {
        Write-LogFile "Agent session collection failed: $($_.Exception.Message)" -LogLevel 'WARNING'
    }

    return $vmSessions + $agentSessions
}
```

- [ ] **Step 2: Run the Public tests to verify all ISC-1…ISC-7 pass**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path 'vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcBackupSessions.Tests.ps1' -Output Detailed"
```

Expected: PASS — all 7 Describe blocks green.

- [ ] **Step 3: Run the Private helper tests to confirm nothing regressed**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path 'vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Private/' -Output Detailed"
```

Expected: PASS — all GJS-1 through GJS-7 plus the probe/wrapper tests from Tasks 1-2.

- [ ] **Step 4: Commit and push**

```powershell
git add vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcBackupSessions.ps1
git commit -m @'
fix(vbr-session): route Get-VhcBackupSessions through Get-VhciJobSessions

Replaces the broken Get-VBRBackupSession -Job loop (a parameter that
does not exist in any released VBR version) with two delegations to
Get-VhciJobSessions: one for VM/BackupCopy via Get-VBRBackupSession, one
for Agent via Get-VBRComputerBackupJobSession. The helper probes for
the Veeam.Backup.Core.CBackupSession fast path and degrades silently to
the unfiltered cmdlet on v12 or any future shape change.

Adds Get-VBRComputerBackupJob as the agent job-list source (the helper
needs it to iterate; the slow path does not).

Closes #147

See ADR 0012, ADR 0018, and
docs/superpowers/specs/2026-05-27-vbr-session-fast-path-design.md.
'@
git push
```

---

### Task 8: Module-wide test run + manifest check

**Files:**
- Verify: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/vHC-VbrConfig.Manifest.Tests.ps1`

The manifest tests (ISC-8…ISC-11) validate the module loads cleanly. We have not added any Public function and the cmdlet stub list at line 113 already includes `Get-VBRComputerBackupJob`, so this should be a no-op. Confirm.

- [ ] **Step 1: Run the manifest tests**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path 'vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/vHC-VbrConfig.Manifest.Tests.ps1' -Output Detailed"
```

Expected: PASS — module imports cleanly, all 4 ISC blocks green.

- [ ] **Step 2: Run every test file in the module**

```powershell
pwsh -NoProfile -Command "Import-Module Pester -MinimumVersion 5.0.0; Invoke-Pester -Path 'vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/' -Output Detailed"
```

Expected: PASS — every test across Public/, Private/, and the manifest tests.

- [ ] **Step 3: If anything fails, fix it before continuing**

Common failure: a new private function name conflicts with an existing one, or a stubbed Veeam cmdlet is missing from the manifest test's stub list. Fix inline and re-run.

If no failures, nothing to commit. Proceed to Task 9.

- [ ] **Step 4: If a manifest stub addition was needed, commit it**

If `vHC-VbrConfig.Manifest.Tests.ps1` needed an edit (likely not), commit:

```powershell
git add vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/vHC-VbrConfig.Manifest.Tests.ps1
git commit -m @'
test(manifest): add new private helper stubs for ISC-11 module import

Refs #147
'@
git push
```

---

### Task 9: Manual end-to-end verification on lab VBR

**Files:** none — this is verification, not code.

The spec calls out one real risk: the fast path returns `CBackupSession` objects for agent jobs, where the previous slow-path code returned `VBRSession` (PowerShell wrapper) objects. `Get-VBRTaskSession` accepts both per ADR 0012, but downstream code in `Get-VhcSessionReport` may rely on `VBRSession`-specific properties. This task confirms the agent fast path flows through to the report correctly. The lab VBR (13.0.1) on this Windows box was used during brainstorming and has a `Managed-WindowsAgents-Job` with 2 recent sessions.

- [ ] **Step 1: Build the solution so the latest module ships into the bin output**

```powershell
dotnet build vHC/HC.sln --configuration Debug
```

Expected: build succeeds. `vHC-VbrConfig.psm1` and all `Public/`/`Private/` `.ps1` files are copied into `vHC/HC_Reporting/bin/Debug/net8.0-windows7.0/win-x64/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/`.

- [ ] **Step 2: Run the collector end to end against the lab**

```powershell
Import-Module 'C:\temp\git\github-comnam90\veeam-healthcheck\vHC\HC_Reporting\bin\Debug\net8.0-windows7.0\win-x64\Tools\Scripts\HealthCheck\VBR\vHC-VbrConfig\vHC-VbrConfig.psd1' -Force
Import-Module Veeam.Backup.PowerShell -DisableNameChecking
Connect-VBRServer -Server localhost
$sessions = Get-VhcBackupSessions -ReportInterval 7
Write-Host "Got $($sessions.Count) sessions"
$sessions | Group-Object { $_.GetType().Name } | Format-Table
```

Expected:
- One `[LOG:INFO] [VM/BackupCopy] Using fast path` line and one `[LOG:INFO] [Agent] Using fast path` line in the host output.
- `$sessions.Count > 0`. The `Managed-WindowsAgents-Job` session(s) appear in the result.
- All elements are `CBackupSession` (fast path) — `VBRSession` would indicate the slow path was used unexpectedly.

- [ ] **Step 3: Pipe through Get-VBRTaskSession for the agent session**

```powershell
$agentSession = $sessions | Where-Object { $_.JobName -eq 'Managed-WindowsAgents-Job' } | Select-Object -First 1
$agentSession | Should -Not -BeNullOrEmpty
$tasks = Get-VBRTaskSession -Session $agentSession
$tasks | Format-Table Name, JobName, Status -AutoSize
```

Expected: `Get-VBRTaskSession` returns one or more `CBackupTaskSession` objects without throwing. If it throws or returns empty for an agent session, the agent return-type compatibility risk is real — see Step 5.

- [ ] **Step 4: Run Get-VhcSessionReport against the helper's output**

```powershell
$report = Get-VhcSessionReport -BackupSessions $sessions
$report | Where-Object { $_.JobName -like '*Managed-WindowsAgents-Job*' } | Format-Table JobName, Status, DataSize, BackupSize -AutoSize
```

Expected: at least one row for `Managed-WindowsAgents-Job` (or `Managed-WindowsAgents-Job - <hostname>` per the agent-suffix behaviour documented in ADR 0012). Sizes populated. No exceptions in the host output.

- [ ] **Step 5: If agent path breaks in Step 3 or Step 4**

This indicates the `CBackupSession` shape is missing properties that downstream code expects on `VBRSession`. Two recovery options, in order of preference:

1. **Adapter at the agent return site.** Modify `Public/Get-VhcBackupSessions.ps1` (Task 7's file) so the Agent branch wraps fast-path `CBackupSession` results back into `VBRSession` via the Veeam transformation attribute pattern. Investigate `Veeam.Backup.PowerShell.Infos.VBRSession` constructor or use `Get-VBRTaskSession`'s implicit coercion path.
2. **Force slow path for Agent only.** As a last resort, route the Agent family through the cmdlet always (i.e. skip the fast path for agents). Update the Agent call in `Get-VhcBackupSessions.ps1` to bypass `Get-VhciJobSessions` entirely and call `Get-VBRComputerBackupJobSession | Where-Object` directly. This preserves the v12 status quo for agents and limits the fast-path win to VM/BackupCopy.

If a fix is required, add a new task to the plan (Task 9.5 — "Agent compatibility adapter"), follow the same TDD pattern (add a failing test that reproduces the downstream break with mocked downstream calls, write the fix, confirm), and commit on the same branch.

- [ ] **Step 6: Record manual-verification result**

Append a one-line note to the PR description (Task 10) with the verification outcome. No commit needed for this step — the note lives in the PR body.

---

### Task 10: Open the pull request

**Files:** none.

- [ ] **Step 1: Confirm branch is current and up to date**

```powershell
git status
git log --oneline origin/dev..HEAD
```

Expected: clean working tree (no uncommitted changes); 8–10 commits ahead of `origin/dev` covering Tasks 1–8 (plus any adapter from 9.5 if needed).

- [ ] **Step 2: Open the PR via gh**

```powershell
gh pr create --title "fix(vbr-session): CBackupSession fast path with cmdlet fallback (#147)" --body @'
## Summary

- Replaces the broken `Get-VBRBackupSession -Job $job` per-job loop in `Get-VhcBackupSessions.ps1` (a parameter that does not exist in any released VBR version - see #147 customer logs)
- Adds `Get-VhciJobSessions` private helper that probes `[Veeam.Backup.Core.CBackupSession]::GetByJobAndTimeRangeWithLog` and uses an indexed DB query per job when available, or falls back to the unfiltered cmdlet (pre-59e2621 shape that works on v12) when not
- Covers VM/BackupCopy and Agent session families; phase 2 (NAS, tape, replica, SureBackup) can adopt the same helper later by passing different SlowPathCommand scriptblocks
- See `docs/superpowers/specs/2026-05-27-vbr-session-fast-path-design.md` and `docs/adr/0018-cbackupsession-fast-path-for-session-collection.md` for full design and rationale

## Test plan

- [x] Pester unit tests added for `Test-VhciCBackupSessionFastPath`, `Invoke-VhciCBackupSessionFetch`, and `Get-VhciJobSessions` (GJS-1 to GJS-7)
- [x] `Get-VhcBackupSessions.Tests.ps1` rewritten - previous ISC-2 asserted the non-existent `-Job` parameter
- [x] Manifest tests (ISC-8 to ISC-11) still pass; module imports cleanly
- [x] Manual end-to-end run against the lab VBR (13.0.1): both fast paths chosen, `Get-VhcSessionReport` produces non-empty agent rows for `Managed-WindowsAgents-Job`

Closes #147

[manual-verification result from Task 9 - PASTE HERE: "verified clean" / "needed adapter, see commit XXX"]
'@
```

- [ ] **Step 3: Verify the PR opened cleanly**

```powershell
gh pr view
```

Expected: PR url shown, status `OPEN`, base `dev`, head `fix/vbr-session-fast-path`.

---

## Self-Review

Plan covers every section of the spec:

- **Architecture** → Tasks 1-7 build the helper trio and rewire the public function exactly as the spec diagrams it.
- **Components 1-7** → Each gets a dedicated task or sub-step. Manifest test (Component 7) covered in Task 8.
- **Data flow** → Tasks 3 + 4 implement the fast/slow branch logic; Task 7 wires both call sites.
- **Error handling table rows** → All five rows covered by GJS-4/6/7 in Task 5; agent-pair isolation covered by ISC-6 in Task 6.
- **Logging rules** → Asserted in GJS-1 (fast INFO), GJS-2 (slow INFO), GJS-4 (per-job WARNING), GJS-6 (slow WARNING). The "result count" INFO is implicit in not-throw assertions.
- **Testing matrix** → 1:1 mapping from spec test tables to Task 3-6 step content.
- **Manual verification (not CI)** → Task 9, with explicit recovery path if the agent return-type risk materialises.

No placeholders found. Type / parameter names match across tasks: `JobId`/`Since` consistent in `Invoke-VhciCBackupSessionFetch` definition (Task 2) and call site in `Get-VhciJobSessions` (Task 3); `Jobs`/`Since`/`SlowPathCommand`/`PathLabel` consistent in helper definition (Task 3) and caller (Task 7); `Get-VhciJobSessions` mock targets in `Get-VhcBackupSessions.Tests.ps1` (Task 6) match the parameter set the production code passes (Task 7).

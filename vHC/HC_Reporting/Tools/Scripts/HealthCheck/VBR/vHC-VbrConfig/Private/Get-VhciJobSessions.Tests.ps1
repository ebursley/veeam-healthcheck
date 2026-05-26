#Requires -Version 7.0
# Pester v5 tests for Get-VhciJobSessions (GJS-1 through GJS-7).
# PS 7 is required because the project's test convention runs Pester v5 under
# pwsh; PS 5.1 ships Pester v3 which lacks the Should -BeOfType syntax used
# below. See docs/plans/2026-05-27-vbr-session-fast-path.md Task Conventions.
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

    It 'excludes sessions older than $Since' {
        # Slow path ignores $Jobs (correct per design); empty job list is fine here.
        $result = @(Get-VhciJobSessions -Jobs @() `
            -Since (Get-Date).AddDays(-7) -SlowPathCommand $script:slowSb -PathLabel 'VM/BackupCopy')
        # Two sessions are fed in (one 10 days old, one 1 hour old). Only the
        # 1-hour-old one is within the 7-day window.
        $result.Count | Should -Be 1
    }

    It 'includes sessions newer than $Since' {
        $result = @(Get-VhciJobSessions -Jobs @() `
            -Since (Get-Date).AddDays(-7) -SlowPathCommand $script:slowSb -PathLabel 'VM/BackupCopy')
        $result[0].CreationTime | Should -BeGreaterThan (Get-Date).AddDays(-7)
    }
}

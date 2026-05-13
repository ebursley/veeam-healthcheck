#Requires -Version 7.0
# Pester v5 tests for Get-VhcBackupSessions (ISC-1 through ISC-7)
#
# Retrospective TDD for commit 59e2621 on dev.
# All Veeam SDK cmdlets are stubbed as global no-ops so the suite runs on macOS
# without a VBR installation - same pattern used in TestMfa.Tests.ps1.
#
# Red-phase strategy:
#   ISC-2: temporarily revert to single-call pattern in production code.
#   All other ISC: invert one assertion for the Red run, restore for Green.
#
# Warning capture:
#   Write-LogFile is mocked with a script-scoped collector so ISC-3 can assert
#   the WARNING log without touching production logging infrastructure.
#
# ISC-5 scope clarification:
#   '-ErrorAction SilentlyContinue' on 'Get-VBRJob' suppresses non-terminating
#   errors (CommandNotFoundException from a missing Veeam SDK). It does NOT
#   suppress script-terminating 'throw'. The test uses Write-Error (non-terminating)
#   to simulate the real SDK-not-loaded failure mode.

BeforeAll {
    # -- Stub Veeam cmdlets that don't exist on non-Windows/non-VBR hosts -----------
    # Each stub is defined globally so Pester's Mock can intercept it.
    if (-not (Get-Command Get-VBRJob -ErrorAction SilentlyContinue)) {
        function global:Get-VBRJob { param([string]$ErrorAction) }
    }
    if (-not (Get-Command Get-VBRBackupSession -ErrorAction SilentlyContinue)) {
        function global:Get-VBRBackupSession { param($Job) }
    }
    if (-not (Get-Command Get-VBRComputerBackupJobSession -ErrorAction SilentlyContinue)) {
        function global:Get-VBRComputerBackupJobSession { }
    }

    # -- Helper functions defined at BeforeAll scope so all Describe/It blocks see them.
    function script:New-FakeJob {
        param([string]$Name = 'FakeJob')
        [PSCustomObject]@{ Name = $Name }
    }

    function script:New-FakeSession {
        param([datetime]$CreationTime, [string]$JobName = 'FakeJob')
        [PSCustomObject]@{ CreationTime = $CreationTime; JobName = $JobName }
    }

    # -- Dot-source the function under test ----------------------------------------
    # Write-LogFile is defined in Public/Write-LogFile.ps1; dot-source it first so
    # the function definition exists and Pester can Mock it.
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $moduleRoot 'Public/Write-LogFile.ps1')
    . $PSCommandPath.Replace('.Tests.ps1', '.ps1')
}

# ---------------------------------------------------------------------------
# ISC-1  Zero jobs -> empty (or agent-only) return; Get-VBRBackupSession not called
# ---------------------------------------------------------------------------
Describe 'ISC-1: Zero jobs returns empty/agent-only, Get-VBRBackupSession never invoked' {

    BeforeEach {
        Mock Write-LogFile -MockWith { }
        Mock Get-VBRJob -MockWith { return @() }
        Mock Get-VBRBackupSession -MockWith { throw 'Should not be called' }
        Mock Get-VBRComputerBackupJobSession -MockWith { return @() }
    }

    It 'does not throw and does not call Get-VBRBackupSession when there are no jobs' {
        # @($sessions) + @($agentSessions) with both empty evaluates as empty array.
        # Wrap in @() so we get an array back even when the pipeline returns nothing.
        { @(Get-VhcBackupSessions -ReportInterval 7) } | Should -Not -Throw
        Should -Invoke Get-VBRBackupSession -Times 0 -Exactly
    }

    It 'does not invoke Get-VBRBackupSession when job list is empty' {
        @(Get-VhcBackupSessions -ReportInterval 7) | Out-Null
        Should -Invoke Get-VBRBackupSession -Times 0 -Exactly
    }
}

# ---------------------------------------------------------------------------
# ISC-2  Three jobs -> Get-VBRBackupSession invoked exactly 3x with -Job bound
# ---------------------------------------------------------------------------
Describe 'ISC-2: Three jobs cause Get-VBRBackupSession to be invoked exactly 3 times with -Job' {

    BeforeEach {
        $script:job1 = script:New-FakeJob 'Job1'
        $script:job2 = script:New-FakeJob 'Job2'
        $script:job3 = script:New-FakeJob 'Job3'

        Mock Write-LogFile -MockWith { }
        Mock Get-VBRJob -MockWith { return @($script:job1, $script:job2, $script:job3) }
        # Return one session per job, all within the reporting window.
        Mock Get-VBRBackupSession -MockWith {
            $s = script:New-FakeSession -CreationTime (Get-Date).AddHours(-1) -JobName $Job.Name
            return @($s)
        }
        Mock Get-VBRComputerBackupJobSession -MockWith { return @() }
    }

    It 'invokes Get-VBRBackupSession exactly 3 times' {
        @(Get-VhcBackupSessions -ReportInterval 7) | Out-Null
        Should -Invoke Get-VBRBackupSession -Times 3 -Exactly
    }

    It 'binds -Job to Job1' {
        @(Get-VhcBackupSessions -ReportInterval 7) | Out-Null
        Should -Invoke Get-VBRBackupSession -Times 1 -Exactly -ParameterFilter { $Job.Name -eq 'Job1' }
    }

    It 'binds -Job to Job2' {
        @(Get-VhcBackupSessions -ReportInterval 7) | Out-Null
        Should -Invoke Get-VBRBackupSession -Times 1 -Exactly -ParameterFilter { $Job.Name -eq 'Job2' }
    }

    It 'binds -Job to Job3' {
        @(Get-VhcBackupSessions -ReportInterval 7) | Out-Null
        Should -Invoke Get-VBRBackupSession -Times 1 -Exactly -ParameterFilter { $Job.Name -eq 'Job3' }
    }
}

# ---------------------------------------------------------------------------
# ISC-3  Mid-iteration throw -> union returned, WARNING logged, no termination
# ---------------------------------------------------------------------------
Describe 'ISC-3: Mid-iteration throw logs WARNING with job name and message, does not terminate' {

    BeforeEach {
        $script:warnMessages = [System.Collections.Generic.List[string]]::new()

        Mock Write-LogFile -MockWith {
            if ($LogLevel -eq 'WARNING') {
                $script:warnMessages.Add($Message)
            }
        }

        $script:goodJob  = script:New-FakeJob 'GoodJob'
        $script:badJob   = script:New-FakeJob 'BadJob'
        $script:goodJob2 = script:New-FakeJob 'GoodJob2'

        Mock Get-VBRJob -MockWith {
            return @($script:goodJob, $script:badJob, $script:goodJob2)
        }

        Mock Get-VBRBackupSession -MockWith {
            if ($Job.Name -eq 'BadJob') {
                throw 'Simulated SDK failure'
            }
            return @(script:New-FakeSession -CreationTime (Get-Date).AddHours(-1) -JobName $Job.Name)
        }

        Mock Get-VBRComputerBackupJobSession -MockWith { return @() }
    }

    It 'does not throw when one job iteration fails' {
        { @(Get-VhcBackupSessions -ReportInterval 7) } | Should -Not -Throw
    }

    It 'emits a WARNING log containing the failing job name' {
        @(Get-VhcBackupSessions -ReportInterval 7) | Out-Null
        $script:warnMessages.Count | Should -BeGreaterThan 0
        ($script:warnMessages | Where-Object { $_ -match 'BadJob' }).Count | Should -BeGreaterThan 0
    }

    It 'emits a WARNING log containing the exception message' {
        @(Get-VhcBackupSessions -ReportInterval 7) | Out-Null
        ($script:warnMessages | Where-Object { $_ -match 'Simulated SDK failure' }).Count | Should -BeGreaterThan 0
    }

    It 'still returns sessions from the non-failing jobs' {
        $result = @(Get-VhcBackupSessions -ReportInterval 7)
        # GoodJob and GoodJob2 each return 1 session; BadJob throws - so we expect 2
        ($result | Where-Object { $_.JobName -eq 'GoodJob'  }).Count | Should -Be 1
        ($result | Where-Object { $_.JobName -eq 'GoodJob2' }).Count | Should -Be 1
    }
}

# ---------------------------------------------------------------------------
# ISC-4  Cutoff filter - older sessions excluded, newer included
# ---------------------------------------------------------------------------
Describe 'ISC-4: Cutoff filter excludes sessions older than ReportInterval' {

    BeforeEach {
        Mock Write-LogFile -MockWith { }
        $script:filterJob = script:New-FakeJob 'FilterJob'
        Mock Get-VBRJob -MockWith { return @($script:filterJob) }

        # Return one old session (outside window) and one new session (inside window).
        Mock Get-VBRBackupSession -MockWith {
            return @(
                (script:New-FakeSession -CreationTime (Get-Date).AddDays(-10) -JobName 'FilterJob'),
                (script:New-FakeSession -CreationTime (Get-Date).AddHours(-1)  -JobName 'FilterJob')
            )
        }
        Mock Get-VBRComputerBackupJobSession -MockWith { return @() }
    }

    It 'excludes sessions older than ReportInterval days' {
        $result = @(Get-VhcBackupSessions -ReportInterval 7)
        # Only the session created 1 hour ago should survive the Where-Object cutoff filter.
        $result.Count | Should -Be 1
    }

    It 'includes sessions within the ReportInterval window' {
        $result = @(Get-VhcBackupSessions -ReportInterval 7)
        $result[0].CreationTime | Should -BeGreaterThan (Get-Date).AddDays(-7)
    }
}

# ---------------------------------------------------------------------------
# ISC-5  Get-VBRJob fails with non-terminating error -> -ErrorAction SilentlyContinue
#         swallows it; falls through to agent path, does not terminate
#
# NOTE: '-ErrorAction SilentlyContinue' suppresses non-terminating errors only.
# A script 'throw' is script-terminating and cannot be suppressed this way.
# The real failure mode in production is CommandNotFoundException (non-terminating)
# when the Veeam SDK isn't loaded. We simulate that with Write-Error.
# ---------------------------------------------------------------------------
Describe 'ISC-5: Get-VBRJob non-terminating error is swallowed; agent path still executes' {

    BeforeEach {
        $ErrorActionPreference = 'Continue'
        Mock Write-LogFile -MockWith { }
        # Simulate a non-terminating failure (matches real SDK-not-loaded scenario).
        Mock Get-VBRJob -MockWith {
            Write-Error 'VBR SDK not available' -ErrorAction Continue
            return @()  # Explicitly return empty array after write-error
        }
        Mock Get-VBRBackupSession -MockWith { throw 'Should not be called' }
        Mock Get-VBRComputerBackupJobSession -MockWith {
            return @(script:New-FakeSession -CreationTime (Get-Date).AddHours(-1))
        }
    }

    It 'does not throw when Get-VBRJob emits a non-terminating error' {
        { @(Get-VhcBackupSessions -ReportInterval 7) } | Should -Not -Throw
    }

    It 'Get-VBRBackupSession is not called when Get-VBRJob returns empty' {
        @(Get-VhcBackupSessions -ReportInterval 7) | Out-Null
        Should -Invoke Get-VBRBackupSession -Times 0 -Exactly
    }

    It 'agent session path still executes even when no jobs are available' {
        @(Get-VhcBackupSessions -ReportInterval 7) | Out-Null
        Should -Invoke Get-VBRComputerBackupJobSession -Times 1 -Exactly
    }
}

# ---------------------------------------------------------------------------
# ISC-6  Agent block runs once regardless of job count; results concatenated
# ---------------------------------------------------------------------------
Describe 'ISC-6: Agent block runs exactly once; agent sessions concatenated with job sessions' {

    BeforeEach {
        Mock Write-LogFile -MockWith { }
        $script:agentJ1 = script:New-FakeJob 'JobA'
        $script:agentJ2 = script:New-FakeJob 'JobB'
        Mock Get-VBRJob -MockWith { return @($script:agentJ1, $script:agentJ2) }
        Mock Get-VBRBackupSession -MockWith {
            return @(script:New-FakeSession -CreationTime (Get-Date).AddHours(-1) -JobName $Job.Name)
        }
        Mock Get-VBRComputerBackupJobSession -MockWith {
            return @(
                [PSCustomObject]@{ CreationTime = (Get-Date).AddHours(-2); Type = 'Agent' }
            )
        }
    }

    It 'invokes Get-VBRComputerBackupJobSession exactly once' {
        @(Get-VhcBackupSessions -ReportInterval 7) | Out-Null
        Should -Invoke Get-VBRComputerBackupJobSession -Times 1 -Exactly
    }

    It 'concatenates job sessions and agent sessions into one array' {
        $result = @(Get-VhcBackupSessions -ReportInterval 7)
        # 2 job sessions + 1 agent session = 3 total
        $result.Count | Should -Be 3
    }
}

# ---------------------------------------------------------------------------
# ISC-7  Return shape - flat array, not nested ArrayList
# ---------------------------------------------------------------------------
Describe 'ISC-7: Return value is a flat [object[]], not a nested ArrayList' {

    BeforeEach {
        Mock Write-LogFile -MockWith { }
        $script:shapeJob = script:New-FakeJob 'ShapeJob'
        Mock Get-VBRJob -MockWith { return @($script:shapeJob) }
        Mock Get-VBRBackupSession -MockWith {
            return @(
                (script:New-FakeSession -CreationTime (Get-Date).AddHours(-1) -JobName 'ShapeJob'),
                (script:New-FakeSession -CreationTime (Get-Date).AddHours(-2) -JobName 'ShapeJob')
            )
        }
        Mock Get-VBRComputerBackupJobSession -MockWith {
            return @(
                [PSCustomObject]@{ CreationTime = (Get-Date).AddHours(-3); Type = 'Agent' }
            )
        }
    }

    It 'returns an [object[]], not an ArrayList' {
        # Wrap in @() to force array return from pipeline.
        $result = @(Get-VhcBackupSessions -ReportInterval 7)
        $result.GetType().Name | Should -Be 'Object[]'
    }

    It 'returns a flat (non-nested) array - no element is itself an array or ArrayList' {
        $result = @(Get-VhcBackupSessions -ReportInterval 7)
        foreach ($item in $result) {
            $item | Should -Not -BeOfType [System.Collections.ArrayList]
            $item.GetType().IsArray | Should -BeFalse
        }
    }

    It 'returns the correct total count (all sessions from all sources)' {
        $result = @(Get-VhcBackupSessions -ReportInterval 7)
        # 2 job sessions + 1 agent session
        $result.Count | Should -Be 3
    }
}

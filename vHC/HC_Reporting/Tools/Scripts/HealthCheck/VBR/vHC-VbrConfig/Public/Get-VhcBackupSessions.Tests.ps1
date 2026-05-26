#Requires -Version 7.0
# Pester v5 tests for Get-VhcBackupSessions (ISC-1 through ISC-7).
#
# Rewritten 2026-05-27 (ADR 0018, issue #147). The previous ISC-2 asserted
# Get-VBRBackupSession -Job binding; that parameter does not exist in any
# released VBR version. The function now delegates path selection to the
# private Get-VhciJobSessions helper, which is tested separately.
#
# PS 7 is required because the project's test convention runs Pester v5 under
# pwsh; PS 5.1 ships Pester v3 which lacks the Should -BeOfType syntax used
# below. See docs/plans/2026-05-27-vbr-session-fast-path.md Task Conventions.

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

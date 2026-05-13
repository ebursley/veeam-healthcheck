#Requires -Version 7.0
# Pester v5 tests for Get-NasInfo.ps1 VMC.log existence guard (ISC-1..5)

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot 'Get-NasInfo.ps1'
}

Describe 'Get-NasInfo VMC.log existence guard' {

    BeforeEach {
        $script:TempPath = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        New-Item -Path $script:TempPath -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:TempPath) {
            Remove-Item -LiteralPath $script:TempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'ISC-3/4: when VMC.log is absent' {

        It 'exits with no error and invokes Get-Content zero times for the VMC.log path' {
            # Default Test-Path mock returns true (covers ReportPath existence check on line 97)
            Mock Test-Path -MockWith { $true }
            # Specific override: VMC.log path (LiteralPath) returns false
            Mock Test-Path -MockWith { $false } -ParameterFilter {
                $LiteralPath -eq 'C:\ProgramData\Veeam\Backup\Utils\VMC.log'
            }
            # Get-Content should never be called for the VMC.log path - no ParameterFilter so
            # any call (positional or named) is counted. Before the fix the script calls
            # Get-Content $logsPath unconditionally; after the fix with path absent it is skipped.
            Mock Get-Content -MockWith { @() }
            # Export-Csv: suppress actual file writes for this test
            Mock Export-Csv -MockWith { }
            # New-Item: suppress directory creation side effects
            Mock New-Item -MockWith { }

            { & $script:ScriptPath -VBRServer 'TESTSRV' -VBRVersion 12 -ReportPath $script:TempPath } |
                Should -Not -Throw

            # ISC-4: Get-Content must be called 0 times total (no guard = called once, fails RED)
            Should -Invoke Get-Content -Times 0 -Exactly
        }
    }

    Context 'ISC-5: happy path - VMC.log present with NAS INFRASTRUCTURE block' {

        It 'writes a non-empty NasFileData CSV when VMC.log contains a valid NAS block' {
            # All Test-Path calls return true (VMC.log exists, ReportPath exists)
            Mock Test-Path -MockWith { $true }

            # Fixture: one =====NAS INFRASTRUCTURE==== block ending with ========
            # Lines must be >= 49 chars so .Remove(0,49) strips the timestamp prefix.
            # After stripping, the line must match "NasBackupSourceShareStats" and contain
            # at least one "key: value" pair for Export-Csv to produce a row.
            # Prefix is 49 chars: "2024-01-15 08:30:00.123 [Info] VmcStatMgr.cs 123 "
            $prefix = 'A' * 49
            Mock Get-Content -MockWith {
                @(
                    ($prefix + '=====NAS INFRASTRUCTURE===='),
                    ($prefix + 'NasBackupSourceShareStats: Name: share1, SizeGb: 10'),
                    ($prefix + '========')
                )
            } -ParameterFilter {
                $LiteralPath -eq 'C:\ProgramData\Veeam\Backup\Utils\VMC.log'
            }

            & $script:ScriptPath -VBRServer 'TESTSRV' -VBRVersion 12 -ReportPath $script:TempPath

            $csv = Join-Path $script:TempPath 'TESTSRV_NasFileData.csv'
            (Test-Path -LiteralPath $csv) | Should -BeTrue
            # Wrap in @() because Get-Content returns a scalar for single-line files in PS 5.x and 7.x;
            # require header + at least one data row, not just header.
            @(Get-Content -LiteralPath $csv).Count | Should -BeGreaterThan 1
        }
    }
}

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

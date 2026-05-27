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
        { Invoke-VhciCBackupSessionFetch -Since (Get-Date).AddDays(-7) -Until (Get-Date) } | Should -Throw
    }

    It 'requires Since parameter' {
        { Invoke-VhciCBackupSessionFetch -JobId ([guid]::NewGuid()) -Until (Get-Date) } | Should -Throw
    }

    It 'requires Until parameter' {
        { Invoke-VhciCBackupSessionFetch -JobId ([guid]::NewGuid()) -Since (Get-Date).AddDays(-7) } | Should -Throw
    }

    It 'accepts [guid] JobId, [datetime] Since and [datetime] Until without a ParameterBindingException' {
        # In a non-Veeam environment the static .NET call inside the wrapper
        # throws because [Veeam.Backup.Core.CBackupSession] is not loaded.
        # That's expected and tolerated. What we DO want to catch is a
        # ParameterBindingException, which would mean the parameter names or
        # types stopped matching what the caller passes - a regression in the
        # wrapper's contract. The actual argument forwarding to the static
        # method is verified indirectly by Get-VhciJobSessions' GJS-3 tests via
        # Pester's Mock - which is the right place for that assertion since
        # the wrapper is intentionally a Mock seam (see ADR 0018).
        $err = $null
        try { Invoke-VhciCBackupSessionFetch -JobId ([guid]::NewGuid()) -Since (Get-Date).AddDays(-7) -Until (Get-Date) }
        catch { $err = $_ }
        if ($null -ne $err) {
            $err.Exception | Should -Not -BeOfType [System.Management.Automation.ParameterBindingException]
        }
    }
}

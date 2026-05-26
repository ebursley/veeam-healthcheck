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

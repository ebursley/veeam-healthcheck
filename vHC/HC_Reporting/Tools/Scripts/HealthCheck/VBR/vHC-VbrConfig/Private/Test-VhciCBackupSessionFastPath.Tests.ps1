#Requires -Version 7.0
# Pester v5 tests for Test-VhciCBackupSessionFastPath.
# PS 7 is required because the project's test convention runs Pester v5 under
# pwsh; PS 5.1 ships Pester v3 which lacks the Should -BeOfType syntax used
# below. See docs/plans/2026-05-27-vbr-session-fast-path.md Task Conventions.

BeforeAll {
    . $PSCommandPath.Replace('.Tests.ps1', '.ps1')
}

Describe 'Test-VhciCBackupSessionFastPath' {

    It 'returns $false when the Veeam.Backup.Core.CBackupSession type is not loaded' {
        # In a dev/CI environment without Veeam the -as [type] check returns $null
        # and the probe must return $false.  On a live VBR host (or after another
        # test in the same Pester run has loaded Veeam.Backup.Core.dll), the type
        # IS present and the probe correctly returns $true - so we skip the
        # "must-be-false" assertion in that case.
        $typeAvailable = $null -ne ('Veeam.Backup.Core.CBackupSession' -as [type])
        $result = Test-VhciCBackupSessionFastPath
        $result | Should -BeOfType [bool]
        if (-not $typeAvailable) {
            $result | Should -BeFalse
        }
        # If $typeAvailable is $true the probe returning $true is also correct;
        # the side-effect-free test below verifies no accidental side-loads occur.
    }

    It 'is side-effect-free (calling the probe does not load Veeam.Backup.Core)' {
        # If the probe accidentally side-loaded the Veeam dll, the type would
        # become resolvable AFTER the call but not BEFORE. Type resolution in
        # the .NET AppDomain is monotonic - once loaded, stays loaded - so a
        # before-null/after-non-null transition is exactly the failure shape
        # we want to catch.
        $before = 'Veeam.Backup.Core.CBackupSession' -as [type]
        { Test-VhciCBackupSessionFastPath } | Should -Not -Throw
        $after  = 'Veeam.Backup.Core.CBackupSession' -as [type]

        if ($null -eq $before) {
            # Probe must not have caused a load.
            $after | Should -BeNullOrEmpty -Because 'the probe must be read-only'
        }
        # If $before was non-null, $after will also be non-null (monotonic);
        # nothing to assert in that branch.
    }
}

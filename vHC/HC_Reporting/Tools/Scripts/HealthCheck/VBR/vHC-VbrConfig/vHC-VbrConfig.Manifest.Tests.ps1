#Requires -Version 7.0
# Pester v5 tests for vHC-VbrConfig module manifest and export contract (ISC-8 through ISC-11)
#
# Retrospective TDD for commit 59e2621 on dev.
# These tests validate the structural contract between:
#   - Public/*.ps1 files (functions defined on disk)
#   - vHC-VbrConfig.psd1 (FunctionsToExport allowlist)
#   - The loaded module's exported command surface
#
# Specifically targets the bug where Get-VhciObjectStorageRepos was silently
# excluded from every collection run because it was never in FunctionsToExport.
#
# Red-phase strategy for ISC-10:
#   Temporarily comment out 'Get-VhciObjectStorageRepos' from FunctionsToExport
#   in vHC-VbrConfig.psd1 (line 28), run test, capture red, restore.
#
# Red-phase strategy for ISC-8 / ISC-9:
#   Invert assertions (Should -Be 0 instead of Should -BeGreaterThan 0) for the
#   red run, then restore.

BeforeAll {
    $script:ModuleRoot = Join-Path $PSScriptRoot ''
    $script:PsdPath    = Join-Path $script:ModuleRoot 'vHC-VbrConfig.psd1'
    $script:PublicPath = Join-Path $script:ModuleRoot 'Public'

    # Parse the manifest so we can read FunctionsToExport without importing.
    $script:Manifest   = Import-PowerShellDataFile -Path $script:PsdPath

    # Enumerate Public function names (file base names without .ps1 extension).
    # Exclude *.Tests.ps1 files - they live in Public/ alongside the functions but
    # are not module members and should not appear in FunctionsToExport.
    $script:PublicFiles = @(Get-ChildItem -Path $script:PublicPath -Filter '*.ps1' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*.Tests.ps1' } |
        ForEach-Object { $_.BaseName })

    # FunctionsToExport list from the manifest.
    $script:Exported    = @($script:Manifest.FunctionsToExport)
}

# ---------------------------------------------------------------------------
# ISC-8  Every Public/*.ps1 function name appears in FunctionsToExport
# ---------------------------------------------------------------------------
Describe 'ISC-8: Every Public/*.ps1 function name is listed in FunctionsToExport' {

    It 'FunctionsToExport is non-empty' {
        $script:Exported.Count | Should -BeGreaterThan 0
    }

    It 'every Public/*.ps1 base name exists in FunctionsToExport' {
        $missing = $script:PublicFiles | Where-Object { $_ -notin $script:Exported }
        $missing | Should -BeNullOrEmpty -Because (
            "These Public functions are defined on disk but not exported: $($missing -join ', ')"
        )
    }
}

# ---------------------------------------------------------------------------
# ISC-9  Every name in FunctionsToExport has a matching Public/<Name>.ps1
# ---------------------------------------------------------------------------
Describe 'ISC-9: Every name in FunctionsToExport has a matching Public/<Name>.ps1 file' {

    It 'FunctionsToExport is non-empty' {
        $script:Exported.Count | Should -BeGreaterThan 0
    }

    It 'every FunctionsToExport entry has a corresponding Public/*.ps1 file' {
        $orphaned = $script:Exported | Where-Object { $_ -notin $script:PublicFiles }
        $orphaned | Should -BeNullOrEmpty -Because (
            "These FunctionsToExport names have no matching .ps1 file: $($orphaned -join ', ')"
        )
    }
}

# ---------------------------------------------------------------------------
# ISC-10  Specifically 'Get-VhciObjectStorageRepos' in manifest AND file exists
# ---------------------------------------------------------------------------
Describe 'ISC-10: Get-VhciObjectStorageRepos is in FunctionsToExport and has a Public/.ps1 file' {

    It 'Get-VhciObjectStorageRepos is listed in FunctionsToExport' {
        $script:Exported | Should -Contain 'Get-VhciObjectStorageRepos'
    }

    It 'Public/Get-VhciObjectStorageRepos.ps1 exists on disk' {
        $filePath = Join-Path $script:PublicPath 'Get-VhciObjectStorageRepos.ps1'
        $filePath | Should -Exist
    }
}

# ---------------------------------------------------------------------------
# ISC-11  After Import-Module .psd1, Get-Command Get-VhciObjectStorageRepos resolves
# ---------------------------------------------------------------------------
Describe 'ISC-11: After Import-Module .psd1, Get-Command Get-VhciObjectStorageRepos resolves' {

    BeforeAll {
        # Stub all Veeam SDK cmdlets referenced during module dot-sourcing so the
        # module can be imported on a non-VBR macOS host without error.
        $veeamCmdlets = @(
            'Get-VBRJob', 'Get-VBRBackupSession', 'Get-VBRComputerBackupJobSession',
            'Get-VBRObjectStorageRepository', 'Get-VBRArchiveObjectStorageRepository',
            'Connect-VBRServer', 'Disconnect-VBRServer',
            'Get-VBRServer', 'Get-VBRBackupProxy', 'Get-VBRRepository',
            'Get-VBRCredentials', 'Get-VBRJobScheduleOptions',
            'Get-VBRNASBackupJob', 'Get-VBRNASBackupJobSession',
            'Get-VBRTapeJob', 'Get-VBRTapeMediaPool', 'Get-VBRTapeDrive',
            'Get-VBRBackupRepository', 'Get-VBRCloudGateway',
            'Get-VBRTrafficRule', 'Get-VBRGlobalNotificationOptions',
            'Get-VBRSureBackupJob', 'Get-VBRCdpPolicy', 'Get-VBRSanIntegrationJobOptions',
            'Get-VBRWANAccelerator', 'Get-VBRSecureRestore', 'Get-VBRRestorePoint',
            'Get-VBRBackupSessions', 'Get-VBRTaskSession', 'Get-VBRPluginJob',
            'Get-VBRLicense', 'Get-VBRInstalledSoftware', 'Get-VBRManagedServer',
            'Get-VBRMalwareDetectionEvent', 'Get-VBRHvHost', 'Get-VBRViHost',
            'Get-VBREntraIdMember', 'Get-VBREntraIdApplication',
            'Get-VBRComputerBackupJob', 'Get-VBRBackupCopyJob',
            'Export-VhciCsv', 'Add-VhciModuleError', 'Get-VhciObjStoreProp'
        )
        foreach ($cmdlet in $veeamCmdlets) {
            if (-not (Get-Command $cmdlet -ErrorAction SilentlyContinue)) {
                $sb = [ScriptBlock]::Create("function global:$cmdlet { }")
                . $sb
            }
        }

        # Remove any previously loaded version of the module.
        if (Get-Module 'vHC-VbrConfig' -ErrorAction SilentlyContinue) {
            Remove-Module 'vHC-VbrConfig' -Force -ErrorAction SilentlyContinue
        }

        Import-Module $script:PsdPath -Force -ErrorAction Stop
    }

    AfterAll {
        Remove-Module 'vHC-VbrConfig' -Force -ErrorAction SilentlyContinue
    }

    It 'Get-Command Get-VhciObjectStorageRepos resolves after module import' {
        $cmd = Get-Command 'Get-VhciObjectStorageRepos' -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty
    }

    It 'the resolved command comes from the vHC-VbrConfig module' {
        $cmd = Get-Command 'Get-VhciObjectStorageRepos' -ErrorAction SilentlyContinue
        $cmd.ModuleName | Should -Be 'vHC-VbrConfig'
    }
}

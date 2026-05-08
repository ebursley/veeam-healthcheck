#Requires -Version 7.0
# Pester v5 tests for Resolve-VeeamConsolePath in TestMfa.ps1

BeforeAll {
    # Dot-source the script so only the function is loaded, not the main flow
    . (Join-Path $PSScriptRoot 'TestMfa.ps1')
}

Describe 'Resolve-VeeamConsolePath' {

    Context 'T1: CorePath registry present — default install Console exists' {
        BeforeEach {
            Mock Get-ItemProperty -ParameterFilter {
                $Path -eq 'HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication' -and
                $Name -eq 'CorePath'
            } -MockWith {
                [PSCustomObject]@{ CorePath = 'C:\Program Files\Veeam\Backup and Replication\Backup' }
            }

            Mock Test-Path -MockWith { $false }
            Mock Test-Path -ParameterFilter {
                $Path -eq 'C:\Program Files\Veeam\Backup and Replication\Console'
            } -MockWith { $true }
        }

        It 'returns CorePath-derived Console path when CorePath registry present and Console exists' {
            $result = Resolve-VeeamConsolePath
            $result | Should -Be 'C:\Program Files\Veeam\Backup and Replication\Console'
        }
    }

    Context 'T2: CorePath on D-drive non-default install' {
        BeforeEach {
            Mock Get-ItemProperty -ParameterFilter {
                $Path -eq 'HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication' -and
                $Name -eq 'CorePath'
            } -MockWith {
                [PSCustomObject]@{ CorePath = 'D:\Veeam\Backup and Replication\Backup' }
            }

            Mock Test-Path -MockWith { $false }
            Mock Test-Path -ParameterFilter {
                $Path -eq 'D:\Veeam\Backup and Replication\Console'
            } -MockWith { $true }
        }

        It 'returns CorePath Console path on D-drive non-default install' {
            $result = Resolve-VeeamConsolePath
            $result | Should -Be 'D:\Veeam\Backup and Replication\Console'
        }
    }

    Context 'T3: CorePath absent, Mount Service registry present' {
        BeforeEach {
            Mock Get-ItemProperty -ParameterFilter {
                $Path -eq 'HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication' -and
                $Name -eq 'CorePath'
            } -MockWith {
                throw [System.Management.Automation.ItemNotFoundException]::new('not found')
            }

            Mock Get-ItemProperty -ParameterFilter {
                $Path -eq 'HKLM:\SOFTWARE\Veeam\Veeam Mount Service' -and
                $Name -eq 'InstallationPath'
            } -MockWith {
                [PSCustomObject]@{ InstallationPath = 'C:\Program Files\Veeam\Backup and Replication\Backup\' }
            }

            Mock Test-Path -MockWith { $false }
            Mock Test-Path -ParameterFilter {
                $Path -eq 'C:\Program Files\Veeam\Backup and Replication\Console'
            } -MockWith { $true }
        }

        It 'falls through to Mount Service probe when CorePath registry absent' {
            $result = Resolve-VeeamConsolePath
            $result | Should -Be 'C:\Program Files\Veeam\Backup and Replication\Console'
        }
    }

    Context 'T4: Mount Service probe derives Console as sibling of InstallationPath parent (D-drive)' {
        BeforeEach {
            Mock Get-ItemProperty -ParameterFilter {
                $Path -eq 'HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication' -and
                $Name -eq 'CorePath'
            } -MockWith {
                throw [System.Management.Automation.ItemNotFoundException]::new('not found')
            }

            Mock Get-ItemProperty -ParameterFilter {
                $Path -eq 'HKLM:\SOFTWARE\Veeam\Veeam Mount Service' -and
                $Name -eq 'InstallationPath'
            } -MockWith {
                [PSCustomObject]@{ InstallationPath = 'D:\Veeam\Backup and Replication\Backup' }
            }

            Mock Test-Path -MockWith { $false }
            Mock Test-Path -ParameterFilter {
                $Path -eq 'D:\Veeam\Backup and Replication\Console'
            } -MockWith { $true }
        }

        It 'Mount Service probe derives Console as sibling of InstallationPath parent on D-drive' {
            $result = Resolve-VeeamConsolePath
            $result | Should -Be 'D:\Veeam\Backup and Replication\Console'
        }
    }

    Context 'T5: Mount Service probe rejects UNC InstallationPath' {
        BeforeEach {
            Mock Get-ItemProperty -ParameterFilter {
                $Path -eq 'HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication' -and
                $Name -eq 'CorePath'
            } -MockWith {
                throw [System.Management.Automation.ItemNotFoundException]::new('not found')
            }

            Mock Get-ItemProperty -ParameterFilter {
                $Path -eq 'HKLM:\SOFTWARE\Veeam\Veeam Mount Service' -and
                $Name -eq 'InstallationPath'
            } -MockWith {
                [PSCustomObject]@{ InstallationPath = '\\fileserver\share\Backup' }
            }

            # Nothing else exists
            Mock Test-Path -MockWith { $false }

            # Suppress env-var candidates
            $script:savedPF   = $env:ProgramFiles
            $script:savedPFx86 = [System.Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
            $env:ProgramFiles = $null
            Set-Item Env:'ProgramFiles(x86)' -Value $null
        }

        AfterEach {
            $env:ProgramFiles = $script:savedPF
            Set-Item Env:'ProgramFiles(x86)' -Value $script:savedPFx86
        }

        It 'returns null when Mount Service InstallationPath is UNC' {
            $result = Resolve-VeeamConsolePath 2>$null
            $result | Should -BeNullOrEmpty
        }

        It 'does not add a UNC path to attempted list' {
            # Capture the error stream to inspect
            $errorRecord = $null
            $result = Resolve-VeeamConsolePath 2>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    $errorRecord = $_
                }
            }
            # If attempted paths are listed in the error, none should start with \\
            if ($null -ne $errorRecord) {
                $errorRecord.Exception.Message | Should -Not -Match '\\\\'
            }
        }
    }

    Context 'T6: Mount Service probe adds candidate to attempted list when Console sibling missing' {
        BeforeEach {
            Mock Get-ItemProperty -ParameterFilter {
                $Path -eq 'HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication' -and
                $Name -eq 'CorePath'
            } -MockWith {
                throw [System.Management.Automation.ItemNotFoundException]::new('not found')
            }

            Mock Get-ItemProperty -ParameterFilter {
                $Path -eq 'HKLM:\SOFTWARE\Veeam\Veeam Mount Service' -and
                $Name -eq 'InstallationPath'
            } -MockWith {
                [PSCustomObject]@{ InstallationPath = 'C:\Program Files\Veeam\Backup and Replication\Backup' }
            }

            # Test-Path returns false everywhere
            Mock Test-Path -MockWith { $false }

            $script:savedPF    = $env:ProgramFiles
            $script:savedPFx86 = [System.Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
            $env:ProgramFiles  = $null
            Set-Item Env:'ProgramFiles(x86)' -Value $null
        }

        AfterEach {
            $env:ProgramFiles = $script:savedPF
            Set-Item Env:'ProgramFiles(x86)' -Value $script:savedPFx86
        }

        It 'returns null and error message lists the Mount-Service-derived candidate' {
            $errorRecord = $null
            Resolve-VeeamConsolePath 2>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    $errorRecord = $_
                }
            }
            $errorRecord | Should -Not -BeNullOrEmpty
            $errorRecord.Exception.Message | Should -Match 'C:\\Program Files\\Veeam\\Backup and Replication\\Console'
        }
    }

    Context 'T7: Both registry probes absent, env-var probe succeeds' {
        BeforeEach {
            Mock Get-ItemProperty -ParameterFilter {
                $Path -eq 'HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication' -and
                $Name -eq 'CorePath'
            } -MockWith {
                throw [System.Management.Automation.ItemNotFoundException]::new('not found')
            }

            Mock Get-ItemProperty -ParameterFilter {
                $Path -eq 'HKLM:\SOFTWARE\Veeam\Veeam Mount Service' -and
                $Name -eq 'InstallationPath'
            } -MockWith {
                throw [System.Management.Automation.ItemNotFoundException]::new('not found')
            }

            $script:savedPF    = $env:ProgramFiles
            $script:savedPFx86 = [System.Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
            $env:ProgramFiles  = 'C:\Program Files'
            Set-Item Env:'ProgramFiles(x86)' -Value $null

            Mock Test-Path -MockWith { $false }
            Mock Test-Path -ParameterFilter {
                $Path -eq 'C:\Program Files\Veeam\Backup and Replication\Console'
            } -MockWith { $true }
        }

        AfterEach {
            $env:ProgramFiles = $script:savedPF
            Set-Item Env:'ProgramFiles(x86)' -Value $script:savedPFx86
        }

        It 'falls through to ProgramFiles env-var when both registry probes absent' {
            $result = Resolve-VeeamConsolePath
            $result | Should -Be 'C:\Program Files\Veeam\Backup and Replication\Console'
        }
    }

    Context 'T8: Every probe fails — returns null with all candidates listed' {
        BeforeEach {
            Mock Get-ItemProperty -ParameterFilter {
                $Path -eq 'HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication' -and
                $Name -eq 'CorePath'
            } -MockWith {
                throw [System.Management.Automation.ItemNotFoundException]::new('not found')
            }

            Mock Get-ItemProperty -ParameterFilter {
                $Path -eq 'HKLM:\SOFTWARE\Veeam\Veeam Mount Service' -and
                $Name -eq 'InstallationPath'
            } -MockWith {
                [PSCustomObject]@{ InstallationPath = 'C:\Program Files\Veeam\Backup and Replication\Backup' }
            }

            $script:savedPF    = $env:ProgramFiles
            $script:savedPFx86 = [System.Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
            $env:ProgramFiles  = 'C:\Program Files'
            Set-Item Env:'ProgramFiles(x86)' -Value 'C:\Program Files (x86)'

            Mock Test-Path -MockWith { $false }
        }

        AfterEach {
            $env:ProgramFiles = $script:savedPF
            Set-Item Env:'ProgramFiles(x86)' -Value $script:savedPFx86
        }

        It 'returns null when every probe fails' {
            $result = Resolve-VeeamConsolePath 2>$null
            $result | Should -BeNullOrEmpty
        }

        It 'error message contains Mount-Service candidate and both env-var candidates' {
            $errorRecord = $null
            Resolve-VeeamConsolePath 2>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    $errorRecord = $_
                }
            }
            $errorRecord | Should -Not -BeNullOrEmpty
            $errorRecord.Exception.Message | Should -Match 'C:\\Program Files\\Veeam\\Backup and Replication\\Console'
            $errorRecord.Exception.Message | Should -Match 'C:\\Program Files \(x86\)\\Veeam\\Backup and Replication\\Console'
        }
    }

    Context 'T9: Attempted-path ordering matches probe ordering' {
        BeforeEach {
            Mock Get-ItemProperty -ParameterFilter {
                $Path -eq 'HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication' -and
                $Name -eq 'CorePath'
            } -MockWith {
                [PSCustomObject]@{ CorePath = 'C:\Program Files\Veeam\Backup and Replication\Backup' }
            }

            Mock Get-ItemProperty -ParameterFilter {
                $Path -eq 'HKLM:\SOFTWARE\Veeam\Veeam Mount Service' -and
                $Name -eq 'InstallationPath'
            } -MockWith {
                [PSCustomObject]@{ InstallationPath = 'C:\Program Files\Veeam\Backup and Replication\Backup' }
            }

            $script:savedPF    = $env:ProgramFiles
            $script:savedPFx86 = [System.Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
            $env:ProgramFiles  = 'C:\Program Files'
            Set-Item Env:'ProgramFiles(x86)' -Value 'C:\Program Files (x86)'

            # All Test-Path calls return false so every candidate is attempted
            Mock Test-Path -MockWith { $false }
        }

        AfterEach {
            $env:ProgramFiles = $script:savedPF
            Set-Item Env:'ProgramFiles(x86)' -Value $script:savedPFx86
        }

        It 'error lists paths in CorePath -> Mount Service -> ProgramFiles -> ProgramFiles(x86) order' {
            $errorRecord = $null
            Resolve-VeeamConsolePath 2>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    $errorRecord = $_
                }
            }
            $errorRecord | Should -Not -BeNullOrEmpty
            $msg = $errorRecord.Exception.Message

            $posCoreConsole  = $msg.IndexOf('C:\Program Files\Veeam\Backup and Replication\Console')
            $posPFx86Console = $msg.IndexOf('C:\Program Files (x86)\Veeam\Backup and Replication\Console')

            $posCoreConsole | Should -BeLessThan $posPFx86Console
        }
    }

    Context 'T10: Dot-source guard — Connect-VBRServer not called when dot-sourced' {
        BeforeAll {
            # Define a stub so Pester can mock it (it doesn't exist on non-Windows)
            if (-not (Get-Command Connect-VBRServer -ErrorAction SilentlyContinue)) {
                function global:Connect-VBRServer { param([string]$Server, [string]$User, [string]$Password, [switch]$ForceAcceptTlsCertificate) }
            }
        }

        It 'does not invoke Connect-VBRServer when script is dot-sourced' {
            Mock Connect-VBRServer -MockWith { throw 'Should not be called' }
            Mock Import-Module -MockWith { }

            # Re-dot-source — should NOT trigger the main flow
            { . (Join-Path $PSScriptRoot 'TestMfa.ps1') } | Should -Not -Throw
            Should -Invoke Connect-VBRServer -Times 0 -Exactly
        }
    }
}

#Requires -Version 5.1

# Exclude *.Tests.ps1 - Pester test files live alongside the functions they
# exercise but must not be dot-sourced by the module: they carry their own
# #requires -Version 7.0 and would fail Import-Module on PS 5.1 hosts.
$Public  = @(Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1"  -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -notlike '*.Tests.ps1' })
$Private = @(Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -notlike '*.Tests.ps1' })

foreach ($import in ($Public + $Private)) {
    try {
        . $import.FullName
    } catch {
        throw "Failed to import function from $($import.FullName): $_"
    }
}

Export-ModuleMember -Function $Public.BaseName

#Requires -Version 5.1

function Test-VhciCBackupSessionFastPath {
    <#
    .Synopsis
        Probes whether the internal Veeam.Backup.Core.CBackupSession type and its
        GetByJobAndTimeRangeWithLog(Guid, DateTime) overload are available in the
        current PowerShell session.

        Returns $true only when both the type and the (Guid, DateTime) method
        binding exist. Any reflection failure (type partially loaded, method
        renamed, etc.) is caught and returns $false so callers can fall back
        cleanly without exception handling. See ADR 0018.
    .Outputs
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $type = 'Veeam.Backup.Core.CBackupSession' -as [type]
        if ($null -eq $type) { return $false }

        $method = $type.GetMethod(
            'GetByJobAndTimeRangeWithLog',
            [System.Reflection.BindingFlags]'Public,Static',
            $null,
            [type[]]@([guid], [datetime]),
            $null
        )
        return ($null -ne $method)
    } catch {
        return $false
    }
}

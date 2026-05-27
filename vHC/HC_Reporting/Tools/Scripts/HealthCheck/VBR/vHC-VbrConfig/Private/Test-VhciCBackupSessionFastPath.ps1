#Requires -Version 5.1

function Test-VhciCBackupSessionFastPath {
    <#
    .Synopsis
        Probes whether the internal Veeam.Backup.Core.CBackupSession type and its
        GetAllSessionsByPolicyJobAndTimeRange(Guid, DateTime, DateTime) overload
        are available in the current PowerShell session.

        Returns $true only when both the type and the (Guid, DateTime, DateTime)
        method binding exist. Any reflection failure (type partially loaded,
        method renamed, etc.) is caught and returns $false so callers can fall
        back cleanly without exception handling. See ADR 0018.

        Note: the method name includes "Policy" but the underlying query returns
        per-machine child sessions for both policy and non-policy parent jobs,
        which is what we want for the post-ADR-0017 jobSessionSummary rollup.
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
            'GetAllSessionsByPolicyJobAndTimeRange',
            [System.Reflection.BindingFlags]'Public,Static',
            $null,
            [type[]]@([guid], [datetime], [datetime]),
            $null
        )
        return ($null -ne $method)
    } catch {
        return $false
    }
}

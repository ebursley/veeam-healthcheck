#Requires -Version 5.1

function Invoke-VhciCBackupSessionFetch {
    <#
    .Synopsis
        Single-purpose wrapper around
        [Veeam.Backup.Core.CBackupSession]::GetByJobAndTimeRangeWithLog so that
        Pester can mock the .NET edge in tests. Do not add logic here.
        See ADR 0018.
    .Parameter JobId
        The Veeam job UUID (from CBackupJob.Id).
    .Parameter Since
        Earliest CreationTime to include (inclusive of microsecond drift).
    .Outputs
        [Veeam.Backup.Core.CBackupSession[]] from the live VBR config database.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [guid]     $JobId,
        [Parameter(Mandatory)] [datetime] $Since
    )

    return [Veeam.Backup.Core.CBackupSession]::GetByJobAndTimeRangeWithLog($JobId, $Since)
}

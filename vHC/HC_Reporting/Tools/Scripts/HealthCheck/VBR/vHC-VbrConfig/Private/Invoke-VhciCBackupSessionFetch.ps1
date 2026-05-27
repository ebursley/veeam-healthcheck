#Requires -Version 5.1

function Invoke-VhciCBackupSessionFetch {
    <#
    .Synopsis
        Single-purpose wrapper around
        [Veeam.Backup.Core.CBackupSession]::GetAllSessionsByPolicyJobAndTimeRange
        so that Pester can mock the .NET edge in tests. Do not add logic here.
        See ADR 0018.

        Returns the parent job's session AND any per-machine child sessions
        whose creation_time falls within ($Since, $Until]. The method name
        includes "Policy" but the underlying query also returns per-machine
        children for non-policy parent jobs, which is the complete view we
        want for the post-ADR-0017 jobSessionSummary rollup.
    .Parameter JobId
        The Veeam job UUID (from CBackupJob.Id).
    .Parameter Since
        Lower bound CreationTime. Exact-equal boundary behavior is determined
        by the underlying query; Get-VhciJobSessions documents and tests
        strict > semantics, so callers should not depend on the exact-equal case.
    .Parameter Until
        Upper bound CreationTime, typically (Get-Date) at the start of the run.
    .Outputs
        [Veeam.Backup.Core.CBackupSession[]] from the live VBR config database.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [guid]     $JobId,
        [Parameter(Mandatory)] [datetime] $Since,
        [Parameter(Mandatory)] [datetime] $Until
    )

    return [Veeam.Backup.Core.CBackupSession]::GetAllSessionsByPolicyJobAndTimeRange($JobId, $Since, $Until)
}

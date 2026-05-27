#Requires -Version 5.1

function Get-VhcBackupSessions {
    <#
    .Synopsis
        Fetches VBR backup sessions created within the reporting window and returns
        them as pipeline output. The caller (orchestrator) captures the output and
        passes it explicitly to Get-VhcSessionReport via the -BackupSessions parameter.

        Returns a mixed array of two session object families:
        - VM and Backup Copy sessions (CBackupSession / CBackupCopySession)
        - Agent / computer backup sessions

        Both families are accepted by Get-VBRTaskSession, which Get-VhcSessionReport
        uses to resolve task-level detail. See ADR 0012 and ADR 0018.

        Path selection is delegated to the private Get-VhciJobSessions helper. On
        VBR versions that ship Veeam.Backup.Core.CBackupSession with the
        GetAllSessionsByPolicyJobAndTimeRange(Guid, DateTime, DateTime) overload,
        the helper uses an indexed DB query per job (the fast path), which
        returns the parent's session AND per-machine child sessions. On older
        versions or when reflection fails, it falls back to a single unfiltered
        cmdlet call followed by a client-side CreationTime filter (the pre-59e2621
        shape that works on v12).

        Agent jobs returned by Get-VBRJob (still surfaced on v13 with a
        deprecation warning) are removed from the VM/BackupCopy list so each
        agent job is only queried via the Agent path.
    .Parameter ReportInterval
        Number of days back to collect sessions for. Matches the -ReportInterval
        parameter passed to Get-VBRConfig.ps1.
    .Outputs
        [object[]] -- mixed array of Veeam backup session objects.
    .NOTES
        Pre-condition: the Veeam PowerShell snap-in (or Veeam.Backup.PowerShell
        module) must be loaded before calling. Get-VBRConfig.ps1 ensures this
        before invoking this function. If the snap-in is missing the function
        degrades to an empty result and logs a WARNING per missing cmdlet.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [int] $ReportInterval
    )

    Write-LogFile "Fetching backup sessions for the last $ReportInterval days..."
    $cutoff = (Get-Date).AddDays(-$ReportInterval)

    # -ErrorAction SilentlyContinue does not suppress terminating errors
    # like CommandNotFoundException (raised when the Veeam PS snap-in is
    # not loaded). Wrap in try/catch so a missing dependency degrades to
    # an empty job list instead of throwing out of this function.
    $jobs = @()
    try {
        $jobs = @(Get-VBRJob -ErrorAction SilentlyContinue)
    } catch {
        Write-LogFile "Get-VBRJob unavailable: $($_.Exception.Message)" -LogLevel 'WARNING'
    }

    $agentJobs = @()
    try {
        $agentJobs = @(Get-VBRComputerBackupJob -ErrorAction SilentlyContinue)
    } catch {
        Write-LogFile "Get-VBRComputerBackupJob unavailable: $($_.Exception.Message)" -LogLevel 'WARNING'
    }

    # Get-VBRJob still returns agent jobs on v13 (with a deprecation warning).
    # Subtract them so each agent job is only queried via the Agent path -
    # otherwise the fast path runs against the same job_id twice and produces
    # duplicate sessions in the return.
    if ($agentJobs.Count -gt 0 -and $jobs.Count -gt 0) {
        $agentIdSet = @{}
        foreach ($aj in $agentJobs) { $agentIdSet[$aj.Id] = $true }
        $jobs = @($jobs | Where-Object { -not $agentIdSet.ContainsKey($_.Id) })
    }

    $vmSessions = @()
    try {
        $vmSessions = @(Get-VhciJobSessions `
            -Jobs $jobs `
            -Since $cutoff `
            -SlowPathCommand { Get-VBRBackupSession } `
            -PathLabel 'VM/BackupCopy')
    } catch {
        Write-LogFile "VM/BackupCopy session collection failed: $($_.Exception.Message)" -LogLevel 'WARNING'
    }

    $agentSessions = @()
    try {
        $agentSessions = @(Get-VhciJobSessions `
            -Jobs $agentJobs `
            -Since $cutoff `
            -SlowPathCommand { Get-VBRComputerBackupJobSession } `
            -PathLabel 'Agent')
    } catch {
        Write-LogFile "Agent session collection failed: $($_.Exception.Message)" -LogLevel 'WARNING'
    }

    # The fast path returns parent sessions AND per-machine child sessions
    # (e.g. 'Managed-WindowsAgents-Job - vtestvm01.foo'). For agent jobs the
    # parent session's Get-VBRTaskSession output already exposes the per-
    # machine work under the parent name (see ADR 0012), so the child sessions
    # are duplicates. Keep only sessions whose JobName matches a canonical
    # agent-job name. Backup-copy jobs in $vmSessions are NOT filtered: their
    # parent session has no per-machine tasks, so the child sessions are the
    # only place the work appears.
    if ($agentSessions.Count -gt 0 -and $agentJobs.Count -gt 0) {
        $agentNameSet = @{}
        foreach ($aj in $agentJobs) {
            if ($null -ne $aj.Name) { $agentNameSet[$aj.Name] = $true }
        }
        $beforeCount = $agentSessions.Count
        $agentSessions = @($agentSessions | Where-Object {
            # Null JobName means the session is not a canonical agent-job session
            # (e.g. a test sentinel). Keep it - the filter is only there to drop
            # known-duplicate per-machine child sessions.
            $null -eq $_.JobName -or $agentNameSet.ContainsKey($_.JobName)
        })
        $dropped = $beforeCount - $agentSessions.Count
        if ($dropped -gt 0) {
            Write-LogFile "Dropped $dropped per-machine agent child session(s) (data captured via parent task hierarchy)"
        }
    }

    return $vmSessions + $agentSessions
}

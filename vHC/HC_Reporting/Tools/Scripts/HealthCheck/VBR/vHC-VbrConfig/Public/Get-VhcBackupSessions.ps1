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
        GetByJobAndTimeRangeWithLog(Guid, DateTime) overload, the helper uses an
        indexed DB query per job (the fast path). On older versions or when
        reflection fails, it falls back to a single unfiltered cmdlet call
        followed by a client-side CreationTime filter (the pre-59e2621 shape that
        works on v12).
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

    return $vmSessions + $agentSessions
}

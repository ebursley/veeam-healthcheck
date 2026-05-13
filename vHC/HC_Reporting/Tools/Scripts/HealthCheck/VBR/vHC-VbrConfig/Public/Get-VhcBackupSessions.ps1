#Requires -Version 5.1

function Get-VhcBackupSessions {
    <#
    .Synopsis
        Fetches VBR backup sessions created within the reporting window and returns them
        as pipeline output. The caller (orchestrator) captures the output and passes it
        explicitly to Get-VhcSessionReport via the -BackupSessions parameter.

        Returns a mixed array of two session object types:
        - VM and Backup Copy sessions (CBackupSession / CBackupCopySession) via
          Get-VBRBackupSession.
        - Agent/computer backup sessions (VBRSession) via Get-VBRComputerBackupJobSession.
        Both types are accepted by Get-VBRTaskSession, which Get-VhcSessionReport uses
        to resolve task-level detail. See ADR 0012.

        Iterates per job (Get-VBRJob | Get-VBRBackupSession -Job ...) to keep each SQL
        query bounded to a single job's session history. An unfiltered Get-VBRBackupSession
        call against a large environment with remote SQL can exceed the Veeam SDK's
        internal command timeout (~600s); per-job iteration avoids that.
        Same idiom as the NAS session path documented in
        docs/plans/2026-02-21-vbr-config-refactor.md.
    .Parameter ReportInterval
        Number of days back to collect sessions for. Matches the -ReportInterval parameter
        passed to Get-VBRConfig.ps1.
    .Outputs
        [object[]] -- Mixed array of Veeam backup session objects.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [int] $ReportInterval
    )

    Write-LogFile "Fetching backup sessions for the last $ReportInterval days..."
    $cutoff = (Get-Date).AddDays(-$ReportInterval)

    $sessions = New-Object System.Collections.ArrayList
    $jobs = @(Get-VBRJob -ErrorAction SilentlyContinue)
    Write-LogFile "Iterating $($jobs.Count) jobs for session history..."
    foreach ($job in $jobs) {
        try {
            $jobSessions = @(Get-VBRBackupSession -Job $job | Where-Object { $_.CreationTime -gt $cutoff })
            if ($jobSessions.Count -gt 0) {
                [void]$sessions.AddRange($jobSessions)
            }
        } catch {
            Write-LogFile "Failed to get sessions for job '$($job.Name)': $($_.Exception.Message)" -LogLevel "WARNING"
        }
    }
    Write-LogFile "Collected $($sessions.Count) VM/Backup Copy sessions across $($jobs.Count) jobs."

    $agentSessions = @()
    try {
        $agentSessions = @(Get-VBRComputerBackupJobSession | Where-Object { $_.CreationTime -gt $cutoff })
        Write-LogFile "Collected $($agentSessions.Count) agent backup sessions."
    } catch {
        Write-LogFile "Failed to collect agent backup sessions: $($_.Exception.Message)" -LogLevel "WARNING"
    }

    return @($sessions) + @($agentSessions)
}

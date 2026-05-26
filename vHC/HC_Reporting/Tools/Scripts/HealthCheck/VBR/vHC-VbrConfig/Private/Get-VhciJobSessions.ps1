#Requires -Version 5.1

function Get-VhciJobSessions {
    <#
    .Synopsis
        Returns backup-session objects for a list of jobs within a time window,
        using the indexed Veeam.Backup.Core.CBackupSession fast path when
        available and falling back to a caller-supplied cmdlet when not.
        See docs/superpowers/specs/2026-05-27-vbr-session-fast-path-design.md
        and ADR 0018.
    .Parameter Jobs
        Array of job objects (CBackupJob / agent job). Must have an .Id (Guid)
        property in the fast path; unused in slow path. May be empty.
    .Parameter Since
        Earliest CreationTime to include. Sessions with CreationTime > $Since
        are returned.
    .Parameter SlowPathCommand
        Scriptblock invoked once when the fast path is not available. Should
        return all sessions of the relevant family; this function filters by
        $Since client-side. Typical values: { Get-VBRBackupSession } or
        { Get-VBRComputerBackupJobSession }.
    .Parameter PathLabel
        Short identifier used in log line prefixes (e.g. "VM/BackupCopy",
        "Agent"). Does not affect behaviour.
    .Outputs
        [object[]] -- array of session objects (CBackupSession on fast path;
                      whatever $SlowPathCommand returns on slow path).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Jobs,
        [Parameter(Mandatory)] [datetime]    $Since,
        [Parameter(Mandatory)] [scriptblock] $SlowPathCommand,
        [Parameter(Mandatory)] [string]      $PathLabel
    )

    $useFastPath = Test-VhciCBackupSessionFastPath

    if ($useFastPath) {
        Write-LogFile "[$PathLabel] Using fast path (CBackupSession.GetByJobAndTimeRangeWithLog)"

        $results = New-Object System.Collections.ArrayList
        foreach ($job in $Jobs) {
            try {
                $jobResults = @(Invoke-VhciCBackupSessionFetch -JobId $job.Id -Since $Since)
                if ($jobResults.Count -gt 0) {
                    [void]$results.AddRange($jobResults)
                }
            } catch {
                Write-LogFile "[$PathLabel] Failed to fetch sessions for job '$($job.Name)': $($_.Exception.Message)" -LogLevel 'WARNING'
            }
        }
        Write-LogFile "[$PathLabel] Collected $($results.Count) sessions via fast path"
        return @($results)
    }

    # Slow-path branch implemented in Task 4
    Write-LogFile "[$PathLabel] Using slow path (fallback NOT YET IMPLEMENTED)" -LogLevel 'WARNING'
    return @()
}

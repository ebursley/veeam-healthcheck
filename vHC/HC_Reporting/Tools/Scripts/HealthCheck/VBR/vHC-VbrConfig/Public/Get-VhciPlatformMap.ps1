#Requires -Version 5.1

function Get-VhciPlatformMap {
    <#
    .Synopsis
        Builds a hashtable mapping lowercase server name to canonical platform string.
        Used to populate the Platform column in _Servers.csv and _Jobs.csv.
        Requires VBR 12.1+ (returns empty hashtable on earlier versions).
    .Parameter VBRVersion
        Major version integer of the VBR server (e.g. 12).
    .Outputs
        [hashtable] keyed by lowercase server name -> canonical platform string.
        Returns empty hashtable on any failure or when unsupported VBR version.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [int]$VBRVersion = 0
    )

    # Require VBR 12.1+. The major version integer we receive is 12, so guard on < 12.
    if ($VBRVersion -lt 12) {
        Write-LogFile "Skipping platform map: VBR < 12.1"
        return @{}
    }

    # Guards: both cmdlets must exist (Get-VBRSession is the entry point, Get-VBRBackupSession hydrates)
    if (-not (Get-Command Get-VBRSession -ErrorAction SilentlyContinue)) {
        Write-LogFile "Skipping platform map: Get-VBRSession cmdlet not available"
        return @{}
    }
    if (-not (Get-Command Get-VBRBackupSession -ErrorAction SilentlyContinue)) {
        Write-LogFile "Skipping platform map: Get-VBRBackupSession cmdlet not available"
        return @{}
    }

    $map = @{}

    try {
        # Bound to last 30 days to keep cmdlet roundtrips proportional to recent activity.
        # Older sessions don't add hosts the recent ones haven't already classified.
        $sessions = Get-VBRSession -Type PlatformBackupJob -ErrorAction Stop |
                    Where-Object { $_.CreationTime -gt (Get-Date).AddDays(-30) }
        Write-LogFile "Platform map: found $(@($sessions).Count) recent PlatformBackupJob sessions"

        # Track which host names we've already classified — lets us early-exit
        # the inner task-session loop once nothing new will be learned.
        foreach ($sess in @($sessions)) {
            try {
                $full = Get-VBRBackupSession -Id $sess.Id -ErrorAction Stop
                if ($null -eq $full) { continue }

                $platStr = $null
                try {
                    $platStr = $full.Platform.ToHumanReadable()
                } catch {
                    # Platform not available on this session — skip
                    continue
                }

                if ([string]::IsNullOrEmpty($platStr)) { continue }

                $taskSessions = $full.GetTaskSessions()
                foreach ($task in @($taskSessions)) {
                    try {
                        $hostName = $task.Info.HostName
                        if (-not [string]::IsNullOrEmpty($hostName)) {
                            $key = $hostName.ToLowerInvariant()
                            # First writer wins — keep earliest-seen platform per host
                            if (-not $map.ContainsKey($key)) {
                                $map[$key] = $platStr
                            }
                        }
                    } catch {
                        Write-LogFile "Platform map: skipped task session (host name unreadable): $($_.Exception.Message)" -LogLevel "DEBUG"
                    }
                }
            } catch {
                Write-LogFile "Platform map: error processing session $($sess.Id): $($_.Exception.Message)" -LogLevel "WARNING"
            }
        }

        Write-LogFile "Platform map: built $($map.Count) host->platform entries"
    } catch {
        Add-VhciModuleError -CollectorName 'PlatformMap' -ErrorMessage $_.Exception.Message
        Write-LogFile "Platform map collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
        return @{}
    }

    return $map
}

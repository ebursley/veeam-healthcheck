#Requires -Version 5.1

function Get-VhciCloudReplica {
    <#
    .Synopsis
        Collects VBR replica objects and their restore point counts.
        Original location is resolved best-effort from the replica job's source objects;
        left empty when the source vCenter/host is unreachable from this server.
        Returns a flat array of pscustomobject rows ready for Export-VhciCsv.
    #>
    [CmdletBinding()]
    param()

    $rows = [System.Collections.Generic.List[pscustomobject]]::new()

    $replicas = @()
    try { $replicas = @(Get-VBRReplica) } catch {
        Write-LogFile "Get-VBRReplica failed: $($_.Exception.Message)" -LogLevel "WARNING"
        return $rows
    }

    Write-LogFile "Found $($replicas.Count) replicas"

    foreach ($r in $replicas) {
        $rpCount = 0
        try { $rpCount = @(Get-VBRRestorePoint -Backup $r).Count } catch {}

        $origLoc = ''
        try {
            $job = Get-VBRJob -Name $r.JobName -ErrorAction SilentlyContinue
            if ($null -ne $job) {
                $srcObjects = @($job.GetObjectsInJob())
                if ($srcObjects.Count -gt 0) {
                    $origLoc = $srcObjects[0].Name
                }
            }
        } catch {}

        $rows.Add([pscustomobject]@{
            Name              = $r.Name
            JobName           = $r.JobName
            Status            = $r.Status
            RestorePointCount = $rpCount
            OriginalLocation  = $origLoc
            ReplicaLocation   = ''
            Platform          = $r.Platform
        })
    }

    return $rows
}

#Requires -Version 5.1

function Get-VhciCloudTenantResource {
    <#
    .Synopsis
        Expands per-tenant backup quota resources and hardware-plan replication resources.
        Returns @{ Backup = []; Replication = [] } — two flat arrays ready for Export-VhciCsv.
    .Parameter Tenants
        Array of VBRCloudTenant objects from Get-VBRCloudTenant.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Tenants
    )

    $backupRows = [System.Collections.Generic.List[pscustomobject]]::new()
    $replicationRows = [System.Collections.Generic.List[pscustomobject]]::new()

    foreach ($tenant in $Tenants) {
        # ── Backup storage resources (per quota repo) ─────────────────────────
        foreach ($r in @($tenant.Resources)) {
            $backupRows.Add([pscustomobject]@{
                TenantId                = $tenant.Id
                TenantName              = $tenant.Name
                RepositoryFriendlyName  = $r.RepositoryFriendlyName
                RepositoryName          = $r.Repository.Name
                RepositoryType          = $r.Repository.Type
                RepositoryQuotaMB       = $r.RepositoryQuota
                UsedSpaceMB             = $r.UsedSpace
                UsedSpacePercentage     = $r.UsedSpacePercentage
                FreeSpaceMB             = ($r.RepositoryQuota - $r.UsedSpace)
                RepositoryQuotaPath     = $r.RepositoryQuotaPath
                PerformanceTierUsedMB   = $r.PerformanceTierUsedSpace
                CapacityTierUsedMB      = $r.CapacityTierUsedSpace
                ArchiveTierUsedMB       = $r.ArchiveTierUsedSpace
                WanAccelerationEnabled  = $r.WanAccelerationEnabled
                WanAcceleratorName      = $r.WanAccelerator.Name
            })
        }

        # ── Replication resources (per hardware plan subscription) ─────────────
        $replResources = $null
        try { $replResources = $tenant.ReplicationResources } catch {}

        $hwPlanOptions = @()
        try { $hwPlanOptions = @($replResources.HardwarePlanOptions) } catch {}

        foreach ($opt in $hwPlanOptions) {
            $dsQuotas = @()
            try { $dsQuotas = @($opt.DatastoreQuota) } catch {}

            if ($dsQuotas.Count -eq 0) {
                $replicationRows.Add([pscustomobject]@{
                    TenantId              = $tenant.Id
                    TenantName            = $tenant.Name
                    HardwarePlanName      = $opt.HardwarePlan.Name
                    HardwarePlanId        = $opt.HardwarePlan.Id
                    UsedCPU               = $opt.UsedCPU
                    UsedMemoryMB          = $opt.UsedMemory
                    DatastoreFriendlyName = ''
                    DatastoreQuotaGB      = ''
                    DatastoreUsedSpaceGB  = ''
                    CPUQuota              = ''
                    MemoryQuota           = ''
                })
            } else {
                foreach ($ds in $dsQuotas) {
                    $replicationRows.Add([pscustomobject]@{
                        TenantId              = $tenant.Id
                        TenantName            = $tenant.Name
                        HardwarePlanName      = $opt.HardwarePlan.Name
                        HardwarePlanId        = $opt.HardwarePlan.Id
                        UsedCPU               = $opt.UsedCPU
                        UsedMemoryMB          = $opt.UsedMemory
                        DatastoreFriendlyName = $ds.FriendlyName
                        DatastoreQuotaGB      = $ds.Quota
                        DatastoreUsedSpaceGB  = $ds.UsedSpace
                        CPUQuota              = $ds.CPUQuota
                        MemoryQuota           = $ds.MemoryQuota
                    })
                }
            }
        }
    }

    return @{
        Backup      = $backupRows
        Replication = $replicationRows
    }
}

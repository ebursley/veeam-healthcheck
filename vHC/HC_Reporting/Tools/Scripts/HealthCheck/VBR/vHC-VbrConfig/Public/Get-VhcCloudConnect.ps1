#Requires -Version 5.1

function Get-VhcCloudConnect {
    <#
    .Synopsis
        Collects Veeam Cloud Connect data for Cloud Service Provider installations.
        Exports: _CloudGateways.csv, _CloudGatewayPools.csv, _CloudTenants.csv,
                 _CloudTenantBackupResources.csv, _CloudTenantReplicationResources.csv,
                 _CloudHardwarePlans.csv, _CloudHardwarePlanDatastores.csv,
                 _CloudReplicas.csv, _CloudFailoverPlans.csv, _CloudFailoverPlanObjects.csv
        Skipped when the Cloud Connect licence flag is Disabled.
    #>
    [CmdletBinding()]
    param()

    $message = "Collecting Cloud Connect data..."
    Write-LogFile $message

    # Pre-flight: Cloud Connect cmdlets require the SP licence.
    $lic = $null
    try { $lic = Get-VBRInstalledLicense } catch {}
    if ($null -eq $lic -or $lic.CloudConnect -eq 'Disabled') {
        Write-LogFile "Cloud Connect not licensed (CloudConnect=$($lic?.CloudConnect)) - skipping." -LogLevel "INFO"
        return
    }

    try {
        # ── Gateways ─────────────────────────────────────────────────────────
        Write-LogFile "Collecting Cloud Gateways..."
        $cloudGateways = @(Get-VBRCloudGateway)
        Write-LogFile "Found $($cloudGateways.Count) cloud gateways"

        $gatewayOutput = $cloudGateways | Select-Object `
            'Id', 'Name', 'Description', 'Enabled',
            @{n = 'IPAddress';    e = { $_.IPAddress } },
            @{n = 'NetworkMode';  e = { $_.NetworkMode } },
            @{n = 'NATPort';      e = { $_.NATPort } },
            @{n = 'IncomingPort'; e = { $_.IncomingPort } },
            @{n = 'HostName';     e = { $_.Host.Name } },
            @{n = 'HostId';       e = { $_.Host.Id } }

        $gatewayOutput | Export-VhciCsv -FileName '_CloudGateways.csv'

        # ── Gateway Pools (one row per pool × member gateway) ─────────────────
        Write-LogFile "Collecting Cloud Gateway Pools..."
        $gatewayPools = @(Get-VBRCloudGatewayPool)
        Write-LogFile "Found $($gatewayPools.Count) gateway pools"

        $poolRows = [System.Collections.Generic.List[pscustomobject]]::new()
        foreach ($pool in $gatewayPools) {
            $members = @($pool.CloudGateways)
            if ($members.Count -eq 0) {
                $poolRows.Add([pscustomobject]@{
                    Id          = $pool.Id
                    PoolName    = $pool.Name
                    Description = $pool.Description
                    GatewayName = ''
                    GatewayId   = ''
                })
            } else {
                foreach ($gw in $members) {
                    $poolRows.Add([pscustomobject]@{
                        Id          = $pool.Id
                        PoolName    = $pool.Name
                        Description = $pool.Description
                        GatewayName = $gw.Name
                        GatewayId   = $gw.Id
                    })
                }
            }
        }
        $poolRows | Export-VhciCsv -FileName '_CloudGatewayPools.csv'

        # ── Tenants ───────────────────────────────────────────────────────────
        Write-LogFile "Collecting Cloud Tenants..."
        $cloudTenants = @(Get-VBRCloudTenant)
        Write-LogFile "Found $($cloudTenants.Count) cloud tenants"

        $tenantOutput = $cloudTenants | Select-Object `
            'Id', 'Name', 'Description', 'Enabled', 'Type',
            'LastActive', 'LastResult',
            'VMCount', 'ServerCount', 'WorkstationCount', 'ReplicaCount',
            'NewVMBackupCount', 'NewServerBackupCount', 'NewWorkstationBackupCount', 'NewReplicaCount',
            'RentalVMBackupCount', 'RentalServerBackupCount', 'RentalWorkstationBackupCount', 'RentalReplicaCount',
            'MaxConcurrentTask',
            'ThrottlingEnabled', 'ThrottlingValue', 'ThrottlingUnit',
            @{n = 'GatewaySelectionType'; e = { $_.GatewaySelectionType } },
            @{n = 'GatewayPoolName';      e = { $_.GatewayPool.Name } },
            'GatewayFailoverEnabled',
            'LeaseExpirationEnabled',
            @{n = 'LeaseExpirationDate';  e = { $_.LeaseExpirationDate } },
            'BackupProtectionEnabled',
            @{n = 'BackupProtectionPeriod'; e = { $_.BackupProtectionPeriod } }

        $tenantOutput | Export-VhciCsv -FileName '_CloudTenants.csv'

        # ── Tenant backup/replication resources ───────────────────────────────
        if ($cloudTenants.Count -gt 0) {
            $resources = Get-VhciCloudTenantResource -Tenants $cloudTenants
            $resources.Backup      | Export-VhciCsv -FileName '_CloudTenantBackupResources.csv'
            $resources.Replication | Export-VhciCsv -FileName '_CloudTenantReplicationResources.csv'
        }

        # ── Hardware Plans (one summary row + separate datastore detail) ──────
        Write-LogFile "Collecting Cloud Hardware Plans..."
        $hwPlans = @(Get-VBRCloudHardwarePlan)
        Write-LogFile "Found $($hwPlans.Count) hardware plans"

        $hwPlanOutput = $hwPlans | Select-Object `
            'Id', 'Name', 'Platform',
            @{n = 'CpuMhz';                 e = { $_.CPU } },
            @{n = 'MemoryMB';               e = { $_.Memory } },
            @{n = 'NetworksWithInternet';    e = { $_.NumberOfNetWithInternet } },
            @{n = 'NetworksWithoutInternet'; e = { $_.NumberOfNetWithoutInternet } },
            @{n = 'SubscribedTenantCount';   e = { @($_.SubscribedTenantId).Count } },
            @{n = 'TotalDatastoreQuotaGB';   e = { ($_.Datastore | Measure-Object -Property Quota -Sum).Sum } },
            @{n = 'HostName';               e = { $_.Host.Name } }

        $hwPlanOutput | Export-VhciCsv -FileName '_CloudHardwarePlans.csv'

        $dsRows = [System.Collections.Generic.List[pscustomobject]]::new()
        foreach ($plan in $hwPlans) {
            foreach ($ds in @($plan.Datastore)) {
                $dsRows.Add([pscustomobject]@{
                    HardwarePlanId       = $plan.Id
                    HardwarePlanName     = $plan.Name
                    DatastoreFriendlyName = $ds.FriendlyName
                    DatastorePath        = if ($null -ne $ds.PSObject.Properties['Path']) { $ds.Path } else { '' }
                    QuotaGB              = $ds.Quota
                })
            }
        }
        $dsRows | Export-VhciCsv -FileName '_CloudHardwarePlanDatastores.csv'

        # ── Replicas ──────────────────────────────────────────────────────────
        $replicas = Get-VhciCloudReplica
        $replicas | Export-VhciCsv -FileName '_CloudReplicas.csv'

        # ── Failover Plans ────────────────────────────────────────────────────
        $fpResult = Get-VhciCloudFailoverPlan
        $fpResult.Plans   | Export-VhciCsv -FileName '_CloudFailoverPlans.csv'
        $fpResult.Objects | Export-VhciCsv -FileName '_CloudFailoverPlanObjects.csv'

        Write-LogFile ($message + "DONE")
    } catch {
        Write-LogFile ($message + "FAILED!")
        Write-LogFile $_.Exception.Message -LogLevel "ERROR"
        Add-VhciModuleError -CollectorName 'CloudConnect' -ErrorMessage $_.Exception.Message
    }
}

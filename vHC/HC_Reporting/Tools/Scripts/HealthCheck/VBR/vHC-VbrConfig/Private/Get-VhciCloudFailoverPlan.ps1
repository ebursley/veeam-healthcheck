#Requires -Version 5.1

function Get-VhciCloudFailoverPlan {
    <#
    .Synopsis
        Collects Cloud and Tenant failover plans (excludes Local plans).
        Returns @{ Plans = []; Objects = [] } -- plan summary rows and per-VM detail rows.
    #>
    [CmdletBinding()]
    param()

    $planRows   = [System.Collections.Generic.List[pscustomobject]]::new()
    $objectRows = [System.Collections.Generic.List[pscustomobject]]::new()

    $allPlans = @()
    try {
        $allPlans = @(Get-VBRFailoverPlan | Where-Object { $_.Type -in @('Cloud', 'Tenant') })
    } catch {
        Write-LogFile "Get-VBRFailoverPlan failed: $($_.Exception.Message)" -LogLevel "WARNING"
        return @{ Plans = $planRows; Objects = $objectRows }
    }

    Write-LogFile "Found $($allPlans.Count) cloud/tenant failover plans"

    foreach ($plan in $allPlans) {
        $publicIpEnabled = ''
        $providerId      = ''
        $tenantId        = ''
        try { $publicIpEnabled = $plan.PublicIpEnabled } catch {}
        try { $providerId      = $plan.ProviderId      } catch {}
        try { $tenantId        = $plan.TenantId        } catch {}

        $planRows.Add([pscustomobject]@{
            Id                  = $plan.Id
            Name                = $plan.Name
            Description         = $plan.Description
            Type                = $plan.Type
            Platform            = $plan.Platform
            Status              = $plan.Status
            VmCount             = $plan.VMCount
            PreFailoverCommand  = $plan.PrefailoverCommand
            PostFailoverCommand = $plan.PostfailoverCommand
            PublicIpEnabled     = $publicIpEnabled
            ProviderId          = $providerId
            TenantId            = $tenantId
        })

        foreach ($obj in @($plan.FailoverPlanObject)) {
            $vmName     = ''
            $bootOrder  = ''
            $bootDelay  = ''
            $publicIpRule = ''
            try { $vmName     = $obj.Item.Name   } catch {}
            try { $bootOrder  = $obj.BootOrder   } catch {}
            try { $bootDelay  = $obj.BootDelay   } catch {}
            try { $publicIpRule = $obj.PublicIpRule } catch {}

            $objectRows.Add([pscustomobject]@{
                FailoverPlanId   = $plan.Id
                FailoverPlanName = $plan.Name
                VmName           = $vmName
                BootOrder        = $bootOrder
                BootDelay        = $bootDelay
                PublicIpRule     = $publicIpRule
            })
        }
    }

    return @{
        Plans   = $planRows
        Objects = $objectRows
    }
}

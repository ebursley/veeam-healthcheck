#Requires -Version 7
# Check-CorruptionGuard-PS.ps1
# Reports Storage-level Corruption Guard (Perform backup files health check)
# for all VBR jobs via the Veeam.Backup.PowerShell module.
#
# NOTE: GenerationPolicy.EnableRecheck also returns True for NAS and Backup Copy
# jobs (different internal feature). Use the REST variant for VM-job-only results.

param(
    [string] $Server     = "vbr-v13-rtm.home.lab",
    [string] $Username   = "veeamadmin"
)

Import-Module Veeam.Backup.PowerShell -ErrorAction Stop

$cred = New-Object System.Management.Automation.PSCredential(
    $Username,
    (Read-Host "Password for $Username" -AsSecureString)
)

Connect-VBRServer -Server $Server -Credential $cred

try {
    Get-VBRJob | ForEach-Object {
        $gp = $_.GetOptions().GenerationPolicy

        $schedule = if ($gp.EnableRecheck) {
            if ($gp.RecheckScheduleKind -eq 'Monthly') {
                $m = $gp.RecheckBackupMonthlyScheduleOptions
                "$($gp.RecheckTime) | Monthly: $($m.DayNumberInMonth) $($m.DayOfWeek)"
            } else {
                "$($gp.RecheckTime) | Weekly: $($gp.RecheckDays)"
            }
        } else {
            "N/A"
        }

        [PSCustomObject]@{
            Job         = $_.Name
            Type        = $_.TypeToString
            HealthCheck = $gp.EnableRecheck
            Schedule    = $schedule
        }
    } | Sort-Object HealthCheck -Descending | Format-Table -AutoSize
}
finally {
    Disconnect-VBRServer
}

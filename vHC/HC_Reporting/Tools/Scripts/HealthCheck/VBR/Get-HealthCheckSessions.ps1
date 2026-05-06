#Requires -Version 7
# Get-HealthCheckSessions.ps1
# Retrieves Storage-level Corruption Guard (backup health check) session history
# from VBR via internal .NET reflection.
#
# The VBR REST API and standard PS cmdlets do NOT expose health check sessions -
# they live in an internal DB scope (EDbJobType.HealthCheck) not surfaced publicly.
# This script accesses them via CDbManager reflection, which is the same mechanism
# the VBR console uses.

param(
    [string]   $Server   = "vbr-v13-rtm.home.lab",
    [string]   $Username = "veeamadmin",
    [datetime] $FromDate = (Get-Date).AddDays(-30),
    [datetime] $ToDate   = (Get-Date)
)

Import-Module Veeam.Backup.PowerShell -ErrorAction Stop

$cred = New-Object System.Management.Automation.PSCredential(
    $Username,
    (Read-Host "Password for $Username" -AsSecureString)
)

Connect-VBRServer -Server $Server -Credential $cred

try {
    # Resolve internal types via reflection
    $assemblies = [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -like 'Veeam*' }

    $dbMgrType = $assemblies | ForEach-Object { try { $_.GetTypes() } catch {} } |
        Where-Object { $_.FullName -eq 'Veeam.Backup.DBManager.CDbManager' }

    $enumType = $assemblies | ForEach-Object { try { $_.GetTypes() } catch {} } |
        Where-Object { $_.FullName -eq 'Veeam.Backup.Abstractions.EDbJobType' }

    $mgr = $dbMgrType.GetProperty('Instance',
        [System.Reflection.BindingFlags]'Static,Public').GetValue($null)

    $hcJobType = [System.Enum]::Parse($enumType, 'HealthCheck')

    # Query health check sessions then filter client-side.
    # GetSessionsByTypeAndInterval marshals DateTime through a resilient proxy wrapper
    # that returns objects with empty/default property values from a script context -
    # GetSessionsByTypes does not have this issue.
    $sessions = @($mgr.BackupJobsSessions.GetSessionsByTypes(@($hcJobType)) |
        Where-Object { $_.CreationTime -ge $FromDate -and $_.CreationTime -le $ToDate })

    if ($sessions.Count -eq 0) {
        Write-Host "No health check sessions found between $FromDate and $ToDate"
        return
    }

    $sessions | ForEach-Object {
        # Parse BackupJobId from JobSpec XML to link back to the source backup job
        $backupJobId = $null
        if ($_.JobSpec) {
            $xml = [xml]$_.JobSpec
            $backupJobId = $xml.HealthCheckJobSpec.BackupJobId
        }

        [PSCustomObject]@{
            SessionName  = $_.JobName
            BackupJobId  = $backupJobId
            Result       = $_.Result
            State        = $_.State
            StartTime    = $_.CreationTime
            EndTime      = $_.EndTime
            Duration     = if ($_.EndTime -gt $_.CreationTime) {
                               ($_.EndTime - $_.CreationTime).ToString('hh\:mm\:ss')
                           } else { 'N/A' }
            Warnings     = $_.Warnings
            Failures     = $_.Failures
            RunManually  = $_.RunManually
            IsRetry      = $_.IsRecheckRetry
        }
    } | Sort-Object StartTime -Descending | Format-Table -AutoSize
}
finally {
    Disconnect-VBRServer
}

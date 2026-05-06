#Requires -Version 7
# Check-CorruptionGuard-REST.ps1
# Reports Storage-level Corruption Guard (Perform backup files health check)
# for all VBR jobs via the REST API (port 9419).
#
# backupHealth.isEnabled is null for NAS and Backup Copy jobs - those show as
# "N/A (non-VM)" and are excluded from the True/False results automatically.

param(
    [string] $Server   = "vbr-v13-rtm.home.lab",
    [int]    $Port     = 9419,
    [string] $Username = "veeamadmin",
    [string] $ApiVer   = "1.3-rev1"
)

$password = Read-Host "Password for $Username" -AsSecureString
$plainPw  = [System.Net.NetworkCredential]::new("", $password).Password

$tok = Invoke-RestMethod -SkipCertificateCheck `
    -Method POST `
    -Uri "https://${Server}:${Port}/api/oauth2/token" `
    -Headers @{ "x-api-version" = $ApiVer } `
    -ContentType "application/x-www-form-urlencoded" `
    -Body "grant_type=password&username=$Username&password=$([uri]::EscapeDataString($plainPw))"

$headers = @{
    "Authorization" = "Bearer $($tok.access_token)"
    "x-api-version" = $ApiVer
}

$jobs = Invoke-RestMethod -SkipCertificateCheck `
    -Uri "https://${Server}:${Port}/api/v1/jobs" `
    -Headers $headers

$jobs.data | ForEach-Object {
    $detail = Invoke-RestMethod -SkipCertificateCheck `
        -Uri "https://${Server}:${Port}/api/v1/jobs/$($_.id)" `
        -Headers $headers

    $bh = $detail.storage.advancedSettings.backupHealth

    $schedule = if ($bh.isEnabled) {
        if ($bh.monthly.isEnabled) {
            "$($bh.monthly.localTime) | Monthly: $($bh.monthly.dayNumberInMonth) $($bh.monthly.dayOfWeek)"
        } elseif ($bh.weekly.isEnabled) {
            "$($bh.weekly.localTime) | Weekly: $($bh.weekly.days -join ', ')"
        } else {
            "Enabled (no schedule)"
        }
    } else {
        "N/A"
    }

    [PSCustomObject]@{
        Job         = $_.name
        HealthCheck = if ($null -eq $bh.isEnabled) { "N/A (non-VM)" } else { $bh.isEnabled }
        Schedule    = $schedule
    }
} | Sort-Object HealthCheck -Descending | Format-Table -AutoSize

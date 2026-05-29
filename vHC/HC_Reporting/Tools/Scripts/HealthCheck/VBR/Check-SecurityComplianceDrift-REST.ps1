#Requires -Version 7
# Check-SecurityComplianceDrift-REST.ps1
# Fetches security compliance best-practice results from the VBR REST API and compares
# them against VbrConfig.json.SecurityComplianceRuleNames.
#
# Runs against a single lab (-Lab) or all labs in labs-config.json automatically.
# VPN-aware: env-var PRIMARY/FALLBACK probe for single-lab mode; labs-config.json
# handles multi-lab with per-lab credentials and enable/disable flags.
#
# REST FIELD NOTE: bestPractice returns the full console label ("Firewall should be
# enabled"), not the enum name (FirewallEnabled). Comparison is against JSON values.
# REST id (guid) == PS SDK Id (guid) - join them to auto-map enum->label.
#
# USAGE - single lab via env vars
#   $env:VBR_LAB_PRIMARY  = "vbr-lab1.example.com"
#   $env:VBR_LAB_FALLBACK = "vbr-lab2.corp.example.com"
#   $env:VBR_LAB_USER     = "veeamadmin"
#   $env:VBR_LAB_PASSWORD = "hunter2"
#   .\Check-SecurityComplianceDrift-REST.ps1
#
# USAGE - all labs from config file
#   Copy labs-config.example.json -> labs-config.json, fill in hosts + env var names
#   .\Check-SecurityComplianceDrift-REST.ps1 -LabsConfig .\labs-config.json
#
#   (auto-detected: if labs-config.json exists alongside the script, used automatically)
#
# USAGE - single lab override
#   .\Check-SecurityComplianceDrift-REST.ps1 -Lab 192.168.20.184 -RunScan
#
# EXIT CODES
#   0  No drift on any lab
#   1  Drift detected on one or more labs
#   2  No lab reachable
#   3  Auth or API failure

param(
    [string] $Lab         = "",          # single-lab override; skips labs-config
    [string] $LabsConfig  = "",          # path to labs-config.json; auto-detected if omitted
    [int]    $Port        = 0,           # overrides per-lab port (single-lab mode)
    [string] $Username    = "",          # overrides env var (single-lab mode)
    [string] $Password    = "",          # overrides env var (single-lab mode)
    [int]    $ConnectTimeoutSeconds = 0,
    [string] $ApiVer      = "1.3-rev1",
    [switch] $RunScan,
    [int]    $ScanPollSeconds = 300,
    [switch] $Json,
    [string] $OutFile     = ""
)

$ErrorActionPreference = "Stop"

# ----------------------------------------------------------
# Load .env file (does NOT override existing env vars)
# ----------------------------------------------------------
$dotEnvPath = Join-Path $PSScriptRoot ".env"
if (Test-Path $dotEnvPath) {
    foreach ($line in Get-Content $dotEnvPath) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^\s*([^=]+?)\s*=\s*(.*?)\s*$') {
            $k = $Matches[1]; $v = $Matches[2] -replace '^[''"]|[''"]$'
            if (-not (Get-Item "env:$k" -ErrorAction SilentlyContinue)) {
                Set-Item "env:$k" $v
            }
        }
    }
    Write-Host "Loaded .env from $dotEnvPath"
}

# ----------------------------------------------------------
# TCP probe helper
# ----------------------------------------------------------
function Test-TcpPort {
    param([string]$Hostname, [int]$Port, [int]$TimeoutMs)
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $ar  = $tcp.BeginConnect($Hostname, $Port, $null, $null)
        $ok  = $ar.AsyncWaitHandle.WaitOne($TimeoutMs)
        if ($ok -and $tcp.Connected) { $tcp.Close(); return $true }
        $tcp.Close()
        return $false
    } catch { return $false }
}

# ----------------------------------------------------------
# Probe one lab, return result object
# ----------------------------------------------------------
function Invoke-LabDriftCheck {
    param(
        [string] $LabHost,
        [int]    $LabPort,
        [string] $LabUser,
        [string] $LabPass,
        [string] $LabName,
        [int]    $TimeoutSeconds,
        [bool]   $DoRunScan,
        [int]    $PollSeconds,
        [string] $ApiVersion,
        [object] $LabelMap,
        [string] $ValidatedFor
    )

    $result = [pscustomobject]@{
        Name          = $LabName
        Host          = $LabHost
        Reachable     = $false
        AuthOk        = $false
        TotalRules    = 0
        MappedRules   = 0
        UnmappedRules = 0
        HasDrift      = $false
        Skipped       = $false
        Error         = ""
        DriftRows     = @()
        AllRows       = @()
    }

    Write-Host ""
    Write-Host "[$LabName] Probing ${LabHost}:${LabPort} ..." -NoNewline
    if (-not (Test-TcpPort -Hostname $LabHost -Port $LabPort -TimeoutMs ($TimeoutSeconds * 1000))) {
        Write-Host " unreachable" -ForegroundColor Yellow
        $result.Skipped = $true
        $result.Error   = "Unreachable"
        return $result
    }
    Write-Host " reachable" -ForegroundColor Green
    $result.Reachable = $true

    $baseUrl = "https://${LabHost}:${LabPort}"

    try {
        $tok = Invoke-RestMethod -SkipCertificateCheck `
            -Method      POST `
            -Uri         "$baseUrl/api/oauth2/token" `
            -Headers     @{ "x-api-version" = $ApiVersion } `
            -ContentType "application/x-www-form-urlencoded" `
            -Body        "grant_type=password&username=$LabUser&password=$([uri]::EscapeDataString($LabPass))"
    } catch {
        Write-Host "[$LabName] ERROR: Auth failed - $($_.Exception.Message)" -ForegroundColor Red
        $result.Error = "AuthFailed: $($_.Exception.Message)"
        return $result
    }
    $result.AuthOk = $true

    $hdrs = @{ "Authorization" = "Bearer $($tok.access_token)"; "x-api-version" = $ApiVersion }

    if ($DoRunScan) {
        Write-Host "[$LabName] Starting scan ..." -NoNewline
        try {
            Invoke-RestMethod -SkipCertificateCheck -Method POST `
                -Uri "$baseUrl/api/v1/securityAnalyzer/start" -Headers $hdrs | Out-Null
        } catch {
            Write-Host " WARNING: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        $deadline = (Get-Date).AddSeconds($PollSeconds)
        $done = $false
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 5
            try {
                $lr = Invoke-RestMethod -SkipCertificateCheck `
                    -Uri "$baseUrl/api/v1/securityAnalyzer/lastRun" -Headers $hdrs
                if ($lr.status -notin @("Running", "Analyzing", "Pending")) {
                    Write-Host " done ($($lr.status))" -ForegroundColor Green
                    $done = $true; break
                }
                Write-Host "." -NoNewline
            } catch { break }
        }
        if (-not $done) { Write-Host " timed out - using last results" -ForegroundColor Yellow }
    }

    try {
        $resp = Invoke-RestMethod -SkipCertificateCheck `
            -Uri "$baseUrl/api/v1/securityAnalyzer/bestPractices" -Headers $hdrs
    } catch {
        Write-Host "[$LabName] ERROR: Fetch failed - $($_.Exception.Message)" -ForegroundColor Red
        $result.Error = "FetchFailed: $($_.Exception.Message)"
        return $result
    }

    $items = if ($resp.items) { $resp.items } elseif ($resp.data) { $resp.data } else { @($resp) }
    $sample = ($items | Select-Object -First 1).bestPractice
    $fmt = if ($sample -match '\s') { "label" } else { "enum" }

    $rows = foreach ($r in $items) {
        $bp = $r.bestPractice; $inJson = $false; $enumKey = ""
        if ($fmt -eq "label") {
            $m = $LabelMap.PSObject.Properties | Where-Object { $_.Value -ieq $bp } | Select-Object -First 1
            $inJson = $null -ne $m
            $enumKey = if ($inJson) { $m.Name } else { "" }
        } else {
            $inJson  = ($LabelMap.PSObject.Properties.Name -contains $bp)
            $enumKey = $bp
        }
        [pscustomobject]@{ Id=$r.id; Label=$bp; Status=$r.status; EnumKey=$enumKey; InJsonMap=$inJson }
    }

    $driftRows = @($rows | Where-Object { -not $_.InJsonMap })

    $result.TotalRules    = $items.Count
    $result.MappedRules   = ($rows | Where-Object { $_.InJsonMap }).Count
    $result.UnmappedRules = $driftRows.Count
    $result.HasDrift      = ($driftRows.Count -gt 0)
    $result.DriftRows     = $driftRows
    $result.AllRows       = $rows

    if ($result.HasDrift) {
        Write-Host "[$LabName] DRIFT: $($driftRows.Count) unmapped rule(s)" -ForegroundColor Yellow
        $driftRows | ForEach-Object { Write-Host "  -> $($_.Label)  [$($_.Status)]" -ForegroundColor Yellow }
    } else {
        Write-Host "[$LabName] OK: all $($items.Count) rule(s) mapped" -ForegroundColor Green
    }

    # Reverse: rules in JSON not seen from this lab (platform-gated)
    if ($fmt -eq "label") {
        $seenLabels   = @($rows | ForEach-Object { $_.Label })
        $jsonOnlyVals = $LabelMap.PSObject.Properties.Value | Where-Object { $seenLabels -inotcontains $_ }
        if ($jsonOnlyVals.Count -gt 0) {
            Write-Host "[$LabName] NOTE: $($jsonOnlyVals.Count) JSON label(s) not returned (platform-gated or version-specific)" -ForegroundColor Cyan
        }
    }

    return $result
}

# ----------------------------------------------------------
# Load VbrConfig.json
# ----------------------------------------------------------
$configPath = Join-Path $PSScriptRoot "VbrConfig.json"
if (-not (Test-Path $configPath)) {
    Write-Host "ERROR: VbrConfig.json not found at $configPath" -ForegroundColor Red
    exit 3
}
$vbrConfig    = Get-Content $configPath -Raw | ConvertFrom-Json
$labelMap     = $vbrConfig.SecurityComplianceRuleNames
$validatedFor = $vbrConfig.SecurityComplianceRulesValidatedForVbrVersion
Write-Host "VbrConfig.json: $(@($labelMap.PSObject.Properties).Count) mappings (validated for VBR $validatedFor)."

# ----------------------------------------------------------
# Build lab list
# ----------------------------------------------------------
$defaultTimeout = if ($ConnectTimeoutSeconds -gt 0) { $ConnectTimeoutSeconds }
                  elseif ($env:VBR_LAB_CONNECT_TIMEOUT_SECONDS) { [int]$env:VBR_LAB_CONNECT_TIMEOUT_SECONDS }
                  else { 5 }

$labList = [System.Collections.ArrayList]::new()

if ($Lab) {
    # Explicit single-lab override
    $user = if ($Username)  { $Username }  elseif ($env:VBR_LAB_USER)     { $env:VBR_LAB_USER }     else { Read-Host "VBR username" }
    $pass = if ($Password)  { $Password }  elseif ($env:VBR_LAB_PASSWORD) { $env:VBR_LAB_PASSWORD } else { [System.Net.NetworkCredential]::new("",(Read-Host "Password" -AsSecureString)).Password }
    $p    = if ($Port -gt 0) { $Port } elseif ($env:VBR_LAB_PORT) { [int]$env:VBR_LAB_PORT } else { 9419 }
    [void]$labList.Add([pscustomobject]@{ Name="CLI override"; Host=$Lab; Port=$p; User=$user; Pass=$pass; Enabled=$true })
} else {
    # Auto-detect labs-config.json if not specified
    if (-not $LabsConfig) {
        $autoPath = Join-Path $PSScriptRoot "labs-config.json"
        if (Test-Path $autoPath) { $LabsConfig = $autoPath }
    }

    if ($LabsConfig -and (Test-Path $LabsConfig)) {
        Write-Host "Loading labs from $LabsConfig"
        $cfg     = Get-Content $LabsConfig -Raw | ConvertFrom-Json
        $timeout = if ($cfg.options -and $cfg.options.connectTimeoutSeconds) { [int]$cfg.options.connectTimeoutSeconds } else { $defaultTimeout }
        $defaultTimeout = $timeout
        foreach ($labEntry in $cfg.labs) {
            $labEnabled  = [string]($labEntry.PSObject.Properties['enabled']?.Value)
            if ($labEnabled -eq 'False') { continue }

            $userVarName = [string]$labEntry.userEnvVar
            $passVarName = [string]$labEntry.passwordEnvVar
            $labName     = [string]$labEntry.name
            $labHost     = [string]$labEntry.host
            $labPort     = if ($labEntry.port) { [int]$labEntry.port } else { 9419 }

            $u = [System.Environment]::GetEnvironmentVariable($userVarName)
            $p = [System.Environment]::GetEnvironmentVariable($passVarName)

            if (-not $u -or -not $p) {
                Write-Host "WARNING: Skipping '$labName' - env vars not set ($userVarName / $passVarName)" -ForegroundColor Yellow
                continue
            }
            [void]$labList.Add([pscustomobject]@{
                Name = $labName; Host = $labHost; Port = $labPort; User = $u; Pass = $p
            })
        }
    } else {
        # Fallback: env-var single-lab with primary/fallback probe
        $primary  = if ($env:VBR_LAB_PRIMARY)  { $env:VBR_LAB_PRIMARY }  else { "" }
        $fallback = if ($env:VBR_LAB_FALLBACK) { $env:VBR_LAB_FALLBACK } else { "" }
        $user     = if ($env:VBR_LAB_USER)     { $env:VBR_LAB_USER }     else { Read-Host "VBR username" }
        $pass     = if ($env:VBR_LAB_PASSWORD) { $env:VBR_LAB_PASSWORD } else { [System.Net.NetworkCredential]::new("",(Read-Host "Password" -AsSecureString)).Password }
        $port     = if ($env:VBR_LAB_PORT)     { [int]$env:VBR_LAB_PORT } else { 9419 }

        if (-not $primary -and -not $fallback) {
            Write-Host "ERROR: No lab specified. Use -Lab, -LabsConfig, or set VBR_LAB_PRIMARY/VBR_LAB_FALLBACK." -ForegroundColor Red
            exit 2
        }

        $resolved = $null
        foreach ($candidate in @($primary, $fallback) | Where-Object { $_ }) {
            Write-Host "Probing ${candidate}:${port} ..." -NoNewline
            if (Test-TcpPort -Hostname $candidate -Port $port -TimeoutMs ($defaultTimeout * 1000)) {
                Write-Host " reachable" -ForegroundColor Green
                $resolved = $candidate; break
            } else {
                Write-Host " unreachable" -ForegroundColor Yellow
            }
        }
        if (-not $resolved) {
            Write-Host "ERROR: Neither primary ($primary) nor fallback ($fallback) is reachable. Check VPN." -ForegroundColor Red
            exit 2
        }
        [void]$labList.Add([pscustomobject]@{ Name="Lab ($resolved)"; Host=$resolved; Port=$port; User=$user; Pass=$pass; Enabled=$true })
    }
}

if ($labList.Count -eq 0) {
    Write-Host "ERROR: No labs to check. Check labs-config.json or env vars." -ForegroundColor Red
    exit 2
}

# ----------------------------------------------------------
# Run drift check against each lab
# ----------------------------------------------------------
$allResults = foreach ($entry in $labList) {
    Invoke-LabDriftCheck `
        -LabHost        $entry.Host `
        -LabPort        $entry.Port `
        -LabUser        $entry.User `
        -LabPass        $entry.Pass `
        -LabName        $entry.Name `
        -TimeoutSeconds $defaultTimeout `
        -DoRunScan      $RunScan.IsPresent `
        -PollSeconds    $ScanPollSeconds `
        -ApiVersion     $ApiVer `
        -LabelMap       $labelMap `
        -ValidatedFor   $validatedFor
}

# ----------------------------------------------------------
# Aggregate summary
# ----------------------------------------------------------
$totalDrift     = ($allResults | Where-Object { $_.HasDrift }).Count
$totalReachable = ($allResults | Where-Object { $_.Reachable }).Count
$totalSkipped   = ($allResults | Where-Object { $_.Skipped }).Count

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "SUMMARY: $totalReachable/$($labList.Count) lab(s) reached  |  $totalDrift drift  |  $totalSkipped skipped" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

if ($Json -or $OutFile) {
    $report = [pscustomobject]@{
        ValidatedFor = $validatedFor
        GeneratedAt  = (Get-Date -Format "o")
        TotalLabs    = $labList.Count
        ReachedLabs  = $totalReachable
        DriftLabs    = $totalDrift
        Results      = $allResults
    }
    $json = $report | ConvertTo-Json -Depth 6
    if ($Json)    { Write-Output $json }
    if ($OutFile) { $json | Set-Content -Path $OutFile -Encoding UTF8; Write-Host "Report written to $OutFile" }
}

if ($totalDrift -gt 0) { exit 1 } else { exit 0 }

param(
    [Parameter(Mandatory)]
    [string]$VBRServer,
    [Parameter(Mandatory)]
    [int]$VBRVersion,
    [Parameter(Mandatory = $false)]
    [string]$ReportPath = ""
)

# If ReportPath not provided, use default with server name and timestamp structure
if ([string]::IsNullOrEmpty($ReportPath)) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $ReportPath = "C:\temp\vHC\Original\VBR\$VBRServer\$timestamp"
}

# VMC log path is hardcoded for now. If logs are sent elsewhere, please adjust accordingly.
 $logsPath = "C:\ProgramData\Veeam\Backup\Utils\VMC.log"

 # section identifiers
 $unstrucStart = "=====UNSTRUCTURED DATA===="
  $nasStart = "=====NAS INFRASTRUCTURE===="
 $sectionEnd = "========"
 
 #get file info and set empty containers.
 if (Test-Path -LiteralPath $logsPath) {
     $content = Get-Content -LiteralPath $logsPath
 } else {
     Write-Verbose "VMC.log not found at $logsPath - skipping unstructured/NAS section parsing"
     $content = @()
 }
 $sections = @()
 $currentSection = @()
 $capturing = $false
 
 foreach($line in $content){
     if(-not $capturing -and $line -match $unstrucStart){
         $capturing = $true
         $currentSection = @()
     }
     elseif(-not $capturing -and $line -match $nasStart){
        $capturing = $true
        $currentSection = @()
    }
     elseif($capturing){
         if($line -match $sectionEnd){
             $capturing = $false
             $sections += ,($currentSection)
             $currentSection = @()
         }
         else{
             if (-not ($line -match '\[VmcStats\]')) {
                 $stripped = $line -replace '^\[[\d.:\s]+\]\s+\d+(?:\s+\[\w+\])?\s+\w+\s+\(\d+\)\s+', ''
                 $currentSection += $stripped
             }
         }
     }
 }
 
 # Here we set a new list to only contain the final data section from the log:
 $dataLines = $sections[$sections.Count-1]

 # search each line, looking for these strings: TotalObjectStorageSize, NasBackupSourceShareStats, TotalShareSize. Group each into their own list
    $totalObjectStorageSize = @()
    $nasBackupSourceShareStats = @()
    $totalShareSize = @()      # v12: combined single-line records
    $parentShares = @()        # v13: parent lines (SmbServer / NfsServer, not ChildShare)
    $childShares = @()         # v13: child lines (SmbServerChildShare / NfsServerChildShare)

    $dataLines | ForEach-Object {
        if ($_ -match "TotalObjectStorageSize") {
            $totalObjectStorageSize += $_
        }
        elseif ($_ -match "NasBackupSourceShareStats") {
            $nasBackupSourceShareStats += $_
        }
        # Check child before parent — "SmbServer" is a substring of "SmbServerChildShare"
        elseif ($_ -match "SmbServerChildShare|NfsServerChildShare") {
            $childShares += $_
        }
        elseif ($_ -match "SmbServer|NfsServer") {
            $parentShares += $_
        }
        elseif ($_ -match "TotalShareSize") {
            $totalShareSize += $_
        }
    }

 
# Parse a log line into a hashtable of key-value pairs
function ConvertTo-LogProperties([string]$logLine) {
    $props = @{}
    $logLine.Trim() -split ', ' | ForEach-Object {
        $parts = $_.Split(':', 2)
        if ($parts.Count -eq 2) {
            $props[$parts[0].Trim()] = $parts[1].Trim()
        }
    }
    return $props
}

$csvData = @($totalObjectStorageSize | ForEach-Object { [PSCustomObject](ConvertTo-LogProperties $_) })
if (!(Test-Path $ReportPath)) { New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null }
$csvData | Export-Csv -Path "$ReportPath\${VBRServer}_NasObjectSourceStorageSize.csv" -NoTypeInformation

$csvData2 = @($nasBackupSourceShareStats | ForEach-Object { [PSCustomObject](ConvertTo-LogProperties $_) })
$csvData2 | Export-Csv -Path "$ReportPath\${VBRServer}_NasFileData.csv" -NoTypeInformation

# Parse v12 combined lines
$v12Rows = @($totalShareSize | ForEach-Object {
    $props = ConvertTo-LogProperties $_
    if (-not $props.ContainsKey('ParentServerID')) { $props['ParentServerID'] = $null }
    [PSCustomObject]$props
})

# Parse v13 parent lines into a hashtable keyed by FileShareID
$parentMap = @{}
$parentShares | ForEach-Object {
    $props = ConvertTo-LogProperties $_
    if ($props.ContainsKey('FileShareID')) {
        $parentMap[$props['FileShareID']] = $props
    }
}

# Parse v13 child lines and join with parent
$v13Rows = @($childShares | ForEach-Object {
    $childProps = ConvertTo-LogProperties $_
    $merged = @{}

    # Start with parent properties (if parent found)
    $parentId = $childProps['ParentServerID']
    if ($parentId -and $parentMap.ContainsKey($parentId)) {
        foreach ($key in $parentMap[$parentId].Keys) {
            $merged[$key] = $parentMap[$parentId][$key]
        }
    }

    # Overlay child properties (child wins on conflict)
    foreach ($key in $childProps.Keys) {
        $merged[$key] = $childProps[$key]
    }

    # Ensure ParentServerID always present
    if (-not $merged.ContainsKey('ParentServerID')) { $merged['ParentServerID'] = $null }
    [PSCustomObject]$merged
})

# Union v12 and v13 rows; v13 rows first so the header reflects the full v13 schema
$allShareRows = @()
if ($v13Rows.Count -gt 0) { $allShareRows += $v13Rows }
if ($v12Rows.Count -gt 0) { $allShareRows += $v12Rows }

$allShareRows | Export-Csv -Path "$ReportPath\${VBRServer}_NasSharesize.csv" -NoTypeInformation
#Requires -Version 5.1

function Export-VhciComplianceMeta {
    <#
    .Synopsis
        Writes scan-duration telemetry for the Security & Compliance analyzer
        to a sidecar CSV (_SecurityComplianceMeta.csv). Always called regardless
        of scan outcome so the HTML/JSON renderers can show why the rule table
        is missing rather than rendering an empty section.
    .Parameter DurationSeconds
        Wall-clock seconds the scan took. Rounded to 1 decimal in the CSV.
    .Parameter Status
        One of: 'Completed' | 'TimedOut' | 'Failed'.
    .Parameter StartedAt
        DateTime the scan kicked off. Serialized as ISO-8601 round-trip ('o').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [double]   $DurationSeconds,
        [Parameter(Mandatory)] [ValidateSet('Completed','TimedOut','Failed')] [string] $Status,
        [Parameter(Mandatory)] [datetime] $StartedAt
    )

    $meta = [pscustomobject][ordered]@{
        ScanStartedAt       = $StartedAt.ToUniversalTime().ToString('o')
        ScanCompletedAt     = (Get-Date).ToUniversalTime().ToString('o')
        ScanDurationSeconds = [math]::Round($DurationSeconds, 1)
        ScanStatus          = $Status
    }

    $meta | Export-VhciCsv -FileName '_SecurityComplianceMeta.csv'
}

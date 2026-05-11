#Requires -Version 5.1

function Get-VhcSecurityCompliance {
    <#
    .Synopsis
        Triggers a Security & Compliance Analyzer scan and exports results.
        v13+: runs Start-VBRSecurityComplianceAnalyzer -Wait inside Start-ThreadJob
              so the main thread can log heartbeats while the scan runs. Hard ceiling
              from $Config.Thresholds.CompliancePollMaxSeconds (default 600s) prevents
              true hangs.
        v12:  reads results via [Veeam.Backup.DBManager.CDBManager]::Instance.BestPractices.GetAll()
              after starting the analyzer (no -Wait support pre-v13).
        Always writes _SecurityComplianceMeta.csv with scan duration + status so the
        HTML/JSON renderer can surface "TimedOut" / "Failed" instead of a silent empty
        section.
        Rule names are resolved from $Config.SecurityComplianceRuleNames (VbrConfig.json).
        Unknown rule types are output with the raw Type string (not dropped) to preserve
        visibility of new compliance rules when the JSON mapping is stale.
        Gated on VBR v12+ (VBRVersion -gt 11).
        Exports _SecurityCompliance.csv (rule rows) and _SecurityComplianceMeta.csv
        (scan telemetry).
    .Parameter VBRVersion
        Major VBR version integer. Function is a no-op for versions 11 and below.
    .Parameter Config
        Deserialized VbrConfig.json object. Must contain a SecurityComplianceRuleNames
        property and Thresholds with CompliancePollMaxSeconds + ComplianceHeartbeatSeconds.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$VBRVersion = 0,

        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    if ($VBRVersion -le 11) {
        Write-LogFile "VBR Version ($VBRVersion) does not support Security & Compliance - skipping"
        return
    }

    Write-LogFile "VBR Version ($VBRVersion) supports Security & Compliance - starting collection..."

    $StatusObj = @{
        'Ok'            = 'Passed'
        'Violation'     = 'Not Implemented'
        'UnableToCheck' = 'Unable to detect'
        'Suppressed'    = 'Suppressed'
    }

    $hardCeilingSeconds = if ($Config.Thresholds.CompliancePollMaxSeconds) { [int]$Config.Thresholds.CompliancePollMaxSeconds } else { 600 }
    $heartbeatSeconds   = if ($Config.Thresholds.ComplianceHeartbeatSeconds) { [int]$Config.Thresholds.ComplianceHeartbeatSeconds } else { 15 }
    $scanStart = Get-Date

    try {
        # ---------------------------------------------------------------
        # Trigger scan and wait for completion
        # ---------------------------------------------------------------
        Write-LogFile "Starting Security & Compliance scan..."
        $SecurityCompliances = $null

        if ($VBRVersion -ge 13) {
            # v13+ supports Start-VBRSecurityComplianceAnalyzer -Wait. Run it in a
            # ThreadJob so the main thread can log heartbeats while the scan runs.
            Write-LogFile "Running Start-VBRSecurityComplianceAnalyzer -Wait in ThreadJob (heartbeat ${heartbeatSeconds}s, ceiling ${hardCeilingSeconds}s)..."

            $analyzerJob = Start-ThreadJob -ScriptBlock {
                Start-VBRSecurityComplianceAnalyzer -Wait -ErrorAction Stop `
                    -WarningAction SilentlyContinue -InformationAction SilentlyContinue
            }

            while ($analyzerJob.State -eq 'Running') {
                $elapsed = [int]((Get-Date) - $scanStart).TotalSeconds
                if ($elapsed -ge $hardCeilingSeconds) { break }
                Start-Sleep -Seconds $heartbeatSeconds
                $elapsed = [int]((Get-Date) - $scanStart).TotalSeconds
                Write-LogFile "[SecurityCompliance] Scan in progress... ${elapsed}s elapsed (max ${hardCeilingSeconds}s)"
            }

            $scanDuration = (Get-Date) - $scanStart

            if ($analyzerJob.State -eq 'Running') {
                Stop-Job -Job $analyzerJob -ErrorAction SilentlyContinue
                Remove-Job -Job $analyzerJob -Force -ErrorAction SilentlyContinue
                $msg = "Compliance scan exceeded ${hardCeilingSeconds}s hard ceiling - aborted. Increase Thresholds.CompliancePollMaxSeconds in VbrConfig.json."
                Write-LogFile $msg -LogLevel "ERROR"
                Add-VhciModuleError -CollectorName 'SecurityCompliance' -ErrorMessage $msg
                Export-VhciComplianceMeta -DurationSeconds $scanDuration.TotalSeconds -Status 'TimedOut' -StartedAt $scanStart
                return
            }

            if ($analyzerJob.State -eq 'Failed') {
                $jobReason = ($analyzerJob.ChildJobs | ForEach-Object { $_.JobStateInfo.Reason.Message }) -join '; '
                Remove-Job -Job $analyzerJob -Force -ErrorAction SilentlyContinue
                $msg = "Start-VBRSecurityComplianceAnalyzer failed: $jobReason"
                Write-LogFile $msg -LogLevel "ERROR"
                Add-VhciModuleError -CollectorName 'SecurityCompliance' -ErrorMessage $msg
                Export-VhciComplianceMeta -DurationSeconds $scanDuration.TotalSeconds -Status 'Failed' -StartedAt $scanStart
                return
            }

            Receive-Job -Job $analyzerJob | Out-Null
            Remove-Job -Job $analyzerJob -Force -ErrorAction SilentlyContinue
            Write-LogFile "[SecurityCompliance] Scan completed in $([math]::Round($scanDuration.TotalSeconds, 1))s"

            $SecurityCompliances = Get-VhciComplianceResults -VBRVersion $VBRVersion
        }
        else {
            # v12: no -Wait parameter. Kick off the scan, then sleep up to the
            # hard ceiling while heartbeating; pull results from the v12 DB path.
            try {
                Start-VBRSecurityComplianceAnalyzer -ErrorAction Stop `
                    -WarningAction SilentlyContinue -InformationAction SilentlyContinue
                Write-LogFile "Start-VBRSecurityComplianceAnalyzer completed successfully"
            }
            catch {
                $errMsg  = if ($_.Exception.Message) { $_.Exception.Message.ToString() } else { "No error message" }
                $errType = if ($_.Exception)         { $_.Exception.GetType().FullName  } else { "Unknown" }
                Write-LogFile "Start-VBRSecurityComplianceAnalyzer failed: $errMsg" -LogLevel "ERROR"
                Write-LogFile "Exception Type: $errType" -LogLevel "ERROR"
                throw
            }

            $elapsed = 0
            while ($elapsed -lt $hardCeilingSeconds) {
                Start-Sleep -Seconds $heartbeatSeconds
                $elapsed += $heartbeatSeconds
                Write-LogFile "[SecurityCompliance] Scan in progress... ${elapsed}s elapsed (max ${hardCeilingSeconds}s)"
                try {
                    $SecurityCompliances = Get-VhciComplianceResults -VBRVersion $VBRVersion
                    if ($SecurityCompliances -and $SecurityCompliances.Count -gt 0) { break }
                }
                catch {
                    Write-LogFile "Result retrieval at ${elapsed}s not ready, continuing..."
                }
            }

            if (-not $SecurityCompliances -or $SecurityCompliances.Count -eq 0) {
                $SecurityCompliances = Get-VhciComplianceResults -VBRVersion $VBRVersion
            }
        }

        $scanDuration = (Get-Date) - $scanStart
        Write-LogFile "Security & Compliance scan completed."

        # ---------------------------------------------------------------
        # Map results to output rows
        # ---------------------------------------------------------------
        $OutObj = [System.Collections.ArrayList]::new()
        Write-LogFile "Processing $($SecurityCompliances.Count) compliance rules..."
        Write-LogFile "SecurityComplianceRuleNames has $($Config.SecurityComplianceRuleNames.PSObject.Properties.Count) entries"

        $unmappedTypes  = [System.Collections.Generic.List[string]]::new()
        $processedCount = 0
        $skippedCount   = 0
        $errorCount     = 0

        foreach ($SecurityCompliance in $SecurityCompliances) {
            try {
                $complianceType   = $null
                $complianceStatus = $null

                if ($SecurityCompliance.Type) {
                    $complianceType = $SecurityCompliance.Type.ToString()
                }
                else {
                    Write-LogFile "Warning: Compliance item has null Type - skipping" -LogLevel "WARNING"
                    $skippedCount++
                    continue
                }

                if ($SecurityCompliance.Status) {
                    $complianceStatus = $SecurityCompliance.Status.ToString()
                }
                else {
                    Write-LogFile "Warning: Compliance item '$complianceType' has null Status - skipping" -LogLevel "WARNING"
                    $skippedCount++
                    continue
                }

                # Resolve rule name - fall back to raw type string for unknown rules
                # so that new compliance checks remain visible even when VbrConfig.json is stale.
                $ruleName = $Config.SecurityComplianceRuleNames.$complianceType
                if (-not $ruleName) {
                    $unmappedTypes.Add($complianceType)
                    $ruleName = $complianceType
                }

                # Resolve status - fall back to raw status string for unknown values
                $statusDisplay = if ($StatusObj.ContainsKey($complianceStatus)) {
                    $StatusObj[$complianceStatus]
                }
                else {
                    Write-LogFile "Warning: Unknown compliance status '$complianceStatus' for type '$complianceType' - using raw value" -LogLevel "WARNING"
                    $complianceStatus
                }

                $inObj = [pscustomobject][ordered]@{
                    'Best Practice' = $ruleName
                    'Status'        = $statusDisplay
                }
                [void]$OutObj.Add($inObj)
                $processedCount++
            }
            catch {
                $errorCount++
                $errMsg  = if ($_.Exception.Message) { $_.Exception.Message.ToString() } else { "No error message" }
                $errType = if ($_.Exception)         { $_.Exception.GetType().FullName  } else { "Unknown" }
                Write-LogFile "Error processing compliance rule ($errorCount): $errMsg" -LogLevel "ERROR"
                Write-LogFile "Exception Type: $errType" -LogLevel "ERROR"
                if ($complianceType)   { Write-LogFile "Rule Type: $complianceType"     -LogLevel "ERROR" }
                if ($complianceStatus) { Write-LogFile "Rule Status: $complianceStatus" -LogLevel "ERROR" }
            }
        }

        Write-LogFile "Processed $processedCount compliance rules, skipped $skippedCount, errors $errorCount"
        Write-LogFile "OutObj count: $($OutObj.Count)"

        if ($unmappedTypes.Count -gt 0) {
            $validatedFor = $Config.SecurityComplianceRulesValidatedForVbrVersion
            $msg = "$($unmappedTypes.Count) compliance rule(s) have no label mapping in VbrConfig.json " +
                   "(mapping validated for VBR $validatedFor, running VBR $VBRVersion): " +
                   ($unmappedTypes -join ', ')
            Write-LogFile $msg -LogLevel "WARNING"
            Add-VhciModuleError -CollectorName 'SecurityCompliance' -ErrorMessage $msg
        }

        if ($OutObj.Count -gt 0) {
            try {
                Write-LogFile "Exporting $($OutObj.Count) compliance items to CSV..."
                $OutObj | Export-VhciCsv -FileName '_SecurityCompliance.csv'
                Write-LogFile "Security Compliance CSV export completed successfully"
            }
            catch {
                $errMsg     = if ($_.Exception.Message)    { $_.Exception.Message.ToString()   } else { "No error message" }
                $errType    = if ($_.Exception)            { $_.Exception.GetType().FullName    } else { "Unknown" }
                $stackTrace = if ($_.ScriptStackTrace)     { $_.ScriptStackTrace.ToString()     } else { "No stack trace" }
                Write-LogFile "Failed to export Security Compliance CSV: $errMsg" -LogLevel "ERROR"
                Write-LogFile "Exception Type: $errType"                          -LogLevel "ERROR"
                Write-LogFile "Stack Trace: $stackTrace"                          -LogLevel "ERROR"
            }
        }
        else {
            Write-LogFile "No compliance data to export - OutObj is empty" -LogLevel "WARNING"
        }

        Export-VhciComplianceMeta -DurationSeconds $scanDuration.TotalSeconds -Status 'Completed' -StartedAt $scanStart
    }
    catch {
        $errMsg     = if ($_.Exception.Message) { $_.Exception.Message.ToString() } else { $_.ToString() }
        $errType    = if ($_.Exception)         { $_.Exception.GetType().FullName  } else { "Unknown" }
        $stackTrace = if ($_.ScriptStackTrace)  { $_.ScriptStackTrace.ToString()   } else { "No stack trace available" }
        Write-LogFile "Security & Compliance collection failed: $errMsg" -LogLevel "ERROR"
        Write-LogFile "Exception Type: $errType"                         -LogLevel "ERROR"
        Write-LogFile "Stack Trace: $stackTrace"                         -LogLevel "ERROR"
        Add-VhciModuleError -CollectorName 'SecurityCompliance' -ErrorMessage $errMsg

        $failDuration = if ($scanStart) { ((Get-Date) - $scanStart).TotalSeconds } else { 0 }
        $failStart    = if ($scanStart) { $scanStart } else { Get-Date }
        try { Export-VhciComplianceMeta -DurationSeconds $failDuration -Status 'Failed' -StartedAt $failStart } catch { }
    }
}

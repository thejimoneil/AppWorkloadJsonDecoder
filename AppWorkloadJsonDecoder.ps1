# Intune App Install Analyzer
# Analyzes AppWorkload.log, AgentExecutor.log, and IntuneManagementExtension.log
# for a specific App ID to show the most recent install attempt details.

param(
    [string]$AppID,
    [string]$LogDir = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs",
    [string]$OutputDir = ".",
    [switch]$Help
)

if ($Help) {
    Write-Host @"
Intune App Install Analyzer - Help

DESCRIPTION:
    Analyzes three Intune Management Extension log files for a specific App ID
    to surface the most recent install attempt details:

      AppWorkload.log                 : Install info (JSON decoded, detection script decoded from base64)
      AgentExecutor.log               : Detection and requirements failure info
      IntuneManagementExtension.log   : Overall policy info and Intune action overview

PARAMETERS:
    -AppID      : App GUID to search for (required; prompted if omitted)
    -LogDir     : Directory containing IME log files
                  (default: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs)
    -OutputDir  : Directory for output files (default: current directory)
    -Help       : Show this help message

USAGE EXAMPLES:
    # Analyze a specific app
    .\AppWorkloadJsonDecoder.ps1 -AppID "7211687c-d63c-4470-b1bf-4f1714fc4d9f"

    # Custom log directory and output directory
    .\AppWorkloadJsonDecoder.ps1 -AppID "7211687c-d63c-4470-b1bf-4f1714fc4d9f" -LogDir "C:\Logs" -OutputDir "C:\Analysis"

OUTPUT FILES:
    - {AppID}_{DateTime}_AppWorkload.json    : Decoded AppWorkload policy data
    - {AppID}_{DateTime}_DetectionRule.ps1   : Decoded detection script
    - {AppID}_{DateTime}_AgentExecutor.txt   : AgentExecutor log entries for the app
    - {AppID}_{DateTime}_IME.txt             : IntuneManagementExtension log entries for the app

"@ -ForegroundColor Green
    exit 0
}

# Prompt for AppID if not provided
if ([string]::IsNullOrWhiteSpace($AppID)) {
    $AppID = Read-Host "Enter the App ID (GUID) to search for"
    if ([string]::IsNullOrWhiteSpace($AppID)) {
        Write-Error "No App ID provided. Exiting."
        exit 1
    }
}

# Ensure output directory exists
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Log file paths
$AppWorkloadLog   = Join-Path $LogDir "AppWorkload.log"
$AgentExecutorLog = Join-Path $LogDir "AgentExecutor.log"
$IMELog           = Join-Path $LogDir "IntuneManagementExtension.log"

# Fallback datetime string used for output file naming
$dateTimeString = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")

Write-Host "`n=== Intune App Install Analyzer ===" -ForegroundColor Cyan
Write-Host "App ID      : $AppID"        -ForegroundColor White
Write-Host "Log Dir     : $LogDir"       -ForegroundColor White
Write-Host "Output Dir  : $OutputDir`n"  -ForegroundColor White

# ---------------------------------------------------------------------------
# Helper: parse datetime from a CMTrace-format log line.
# Handles time strings like "06:48:58.5778926" and "06:48:58.577+000".
# ---------------------------------------------------------------------------
function Get-LogDateTime {
    param([string]$Line)
    $dateMatch = [regex]::Match($Line, 'date="([^"]+)"')
    $timeMatch = [regex]::Match($Line, 'time="([^"]+)"')
    if ($dateMatch.Success -and $timeMatch.Success) {
        $dateStr = $dateMatch.Groups[1].Value
        # Strip sub-seconds and any UTC offset (e.g. +000 or -060)
        $timeStr = $timeMatch.Groups[1].Value -replace '\.\d+.*$', ''
        try {
            return [DateTime]::ParseExact("$dateStr $timeStr", "MM-dd-yyyy HH:mm:ss", $null)
        } catch {
            return $null
        }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Helper: extract the log message from a CMTrace log line.
# ---------------------------------------------------------------------------
function Get-LogMessage {
    param([string]$Line)
    $match = [regex]::Match($Line, '\[LOG\[(.*?)\]LOG\]', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }
    return $Line.Trim()
}

# ---------------------------------------------------------------------------
# Helper: given log lines that all contain the AppID, return only those that
# fall within a 2-hour window ending at the most recent entry.
# ---------------------------------------------------------------------------
function Get-MostRecentAttemptEntries {
    param([string[]]$Lines)
    if (-not $Lines -or $Lines.Count -eq 0) { return @() }

    $lastLine = $Lines[$Lines.Count - 1]
    $lastDt   = Get-LogDateTime -Line $lastLine
    if (-not $lastDt) { return $Lines }

    $windowStart = $lastDt.AddHours(-2)
    $result = @()
    foreach ($line in $Lines) {
        $dt = Get-LogDateTime -Line $line
        if ($dt -and $dt -ge $windowStart -and $dt -le $lastDt) {
            $result += $line
        }
    }
    if ($result.Count -gt 0) { return $result }
    return $Lines
}

###############################################################################
# SECTION 1: AppWorkload.log
###############################################################################
Write-Host "=== AppWorkload.log ===" -ForegroundColor Magenta

if (-not (Test-Path $AppWorkloadLog)) {
    Write-Warning "AppWorkload.log not found at: $AppWorkloadLog"
} else {
    try {
        # Collect every "Get policies =" line in the log.  We intentionally
        # do NOT pre-filter by AppID here: the AppID can appear anywhere in a
        # "Get policies =" line (e.g. nested inside another app's policy as a
        # supersedence/dependency reference).  Pre-filtering on the raw text
        # would cause the wrong app's policy to be selected when the AppID
        # matches such a nested field rather than a top-level policy entry.
        $allPolicyLines = @(Get-Content $AppWorkloadLog |
            Where-Object { $_ -like "*Get policies =*" })

        $marker         = "Get policies = "
        $mostRecent     = $null
        $jsonString     = $null
        $jsonObject     = $null
        $targetPolicies = @()

        if ($allPolicyLines.Count -eq 0) {
            Write-Warning "No 'Get policies =' entries found in AppWorkload.log"
        } else {
            # Walk from newest to oldest.  For each line that contains the
            # AppID as plain text (quick pre-filter), parse the JSON and
            # confirm the AppID is a genuine top-level policy Id before
            # accepting the entry.  This guarantees we display the correct
            # App ID and policy data.
            for ($i = $allPolicyLines.Count - 1; $i -ge 0; $i--) {
                $line = $allPolicyLines[$i]
                if ($line -notlike "*$AppID*") { continue }

                $markerIdx = $line.IndexOf($marker)
                $jsonEnd   = $line.LastIndexOf("]LOG]!")
                if ($markerIdx -lt 0) { continue }

                $jsonStart = $markerIdx + $marker.Length
                $candidate = if ($jsonEnd -gt $jsonStart) {
                    $line.Substring($jsonStart, $jsonEnd - $jsonStart)
                } else {
                    $line.Substring($jsonStart)
                }

                try {
                    $parsed   = $candidate | ConvertFrom-Json
                    $matching = @($parsed | Where-Object { $_.Id -eq $AppID })
                    if ($matching.Count -gt 0) {
                        $mostRecent     = $line
                        $jsonString     = $candidate
                        $jsonObject     = $parsed
                        $targetPolicies = $matching
                        break
                    }
                } catch { continue }
            }
        }

        if (-not $mostRecent) {
            Write-Warning "No 'Get policies =' entries found for App ID '$AppID' in AppWorkload.log"
        } else {
            # Determine datetime for output file naming
            $logDt = Get-LogDateTime -Line $mostRecent
            if ($logDt) {
                $dateTimeString = $logDt.ToString("yyyy-MM-dd_HH-mm-ss")
                Write-Host "Most recent policy fetch : $($logDt.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Green
            } else {
                Write-Warning "Could not parse datetime from AppWorkload.log entry; using current time for file names."
            }

            Write-Host "Extracted JSON length    : $($jsonString.Length) characters" -ForegroundColor Cyan

            # Save full prettified JSON
            $prettyJson     = $jsonObject | ConvertTo-Json -Depth 10
            $jsonOutputPath = Join-Path $OutputDir "$($AppID)_$($dateTimeString)_AppWorkload.json"
            $prettyJson | Out-File -FilePath $jsonOutputPath -Encoding UTF8
            Write-Host "JSON saved to            : $jsonOutputPath" -ForegroundColor Green

            # Per-policy summary and decoded fields
            Write-Host "`nPolicy Summary:" -ForegroundColor Yellow
            foreach ($policy in $targetPolicies) {
                Write-Host "  Name          : $($policy.Name)"    -ForegroundColor White
                Write-Host "  ID            : $($policy.Id)"      -ForegroundColor Gray
                Write-Host "  Version       : $($policy.Version)" -ForegroundColor Gray
                Write-Host "  Intent        : $($policy.Intent)"  -ForegroundColor Gray

                # Decode RequirementRules
                if ($policy.RequirementRules) {
                    try {
                        $reqRules = $policy.RequirementRules | ConvertFrom-Json
                        Write-Host "`n  Requirement Rules:" -ForegroundColor Cyan
                        Write-Host "    OS Architecture   : $($reqRules.RequiredOSArchitecture)"     -ForegroundColor Gray
                        Write-Host "    Min Windows Build : $($reqRules.MinimumWindows10BuildNumer)" -ForegroundColor Gray
                        Write-Host "    Run as 32-bit     : $($reqRules.RunAs32Bit)"                 -ForegroundColor Gray
                    } catch {
                        Write-Warning "  Could not parse RequirementRules: $($_.Exception.Message)"
                    }
                }

                # Decode InstallEx
                if ($policy.InstallEx) {
                    try {
                        $installEx = $policy.InstallEx | ConvertFrom-Json
                        Write-Host "`n  Install Settings:" -ForegroundColor Cyan
                        Write-Host "    Run As            : $($installEx.RunAs)"               -ForegroundColor Gray
                        Write-Host "    Requires Logon    : $($installEx.RequiresLogon)"       -ForegroundColor Gray
                        Write-Host "    Max Runtime (min) : $($installEx.MaxRunTimeInMinutes)" -ForegroundColor Gray
                        Write-Host "    Max Retries       : $($installEx.MaxRetries)"          -ForegroundColor Gray
                    } catch {
                        Write-Warning "  Could not parse InstallEx: $($_.Exception.Message)"
                    }
                }

                # Decode DetectionRule (including base64 ScriptBody)
                if ($policy.DetectionRule) {
                    try {
                        $detectionRules = @($policy.DetectionRule | ConvertFrom-Json)
                        Write-Host "`n  Detection Rule:" -ForegroundColor Cyan
                        foreach ($rule in $detectionRules) {
                            Write-Host "    Detection Type : $($rule.DetectionType)" -ForegroundColor Gray
                            if ($rule.DetectionText) {
                                try {
                                    $detectionText = $rule.DetectionText | ConvertFrom-Json
                                    if ($detectionText.ScriptBody) {
                                        try {
                                            $decodedScript = [System.Text.Encoding]::UTF8.GetString(
                                                [System.Convert]::FromBase64String($detectionText.ScriptBody)
                                            )
                                            # Strip BOM (U+FEFF) if present
                                            $decodedScript = $decodedScript.TrimStart([char]0xFEFF)

                                            Write-Host "`n    Decoded Detection Script:" -ForegroundColor Cyan
                                            Write-Host $decodedScript -ForegroundColor White

                                            $scriptHeader = @"
# Detection Rule Script for $($policy.Name)
# Policy ID     : $($policy.Id)
# Extracted on  : $(Get-Date)
# Detection Type: $($rule.DetectionType)

"@
                                            $scriptOutputPath = Join-Path $OutputDir "$($AppID)_$($dateTimeString)_DetectionRule.ps1"
                                            ($scriptHeader + $decodedScript) | Out-File -FilePath $scriptOutputPath -Encoding UTF8
                                            Write-Host "    Detection script saved to: $scriptOutputPath" -ForegroundColor Green
                                        } catch {
                                            Write-Warning "    Could not decode base64 script: $($_.Exception.Message)"
                                        }
                                    }
                                } catch {
                                    Write-Warning "    Could not parse DetectionText JSON: $($_.Exception.Message)"
                                }
                            }
                        }
                    } catch {
                        Write-Warning "  Could not parse DetectionRule JSON: $($_.Exception.Message)"
                    }
                }

                Write-Host ""
            }
        }
    } catch {
        Write-Error "Error reading AppWorkload.log: $($_.Exception.Message)"
    }
}

###############################################################################
# SECTION 2: AgentExecutor.log
###############################################################################
Write-Host "`n=== AgentExecutor.log ===" -ForegroundColor Magenta

if (-not (Test-Path $AgentExecutorLog)) {
    Write-Warning "AgentExecutor.log not found at: $AgentExecutorLog"
} else {
    try {
        $agentAllLines = @(Get-Content $AgentExecutorLog | Where-Object { $_ -like "*$AppID*" })

        if ($agentAllLines.Count -eq 0) {
            Write-Warning "No entries found for App ID '$AppID' in AgentExecutor.log"
        } else {
            $agentEntries = Get-MostRecentAttemptEntries -Lines $agentAllLines
            $lastAgentDt  = Get-LogDateTime -Line ($agentEntries[$agentEntries.Count - 1])
            $windowInfo   = if ($lastAgentDt) { "ending $($lastAgentDt.ToString('yyyy-MM-dd HH:mm:ss'))" } else { "" }

            Write-Host "Most recent install attempt entries ($($agentEntries.Count) lines) $windowInfo :" -ForegroundColor Yellow

            $agentOutputLines = @()
            foreach ($line in $agentEntries) {
                $msg     = Get-LogMessage -Line $line
                $dt      = Get-LogDateTime -Line $line
                $prefix  = if ($dt) { "[$($dt.ToString('yyyy-MM-dd HH:mm:ss'))] " } else { "" }
                $display = "$prefix$msg"
                Write-Host $display -ForegroundColor White
                $agentOutputLines += $display
            }

            # Highlight detection / requirements related lines
            $detectionLines   = @($agentEntries | Where-Object { $_ -imatch 'detect' })
            $requirementLines = @($agentEntries | Where-Object { $_ -imatch 'requirement' })

            if ($detectionLines.Count -gt 0) {
                Write-Host "`n  Detection-related entries:" -ForegroundColor Red
                foreach ($line in $detectionLines) {
                    Write-Host "  $(Get-LogMessage -Line $line)" -ForegroundColor Yellow
                }
            }

            if ($requirementLines.Count -gt 0) {
                Write-Host "`n  Requirement-related entries:" -ForegroundColor Red
                foreach ($line in $requirementLines) {
                    Write-Host "  $(Get-LogMessage -Line $line)" -ForegroundColor Yellow
                }
            }

            $agentOutputPath = Join-Path $OutputDir "$($AppID)_$($dateTimeString)_AgentExecutor.txt"
            $agentOutputLines | Out-File -FilePath $agentOutputPath -Encoding UTF8
            Write-Host "`nAgentExecutor entries saved to: $agentOutputPath" -ForegroundColor Green
        }
    } catch {
        Write-Error "Error reading AgentExecutor.log: $($_.Exception.Message)"
    }
}

###############################################################################
# SECTION 3: IntuneManagementExtension.log
###############################################################################
Write-Host "`n=== IntuneManagementExtension.log ===" -ForegroundColor Magenta

if (-not (Test-Path $IMELog)) {
    Write-Warning "IntuneManagementExtension.log not found at: $IMELog"
} else {
    try {
        $imeAllLines = @(Get-Content $IMELog | Where-Object { $_ -like "*$AppID*" })

        if ($imeAllLines.Count -eq 0) {
            Write-Warning "No entries found for App ID '$AppID' in IntuneManagementExtension.log"
        } else {
            $imeEntries = Get-MostRecentAttemptEntries -Lines $imeAllLines
            $lastImeDt  = Get-LogDateTime -Line ($imeEntries[$imeEntries.Count - 1])
            $windowInfo = if ($lastImeDt) { "ending $($lastImeDt.ToString('yyyy-MM-dd HH:mm:ss'))" } else { "" }

            Write-Host "Most recent Intune policy entries ($($imeEntries.Count) lines) $windowInfo :" -ForegroundColor Yellow

            $imeOutputLines = @()
            foreach ($line in $imeEntries) {
                $msg     = Get-LogMessage -Line $line
                $dt      = Get-LogDateTime -Line $line
                $prefix  = if ($dt) { "[$($dt.ToString('yyyy-MM-dd HH:mm:ss'))] " } else { "" }
                $display = "$prefix$msg"
                Write-Host $display -ForegroundColor White
                $imeOutputLines += $display
            }

            $imeOutputPath = Join-Path $OutputDir "$($AppID)_$($dateTimeString)_IME.txt"
            $imeOutputLines | Out-File -FilePath $imeOutputPath -Encoding UTF8
            Write-Host "`nIME entries saved to: $imeOutputPath" -ForegroundColor Green
        }
    } catch {
        Write-Error "Error reading IntuneManagementExtension.log: $($_.Exception.Message)"
    }
}

Write-Host "`n=== Analysis Complete ===" -ForegroundColor Cyan

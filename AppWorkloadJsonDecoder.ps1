# AppWorkload Log JSON Decoder
# This script extracts and prettifies JSON from "Get policies =" entries in Appworkload.log
# Compatible with Windows PowerShell 5.1+ and PowerShell 7+

#Requires -Version 5.1

param(
    [string]$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Appworkload.log",
    [string]$OutputDir = ".",
    [string]$AppGUID = $null,
    [switch]$Help
)

if ($Help) {
    Write-Host @"
AppWorkload JSON Decoder - Help

DESCRIPTION:
    Extracts and prettifies JSON from Intune AppWorkload log files.
    Creates two output files: a JSON file with policy data and a PowerShell script with the detection rule.

PARAMETERS:
    -LogPath    : Path to the Appworkload.log file (default: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Appworkload.log)
    -OutputDir  : Directory for output files (default: current directory)
    -AppGUID    : Specific App GUID to search for (optional)
    -Help       : Show this help message

USAGE EXAMPLES:
    # Interactive mode - prompts for options
    .\AppWorkloadJsonDecoder.ps1

    # Search for a specific App GUID
    .\AppWorkloadJsonDecoder.ps1 -AppGUID "66de285e-94ce-49ef-9d29-8ab814df9db6"

    # Get most recent entry with custom output directory
    .\AppWorkloadJsonDecoder.ps1 -OutputDir "C:\Analysis"

    # Custom log path and specific App GUID
    .\AppWorkloadJsonDecoder.ps1 -LogPath "C:\Logs\AppWorkload.log" -AppGUID "your-guid-here"

OUTPUT FILES:
    - {AppGUID}_{DateTime}.json - Prettified JSON policy data
    - {AppGUID}_{DateTime}_DetectionRule.ps1 - Decoded detection script

"@ -ForegroundColor Green
    exit 0
}

Write-Host "Analyzing Appworkload.log for the most recent 'Get policies =' entry..." -ForegroundColor Green

# If no AppGUID provided, prompt user for input
if (-not $AppGUID) {
    Write-Host "`nAvailable options:" -ForegroundColor Yellow
    Write-Host "1. Search for a specific App GUID" -ForegroundColor Cyan
    Write-Host "2. Get the most recent entry (any app)" -ForegroundColor Cyan
    
    $choice = Read-Host "`nEnter your choice (1 or 2)"
    
    if ($choice -eq "1") {
        $AppGUID = Read-Host "`nEnter the App GUID to search for"
        if ([string]::IsNullOrWhiteSpace($AppGUID)) {
            Write-Error "No App GUID provided. Exiting."
            exit 1
        }
        Write-Host "Searching for App GUID: $AppGUID" -ForegroundColor Green
    } elseif ($choice -eq "2") {
        Write-Host "Searching for the most recent entry..." -ForegroundColor Green
    } else {
        Write-Error "Invalid choice. Please enter 1 or 2."
        exit 1
    }
}

try {
    # Find the most recent "Get policies =" entry, optionally filtered by AppGUID
    if ($AppGUID) {
        # Search for entries containing the specific AppGUID
        $logEntries = Get-Content $LogPath | Select-String "Get policies =" | Where-Object { $_.Line -like "*$AppGUID*" }
        if (-not $logEntries) {
            Write-Error "No 'Get policies =' entries found for App GUID: $AppGUID"
            exit 1
        }
        $logEntry = $logEntries | Select-Object -Last 1
        Write-Host "Found most recent entry for App GUID $AppGUID" -ForegroundColor Green
    } else {
        # Get the most recent entry regardless of AppGUID
        $logEntry = Get-Content $LogPath | Select-String "Get policies =" | Select-Object -Last 1
        if (-not $logEntry) {
            Write-Error "No 'Get policies =' entries found in the log file."
            exit 1
        }
        Write-Host "Found most recent entry (any app)" -ForegroundColor Green
    }
    
    Write-Host "Found most recent entry from: $($logEntry.Line)" -ForegroundColor Yellow
    
    # Extract the JSON part from the log entry
    $logLine = $logEntry.Line
    $jsonStart = $logLine.IndexOf("Get policies = ") + "Get policies = ".Length
    $jsonEnd = $logLine.LastIndexOf("]LOG]!")
    
    if ($jsonEnd -eq -1) {
        # If no ]LOG]! found, take everything from jsonStart to end
        $jsonString = $logLine.Substring($jsonStart)
    } else {
        $jsonString = $logLine.Substring($jsonStart, $jsonEnd - $jsonStart)
    }
    
    Write-Host "Extracted JSON string length: $($jsonString.Length) characters" -ForegroundColor Cyan
    
        # Parse and prettify the JSON
        try {
            $jsonObject = $jsonString | ConvertFrom-Json
            
            # Debug: Show JSON structure information
            Write-Host "`nDEBUG: JSON Structure Analysis:" -ForegroundColor Yellow
            Write-Host "JSON Type: $($jsonObject.GetType().Name)" -ForegroundColor Gray
            if ($jsonObject -is [Array]) {
                Write-Host "Array Length: $($jsonObject.Count)" -ForegroundColor Gray
                if ($jsonObject.Count -gt 0) {
                    Write-Host "First Object Type: $($jsonObject[0].GetType().Name)" -ForegroundColor Gray
                    $firstObjProperties = ($jsonObject[0] | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name) -join ', '
                    Write-Host "First Object Properties: $firstObjProperties" -ForegroundColor Gray
                }
            } else {
                Write-Host "Single Object Type: $($jsonObject.GetType().Name)" -ForegroundColor Gray
                $objProperties = ($jsonObject | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name) -join ', '
                Write-Host "Object Properties: $objProperties" -ForegroundColor Gray
            }
            Write-Host ""
            
            # If searching by AppGUID, verify we found the correct policy
            if ($AppGUID) {
                $foundPolicy = $jsonObject | Where-Object { $_.Id -eq $AppGUID }
                if (-not $foundPolicy) {
                    Write-Warning "The extracted JSON does not contain the specified App GUID: $AppGUID"
                    Write-Host "Available App GUIDs in this entry:" -ForegroundColor Yellow
                    foreach ($policy in $jsonObject) {
                        Write-Host "  - $($policy.Id) ($($policy.Name))" -ForegroundColor Gray
                    }
                }
            }        # Extract timestamp from log entry (format: date="10-14-2025" time="06:48:58.5778926")
        $dateMatch = [regex]::Match($logLine, 'date="([^"]+)"')
        $timeMatch = [regex]::Match($logLine, 'time="([^"]+)"')
        
        if ($dateMatch.Success -and $timeMatch.Success) {
            $dateStr = $dateMatch.Groups[1].Value
            $timeStr = $timeMatch.Groups[1].Value -replace '\.\d+$', ''  # Remove microseconds
            try {
                $logDateTime = [DateTime]::ParseExact("$dateStr $timeStr", "MM-dd-yyyy HH:mm:ss", $null)
                $dateTimeString = $logDateTime.ToString("yyyy-MM-dd_HH-mm-ss")
            } catch {
                Write-Warning "Could not parse datetime from log, using current time"
                $dateTimeString = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
            }
        } else {
            Write-Warning "Could not extract datetime from log, using current time"
            $dateTimeString = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
        }
        
        # Create output file names using ID and datetime
        # Handle both single policy and array of policies
        if ($jsonObject -is [Array] -and $jsonObject.Count -gt 0) {
            $policyId = $jsonObject[0].Id  # Get the first policy's ID from array
            $targetPolicy = $jsonObject[0]
            Write-Host "DEBUG: Using ID from array[0]: $policyId" -ForegroundColor Gray
        } elseif ($jsonObject.Id) {
            $policyId = $jsonObject.Id     # Single policy object
            $targetPolicy = $jsonObject
            Write-Host "DEBUG: Using ID from single object: $policyId" -ForegroundColor Gray
        } else {
            Write-Host "ERROR: Could not extract Policy ID from JSON data" -ForegroundColor Red
            Write-Host "JSON Object Details:" -ForegroundColor Red
            Write-Host "Type: $($jsonObject.GetType().Name)" -ForegroundColor Red
            if ($jsonObject -is [Array]) {
                Write-Host "Array Count: $($jsonObject.Count)" -ForegroundColor Red
            }
            $availableProperties = ($jsonObject | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name) -join ', '
            Write-Host "Available Properties: $availableProperties" -ForegroundColor Red
            Write-Host "Raw JSON Sample (first 500 chars): $($jsonString.Substring(0, [Math]::Min(500, $jsonString.Length)))" -ForegroundColor Red
            exit 1
        }
        
        $jsonOutputPath = Join-Path $OutputDir "$($policyId)_$($dateTimeString).json"
        $scriptOutputPath = Join-Path $OutputDir "$($policyId)_$($dateTimeString)_DetectionRule.ps1"
        
        # Enhance the JSON by parsing nested JSON strings
        try {
            $enhancedObject = $jsonObject.PSObject.Copy()
            
            # Parse RequirementRules if it's a JSON string
            if ($enhancedObject.RequirementRules -and $enhancedObject.RequirementRules -is [string]) {
                try {
                    $enhancedObject.RequirementRules = $enhancedObject.RequirementRules | ConvertFrom-Json
                } catch {
                    Write-Warning "Could not parse RequirementRules as JSON"
                }
            }
            
            # Parse InstallEx if it's a JSON string
            if ($enhancedObject.InstallEx -and $enhancedObject.InstallEx -is [string]) {
                try {
                    $enhancedObject.InstallEx = $enhancedObject.InstallEx | ConvertFrom-Json
                } catch {
                    Write-Warning "Could not parse InstallEx as JSON"
                }
            }
            
            # Parse ReturnCodes if it's a JSON string
            if ($enhancedObject.ReturnCodes -and $enhancedObject.ReturnCodes -is [string]) {
                try {
                    $enhancedObject.ReturnCodes = $enhancedObject.ReturnCodes | ConvertFrom-Json
                } catch {
                    Write-Warning "Could not parse ReturnCodes as JSON"
                }
            }
            
            # Parse DetectionRule if it's a JSON string
            if ($enhancedObject.DetectionRule -and $enhancedObject.DetectionRule -is [string]) {
                try {
                    $enhancedObject.DetectionRule = $enhancedObject.DetectionRule | ConvertFrom-Json
                } catch {
                    Write-Warning "Could not parse DetectionRule as JSON"
                }
            }
            
            # Create enhanced pretty JSON
            $prettyJson = $enhancedObject | ConvertTo-Json -Depth 10
            
            # Display the enhanced JSON
            Write-Host "`nPrettified JSON (with parsed nested objects):" -ForegroundColor Green
            Write-Host $prettyJson
            
            # Save the enhanced JSON
            $prettyJson | Out-File -FilePath $jsonOutputPath -Encoding UTF8
            Write-Host "`nJSON saved to: $jsonOutputPath" -ForegroundColor Green
            
        } catch {
            Write-Warning "Could not create enhanced JSON version: $($_.Exception.Message)"
            # Fallback to basic pretty JSON
            $prettyJson = $jsonObject | ConvertTo-Json -Depth 10
            Write-Host "`nPrettified JSON:" -ForegroundColor Green
            Write-Host $prettyJson
            
            # Save JSON to file
            $prettyJson | Out-File -FilePath $jsonOutputPath -Encoding UTF8
            Write-Host "`nJSON saved to: $jsonOutputPath" -ForegroundColor Green
        }
        
        # Display some key information about the policies
        Write-Host "`nPolicy Summary:" -ForegroundColor Magenta
        
        # Handle both single policy and array of policies for display
        $policiesToProcess = if ($jsonObject -is [Array]) { $jsonObject } else { @($jsonObject) }
        
        foreach ($policy in $policiesToProcess) {
            Write-Host "  - Name: $($policy.Name)" -ForegroundColor White
            Write-Host "    ID: $($policy.Id)" -ForegroundColor Gray
            Write-Host "    Version: $($policy.Version)" -ForegroundColor Gray
            Write-Host "    Intent: $($policy.Intent)" -ForegroundColor Gray
            Write-Host ""
            
            # Decode nested JSON strings
            Write-Host "  Detailed Information:" -ForegroundColor Yellow
            
            # Decode DetectionRule if present
            if ($policy.DetectionRule) {
                try {
                    $detectionRule = $policy.DetectionRule | ConvertFrom-Json
                    Write-Host "    Detection Rule:" -ForegroundColor Cyan
                    foreach ($rule in $detectionRule) {
                        Write-Host "      - Detection Type: $($rule.DetectionType)" -ForegroundColor Gray
                        if ($rule.DetectionText) {
                            $detectionText = $rule.DetectionText | ConvertFrom-Json
                            Write-Host "      - Script Body (decoded):" -ForegroundColor Cyan
                            if ($detectionText.ScriptBody) {
                                try {
                                    $decodedScript = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($detectionText.ScriptBody))
                                    
                                    # Remove BOM (Byte Order Mark) character U+FEFF if present
                                    $decodedScript = $decodedScript.TrimStart([char]0xFEFF)
                                    
                                    Write-Host $decodedScript -ForegroundColor White
                                    
                                    # Save the decoded script to a .ps1 file
                                    $scriptHeader = @"
# Detection Rule Script for $($policy.Name)
# Policy ID: $($policy.Id)
# Extracted on: $(Get-Date)
# Detection Type: $($rule.DetectionType)

"@
                                    $fullScript = $scriptHeader + $decodedScript
                                    $fullScript | Out-File -FilePath $scriptOutputPath -Encoding UTF8
                                    Write-Host "      - Detection script saved to: $scriptOutputPath" -ForegroundColor Green
                                    
                                } catch {
                                    Write-Host "        (Could not decode base64 script)" -ForegroundColor Red
                                }
                            }
                        }
                    }
                } catch {
                    Write-Host "    (Could not parse DetectionRule JSON)" -ForegroundColor Red
                }
            }
            
            # Decode RequirementRules if present
            if ($policy.RequirementRules) {
                try {
                    $requirementRules = $policy.RequirementRules | ConvertFrom-Json
                    Write-Host "    Requirement Rules:" -ForegroundColor Cyan
                    Write-Host "      - OS Architecture: $($requirementRules.RequiredOSArchitecture)" -ForegroundColor Gray
                    Write-Host "      - Min Windows Build: $($requirementRules.MinimumWindows10BuildNumer)" -ForegroundColor Gray
                    Write-Host "      - Run as 32-bit: $($requirementRules.RunAs32Bit)" -ForegroundColor Gray
                } catch {
                    Write-Host "    (Could not parse RequirementRules JSON)" -ForegroundColor Red
                }
            }
            
            # Decode InstallEx if present
            if ($policy.InstallEx) {
                try {
                    $installEx = $policy.InstallEx | ConvertFrom-Json
                    Write-Host "    Install Settings:" -ForegroundColor Cyan
                    Write-Host "      - Run As: $($installEx.RunAs)" -ForegroundColor Gray
                    Write-Host "      - Requires Logon: $($installEx.RequiresLogon)" -ForegroundColor Gray
                    Write-Host "      - Max Runtime (min): $($installEx.MaxRunTimeInMinutes)" -ForegroundColor Gray
                    Write-Host "      - Max Retries: $($installEx.MaxRetries)" -ForegroundColor Gray
                } catch {
                    Write-Host "    (Could not parse InstallEx JSON)" -ForegroundColor Red
                }
            }
            
            Write-Host ""
        }
        
    } catch {
        Write-Error "Failed to parse JSON: $($_.Exception.Message)"
        Write-Host "Raw extracted string:" -ForegroundColor Red
        Write-Host $jsonString
    }
    
} catch {
    Write-Error "Error processing log file: $($_.Exception.Message)"
}

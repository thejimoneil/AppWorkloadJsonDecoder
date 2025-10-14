# AppWorkload JSON Decoder

A PowerShell script that extracts and prettifies JSON policy data from Microsoft Intune Management Extension (IME) AppWorkload log files. This tool helps administrators analyze Intune application deployment policies and extract detection rules for troubleshooting and documentation purposes.

## Features

- 🔍 **Smart Search**: Find the most recent log entry for any app or search by specific App GUID
- 📄 **Enhanced JSON Extraction**: Automatically extracts and prettifies JSON policy data with parsed nested objects
- 🛠️ **Detection Rule Decoding**: Decodes base64-encoded PowerShell detection scripts with BOM removal
- 🎯 **Intelligent JSON Parsing**: Converts nested JSON strings (RequirementRules, InstallEx, ReturnCodes, DetectionRule) into proper objects
- 📁 **Organized Output**: Creates timestamped files with meaningful names
- 🧹 **Clean Scripts**: Removes BOM characters that can cause script execution errors
- 💬 **Interactive Mode**: User-friendly prompts for easy operation
- � **Enhanced Debugging**: Comprehensive error handling and diagnostic information
- �📖 **Comprehensive Help**: Built-in documentation and usage examples
- ⚡ **Cross-Compatible**: Works with both Windows PowerShell 5.1 and PowerShell 7+

## Requirements

- **Windows PowerShell 5.1** or **PowerShell 7+** (compatible with both)
- Access to Intune Management Extension logs (typically requires administrative privileges)
- Microsoft Intune environment with deployed applications

> **Note**: The script has been tested and is compatible with both Windows PowerShell 5.1 (default on Windows 10/11) and PowerShell 7+. It uses only built-in cmdlets and avoids PowerShell 7-specific features for maximum compatibility.

## Installation

1. Download the `AppWorkloadJsonDecoder.ps1` script
2. Place it in your preferred directory
3. Ensure PowerShell execution policy allows script execution:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

## Usage

### Interactive Mode
Run the script without parameters for guided operation:
```powershell
.\AppWorkloadJsonDecoder.ps1
```

The script will prompt you to choose:
- **Option 1**: Search for a specific App GUID
- **Option 2**: Get the most recent entry (any application)

### Command Line Mode

#### Search for a specific App GUID:
```powershell
.\AppWorkloadJsonDecoder.ps1 -AppGUID "66de285e-94ce-49ef-9d29-8ab814df9db6"
```

#### Custom output directory:
```powershell
.\AppWorkloadJsonDecoder.ps1 -OutputDir "C:\Analysis"
```

#### Custom log file path:
```powershell
.\AppWorkloadJsonDecoder.ps1 -LogPath "C:\CustomPath\Appworkload.log"
```

#### Show help:
```powershell
.\AppWorkloadJsonDecoder.ps1 -Help
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-LogPath` | String | `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Appworkload.log` | Path to the AppWorkload log file |
| `-OutputDir` | String | `.` (current directory) | Directory where output files will be saved |
| `-AppGUID` | String | `$null` | Specific App GUID to search for (optional) |
| `-Help` | Switch | `$false` | Display help information |

## Output Files

The script generates two files with timestamps for easy organization:

### 1. Enhanced JSON Policy File
**Format**: `{AppGUID}_{DateTime}.json`

**Example**: `66de285e-94ce-49ef-9d29-8ab814df9db6_2025-10-14_06-48-58.json`

Contains enhanced JSON with complete policy configuration including:
- Application metadata (ID, Name, Version)
- Installation/uninstallation commands
- **RequirementRules** - Parsed as structured objects (OS requirements, system specs)
- **InstallEx** - Installation settings as readable objects (timeouts, retries, visibility)
- **ReturnCodes** - Array of return code objects with types
- **DetectionRule** - Parsed detection rule structure
- All other policy settings in clean, readable format

### 2. Detection Rule Script
**Format**: `{AppGUID}_{DateTime}_DetectionRule.ps1`

**Example**: `66de285e-94ce-49ef-9d29-8ab814df9db6_2025-10-14_06-48-58_DetectionRule.ps1`

Contains:
- Decoded PowerShell detection script (ready to execute)
- Header with metadata (App name, Policy ID, extraction date, detection type)
- Clean script without BOM characters or encoding issues

## Examples

### Example 1: Analyze VLC Media Player Policy
```powershell
.\AppWorkloadJsonDecoder.ps1 -AppGUID "66de285e-94ce-49ef-9d29-8ab814df9db6"
```

**Output**:
- `66de285e-94ce-49ef-9d29-8ab814df9db6_2025-10-14_06-48-58.json` (Enhanced with parsed objects)
- `66de285e-94ce-49ef-9d29-8ab814df9db6_2025-10-14_06-48-58_DetectionRule.ps1`

### Example 2: Batch Analysis
```powershell
# Create analysis directory
New-Item -ItemType Directory -Path "C:\IntuneAnalysis" -Force

# Analyze most recent policy
.\AppWorkloadJsonDecoder.ps1 -OutputDir "C:\IntuneAnalysis"
```

## Sample Output

### Console Output
```
Analyzing Appworkload.log for the most recent 'Get policies =' entry...
Found most recent entry for App GUID 66de285e-94ce-49ef-9d29-8ab814df9db6
Extracted JSON string length: 2152 characters

DEBUG: JSON Structure Analysis:
JSON Type: PSCustomObject
Object Properties: [list of all available properties]

Prettified JSON (with parsed nested objects):
{
  "RequirementRules": {
    "RequiredOSArchitecture": 2,
    "MinimumWindows10BuildNumer": "10.0.18363",
    "RunAs32Bit": false
  },
  "InstallEx": {
    "RunAs": 1,
    "RequiresLogon": true,
    "MaxRetries": 3,
    "MaxRunTimeInMinutes": 60
  },
  "ReturnCodes": [
    {
      "ReturnCode": 0,
      "Type": 1
    }
  ]
}

Policy Summary:
  - Name: VLC
    ID: 66de285e-94ce-49ef-9d29-8ab814df9db6
    Version: 1
    Intent: 1

  Detailed Information:
    Detection Rule:
      - Detection Type: 3
      - Script Body (decoded):
$versionCheck = "3.0.16"
$install = Get-Item -Path "C:\Program Files\VideoLAN\VLC\vlc.exe" -ErrorAction SilentlyContinue

if($install){
    if($install[0].VersionInfo.FileVersion -ge $versionCheck){
        Write-Host "Installed"
        Exit 0
    }
}
```

## Troubleshooting

### Common Issues

#### 1. Access Denied
**Problem**: Cannot access the log file
**Solution**: Run PowerShell as Administrator

#### 2. No Entries Found
**Problem**: Script reports no "Get policies =" entries
**Solutions**: 
- Verify the log file path is correct
- Check if Intune policies have been processed recently
- Ensure the App GUID is correct

#### 3. Script Execution Policy
**Problem**: Cannot run the script due to execution policy
**Solution**: 
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

#### 4. Invalid App GUID
**Problem**: No entries found for the specified App GUID
**Solution**: 
- Run in interactive mode to see available options
- Check Intune portal for correct App GUID
- Use option 2 to see the most recent entry

#### 5. PowerShell Version Compatibility
**Problem**: Script fails on older PowerShell versions
**Solution**: 
- The script requires PowerShell 5.1 minimum
- Check version with `$PSVersionTable.PSVersion`
- Upgrade PowerShell if needed

#### 6. Enhanced JSON Parsing Warnings
**Problem**: Warnings about parsing nested JSON objects
**Solution**: 
- These are informational warnings
- Script will still work and create output files
- Original data is preserved even if parsing fails

## Log File Location

Default Intune Management Extension log locations:
- **AppWorkload.log**: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Appworkload.log`
- **Alternative locations**: Check `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\` for other log files

## Understanding Detection Rules

Detection rules determine how Intune verifies if an application is installed. Common types:

- **Type 1**: File or folder detection
- **Type 2**: MSI product code detection  
- **Type 3**: PowerShell script detection (most flexible)

The script automatically decodes Type 3 (PowerShell) detection rules for easy analysis and testing.

## Version History

- **v1.0**: Initial release with basic JSON extraction
- **v1.1**: Added App GUID search functionality
- **v1.2**: Added BOM character removal for clean scripts
- **v1.3**: Enhanced help system and interactive mode
- **v1.4**: Added PowerShell 5.1 compatibility (removed PowerShell 7+ dependencies)
- **v1.5**: Enhanced JSON parsing for nested objects (RequirementRules, InstallEx, ReturnCodes)
- **v1.6**: Streamlined output to single enhanced JSON file
- **v1.7**: Added comprehensive debugging and error handling

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve this tool.

## License

This script is provided as-is for educational and administrative purposes. Use at your own discretion in your environment.

## Related Tools

- **Microsoft Intune**: Application deployment and management
- **PowerShell ISE/VS Code**: For editing and testing detection scripts
- **Intune Management Extension**: The service that processes these policies

---

**Note**: This tool is for analyzing existing Intune policies and is not affiliated with Microsoft. Always test detection scripts in a safe environment before deploying to production.

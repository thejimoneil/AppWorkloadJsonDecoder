# AppWorkload JSON Decoder

A PowerShell script that extracts and prettifies JSON policy data from Microsoft Intune Management Extension (IME) AppWorkload log files. This tool helps administrators analyze Intune application deployment policies and extract detection rules for troubleshooting and documentation purposes.

## Features

- 🔍 **Smart Search**: Find the most recent log entry for any app or search by specific App GUID
- 📄 **JSON Extraction**: Automatically extracts and prettifies JSON policy data
- 🛠️ **Detection Rule Decoding**: Decodes base64-encoded PowerShell detection scripts
- 📁 **Organized Output**: Creates timestamped files with meaningful names
- 🧹 **Clean Scripts**: Removes BOM characters that can cause script execution errors
- 💬 **Interactive Mode**: User-friendly prompts for easy operation
- 📖 **Comprehensive Help**: Built-in documentation and usage examples

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Access to Intune Management Extension logs (typically requires administrative privileges)
- Microsoft Intune environment with deployed applications

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
.\AppWorkloadJsonDecoder.ps1 -AppGUID "7211687c-d63c-4470-b1bf-4f1714fc4d9f"
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

### 1. JSON Policy File
**Format**: `{AppGUID}_{DateTime}.json`

**Example**: `7211687c-d63c-4470-b1bf-4f1714fc4d9f_2025-10-14_06-48-58.json`

Contains prettified JSON with complete policy configuration including:
- Application metadata (ID, Name, Version)
- Installation/uninstallation commands
- System requirements
- Return codes
- Detection rules (encoded)
- Installation settings

### 2. Detection Rule Script
**Format**: `{AppGUID}_{DateTime}_DetectionRule.ps1`

**Example**: `7211687c-d63c-4470-b1bf-4f1714fc4d9f_2025-10-14_06-48-58_DetectionRule.ps1`

Contains:
- Decoded PowerShell detection script
- Header with metadata (App name, Policy ID, extraction date)
- Clean script without BOM characters (ready to execute)

## Examples

### Example 1: Analyze VLC Media Player Policy
```powershell
.\AppWorkloadJsonDecoder.ps1 -AppGUID "7211687c-d63c-4470-b1bf-4f1714fc4d9f"
```

**Output**:
- `7211687c-d63c-4470-b1bf-4f1714fc4d9f_2025-10-14_06-48-58.json`
- `7211687c-d63c-4470-b1bf-4f1714fc4d9f_2025-10-14_06-48-58_DetectionRule.ps1`

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
Found most recent entry for App GUID 7211687c-d63c-4470-b1bf-4f1714fc4d9f
Extracted JSON string length: 2152 characters

Policy Summary:
  - Name: VLC
    ID: 7211687c-d63c-4470-b1bf-4f1714fc4d9f
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

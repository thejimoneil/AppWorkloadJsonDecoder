# Intune App Install Analyzer

A PowerShell script that analyzes three Microsoft Intune Management Extension (IME) log files for a specific App ID to surface the most recent install attempt details.

## Overview

| Log File | What it provides |
|----------|-----------------|
| `AppWorkload.log` | Install info — JSON decoded, detection script decoded from base64 |
| `AgentExecutor.log` | Detection and requirements failure details |
| `IntuneManagementExtension.log` | Overall policy info and high-level Intune action view |

## Requirements

- **Windows PowerShell 5.1** or **PowerShell 7+**
- Access to Intune Management Extension logs (typically requires administrative privileges)

## Installation

1. Download `AppWorkloadJsonDecoder.ps1`
2. Ensure PowerShell execution policy allows script execution:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

## Usage

### Provide App ID directly (recommended)
```powershell
.\AppWorkloadJsonDecoder.ps1 -AppID "66de285e-94ce-49ef-9d29-8ab814df9db6"
```

### Interactive (prompted) mode
```powershell
.\AppWorkloadJsonDecoder.ps1
```
The script will prompt for the App ID.

### Custom log directory and output directory
```powershell
.\AppWorkloadJsonDecoder.ps1 -AppID "66de285e-94ce-49ef-9d29-8ab814df9db6" -LogDir "C:\Logs" -OutputDir "C:\Analysis"
```

### Show built-in help
```powershell
.\AppWorkloadJsonDecoder.ps1 -Help
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-AppID` | String | *(prompted)* | App GUID to search for |
| `-LogDir` | String | `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs` | Directory containing IME log files |
| `-OutputDir` | String | `.` (current directory) | Directory where output files are saved |
| `-Help` | Switch | `$false` | Display help information |

## Output Files

All output files are prefixed with `{AppID}_{DateTime}`:

| File | Contents |
|------|----------|
| `{AppID}_{DateTime}_AppWorkload.json` | Prettified JSON policy data from AppWorkload.log |
| `{AppID}_{DateTime}_DetectionRule.ps1` | Decoded PowerShell detection script (ready to execute) |
| `{AppID}_{DateTime}_AgentExecutor.txt` | Timestamped AgentExecutor.log entries for the app |
| `{AppID}_{DateTime}_IME.txt` | Timestamped IntuneManagementExtension.log entries for the app |

## How "Most Recent Install Attempt" is Determined

- **AppWorkload.log** — The most recent `Get policies =` line containing the App ID is used. Its timestamp sets the reference datetime for all output file names.
- **AgentExecutor.log / IntuneManagementExtension.log** — All lines containing the App ID that fall within a **2-hour window ending at the most recent matching entry** are shown. This window reliably captures a single install attempt while filtering out older history.

## Sample Console Output

```
=== Intune App Install Analyzer ===
App ID      : 66de285e-94ce-49ef-9d29-8ab814df9db6
Log Dir     : C:\ProgramData\Microsoft\IntuneManagementExtension\Logs
Output Dir  : .

=== AppWorkload.log ===
Most recent policy fetch : 2025-10-14 06:48:58
Extracted JSON length    : 2152 characters
JSON saved to            : 66de285e-94ce-49ef-9d29-8ab814df9db6_2025-10-14_06-48-58_AppWorkload.json

Policy Summary:
  Name          : VLC
  ID            : 66de285e-94ce-49ef-9d29-8ab814df9db6
  Version       : 1
  Intent        : 1

  Requirement Rules:
    OS Architecture   : 2
    Min Windows Build : 10.0.18363
    Run as 32-bit     : False

  Install Settings:
    Run As            : 1
    Requires Logon    : False
    Max Runtime (min) : 60
    Max Retries       : 3

  Detection Rule:
    Detection Type : 3

    Decoded Detection Script:
$versionCheck = "3.0.16"
$install = Get-Item -Path "C:\Program Files\VideoLAN\VLC\vlc.exe" -ErrorAction SilentlyContinue
if($install){
    if($install[0].VersionInfo.FileVersion -ge $versionCheck){
        Write-Host "Installed"
        Exit 0
    }
}
    Detection script saved to: 66de285e-94ce-49ef-9d29-8ab814df9db6_2025-10-14_06-48-58_DetectionRule.ps1

=== AgentExecutor.log ===
Most recent install attempt entries (5 lines) ending 2025-10-14 06:49:05 :
[2025-10-14 06:48:59] Policy id = 66de285e... execution started
[2025-10-14 06:49:00] Detection check for app 66de285e...
[2025-10-14 06:49:01] Detection result: NotInstalled for 66de285e...
[2025-10-14 06:49:02] Requirement check for 66de285e...: passed
[2025-10-14 06:49:05] Install triggered for 66de285e...

  Detection-related entries:
  Detection check for app 66de285e...
  Detection result: NotInstalled for 66de285e...

  Requirement-related entries:
  Requirement check for 66de285e...: passed

AgentExecutor entries saved to: 66de285e-94ce-49ef-9d29-8ab814df9db6_2025-10-14_06-48-58_AgentExecutor.txt

=== IntuneManagementExtension.log ===
Most recent Intune policy entries (3 lines) ending 2025-10-14 06:49:10 :
[2025-10-14 06:48:55] Processing policy for app 66de285e...
[2025-10-14 06:48:56] App 66de285e... assigned, intent=Install
[2025-10-14 06:49:10] Sending install report for 66de285e...

IME entries saved to: 66de285e-94ce-49ef-9d29-8ab814df9db6_2025-10-14_06-48-58_IME.txt

=== Analysis Complete ===
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Access Denied | Run PowerShell as Administrator |
| No entries found | Verify the App ID is correct; check log file paths with `-LogDir` |
| Execution policy error | `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| Could not decode base64 | The detection rule may use a different detection type (non-script) |

## Log File Locations

Default IME log directory: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`

- `AppWorkload.log`
- `AgentExecutor.log`
- `IntuneManagementExtension.log`

## Detection Rule Types

| Type | Description |
|------|-------------|
| 1 | File or folder detection |
| 2 | MSI product code detection |
| 3 | PowerShell script detection (decoded and saved by this tool) |

---

**Note**: This tool is for analyzing existing Intune policies and is not affiliated with Microsoft. Always test detection scripts in a safe environment before deploying to production.

# Reboot Enforcement - PSADT Package

Modern reboot enforcement solution using PSAppDeployToolkit with BurntToast notifications.

## Features

- ✅ **Runs as SYSTEM** - Has privileges to reboot computers
- ✅ **Modern Toast Notifications** - Interactive notifications users can see
- ✅ **User Scheduling** - Users can schedule convenient reboot times
- ✅ **Progressive Warnings** - Hourly reminders, then 15-minute intervals before deadline
- ✅ **10PM Deadline** - Enforces reboots during 10PM-5AM window
- ✅ **AD Group Exemption** - Exclude computers via Active Directory group
- ✅ **JSON State Management** - No registry permissions needed
- ✅ **SCCM/Intune Ready** - Deploy via Configuration Manager or Intune

## Package Structure

```
RebootEnforcement-PSADT/
├── Deploy-Application.ps1          # Main PSADT script (runs as SYSTEM)
├── SupportFiles/
│   └── Show-RebootToast.ps1        # Toast notification helper (runs as USER)
├── Files/                          # (Empty - no files to deploy)
└── AppDeployToolkit/               # PSADT framework (download separately)
```

## Prerequisites

1. **PSAppDeployToolkit v3.x**
   - Download from: https://psappdeploytoolkit.com
   - Extract the `AppDeployToolkit` folder into this package directory

2. **BurntToast PowerShell Module**
   - Auto-installed by the script if missing
   - Or pre-install: `Install-Module BurntToast -Force`

## Configuration

Edit `Deploy-Application.ps1` to customize settings:

```powershell
# Line ~100 - Configuration Variables
[String]$exemptionADGroup = "RebootExemption"       # AD group for exemptions
[Int32]$uptimeThresholdDays = 7                     # Days before enforcement
[Int32]$rebootHour = 22                             # 10 PM (24-hour format)
[Int32]$rebootWindowEnd = 5                         # 5 AM (24-hour format)
```

## Deployment

### SCCM/ConfigMgr Deployment

1. **Create Application**
   - Copy entire package to your content source location
   - Create new Application in SCCM console
   
2. **Deployment Type Settings**
   - **Installation Program:**
     ```
     Deploy-Application.exe
     ```
   - **Uninstall Program:** (leave blank)
   - **Run as:** System
   - **Installation behavior:** Install for system
   - **Logon requirement:** Whether or not a user is logged on
   - **Maximum runtime:** 15 minutes
   - **Return codes:** 
     - `0` = Success
     - `1641` = Success (reboot initiated)
     - `3010` = Soft reboot

3. **Detection Method**
   - Use **Custom Script** detection
   - Script type: PowerShell
   - Script content:
     ```powershell
     # Always returns false to keep checking
     # This is a monitoring/enforcement script, not an application
     return $false
     ```

4. **Deployment Settings**
   - **Purpose:** Required
   - **Schedule:** 
     - Run every **15 minutes** during business hours
     - Run every **5 minutes** between 9PM-11PM (close to deadline)
   - **Rerun behavior:** Always rerun program
   - **User notifications:** Hide all notifications
   - **Software Installation:** Allowed
   - **Deadline:** Not applicable (ongoing enforcement)

### Intune Deployment

1. **Create Win32 App**
   - Package as `.intunewin` using Microsoft Win32 Content Prep Tool
   - Upload to Intune

2. **App Settings**
   - **Install command:**
     ```
     Deploy-Application.exe
     ```
   - **Uninstall command:** (not applicable)
   - **Install behavior:** System
   - **Return codes:** Same as SCCM above

3. **Requirements**
   - OS: Windows 10/11
   - Architecture: x64

4. **Detection Rules**
   - Use **Custom Detection Script** (PowerShell)
   - Always return false to keep checking

5. **Assignment**
   - Assign as **Required** to target groups
   - No deadline (ongoing enforcement)

## How It Works

### Notification Flow

1. **Initial Warning** (First time uptime exceeds 7 days)
   - Shows toast with "Schedule Reboot" and "Remind Me Later" buttons
   - User can click "Schedule" to pick a convenient time

2. **Hourly Reminders** (More than 90 minutes before deadline)
   - Toast appears every hour
   - User can still schedule a reboot

3. **Final Warnings** (Last 90 minutes)
   - Toast appears every 15 minutes
   - More urgent messaging
   - "Restart Now" button available

4. **Deadline Enforcement** (10PM)
   - If in reboot window (10PM-5AM), forces reboot with 60-second countdown
   - Uses PSADT's `Show-InstallationRestartPrompt` for professional countdown dialog

5. **Scheduled Reboot Flow** (If user schedules)
   - 10-minute warning
   - 5-minute warning
   - 1-minute warning
   - Forced reboot at scheduled time

### User Scheduling

When a user clicks "Schedule Reboot":
1. A time picker dialog appears (Windows Forms)
2. User selects a time before the 10PM deadline
3. Choice is saved to `C:\ProgramData\RebootEnforcement\state.json`
4. Script monitors the scheduled time
5. Countdown warnings appear at 10, 5, and 1 minute
6. Reboot occurs at the scheduled time

### State Management

State is stored in JSON format at:
```
C:\ProgramData\RebootEnforcement\state.json
```

Example state file:
```json
{
  "LastNotificationTime": "2025-12-03T14:30:00Z",
  "ScheduledRebootTime": "2025-12-03T19:00:00Z",
  "NotificationCount": 3
}
```

### AD Exemption

To exempt computers:
1. Create AD group (default name: `RebootExemption`)
2. Add computer objects to the group
3. Script checks membership on each run
4. Exempt computers exit gracefully with no action

## Testing

### Test in WhatIf Mode

1. Open PowerShell as Administrator
2. Navigate to package directory
3. Run:
   ```powershell
   .\Deploy-Application.ps1 -DeployMode Interactive
   ```

### Simulate High Uptime

Temporarily modify line in `Deploy-Application.ps1`:

```powershell
# Around line 240 - replace this:
$uptimeDays = Get-SystemUptimeDays

# With this for testing:
$uptimeDays = 8  # Simulates 8 days uptime
```

### Test Toast Notifications

Run the helper script directly:

```powershell
cd SupportFiles

.\Show-RebootToast.ps1 `
    -NotificationType "InitialWarning" `
    -UptimeDays 8 `
    -Deadline (Get-Date).AddHours(3) `
    -MinutesRemaining 180 `
    -StateFilePath "$env:ProgramData\RebootEnforcement\state.json"
```

## Troubleshooting

### Toast Notifications Don't Appear

**Problem:** Users don't see toast notifications

**Solutions:**
1. Verify BurntToast is installed in user profile:
   ```powershell
   Get-Module -ListAvailable BurntToast
   ```

2. Check Windows notification settings:
   - Settings > System > Notifications
   - Ensure Focus Assist is off
   - Verify notifications are enabled

3. Check PSADT logs:
   ```
   C:\Windows\Logs\Software\RebootEnforcement_*.log
   ```

### Reboot Not Occurring

**Problem:** Deadline passes but computer doesn't reboot

**Solutions:**
1. Verify computer is in reboot window (10PM-5AM)
2. Check if user scheduled a reboot (view state.json)
3. Verify script is running as SYSTEM
4. Check Windows Event Logs for restart failures

### State File Issues

**Problem:** Scheduled reboots not working

**Solutions:**
1. Check state file exists and is readable:
   ```powershell
   Get-Content "$env:ProgramData\RebootEnforcement\state.json"
   ```

2. Verify JSON is valid (not corrupted)
3. Delete state file to reset:
   ```powershell
   Remove-Item "$env:ProgramData\RebootEnforcement\state.json" -Force
   ```

### AD Exemption Not Working

**Problem:** Exempt computers still get notifications

**Solutions:**
1. Verify ActiveDirectory module is available on target computers
2. Check computer is member of exemption group:
   ```powershell
   Get-ADComputer $env:COMPUTERNAME -Properties MemberOf | Select -ExpandProperty MemberOf
   ```
3. Verify group name matches configuration

## Logs

**PSADT Main Logs:**
```
C:\Windows\Logs\Software\RebootEnforcement_*.log
```

**Toast Notification Logs:**
- Notifications run in user context (no persistent logs)
- Use `-Verbose` flag for debugging

**View Recent Logs:**
```powershell
Get-Content "C:\Windows\Logs\Software\RebootEnforcement_*.log" -Tail 50
```

## Customization

### Change Notification Text

Edit `SupportFiles\Show-RebootToast.ps1`:
- Modify `$title` and `$message` variables in each switch case (lines ~180-240)

### Adjust Timing

Edit `Deploy-Application.ps1`:
- Line ~375: Change final warning interval from 15 to different value:
  ```powershell
  if (-not $state.LastNotificationTime -or ((Get-Date) - $state.LastNotificationTime).TotalMinutes -ge 15) {
  ```
- Line ~387: Change hourly reminder interval

### Add Email Notifications

Add SMTP notification in `Deploy-Application.ps1` after showing toast:

```powershell
Send-MailMessage -To "helpdesk@company.com" `
    -From "reboot-enforcement@company.com" `
    -Subject "Reboot Warning Sent: $env:COMPUTERNAME" `
    -Body "User: $env:USERNAME, Deadline: $deadline" `
    -SmtpServer "smtp.company.com"
```

## Best Practices

1. **Schedule Frequency**
   - Run every 15 minutes normally
   - Increase to every 5 minutes near deadline (9PM-11PM)

2. **User Communication**
   - Send IT announcement before enabling
   - Explain purpose and scheduling options
   - Provide helpdesk contact

3. **Exemptions**
   - Keep exemption list minimal
   - Review exemptions quarterly
   - Document reasons for exemptions

4. **Monitoring**
   - Set up SCCM report for high-uptime computers
   - Monitor failed reboot attempts
   - Track exemption group membership

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success - No action needed or check completed |
| 1641 | Success - Reboot has been initiated |
| 3010 | Success - Reboot required |
| 60001 | Error - General script error |
| 60008 | Error - PSADT framework not found |

## Support

For issues or questions:
- Check logs first: `C:\Windows\Logs\Software\`
- Review troubleshooting section above
- Contact IT Operations team

## Version History

**v1.0 (December 2025)**
- Initial release
- BurntToast integration
- JSON state management
- PSADT v3.x compatibility
- User scheduling feature
- Progressive notifications

## License

Internal use only - IT Operations

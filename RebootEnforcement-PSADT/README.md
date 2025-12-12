# Reboot Enforcement - PSADT Package

Modern reboot enforcement solution using PSAppDeployToolkit to maintain system health through proactive reboot reminders.

## Overview

This solution monitors workstation uptime and progressively reminds users to restart their computers when uptime exceeds 7 days. The script runs as SYSTEM via SCCM/Intune and displays interactive prompts to logged-in users, ultimately forcing a restart at 10 PM if the user hasn't restarted voluntarily.

## Features

- ✅ **Runs as SYSTEM** - Has privileges to reboot computers
- ✅ **Progressive Notification Strategy** - 4-hour reminders transitioning to urgent warnings
- ✅ **Smart Timing** - Enforces reboots during 10PM-5AM maintenance window
- ✅ **AD Group Exemption** - Exclude computers via Active Directory group membership
- ✅ **JSON State Management** - Persistent tracking without registry dependencies
- ✅ **Demo Mode** - Test notifications without actual reboot enforcement
- ✅ **SCCM/Intune Ready** - Deploy via Configuration Manager or Intune

## How It Works

### Enforcement Logic Flow

```
1. Check Computer Exemption
   └─ Is computer in AD group "RebootExemption"?
      ├─ YES → Exit (no enforcement)
      └─ NO → Continue

2. Check System Uptime
   └─ Has computer been running for 7+ days?
      ├─ NO → Exit (no action needed)
      └─ YES → Continue

3. Calculate Deadline
   └─ Deadline = Today at 10:00 PM

4. Determine Notification Strategy
   └─ Time until deadline?
      ├─ 0 minutes (deadline reached)
      │   └─ Is current time between 10 PM - 5 AM?
      │       ├─ YES → FORCE RESTART (60 second countdown)
      │       └─ NO → Wait for maintenance window
      │
      ├─ 1-90 minutes remaining
      │   └─ Show URGENT prompt:
      │       - "Your system must restart in X minutes"
      │       - Option: "Restart Now" or "Remind in 15 min"
      │       - Repeats every time script runs
      │
      └─ 90+ minutes remaining
          └─ Show STANDARD notification (every 4 hours):
              - "Computer has been online for X days"
              - "Please restart at your convenience"
              - "Auto-restart at 10:00 PM today"
```

### Notification Behavior Timeline

**Example: User's computer has 8 days uptime on a Monday**

| Time | Uptime | Behavior | User Experience |
|------|--------|----------|-----------------|
| 9:00 AM | 8d | Standard notification | "Please restart at convenience, auto-restart at 10 PM today" |
| 1:00 PM | 8d | Standard notification | Same message (4 hours since last) |
| 5:00 PM | 8d | Standard notification | Same message (4 hours since last) |
| 8:30 PM | 8d | **Urgent warning** | "URGENT: Must restart in 90 minutes" - Options: Restart Now / Remind in 15 min |
| 9:00 PM | 8d | **Urgent warning** | "URGENT: Must restart in 60 minutes" |
| 9:30 PM | 8d | **Urgent warning** | "URGENT: Must restart in 30 minutes" |
| 10:00 PM | 8d | **FORCED RESTART** | 60-second countdown, then automatic restart |

**If user restarts voluntarily:**
- Uptime resets to 0 days
- No notifications until uptime exceeds 7 days again

**If deadline passes outside maintenance window:**
- Script waits until next maintenance window (10 PM - 5 AM)
- Continues showing urgent warnings every 15 minutes

## Package Structure

```
RebootEnforcement-PSADT/
├── Deploy-Application.ps1          # Main PSADT script (runs as SYSTEM)
├── Config/
│   └── config.psd1                 # PSADT configuration file
├── Strings/                        # Localization files (if customized)
├── SupportFiles/                   # Custom support scripts (if needed)
└── AppDeployToolkit/               # PSADT framework (download separately - not in repo)
```

> **Note:** The `AppDeployToolkit` folder is excluded from version control. Download PSAppDeployToolkit separately.

## Prerequisites

1. **PSAppDeployToolkit v3.9.3 or later**
   - Download from: https://psappdeploytoolkit.com
   - Extract the `AppDeployToolkit` folder into this package directory
   - Required files: `AppDeployToolkitMain.ps1`, `Deploy-Application.exe`

2. **Active Directory Module** (Optional)
   - Only required if using AD group exemptions
   - Pre-installed on domain-joined Windows 10/11 with RSAT
   - Script gracefully handles missing module (no exemptions applied)

## Configuration

Edit `Deploy-Application.ps1` (lines 120-125) to customize settings:

```powershell
# Reboot Enforcement Configuration
[String]$exemptionADGroup = "RebootExemption"       # AD group name for exempted computers
[Int32]$uptimeThresholdDays = 7                     # Days of uptime before enforcement begins
[Int32]$rebootHour = 22                             # Deadline hour (24-hour format, 22 = 10 PM)
[Int32]$rebootWindowEnd = 5                         # Maintenance window end (5 = 5 AM)
```

### Configuration Options Explained

| Setting | Default | Description | Example Values |
|---------|---------|-------------|----------------|
| `exemptionADGroup` | `"RebootExemption"` | AD security group containing exempted computers | `"NoRebootServers"`, `"IT-DevMachines"` |
| `uptimeThresholdDays` | `7` | Days of continuous uptime before notifications start | `5`, `10`, `14` |
| `rebootHour` | `22` | Hour when deadline occurs (24-hour) | `21` (9 PM), `23` (11 PM), `2` (2 AM) |
| `rebootWindowEnd` | `5` | Hour when maintenance window ends | `6` (6 AM), `7` (7 AM) |

### State File Location

The script maintains state in: `C:\ProgramData\RebootEnforcement\state.json`

This JSON file tracks:
- Last notification timestamp
- Number of notifications sent
- User-scheduled reboot time (if applicable)

**Example state.json:**
```json
{
  "LastNotificationTime": "2025-12-12T13:45:30.1234567-05:00",
  "ScheduledRebootTime": null,
  "NotificationCount": 3
}
```

## Testing

### Demo Mode

Test the notification flow without enforcing actual reboots:

```powershell
# Run in demo mode (simulates 8 days uptime, 60-minute deadline)
.\Deploy-Application.exe -DemoMode

# Interactive mode (shows all prompts)
.\Deploy-Application.exe -DeploymentType Install

# Silent mode (logs only, no UI)
.\Deploy-Application.exe -DeployMode Silent
```

**Demo Mode Behavior:**
- ✅ Simulates 8 days uptime (exceeds 7-day threshold)
- ✅ Sets deadline to 60 minutes from now
- ✅ Skips AD exemption check
- ✅ Shows all notification prompts
- ❌ Does NOT force actual restart
- ✅ Allows dismissing urgent warnings (production blocks this)

### Manual Testing Steps

1. **Test Standard Notification (90+ minutes until deadline)**
   ```powershell
   .\Deploy-Application.exe -DemoMode
   ```
   - Should show: "Computer has been online for 8 days"
   - Message includes: "Please restart at convenience"
   - Button: "OK"

2. **Test Urgent Warning (simulate approaching deadline)**
   - Wait 45 minutes after first demo run
   - Run again: `.\Deploy-Application.exe -DemoMode`
   - Should show: "URGENT: Must restart in ~15 minutes"
   - Options: "Restart Now" / "OK (Demo Only)"

3. **Test Exemption**
   - Add computer to AD group specified in `$exemptionADGroup`
   - Run: `.\Deploy-Application.exe`
   - Should log: "Computer is exempt" and exit immediately

4. **View Logs**
   - Location: `C:\Windows\Logs\Software\`
   - File: `Reboot Enforcement_PSAppDeployToolkit_*.log`
   - Review for errors or unexpected behavior

## Deployment

### SCCM/ConfigMgr Deployment

#### 1. Create Application

- Copy entire package to content source location (e.g., `\\server\source$\RebootEnforcement`)
- In SCCM Console: **Software Library** → **Application Management** → **Applications**
- Right-click → **Create Application** → **Manually specify application information**

#### 2. Deployment Type Settings

| Setting | Value |
|---------|-------|
| **Installation Program** | `Deploy-Application.exe` |
| **Uninstall Program** | *(leave blank)* |
| **Run as** | System |
| **Installation behavior** | Install for system |
| **Logon requirement** | Whether or not a user is logged on |
| **Maximum runtime** | 10 minutes |
| **Estimated installation time** | 2 minutes |

**Return Codes:**
- `0` = Success (no action taken or notification shown)
- `1641` = Success with reboot initiated
- `3010` = Soft reboot required

#### 3. Detection Method

Use **Script** detection (PowerShell):

```powershell
# Always return false - this is a recurring enforcement check
# Not an installed application
return $false
```

> **Why "always false"?** This ensures SCCM re-runs the script every evaluation cycle to continuously monitor uptime.

#### 4. Deployment Settings

| Setting | Value | Notes |
|---------|-------|-------|
| **Purpose** | Required | Ensures all workstations are covered |
| **Available Time** | As soon as possible | |
| **Installation Deadline** | *(none)* | Ongoing enforcement, no deadline |
| **Schedule** | Every 30 minutes | Adjust based on responsiveness needs |
| **Rerun behavior** | Always rerun program | Critical - must rerun to check uptime |
| **User notifications** | Hide all notifications | Script handles its own notifications |
| **Allow users to view and interact** | No | SYSTEM context, users see PSADT prompts |

**Recommended Schedule:**
- **Business hours (6 AM - 9 PM):** Every 30-60 minutes
- **Evening (9 PM - 10 PM):** Every 15 minutes (approaching deadline)
- **After hours (10 PM - 6 AM):** Every 30 minutes

#### 5. Target Collection

- Deploy to: **All Workstations** or **All Windows 10/11 Devices**
- Exclude: Server operating systems (script is designed for workstations)
- Optional: Create exclusion collection for permanently exempted machines

### Intune Deployment

#### 1. Package the Application

```powershell
# Download Win32 Content Prep Tool
# https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool

# Create .intunewin package
.\IntuneWinAppUtil.exe -c "C:\Source\RebootEnforcement-PSADT" -s "Deploy-Application.exe" -o "C:\Output" -q
```

#### 2. Create Win32 App in Intune

**Endpoint Manager Admin Center** → **Apps** → **Windows** → **Add** → **Windows app (Win32)**

**App Information:**
- Name: `Reboot Enforcement`
- Description: `Proactive system maintenance - enforces 7-day reboot cycle`
- Publisher: `IT Operations`

**Program Settings:**
- **Install command:**
  ```
  Deploy-Application.exe
  ```
- **Uninstall command:** *(not applicable)*
- **Install behavior:** System
- **Device restart behavior:** Determine behavior based on return codes

**Requirements:**
- **Operating system:** Windows 10 1607+, Windows 11
- **Architecture:** 64-bit
- **Minimum free disk space:** 100 MB

**Detection Rules:**
- **Rule type:** Use a custom detection script
- **Script type:** PowerShell
- **Script content:**
  ```powershell
  # Always return non-compliant to enable recurring checks
  exit 1
  ```

**Assignment:**
- **Group assignment:** All Users / All Devices
- **Assignment type:** Required
- **End user notifications:** Hide all toast notifications
- **Availability:** As soon as possible
- **Installation deadline:** Not configured (ongoing enforcement)
- **Restart grace period:** Not configured (script handles this)

**Detection Rule Frequency:**
Intune checks detection rules based on app priority. For this recurring check:
- Default: Every 8 hours
- To increase frequency: Deploy as a **PowerShell script** instead (runs every 1 hour)

#### Alternative: Intune Remediation Script

For more frequent checks, deploy as a **Proactive Remediation**:

**Settings** → **Remediations** → **Create script package**

- **Detection script:** `Deploy-Application.ps1` (modified to return exit codes)
- **Remediation script:** *(same as detection)*
- **Run this script using logged-on credentials:** No
- **Enforce script signature check:** No
- **Run script in 64-bit PowerShell:** Yes
- **Schedule:** Every 1 hour

## User Experience

### What Users See

#### Standard Notification (Early Warning)
![Info Dialog](https://via.placeholder.com/450x250/0078d4/ffffff?text=Proactive+System+Maintenance)

**Title:** Proactive System Maintenance  
**Message:**
> Your computer has been online for 8 days. We perform proactive reboots on systems running over 7 days to maintain optimal performance and stability.
> 
> Please restart at your convenience, or your system will automatically restart at 10:00 PM today.

**Button:** OK

---

#### Urgent Warning (Final 90 Minutes)
![Warning Dialog](https://via.placeholder.com/450x250/ff8c00/ffffff?text=URGENT+Restart+Required)

**Title:** URGENT: Restart Required Now  
**Message:**
> Your system must restart in 45 minutes (at 10:00 PM).
> 
> Save all work immediately. Your computer will restart automatically if you do not take action.

**Buttons:** 
- Restart Now
- Remind Me in 15 Minutes

---

#### Forced Restart Countdown
![Countdown Dialog](https://via.placeholder.com/450x250/dc3545/ffffff?text=Restarting+in+60+seconds)

**Title:** Restart Required  
**Message:**
> Your computer will restart in 60 seconds. Please save your work.

**Progress Bar:** 60-second countdown  
**Buttons:**
- Restart Now (accelerate)
- *(No dismiss option)*

### Frequency by Phase

| Phase | Frequency | Can Dismiss? |
|-------|-----------|--------------|
| Standard warnings (90+ min) | Every 4 hours | ✅ Yes |
| Urgent warnings (1-90 min) | Every script run (~15 min) | ✅ Yes (demo), ❌ No (production) |
| Countdown (deadline reached) | Immediate (60 sec) | ❌ No |

## Troubleshooting

### Common Issues

#### 1. Notifications Not Appearing

**Symptoms:** Script runs successfully but users don't see prompts

**Causes & Solutions:**
- **No interactive user logged in**
  - ✅ Expected: Prompts only show when user is logged in
  - Check logs for: "No interactive user detected"

- **User session is locked**
  - ✅ Expected: PSADT prompts appear on lock screen
  - Ensure ServiceUI.exe is being used (PSADT default)

- **PSADT prompts suppressed**
  - Check `Config\config.psd1` → `Toolkit_ShowBalloonNotifications = $true`
  - Ensure not running in `-DeployMode Silent`

#### 2. Script Exits Immediately

**Check logs for:**

```
Computer is exempt from reboot enforcement
```
- Solution: Verify AD group membership, remove from exemption group if needed

```
Uptime below threshold (X days)
```
- Solution: Expected behavior, no action required until 7 days uptime

```
Module [AppDeployToolkitMain.ps1] failed to load
```
- Solution: Ensure PSAppDeployToolkit is installed in `AppDeployToolkit\` folder

#### 3. State File Errors

**Error:** "Error saving state: Access denied"

- Check `C:\ProgramData\RebootEnforcement` folder permissions
- Ensure SYSTEM account has write access
- Manually create folder: `New-Item -Path "C:\ProgramData\RebootEnforcement" -ItemType Directory -Force`

**Error:** State file not persisting

- Verify script is running as SYSTEM (not user context)
- Check for antivirus blocking JSON file writes
- Review logs for serialization errors

#### 4. Uptime Detection Incorrect

**Symptoms:** Script says 0 days uptime on system that's been running

**Solution:**
```powershell
# Verify CIM instance manually
Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object LastBootUpTime
```

If CIM queries fail, ensure:
- WMI service is running
- Windows Management Instrumentation driver started
- Not blocked by security software

### Viewing Logs

**Location:** `C:\Windows\Logs\Software\`

**File Pattern:** `Reboot Enforcement_PSAppDeployToolkit_<HOSTNAME>_<DATETIME>.log`

**Key Log Entries:**

```
# Successful run with notification
[Installation] :: Reboot Enforcement - Starting Check
[Installation] :: System uptime: 8 days
[Installation] :: Uptime exceeds threshold - enforcement active
[Installation] :: Deadline: 2025-12-12 22:00:00 (5.2 hours)
[Installation] :: Showing reboot notification
[Installation] :: User acknowledged notification
```

```
# Exempt system
[Installation] :: Computer is exempt (member of RebootExemption)
[Finalization] :: Exiting with code [0]
```

```
# Forced restart
[Installation] :: Deadline reached and in reboot window - forcing reboot
[Installation] :: Displaying restart prompt with countdown
```

### Manual Override

To **temporarily disable** enforcement on a specific computer:

```powershell
# Add computer to exemption group
Add-ADGroupMember -Identity "RebootExemption" -Members "COMPUTER01$"
```

To **reset state** (clear notification history):

```powershell
Remove-Item "C:\ProgramData\RebootEnforcement\state.json" -Force
```

To **force immediate notification** (testing):

```powershell
# Temporarily modify uptimeThresholdDays to 0
# Or run in -DemoMode
.\Deploy-Application.exe -DemoMode
```

## Best Practices

### Deployment Strategy

1. **Pilot Phase (Week 1-2)**
   - Deploy to IT department first
   - Set `uptimeThresholdDays = 10` (more lenient)
   - Monitor logs and user feedback

2. **Rollout Phase (Week 3-4)**
   - Expand to broader user groups
   - Reduce to `uptimeThresholdDays = 7`
   - Communicate to users via email

3. **Steady State**
   - Deploy to all workstations
   - Review exemption requests quarterly
   - Analyze uptime trends via ConfigMgr/Intune reporting

### User Communication Template

**Email Subject:** Proactive System Maintenance - Scheduled Restarts

**Body:**
> Dear Team,
> 
> To maintain optimal performance and apply security updates, we're implementing proactive system restarts for workstations running continuously for more than 7 days.
> 
> **What to Expect:**
> - If your computer has been on for 7+ days, you'll receive periodic reminders to restart
> - You can restart at your convenience during the day
> - If not restarted manually, an automatic restart will occur at 10:00 PM
> - You'll receive warnings with increasing frequency as the deadline approaches
> 
> **What to Do:**
> - Save your work regularly
> - Restart your computer when prompted at a convenient time
> - If you need an exemption (e.g., long-running processes), contact IT
> 
> Thank you for your cooperation in maintaining a secure and performant environment.

### Exemption Management

**Criteria for Exemption Approval:**
- ✅ Servers or always-on systems
- ✅ Systems running critical 24/7 processes
- ✅ Development machines with complex environment setups
- ❌ General reluctance to restart
- ❌ "Too busy" (can schedule restart)

**Review Process:**
- Quarterly audit of exemption group membership
- Require business justification for continued exemption
- Remove inactive/decomissioned computers

## FAQ

**Q: Can users postpone indefinitely?**  
A: No. Users can postpone reminders, but the 10 PM deadline is firm (unless they're in the exemption group).

**Q: What if a user is working at 10 PM?**  
A: The script detects logged-in users and shows a 60-second countdown. Users have one minute to save work. Consider adjusting `rebootHour` if many users work late.

**Q: Does this work on laptops that are off?**  
A: No enforcement occurs when the device is off. The script checks uptime since last boot, so a laptop that's frequently shut down won't trigger enforcement.

**Q: Can users schedule a specific restart time?**  
A: Not in the current version. Users can only restart immediately or postpone reminders. Consider adding scheduling in a future version.

**Q: What happens if exemption group doesn't exist?**  
A: Script logs a warning and continues without exemptions (all computers subject to enforcement).

**Q: How do I change the deadline from 10 PM?**  
A: Edit `Deploy-Application.ps1` line 123: `[Int32]$rebootHour = 22` (change 22 to desired hour in 24-hour format).

**Q: Can I test without waiting 7 days?**  
A: Yes, run `.\Deploy-Application.exe -DemoMode` to simulate 8 days uptime immediately.

## Version History

### v1.0.0 (2025-12-03)
- Initial release
- Progressive notification strategy (4-hour intervals → urgent warnings)

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

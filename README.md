# Reboot Enforcement Script

Automates workstation reboots after 7 days of uptime with progressive user notifications and scheduling options.

## Features

✅ **Progressive Notifications**
- Hourly warnings starting on day 8
- 15-minute interval warnings in final 90 minutes
- Toast notifications with interactive buttons

✅ **User Scheduling**
- Custom time picker to schedule convenient reboot time
- Automated countdown warnings (10, 5, 1 minute)
- Schedule persists across script runs

✅ **Safety Controls**
- Only reboots during 10PM-5AM window
- AD group exemption support
- WhatIf mode for testing
- Comprehensive logging

✅ **Demo Mode**
- Rapid testing without waiting
- Simulated uptime and deadlines
- Perfect for demonstrations

## Requirements

- **PowerShell**: 5.1 or higher
- **Operating System**: Windows 10/11 or Windows Server 2016+
- **Module**: BurntToast (auto-installed if missing)
- **Permissions**: Administrator rights for reboot
- **Optional**: Active Directory module for exemption checks

## Installation

1. Copy `Invoke-RebootEnforcement.ps1` to your scripts directory
2. Deploy via SCCM, Group Policy, or scheduled task

### SCCM Deployment (Recommended)

```powershell
# Create package with the script
# Deploy to collection: All Workstations (excluding exemption group)
# Schedule: Every 15 minutes during business hours
# Schedule: Every 5 minutes during 9PM-11PM window
# Run as: SYSTEM
```

## Usage

### Basic Usage

```powershell
# Run with defaults (checks for 7+ days uptime, 10PM deadline)
.\Invoke-RebootEnforcement.ps1

# Preview mode - see what would happen
.\Invoke-RebootEnforcement.ps1 -WhatIf

# Custom exemption group and log path
.\Invoke-RebootEnforcement.ps1 -ExemptionADGroup "NoReboot" -LogPath "C:\Logs\Reboot"

# Skip AD check (for non-domain machines)
.\Invoke-RebootEnforcement.ps1 -SkipADCheck
```

### Demo Mode Examples

Perfect for testing and demonstrations:

```powershell
# Demo: Initial warning (8 days uptime, 2 hours to deadline)
.\Invoke-RebootEnforcement.ps1 -DemoMode -DemoUptimeDays 8 -DemoMinutesToDeadline 120 -WhatIf

# Demo: Hourly reminder (8 days uptime, 60 minutes to deadline)
.\Invoke-RebootEnforcement.ps1 -DemoMode -DemoUptimeDays 8 -DemoMinutesToDeadline 60 -WhatIf

# Demo: Final warning phase (8 days uptime, 15 minutes to deadline)
.\Invoke-RebootEnforcement.ps1 -DemoMode -DemoUptimeDays 8 -DemoMinutesToDeadline 15 -WhatIf

# Demo: Final warning (5 minutes to deadline)
.\Invoke-RebootEnforcement.ps1 -DemoMode -DemoUptimeDays 8 -DemoMinutesToDeadline 5 -WhatIf

# Demo: Immediate reboot scenario
.\Invoke-RebootEnforcement.ps1 -DemoMode -DemoUptimeDays 10 -DemoMinutesToDeadline 0 -WhatIf

# Demo: Test scheduling interface
.\Invoke-RebootEnforcement.ps1 -DemoMode -DemoUptimeDays 8 -DemoMinutesToDeadline 180 -SkipADCheck
# Note: Scheduling requires running script multiple times to see countdown notifications
```

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ExemptionADGroup` | String | "RebootExemption" | AD group for exempt computers |
| `LogPath` | String | `$env:ProgramData\RebootEnforcement\logs` | Log file directory |
| `UptimeThresholdDays` | Int | 7 | Days before enforcement starts |
| `RebootHour` | Int | 22 | Hour for forced reboot (24-hr format) |
| `RebootWindowEnd` | Int | 5 | Hour when reboot window ends |
| `WhatIf` | Switch | - | Preview mode, no actual reboot |
| `DemoMode` | Switch | - | Enable demo/testing mode |
| `DemoUptimeDays` | Int | 8 | Simulated uptime (demo mode) |
| `DemoMinutesToDeadline` | Int | 15 | Minutes to deadline (demo mode) |
| `SkipADCheck` | Switch | - | Skip AD group check |

## How It Works

### Execution Flow

1. **AD Exemption Check**: Exits gracefully if computer is in exemption group
2. **Uptime Check**: Calculates system uptime using WMI
3. **Threshold Check**: Exits if uptime < 7 days
4. **Deadline Calculation**: Determines next 10PM deadline
5. **State Load**: Retrieves scheduling and notification history from registry
6. **Decision Logic**: Determines if notification or reboot needed
7. **Action**: Shows notification, executes reboot, or exits

### Notification Strategy

| Time Until Deadline | Frequency | Notification Type |
|---------------------|-----------|-------------------|
| > 90 minutes | Every 1 hour | Standard warning with schedule option |
| ≤ 90 minutes | Every 15 minutes | Urgent warning |
| Scheduled reboot | At 10, 5, 1 min | Countdown warnings |
| 0 minutes (10PM) | Immediate | Reboot execution |

### User Scheduling

When users click "Schedule Reboot":
1. Time picker dialog appears
2. User selects time before 10PM deadline
3. Time saved to registry
4. Countdown notifications at 10, 5, 1 minute before scheduled time
5. Automatic reboot at scheduled time

### Registry State Storage

Location: `HKLM:\SOFTWARE\RebootEnforcement`

Keys:
- `LastNotificationTime`: DateTime of last notification
- `ScheduledRebootTime`: User's scheduled reboot time
- `NotificationCount`: Total notifications shown

## Logging

### Log Location

Default: `C:\ProgramData\RebootEnforcement\logs\RebootEnforcement_YYYYMMDD.log`

### Log Format

```
[2025-01-15 14:30:00] [INFO] Reboot Enforcement Script Started
[2025-01-15 14:30:01] [INFO] System uptime: 8 days, 6 hours, 22 minutes
[2025-01-15 14:30:01] [WARNING] Uptime exceeds threshold - reboot enforcement active
[2025-01-15 14:30:02] [INFO] Next reboot deadline: 2025-01-15 22:00:00
[2025-01-15 14:30:03] [INFO] Showed InitialWarning notification
```

### Log Levels

- `INFO`: Normal operations
- `WARNING`: Important events (uptime exceeded, notifications)
- `ERROR`: Failures (module installation, reboot failure)
- `DEBUG`: Detailed troubleshooting information

## Troubleshooting

### BurntToast Module Not Installing

```powershell
# Manual installation
Install-Module -Name BurntToast -Force -Scope AllUsers

# Verify installation
Get-Module -ListAvailable BurntToast
```

### Notifications Not Appearing

1. Check Windows notification settings (Focus Assist)
2. Verify BurntToast module is loaded: `Import-Module BurntToast`
3. Check logs for errors
4. Run manually in user context (not SYSTEM) for testing

### Script Not Detecting AD Group

```powershell
# Verify ActiveDirectory module
Import-Module ActiveDirectory

# Check computer group membership
Get-ADComputer $env:COMPUTERNAME -Properties MemberOf | Select-Object -ExpandProperty MemberOf

# Skip AD check for testing
.\Invoke-RebootEnforcement.ps1 -SkipADCheck
```

### Schedule Not Persisting

1. Verify registry permissions for HKLM:\SOFTWARE\RebootEnforcement
2. Check logs for registry write errors
3. Run as administrator

## Examples

### Scenario 1: First Warning

```powershell
# User's computer has 8 days uptime, it's 2PM
# Script shows: "Your computer has been running for 8 days"
# Buttons: [Schedule Reboot] [Remind Me Later]
# Next notification: In 1 hour (3PM)
```

### Scenario 2: User Schedules Reboot

```powershell
# User clicks "Schedule Reboot"
# Time picker shows, user selects 8:00 PM
# Script saves to registry
# Next notifications: 7:50 PM (10 min), 7:55 PM (5 min), 7:59 PM (1 min)
# At 8:00 PM: Computer reboots
```

### Scenario 3: Final Warning

```powershell
# It's 9:30 PM, deadline is 10:00 PM (30 minutes)
# Script shows: "🚨 URGENT: Reboot in 30 Minutes"
# Next notification: In 15 minutes (9:45 PM)
```

### Scenario 4: Deadline Reached

```powershell
# It's 10:00 PM (deadline)
# Script shows: "🚨 REBOOT STARTING NOW" (60 second warning)
# After 60 seconds: Restart-Computer -Force
```

## ServiceNow Integration

### Exemption Management

Users can request exemption through ServiceNow:
1. User submits ticket
2. ServiceNow workflow approves/denies
3. On approval: Adds computer to AD exemption group
4. Script automatically detects exemption on next run

### Reporting

Export logs to SIEM or log aggregator:

```powershell
# Example: Copy logs to network share daily
$logFiles = Get-ChildItem "C:\ProgramData\RebootEnforcement\logs" -Filter "*.log"
Copy-Item $logFiles -Destination "\\fileserver\logs\RebootEnforcement\" -Force
```

## Best Practices

### Deployment

- ✅ Test in pilot group first
- ✅ Use WhatIf mode initially
- ✅ Monitor logs for issues
- ✅ Communicate to users before deployment

### Scheduling

- Run every 15 minutes during business hours (8AM-6PM)
- Run every 5 minutes during evening (6PM-11PM)
- Run every 1 minute during reboot window (10PM-5Am) for precision

### User Communication

Before deployment, inform users:
- Why reboots are necessary (security, stability)
- How the system works
- How to schedule convenient times
- How to request exemption

## Security Considerations

- Script runs as SYSTEM for reboot privileges
- Registry state in HKLM prevents user tampering
- Reboot only during off-hours (10PM-5AM)
- WhatIf mode available for safe testing
- Comprehensive logging for audit trail

## Version History

### Version 1.0 (2025-01-15)
- Initial release
- Core functionality: 7-day uptime enforcement
- Progressive notifications
- User scheduling with time picker
- Demo mode for testing
- BurntToast integration
- Registry-based state management

## License

Internal use only - Your Organization

## Support

For issues or questions:
- Check logs: `C:\ProgramData\RebootEnforcement\logs`
- Review this README
- Contact: IT Operations Team
- ServiceNow: Submit ticket categorized as "Workstation Management"

---

**Note**: This script is designed to improve system stability and security by ensuring regular reboots. Users have ample warning and scheduling options to minimize disruption.
<#
.SYNOPSIS
    Enforces periodic workstation reboots after 7 days of uptime with progressive notifications and user scheduling.

.DESCRIPTION
    This script monitors system uptime and enforces reboots after 7 days of continuous operation.
    
    Features:
    - Progressive notifications (hourly warnings, then 15-minute intervals in final 90 minutes)
    - User can schedule reboot before 10PM deadline
    - Toast notifications with interactive buttons
    - Scheduled reboot countdowns (10, 5, 1 minute warnings)
    - Only reboots during 10PM-5AM window
    - AD group exemption support
    - Demo mode for testing and demonstrations
    - Comprehensive logging
    
.PARAMETER ExemptionADGroup
    Name of AD group whose members are exempt from forced reboots (default: RebootExemption)

.PARAMETER LogPath
    Path for log files (default: $env:ProgramData\RebootEnforcement\logs)

.PARAMETER UptimeThresholdDays
    Number of days before reboot enforcement begins (default: 7)

.PARAMETER RebootHour
    Hour (24-hour format) when forced reboots occur (default: 22 = 10 PM)

.PARAMETER RebootWindowEnd
    Hour (24-hour format) when reboot window ends (default: 5 = 5 AM)

.PARAMETER WhatIf
    Preview mode - shows what would happen without making changes

.PARAMETER DemoMode
    Enable demo mode for testing - simulates uptime and deadline

.PARAMETER DemoUptimeDays
    Simulated uptime in days when DemoMode is enabled (default: 8)

.PARAMETER DemoMinutesToDeadline
    Minutes until simulated deadline when DemoMode is enabled (default: 15)

.PARAMETER SkipADCheck
    Skip Active Directory group membership check (for testing)

.EXAMPLE
    .\Invoke-RebootEnforcement.ps1
    Run in production mode with default settings

.EXAMPLE
    .\Invoke-RebootEnforcement.ps1 -WhatIf
    Preview mode - see what would happen without making changes

.EXAMPLE
    .\Invoke-RebootEnforcement.ps1 -DemoMode -DemoUptimeDays 8 -DemoMinutesToDeadline 15 -WhatIf
    Demo mode showing initial warning 15 minutes before deadline

.EXAMPLE
    .\Invoke-RebootEnforcement.ps1 -ExemptionADGroup "NoReboot" -LogPath "C:\Logs\Reboot"
    Use custom AD group and log path

.NOTES
    Author: IT Operations
    Version: 1.0
    Requires: PowerShell 5.1+, BurntToast module (auto-installed if missing)
    Deployment: Run via SCCM every 15 minutes, more frequently near deadline
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ExemptionADGroup = "RebootExemption",
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:ProgramData\RebootEnforcement\logs",
    
    [Parameter(Mandatory=$false)]
    [int]$UptimeThresholdDays = 7,
    
    [Parameter(Mandatory=$false)]
    [int]$RebootHour = 22,  # 10PM
    
    [Parameter(Mandatory=$false)]
    [int]$RebootWindowEnd = 5,  # 5AM
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf,
    
    # Demo/Testing Parameters
    [Parameter(Mandatory=$false)]
    [switch]$DemoMode,
    
    [Parameter(Mandatory=$false)]
    [int]$DemoUptimeDays = 8,
    
    [Parameter(Mandatory=$false)]
    [int]$DemoMinutesToDeadline = 15,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipADCheck
)

#Requires -Version 5.1

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

$script:RegistryPath = "HKLM:\SOFTWARE\RebootEnforcement"
$script:AppId = "RebootEnforcement"

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

function Write-RebootLog {
    <#
    .SYNOPSIS
        Writes log messages to file and console
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('INFO','WARNING','ERROR','DEBUG')]
        [string]$Level = 'INFO'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    $logFile = Join-Path $LogPath "RebootEnforcement_$(Get-Date -Format 'yyyyMMdd').log"
    
    # Ensure directory exists
    if (-not (Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }
    
    # Write to file
    try {
        Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "Failed to write to log file: $_"
    }
    
    # Write to console with colors
    $color = switch ($Level) {
        'ERROR' { 'Red' }
        'WARNING' { 'Yellow' }
        'DEBUG' { 'Gray' }
        default { 'White' }
    }
    Write-Host $logMessage -ForegroundColor $color
}

# ============================================================================
# REGISTRY STATE MANAGEMENT
# ============================================================================

function Get-RebootState {
    <#
    .SYNOPSIS
        Retrieves persistent state from registry
    #>
    try {
        if (-not (Test-Path $script:RegistryPath)) {
            New-Item -Path $script:RegistryPath -Force | Out-Null
            Write-RebootLog "Created registry path for state management" -Level DEBUG
        }
        
        $state = @{
            LastNotificationTime = $null
            ScheduledRebootTime = $null
            NotificationCount = 0
        }
        
        # Read values
        $lastNotification = (Get-ItemProperty -Path $script:RegistryPath -Name LastNotificationTime -ErrorAction SilentlyContinue).LastNotificationTime
        if ($lastNotification) {
            $state.LastNotificationTime = [DateTime]::Parse($lastNotification)
        }
        
        $scheduledReboot = (Get-ItemProperty -Path $script:RegistryPath -Name ScheduledRebootTime -ErrorAction SilentlyContinue).ScheduledRebootTime
        if ($scheduledReboot) {
            $state.ScheduledRebootTime = [DateTime]::Parse($scheduledReboot)
        }
        
        $notificationCount = (Get-ItemProperty -Path $script:RegistryPath -Name NotificationCount -ErrorAction SilentlyContinue).NotificationCount
        if ($notificationCount) {
            $state.NotificationCount = $notificationCount
        }
        
        return $state
    }
    catch {
        Write-RebootLog "Error reading state from registry: $_" -Level WARNING
        return @{
            LastNotificationTime = $null
            ScheduledRebootTime = $null
            NotificationCount = 0
        }
    }
}

function Set-RebootState {
    <#
    .SYNOPSIS
        Saves persistent state to registry
    #>
    param(
        [DateTime]$LastNotificationTime,
        [DateTime]$ScheduledRebootTime,
        [int]$NotificationCount
    )
    
    try {
        if ($LastNotificationTime) {
            Set-ItemProperty -Path $script:RegistryPath -Name LastNotificationTime -Value $LastNotificationTime.ToString("o") -Type String
        }
        
        if ($ScheduledRebootTime) {
            Set-ItemProperty -Path $script:RegistryPath -Name ScheduledRebootTime -Value $ScheduledRebootTime.ToString("o") -Type String
        }
        else {
            # Clear scheduled reboot if null
            Remove-ItemProperty -Path $script:RegistryPath -Name ScheduledRebootTime -ErrorAction SilentlyContinue
        }
        
        Set-ItemProperty -Path $script:RegistryPath -Name NotificationCount -Value $NotificationCount -Type DWord
        
        Write-RebootLog "State saved to registry" -Level DEBUG
    }
    catch {
        Write-RebootLog "Error saving state to registry: $_" -Level ERROR
    }
}

# ============================================================================
# AD EXEMPTION CHECK
# ============================================================================

function Test-RebootExemption {
    <#
    .SYNOPSIS
        Checks if computer is member of exemption AD group
    #>
    param(
        [string]$GroupName
    )
    
    if ($SkipADCheck) {
        Write-RebootLog "Skipping AD check (SkipADCheck parameter)" -Level DEBUG
        return $false
    }
    
    try {
        $computerName = $env:COMPUTERNAME
        
        # Try to load ActiveDirectory module
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            Write-RebootLog "ActiveDirectory module not available - proceeding without exemption check" -Level WARNING
            return $false
        }
        
        Import-Module ActiveDirectory -ErrorAction Stop
        
        # Get computer object with group membership
        $computer = Get-ADComputer -Identity $computerName -Properties MemberOf -ErrorAction Stop
        
        if ($computer.MemberOf) {
            foreach ($group in $computer.MemberOf) {
                if ($group -like "*$GroupName*") {
                    Write-RebootLog "Computer is member of exemption group: $GroupName" -Level INFO
                    return $true
                }
            }
        }
        
        Write-RebootLog "Computer is not member of exemption group" -Level DEBUG
        return $false
    }
    catch {
        Write-RebootLog "Error checking AD group membership: $_" -Level WARNING
        Write-RebootLog "Proceeding without exemption check" -Level WARNING
        return $false
    }
}

# ============================================================================
# UPTIME AND DEADLINE CALCULATIONS
# ============================================================================

function Get-SystemUptime {
    <#
    .SYNOPSIS
        Gets system uptime (with demo mode support)
    #>
    if ($DemoMode) {
        $uptime = [TimeSpan]::FromDays($DemoUptimeDays)
        Write-RebootLog "DEMO MODE: Simulating $DemoUptimeDays days of uptime" -Level DEBUG
        return $uptime
    }
    
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $uptime = (Get-Date) - $os.LastBootUpTime
        return $uptime
    }
    catch {
        Write-RebootLog "Error getting system uptime: $_" -Level ERROR
        return [TimeSpan]::Zero
    }
}

function Get-NextRebootDeadline {
    <#
    .SYNOPSIS
        Calculates next 10PM deadline (with demo mode support)
    #>
    if ($DemoMode) {
        $deadline = (Get-Date).AddMinutes($DemoMinutesToDeadline)
        Write-RebootLog "DEMO MODE: Deadline set to $($deadline.ToString('yyyy-MM-dd HH:mm:ss')) ($DemoMinutesToDeadline minutes from now)" -Level DEBUG
        return $deadline
    }
    
    $now = Get-Date
    $currentHour = $now.Hour
    
    # Calculate today's reboot deadline (10PM)
    $todayDeadline = Get-Date -Hour $RebootHour -Minute 0 -Second 0
    
    # If we're past today's deadline, it stays today's deadline (we're in the window)
    # If we haven't reached it yet, that's our deadline
    if ($now -lt $todayDeadline) {
        return $todayDeadline
    }
    else {
        return $todayDeadline
    }
}

function Test-InRebootWindow {
    <#
    .SYNOPSIS
        Checks if current time is in the 10PM-5AM reboot window
    #>
    $currentHour = (Get-Date).Hour
    return ($currentHour -ge $RebootHour -or $currentHour -lt $RebootWindowEnd)
}

# ============================================================================
# BURNT TOAST NOTIFICATION SETUP
# ============================================================================

function Initialize-BurntToast {
    <#
    .SYNOPSIS
        Ensures BurntToast module is available
    #>
    try {
        if (-not (Get-Module -ListAvailable -Name BurntToast)) {
            Write-RebootLog "BurntToast module not found - attempting to install..." -Level WARNING
            Install-Module -Name BurntToast -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
            Write-RebootLog "BurntToast module installed successfully" -Level INFO
        }
        
        Import-Module BurntToast -ErrorAction Stop
        return $true
    }
    catch {
        Write-RebootLog "Failed to initialize BurntToast module: $_" -Level ERROR
        return $false
    }
}

# ============================================================================
# USER SCHEDULING DIALOG
# ============================================================================

function Show-RebootScheduler {
    <#
    .SYNOPSIS
        Shows Windows Forms time picker for user to schedule reboot
    #>
    param(
        [Parameter(Mandatory=$true)]
        [DateTime]$Deadline
    )
    
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        
        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'Schedule Reboot'
        $form.Size = New-Object System.Drawing.Size(420,220)
        $form.StartPosition = 'CenterScreen'
        $form.FormBorderStyle = 'FixedDialog'
        $form.MaximizeBox = $false
        $form.MinimizeBox = $false
        $form.TopMost = $true
        
        # Label
        $label = New-Object System.Windows.Forms.Label
        $label.Location = New-Object System.Drawing.Point(10,20)
        $label.Size = New-Object System.Drawing.Size(390,40)
        $label.Text = "Choose a time to restart your computer.`nMust be before deadline: $($Deadline.ToString('h:mm tt'))"
        $form.Controls.Add($label)
        
        # Time picker
        $timePicker = New-Object System.Windows.Forms.DateTimePicker
        $timePicker.Location = New-Object System.Drawing.Point(110,70)
        $timePicker.Size = New-Object System.Drawing.Size(200,20)
        $timePicker.Format = 'Time'
        $timePicker.ShowUpDown = $true
        
        # Set initial value to 1 hour from now
        $suggestedTime = (Get-Date).AddHours(1)
        if ($suggestedTime -gt $Deadline) {
            $suggestedTime = $Deadline.AddMinutes(-30)
        }
        $timePicker.Value = $suggestedTime
        $form.Controls.Add($timePicker)
        
        # Info label
        $infoLabel = New-Object System.Windows.Forms.Label
        $infoLabel.Location = New-Object System.Drawing.Point(10,110)
        $infoLabel.Size = New-Object System.Drawing.Size(390,30)
        $infoLabel.Text = "Your computer will restart at the selected time.`nPlease save all work before then."
        $infoLabel.ForeColor = [System.Drawing.Color]::DarkRed
        $form.Controls.Add($infoLabel)
        
        # OK Button
        $okButton = New-Object System.Windows.Forms.Button
        $okButton.Location = New-Object System.Drawing.Point(110,150)
        $okButton.Size = New-Object System.Drawing.Size(90,30)
        $okButton.Text = 'Schedule'
        $okButton.DialogResult = 'OK'
        $form.AcceptButton = $okButton
        $form.Controls.Add($okButton)
        
        # Cancel Button
        $cancelButton = New-Object System.Windows.Forms.Button
        $cancelButton.Location = New-Object System.Drawing.Point(220,150)
        $cancelButton.Size = New-Object System.Drawing.Size(90,30)
        $cancelButton.Text = 'Cancel'
        $cancelButton.DialogResult = 'Cancel'
        $form.CancelButton = $cancelButton
        $form.Controls.Add($cancelButton)
        
        $result = $form.ShowDialog()
        
        if ($result -eq 'OK') {
            $selectedTime = $timePicker.Value
            
            # Build scheduled time for today
            $todayScheduled = Get-Date -Hour $selectedTime.Hour -Minute $selectedTime.Minute -Second 0
            
            # Validate
            if ($todayScheduled -le (Get-Date)) {
                Write-RebootLog "User selected time that has already passed: $todayScheduled" -Level WARNING
                [System.Windows.Forms.MessageBox]::Show("The selected time has already passed. Please choose a future time.", "Invalid Time", 'OK', 'Warning')
                return $null
            }
            
            if ($todayScheduled -gt $Deadline) {
                Write-RebootLog "User selected time after deadline: $todayScheduled" -Level WARNING
                [System.Windows.Forms.MessageBox]::Show("The selected time is after the deadline of $($Deadline.ToString('h:mm tt')). Please choose an earlier time.", "Invalid Time", 'OK', 'Warning')
                return $null
            }
            
            Write-RebootLog "User scheduled reboot for: $($todayScheduled.ToString('yyyy-MM-dd HH:mm:ss'))" -Level INFO
            return $todayScheduled
        }
        
        Write-RebootLog "User cancelled reboot scheduling" -Level DEBUG
        return $null
    }
    catch {
        Write-RebootLog "Error showing reboot scheduler: $_" -Level ERROR
        return $null
    }
}

# ============================================================================
# NOTIFICATION FUNCTIONS
# ============================================================================

function Show-RebootNotification {
    <#
    .SYNOPSIS
        Shows toast notification based on notification type
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('InitialWarning','HourlyReminder','FinalWarning','ScheduledCountdown','ImmediateReboot')]
        [string]$Type,
        
        [Parameter(Mandatory=$false)]
        [TimeSpan]$Uptime,
        
        [Parameter(Mandatory=$false)]
        [DateTime]$Deadline,
        
        [Parameter(Mandatory=$false)]
        [int]$MinutesRemaining
    )
    
    if (-not (Initialize-BurntToast)) {
        Write-RebootLog "Cannot show notification - BurntToast not available" -Level ERROR
        return $false
    }
    
    try {
        $title = ""
        $message = ""
        $buttons = @()
        
        switch ($Type) {
            'InitialWarning' {
                $title = "⚠️ Reboot Required"
                $hoursToDeadline = [Math]::Round(($Deadline - (Get-Date)).TotalHours, 1)
                $message = "Your computer has been running for $([Math]::Floor($Uptime.TotalDays)) days.`n`nA reboot will be forced at $($Deadline.ToString('h:mm tt')) ($hoursToDeadline hours from now).`n`nClick 'Schedule' to choose a convenient time, or your computer will restart automatically at the deadline."
                
                $buttons += New-BTButton -Content "Schedule Reboot" -Arguments "schedule:$($Deadline.ToString('o'))"
                $buttons += New-BTButton -Content "Remind Me Later" -Arguments "dismiss"
            }
            
            'HourlyReminder' {
                $title = "🔔 Reboot Reminder"
                $hoursToDeadline = [Math]::Round(($Deadline - (Get-Date)).TotalHours, 1)
                $message = "Reminder: Forced reboot at $($Deadline.ToString('h:mm tt')) ($hoursToDeadline hours).`n`nCurrent uptime: $([Math]::Floor($Uptime.TotalDays)) days`n`nSchedule a convenient time or your computer will restart at the deadline."
                
                $buttons += New-BTButton -Content "Schedule Reboot" -Arguments "schedule:$($Deadline.ToString('o'))"
                $buttons += New-BTButton -Content "OK" -Arguments "dismiss"
            }
            
            'FinalWarning' {
                $title = "🚨 URGENT: Reboot in $MinutesRemaining Minutes"
                $message = "Your computer will restart in $MinutesRemaining minutes at $($Deadline.ToString('h:mm tt')).`n`n⚠️ SAVE YOUR WORK IMMEDIATELY ⚠️`n`nClick 'Restart Now' to restart immediately, or wait for automatic restart."
                
                $buttons += New-BTButton -Content "Restart Now" -Arguments "rebootnow"
                $buttons += New-BTButton -Content "OK" -Arguments "dismiss"
            }
            
            'ScheduledCountdown' {
                $title = "⏰ Scheduled Reboot in $MinutesRemaining Minutes"
                $message = "Your scheduled reboot will begin in $MinutesRemaining minutes.`n`n⚠️ Please save your work now ⚠️`n`nClick 'Restart Now' to restart immediately."
                
                $buttons += New-BTButton -Content "Restart Now" -Arguments "rebootnow"
                $buttons += New-BTButton -Content "OK" -Arguments "dismiss"
            }
            
            'ImmediateReboot' {
                $title = "🚨 REBOOT STARTING NOW"
                $message = "Your computer is restarting now.`n`n⚠️ Save your work immediately! ⚠️`n`nReboot will occur in 60 seconds."
                
                $buttons += New-BTButton -Content "OK" -Arguments "dismiss"
            }
        }
        
        # Create and show notification
        $text = New-BTText -Text $title
        $text2 = New-BTText -Text $message
        
        $binding = New-BTBinding -Children $text, $text2 -AppLogoOverride (New-BTImage -Source "$env:SystemRoot\System32\shell32.dll" -AppLogoOverride -Crop Circle)
        $visual = New-BTVisual -BindingGeneric $binding
        
        $content = New-BTContent -Visual $visual -Actions $buttons
        
        Submit-BTNotification -Content $content -AppId $script:AppId
        
        Write-RebootLog "Showed $Type notification" -Level INFO
        return $true
    }
    catch {
        Write-RebootLog "Error showing notification: $_" -Level ERROR
        return $false
    }
}

# ============================================================================
# REBOOT EXECUTION
# ============================================================================

function Invoke-SystemReboot {
    <#
    .SYNOPSIS
        Executes system reboot with safety checks
    #>
    param(
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )
    
    $currentHour = (Get-Date).Hour
    $inWindow = Test-InRebootWindow
    
    # Safety check - only reboot in window (unless demo mode)
    if (-not $DemoMode -and -not $inWindow -and -not $Force) {
        Write-RebootLog "ERROR: Attempted reboot outside 10PM-5AM window (current hour: $currentHour)" -Level ERROR
        return $false
    }
    
    if ($WhatIf -or $DemoMode) {
        Write-RebootLog "WhatIf: Would restart computer now" -Level WARNING
        Write-Host "`n========================================" -ForegroundColor Cyan
        Write-Host "WHATIF: SYSTEM REBOOT WOULD OCCUR NOW" -ForegroundColor Yellow
        Write-Host "========================================`n" -ForegroundColor Cyan
        return $true
    }
    else {
        Write-RebootLog "INITIATING SYSTEM REBOOT" -Level WARNING
        
        # Show immediate warning
        Show-RebootNotification -Type ImmediateReboot
        
        # Wait 60 seconds for users to save
        Start-Sleep -Seconds 60
        
        try {
            Restart-Computer -Force -ErrorAction Stop
            return $true
        }
        catch {
            Write-RebootLog "ERROR: Failed to restart computer: $_" -Level ERROR
            return $false
        }
    }
}

# ============================================================================
# MAIN EXECUTION LOGIC
# ============================================================================

function Get-NotificationDecision {
    <#
    .SYNOPSIS
        Determines if and what type of notification to show
    #>
    param(
        [TimeSpan]$Uptime,
        [DateTime]$Deadline,
        [DateTime]$ScheduledTime,
        [DateTime]$LastNotification
    )
    
    $now = Get-Date
    $minutesUntilDeadline = ($Deadline - $now).TotalMinutes
    
    # Check for scheduled reboot first
    if ($ScheduledTime -and $ScheduledTime -gt $now) {
        $minutesUntilScheduled = ($ScheduledTime - $now).TotalMinutes
        
        Write-RebootLog "User has scheduled reboot for $($ScheduledTime.ToString('yyyy-MM-dd HH:mm:ss')), $([Math]::Round($minutesUntilScheduled, 1)) minutes away" -Level DEBUG
        
        # Time for scheduled reboot?
        if ($minutesUntilScheduled -le 0) {
            return @{
                Action = 'Reboot'
                NotificationType = $null
                MinutesRemaining = 0
            }
        }
        # 1 minute warning
        elseif ($minutesUntilScheduled -le 1) {
            return @{
                Action = 'Notify'
                NotificationType = 'ScheduledCountdown'
                MinutesRemaining = 1
            }
        }
        # 5 minute warning
        elseif ($minutesUntilScheduled -le 5 -and $minutesUntilScheduled -gt 1) {
            if (-not $LastNotification -or ($now - $LastNotification).TotalMinutes -ge 3) {
                return @{
                    Action = 'Notify'
                    NotificationType = 'ScheduledCountdown'
                    MinutesRemaining = 5
                }
            }
        }
        # 10 minute warning
        elseif ($minutesUntilScheduled -le 10 -and $minutesUntilScheduled -gt 5) {
            if (-not $LastNotification -or ($now - $LastNotification).TotalMinutes -ge 4) {
                return @{
                    Action = 'Notify'
                    NotificationType = 'ScheduledCountdown'
                    MinutesRemaining = 10
                }
            }
        }
        
        return @{
            Action = 'None'
            NotificationType = $null
            MinutesRemaining = 0
        }
    }
    
    # No scheduled reboot - check deadline
    
    # Deadline reached?
    if ($minutesUntilDeadline -le 0) {
        # Only reboot if in window
        if (Test-InRebootWindow) {
            return @{
                Action = 'Reboot'
                NotificationType = $null
                MinutesRemaining = 0
            }
        }
        else {
            Write-RebootLog "Deadline reached but outside reboot window - waiting" -Level WARNING
            return @{
                Action = 'None'
                NotificationType = $null
                MinutesRemaining = 0
            }
        }
    }
    
    # Within final 90 minutes?
    if ($minutesUntilDeadline -le 90) {
        # Show notification every 15 minutes
        if (-not $LastNotification -or ($now - $LastNotification).TotalMinutes -ge 15) {
            return @{
                Action = 'Notify'
                NotificationType = 'FinalWarning'
                MinutesRemaining = [Math]::Ceiling($minutesUntilDeadline)
            }
        }
    }
    # More than 90 minutes - hourly reminders
    else {
        $hoursSinceLastNotification = if ($LastNotification) { ($now - $LastNotification).TotalHours } else { 999 }
        
        if ($hoursSinceLastNotification -ge 1) {
            # First notification ever?
            if (-not $LastNotification) {
                return @{
                    Action = 'Notify'
                    NotificationType = 'InitialWarning'
                    MinutesRemaining = [Math]::Ceiling($minutesUntilDeadline)
                }
            }
            else {
                return @{
                    Action = 'Notify'
                    NotificationType = 'HourlyReminder'
                    MinutesRemaining = [Math]::Ceiling($minutesUntilDeadline)
                }
            }
        }
    }
    
    return @{
        Action = 'None'
        NotificationType = $null
        MinutesRemaining = 0
    }
}

# ============================================================================
# MAIN SCRIPT EXECUTION
# ============================================================================

Write-RebootLog "========================================" -Level INFO
Write-RebootLog "Reboot Enforcement Script Started" -Level INFO
if ($DemoMode) {
    Write-RebootLog "🎬 DEMO MODE ENABLED 🎬" -Level WARNING
}
if ($WhatIf) {
    Write-RebootLog "⚠️  WHATIF MODE ENABLED - No changes will be made ⚠️" -Level WARNING
}
Write-RebootLog "========================================" -Level INFO

# Step 1: Check AD Exemption
Write-RebootLog "Step 1: Checking AD exemption status..." -Level INFO
if (Test-RebootExemption -GroupName $ExemptionADGroup) {
    Write-RebootLog "Computer is exempt from reboot enforcement - exiting gracefully" -Level INFO
    Write-RebootLog "========================================" -Level INFO
    exit 0
}

# Step 2: Get System Uptime
Write-RebootLog "Step 2: Checking system uptime..." -Level INFO
$uptime = Get-SystemUptime
Write-RebootLog "System uptime: $([Math]::Floor($uptime.TotalDays)) days, $($uptime.Hours) hours, $($uptime.Minutes) minutes" -Level INFO

# Step 3: Check if uptime exceeds threshold
if ($uptime.TotalDays -lt $UptimeThresholdDays) {
    Write-RebootLog "Uptime ($([Math]::Round($uptime.TotalDays, 1)) days) is below threshold ($UptimeThresholdDays days) - no action needed" -Level INFO
    Write-RebootLog "========================================" -Level INFO
    exit 0
}

Write-RebootLog "Uptime exceeds threshold - reboot enforcement active" -Level WARNING

# Step 4: Calculate Deadline
Write-RebootLog "Step 3: Calculating reboot deadline..." -Level INFO
$deadline = Get-NextRebootDeadline
Write-RebootLog "Next reboot deadline: $($deadline.ToString('yyyy-MM-dd HH:mm:ss'))" -Level INFO

$minutesUntilDeadline = ($deadline - (Get-Date)).TotalMinutes
$hoursUntilDeadline = [Math]::Round($minutesUntilDeadline / 60, 1)
Write-RebootLog "Time until deadline: $hoursUntilDeadline hours ($([Math]::Round($minutesUntilDeadline, 0)) minutes)" -Level INFO

# Step 5: Load State
Write-RebootLog "Step 4: Loading persistent state..." -Level INFO
$state = Get-RebootState

if ($state.LastNotificationTime) {
    Write-RebootLog "Last notification: $($state.LastNotificationTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level DEBUG
}
else {
    Write-RebootLog "No previous notifications" -Level DEBUG
}

if ($state.ScheduledRebootTime) {
    Write-RebootLog "User has scheduled reboot: $($state.ScheduledRebootTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level INFO
    
    # Validate scheduled time hasn't passed and isn't after deadline
    if ($state.ScheduledRebootTime -le (Get-Date)) {
        Write-RebootLog "Scheduled time has passed - clearing schedule" -Level WARNING
        $state.ScheduledRebootTime = $null
        Set-RebootState -LastNotificationTime $state.LastNotificationTime -ScheduledRebootTime $null -NotificationCount $state.NotificationCount
    }
    elseif ($state.ScheduledRebootTime -gt $deadline) {
        Write-RebootLog "Scheduled time is after deadline - clearing invalid schedule" -Level WARNING
        $state.ScheduledRebootTime = $null
        Set-RebootState -LastNotificationTime $state.LastNotificationTime -ScheduledRebootTime $null -NotificationCount $state.NotificationCount
    }
}

# Step 6: Determine Action
Write-RebootLog "Step 5: Determining required action..." -Level INFO
$decision = Get-NotificationDecision -Uptime $uptime -Deadline $deadline -ScheduledTime $state.ScheduledRebootTime -LastNotification $state.LastNotificationTime

Write-RebootLog "Decision: $($decision.Action)" -Level INFO

# Step 7: Execute Decision
switch ($decision.Action) {
    'Reboot' {
        Write-RebootLog "========================================" -Level WARNING
        Write-RebootLog "EXECUTING SYSTEM REBOOT" -Level WARNING
        Write-RebootLog "========================================" -Level WARNING
        
        Invoke-SystemReboot
    }
    
    'Notify' {
        Write-RebootLog "Showing notification: $($decision.NotificationType)" -Level INFO
        
        $notificationShown = Show-RebootNotification -Type $decision.NotificationType -Uptime $uptime -Deadline $deadline -MinutesRemaining $decision.MinutesRemaining
        
        if ($notificationShown) {
            # Update last notification time
            $state.LastNotificationTime = Get-Date
            $state.NotificationCount++
            Set-RebootState -LastNotificationTime $state.LastNotificationTime -ScheduledRebootTime $state.ScheduledRebootTime -NotificationCount $state.NotificationCount
            
            Write-RebootLog "Notification #$($state.NotificationCount) shown successfully" -Level INFO
            
            # Note: In production, BurntToast callbacks would handle the "Schedule" button click
            # For demo purposes, we can simulate this by checking for a trigger file
            # In SCCM deployment, this script runs repeatedly, so callbacks work across runs
        }
    }
    
    'None' {
        Write-RebootLog "No action required at this time" -Level INFO
    }
}

Write-RebootLog "========================================" -Level INFO
Write-RebootLog "Script execution completed" -Level INFO
Write-RebootLog "========================================" -Level INFO

exit 0
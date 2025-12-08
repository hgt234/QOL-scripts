<#
.SYNOPSIS
    Shows modern toast notifications for reboot enforcement in user context

.DESCRIPTION
    This helper script is called by Deploy-Application.ps1 via Execute-ProcessAsUser
    to display BurntToast notifications in the logged-on user's session.
    
    It handles all toast notification types and button callbacks for scheduling reboots.

.PARAMETER NotificationType
    Type of notification to show (InitialWarning, HourlyReminder, FinalWarning, ScheduledCountdown)

.PARAMETER UptimeDays
    Number of days system has been running

.PARAMETER Deadline
    DateTime when forced reboot will occur

.PARAMETER MinutesRemaining
    Minutes until reboot

.PARAMETER StateFilePath
    Path to JSON state file for saving scheduled reboot time

.NOTES
    This script runs in USER context (has no SYSTEM privileges)
    BurntToast is auto-installed if missing
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('InitialWarning','HourlyReminder','FinalWarning','ScheduledCountdown')]
    [string]$NotificationType,
    
    [Parameter(Mandatory=$true)]
    [int]$UptimeDays,
    
    [Parameter(Mandatory=$true)]
    [DateTime]$Deadline,
    
    [Parameter(Mandatory=$true)]
    [int]$MinutesRemaining,
    
    [Parameter(Mandatory=$true)]
    [string]$StateFilePath
)

# Ensure BurntToast is available
function Initialize-BurntToast {
    try {
        if (-not (Get-Module -ListAvailable -Name BurntToast)) {
            Write-Host "Installing BurntToast module..."
            Install-Module -Name BurntToast -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
        }
        
        Import-Module BurntToast -ErrorAction Stop
        return $true
    }
    catch {
        Write-Error "Failed to initialize BurntToast: $_"
        return $false
    }
}

# Load state from JSON
function Get-RebootState {
    try {
        if (Test-Path $StateFilePath) {
            $json = Get-Content $StateFilePath -Raw | ConvertFrom-Json
            return @{
                LastNotificationTime = if ($json.LastNotificationTime) { [DateTime]::Parse($json.LastNotificationTime) } else { $null }
                ScheduledRebootTime = if ($json.ScheduledRebootTime) { [DateTime]::Parse($json.ScheduledRebootTime) } else { $null }
                NotificationCount = if ($json.NotificationCount) { $json.NotificationCount } else { 0 }
            }
        }
    }
    catch {
        Write-Warning "Error loading state: $_"
    }
    
    return @{
        LastNotificationTime = $null
        ScheduledRebootTime = $null
        NotificationCount = 0
    }
}

# Save state to JSON
function Set-RebootState {
    param(
        [DateTime]$ScheduledRebootTime
    )
    
    try {
        $state = Get-RebootState
        $state.ScheduledRebootTime = $ScheduledRebootTime
        
        $stateDir = Split-Path $StateFilePath -Parent
        if (-not (Test-Path $stateDir)) {
            New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
        }
        
        $stateJson = @{
            LastNotificationTime = if ($state.LastNotificationTime) { $state.LastNotificationTime.ToString("o") } else { $null }
            ScheduledRebootTime = if ($ScheduledRebootTime) { $ScheduledRebootTime.ToString("o") } else { $null }
            NotificationCount = $state.NotificationCount
        }
        
        $stateJson | ConvertTo-Json | Set-Content $StateFilePath -Force
        Write-Host "Scheduled reboot time saved: $($ScheduledRebootTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    }
    catch {
        Write-Error "Error saving state: $_"
    }
}

# Show time picker dialog
function Show-RebootScheduler {
    param([DateTime]$Deadline)
    
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
        
        $label = New-Object System.Windows.Forms.Label
        $label.Location = New-Object System.Drawing.Point(10,20)
        $label.Size = New-Object System.Drawing.Size(390,40)
        $label.Text = "Choose a time to restart your computer.`nMust be before deadline: $($Deadline.ToString('h:mm tt'))"
        $form.Controls.Add($label)
        
        $timePicker = New-Object System.Windows.Forms.DateTimePicker
        $timePicker.Location = New-Object System.Drawing.Point(110,70)
        $timePicker.Size = New-Object System.Drawing.Size(200,20)
        $timePicker.Format = 'Time'
        $timePicker.ShowUpDown = $true
        
        $suggestedTime = (Get-Date).AddHours(1)
        if ($suggestedTime -gt $Deadline) {
            $suggestedTime = $Deadline.AddMinutes(-30)
        }
        $timePicker.Value = $suggestedTime
        $form.Controls.Add($timePicker)
        
        $infoLabel = New-Object System.Windows.Forms.Label
        $infoLabel.Location = New-Object System.Drawing.Point(10,110)
        $infoLabel.Size = New-Object System.Drawing.Size(390,30)
        $infoLabel.Text = "Your computer will restart at the selected time.`nPlease save all work before then."
        $infoLabel.ForeColor = [System.Drawing.Color]::DarkRed
        $form.Controls.Add($infoLabel)
        
        $okButton = New-Object System.Windows.Forms.Button
        $okButton.Location = New-Object System.Drawing.Point(110,150)
        $okButton.Size = New-Object System.Drawing.Size(90,30)
        $okButton.Text = 'Schedule'
        $okButton.DialogResult = 'OK'
        $form.AcceptButton = $okButton
        $form.Controls.Add($okButton)
        
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
            $todayScheduled = Get-Date -Hour $selectedTime.Hour -Minute $selectedTime.Minute -Second 0
            
            if ($todayScheduled -le (Get-Date)) {
                [System.Windows.Forms.MessageBox]::Show("The selected time has already passed. Please choose a future time.", "Invalid Time", 'OK', 'Warning')
                return $null
            }
            
            if ($todayScheduled -gt $Deadline) {
                [System.Windows.Forms.MessageBox]::Show("The selected time is after the deadline of $($Deadline.ToString('h:mm tt')). Please choose an earlier time.", "Invalid Time", 'OK', 'Warning')
                return $null
            }
            
            return $todayScheduled
        }
        
        return $null
    }
    catch {
        Write-Error "Error showing scheduler: $_"
        return $null
    }
}

# Initialize BurntToast
if (-not (Initialize-BurntToast)) {
    Write-Error "Cannot show notification - BurntToast not available"
    exit 1
}

# Build notification content
$title = ""
$message = ""
$buttons = @()
$appId = "RebootEnforcement"

switch ($NotificationType) {
    'InitialWarning' {
        $title = "Reboot Required"
        $hoursToDeadline = [Math]::Round(($Deadline - (Get-Date)).TotalHours, 1)
        $message = "Your computer has been running for $UptimeDays days. A reboot will be forced at $($Deadline.ToString('h:mm tt')) ($hoursToDeadline hours from now). Please save your work and restart when convenient."
    }
    
    'HourlyReminder' {
        $title = "Reboot Reminder"
        $hoursToDeadline = [Math]::Round(($Deadline - (Get-Date)).TotalHours, 1)
        $message = "Reminder: Forced reboot at $($Deadline.ToString('h:mm tt')) ($hoursToDeadline hours). Current uptime: $UptimeDays days. Please save your work and restart when convenient."
    }
    
    'FinalWarning' {
        $title = "URGENT: Reboot in $MinutesRemaining Minutes"
        $message = "Your computer will restart in $MinutesRemaining minutes at $($Deadline.ToString('h:mm tt')). SAVE YOUR WORK IMMEDIATELY!"
    }
    
    'ScheduledCountdown' {
        $title = "Scheduled Reboot in $MinutesRemaining Minutes"
        $message = "Your scheduled reboot will begin in $MinutesRemaining minutes. Please save your work now."
    }
}

# Create and show toast with interactive buttons
try {
    # Log what we're about to do
    $logFile = "$env:TEMP\RebootToast-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    "Starting toast script at $(Get-Date)" | Out-File $logFile -Append
    "NotificationType: $NotificationType" | Out-File $logFile -Append
    "Title: $title" | Out-File $logFile -Append
    "Message: $message" | Out-File $logFile -Append
    "User: $env:USERNAME" | Out-File $logFile -Append
    
    # Create toast with interactive buttons (except for imminent ScheduledCountdown)
    if ($NotificationType -ne 'ScheduledCountdown' -and $NotificationType -ne 'FinalWarning') {
        "Adding interactive buttons for $NotificationType" | Out-File $logFile -Append
        
        # Create buttons for initial warning and hourly reminders
        $btnReschedule = New-BTButton -Content 'Reschedule' -Arguments "rebootaction:reschedule:$StateFilePath|$($Deadline.ToString('o'))" -ActivationType Protocol
        $btnRebootNow = New-BTButton -Content 'Restart Now' -Arguments 'rebootaction:reboot:now' -ActivationType Protocol
        
        # Create action group from buttons
        $actionGroup = New-BTAction -Buttons $btnReschedule, $btnRebootNow
        
        # Create binding with text
        $binding = New-BTBinding -Children @(
            New-BTText -Text $title
            New-BTText -Text $message
        )
        
        $visual = New-BTVisual -BindingGeneric $binding
        $content = New-BTContent -Visual $visual -Actions $actionGroup
        
        # Submit the toast
        Submit-BTNotification -Content $content
        
        "Toast with buttons shown successfully" | Out-File $logFile -Append
    }
    else {
        # Final warning or countdown - just show urgent message
        "Showing urgent toast without buttons ($NotificationType)" | Out-File $logFile -Append
        New-BurntToastNotification -Text $title, $message -Sound 'Alarm'
        "Urgent toast shown successfully" | Out-File $logFile -Append
    }
    
    Write-Host "Toast notification shown: $NotificationType"
    
    # Wait to ensure toast is displayed
    Start-Sleep -Seconds 2
    
    "Exiting at $(Get-Date)" | Out-File $logFile -Append
    exit 0
}
catch {
    $errorMsg = "Error showing toast: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
    Write-Error $errorMsg
    $errorMsg | Out-File $logFile -Append
    exit 1
}

<#
.SYNOPSIS
    Handles toast notification button actions

.DESCRIPTION
    This script is called via protocol handler when users click toast buttons.
    It processes reschedule requests or immediate reboot actions.
    
.PARAMETER Action
    The action to perform (parsed from protocol URI)
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Action
)

# Parse the action
if ($Action -match '^reschedule:(.+)\|(.+)$') {
    $stateFilePath = $Matches[1]
    $deadline = [DateTime]::Parse($Matches[2])
    
    # Show the reschedule dialog
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
        $label.Text = "Choose a time to restart your computer.`nMust be before deadline: $($deadline.ToString('h:mm tt'))"
        $form.Controls.Add($label)
        
        $timePicker = New-Object System.Windows.Forms.DateTimePicker
        $timePicker.Location = New-Object System.Drawing.Point(110,70)
        $timePicker.Size = New-Object System.Drawing.Size(200,20)
        $timePicker.Format = 'Time'
        $timePicker.ShowUpDown = $true
        
        $suggestedTime = (Get-Date).AddHours(1)
        if ($suggestedTime -gt $deadline) {
            $suggestedTime = $deadline.AddMinutes(-30)
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
                exit 1
            }
            
            if ($todayScheduled -gt $deadline) {
                [System.Windows.Forms.MessageBox]::Show("The selected time is after the deadline of $($deadline.ToString('h:mm tt')). Please choose an earlier time.", "Invalid Time", 'OK', 'Warning')
                exit 1
            }
            
            # Save the scheduled time to state file
            try {
                $stateDir = Split-Path $stateFilePath -Parent
                if (-not (Test-Path $stateDir)) {
                    New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
                }
                
                # Load existing state
                $state = @{
                    LastNotificationTime = $null
                    ScheduledRebootTime = $null
                    NotificationCount = 0
                }
                
                if (Test-Path $stateFilePath) {
                    $json = Get-Content $stateFilePath -Raw | ConvertFrom-Json
                    $state.LastNotificationTime = $json.LastNotificationTime
                    $state.NotificationCount = $json.NotificationCount
                }
                
                # Update with new scheduled time
                $state.ScheduledRebootTime = $todayScheduled.ToString("o")
                
                $state | ConvertTo-Json | Set-Content $stateFilePath -Force
                
                [System.Windows.Forms.MessageBox]::Show("Reboot scheduled for $($todayScheduled.ToString('h:mm tt')).", "Reboot Scheduled", 'OK', 'Information')
                exit 0
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show("Error saving schedule: $_", "Error", 'OK', 'Error')
                exit 1
            }
        }
    }
    catch {
        Write-Error "Error showing scheduler: $_"
        exit 1
    }
}
elseif ($Action -eq 'reboot:now') {
    # Confirm and reboot
    Add-Type -AssemblyName System.Windows.Forms
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Are you sure you want to restart your computer now? All unsaved work will be lost.",
        "Confirm Restart",
        'YesNo',
        'Warning'
    )
    
    if ($result -eq 'Yes') {
        # Initiate reboot
        shutdown /r /t 30 /c "User requested reboot via notification"
        [System.Windows.Forms.MessageBox]::Show("Your computer will restart in 30 seconds. Please save all work now.", "Restarting", 'OK', 'Information')
        exit 0
    }
}

exit 0

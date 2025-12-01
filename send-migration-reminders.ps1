param(
    [Parameter(Mandatory=$true)]
    [string]$UserListFile,
    
    [Parameter(Mandatory=$false)]
    [int]$ReminderDaysThreshold = 7,  # Send reminder if deadline is within this many days
    
    [switch]$WhatIf
)

<#
.SYNOPSIS
    Sends migration reminder emails to users based on W11MigrationDeadline tag

.DESCRIPTION
    This script processes a file containing usernames and old VM names to:
    - Look up the W11MigrationDeadline tag on each old VM
    - Calculate days remaining until deadline
    - Send reminder emails to users if deadline is approaching

.PARAMETER UserListFile
    Path to CSV or text file with user assignments.
    Format: Username,RITMNumber,OldVMName (one per line)
    Example:
        john.doe@contoso.com,1234567,OLDVM-0
        jane.smith@contoso.com,7654321,OLDVM2-0

.PARAMETER ReminderDaysThreshold
    Send reminders if deadline is within this many days (default: 7)

.PARAMETER WhatIf
    Preview the emails without sending them

.EXAMPLE
    .\send-migration-reminders.ps1 -UserListFile "users.csv"1
    
.EXAMPLE
    .\send-migration-reminders.ps1 -UserListFile "users.csv" -ReminderDaysThreshold 3 -WhatIf
#>

# ============================================================================
# CONFIGURATION - Update these values for your environment
# ============================================================================
##
# Azure Key Vault
$keyVaultName = "my-keyvault"

# Old VM Configuration
$oldVMResourceGroup = "current-rg"  # Resource group where old VMs are located
$oldVMSubscriptionId = "00000000-0000-0000-0000-000000000000"  # Subscription ID for old VMs

# Tag Configuration
$migrationDeadlineTag = "W11MigrationDeadline"

# SMTP Configuration
$smtpServer = "smtp.contoso.com"
$smtpPort = 25
$smtpFrom = "AVD-Support@contoso.com"
$smtpUseSsl = $false
$smtpUseCredentials = $false  # Set to $true if SMTP requires authentication

# Email Subject
$emailSubject = "⏰ Reminder: Windows 11 Migration Deadline Approaching"

# Email Body Template (HTML)
$emailBodyTemplate = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { background-color: #d83b01; color: white; padding: 20px; text-align: center; border-radius: 5px 5px 0 0; }
        .content { background-color: #f5f5f5; padding: 30px; border-radius: 0 0 5px 5px; }
        .warning-box { background-color: #fff4ce; padding: 15px; margin: 15px 0; border-left: 4px solid #d83b01; }
        .info-box { background-color: white; padding: 15px; margin: 15px 0; border-left: 4px solid #0078d4; }
        .footer { text-align: center; margin-top: 20px; font-size: 12px; color: #666; }
        h1 { margin: 0; font-size: 24px; }
        h2 { color: #d83b01; font-size: 18px; }
        .deadline { font-size: 20px; font-weight: bold; color: #d83b01; }
        .button { display: inline-block; padding: 12px 24px; background-color: #0078d4; color: white; text-decoration: none; border-radius: 4px; margin: 10px 0; }
        ul { padding-left: 20px; }
        li { margin: 8px 0; }
        .success { color: #107c10; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>⏰ Migration Deadline Reminder</h1>
        </div>
        <div class="content">
            <p>Hello <strong>{{USERNAME}}</strong>,</p>
            
            <p>This is a friendly reminder that your Windows 11 migration deadline is approaching.</p>
            
            <div class="warning-box">
                <h2>⚠️ Action Required</h2>
                <p>Your current virtual machine <strong>{{OLDVMNAME}}</strong> is scheduled for migration.</p>
                <p class="deadline">Migration Deadline: {{DEADLINE}}</p>
                <p>Days Remaining: <strong>{{DAYSREMAINING}}</strong></p>
            </div>
            
            <div class="info-box">
                <h2>📋 What You Need to Know</h2>
                <ul>
                    <li><strong>New VM Name:</strong> {{NEWVMNAME}}</li>
                    <li><strong>RITM Number:</strong> {{RITM}}</li>
                    <li><strong>Old VM:</strong> {{OLDVMNAME}}</li>
                </ul>
            </div>
            
            <div class="warning-box">
                <h2>⚠️ Important: System Deactivation</h2>
                <p><strong>Your old virtual desktop ({{OLDVMNAME}}) will be disabled after the deadline.</strong></p>
                <p>After {{DEADLINE}}, you will no longer be able to access your current system. Please ensure you have transitioned to your new Windows 11 desktop before this date.</p>
            </div>
            
            <div class="info-box">
                <p class="success">✅ If you have already started using your new Windows 11 desktop, you can safely ignore this reminder. The migration process is automated.</p>
            </div>
            
            <h2>❓ Need Help?</h2>
            <p>If you have questions or concerns about the migration, please contact IT Support:</p>
            <ul>
                <li>📧 Email: support@contoso.com</li>
                <li>📞 Phone: 1-800-123-4567</li>
                <li>🎫 ServiceNow: Reference RITM {{RITM}}</li>
            </ul>
            
            <p><strong>Important:</strong> Please ensure you save any work and log off from your current desktop before the deadline to ensure a smooth transition.</p>
            
            <div class="footer">
                <p>This is an automated reminder. Please do not reply to this email.</p>
                <p>&copy; 2025 Contoso Corporation. All rights reserved.</p>
            </div>
        </div>
    </div>
</body>
</html>
"@

# ============================================================================
# SCRIPT EXECUTION - Do not modify below this line unless needed
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Windows 11 Migration Reminder System" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Mode: $(if ($WhatIf) { 'What-If (Preview)' } else { 'Execute' })"
Write-Host "User List File: $UserListFile"
Write-Host "Reminder Threshold: $ReminderDaysThreshold days"
Write-Host "========================================`n" -ForegroundColor Cyan

# Validate file exists
if (-not (Test-Path $UserListFile)) {
    Write-Error "User list file not found: $UserListFile"
    exit 1
}

# Ensure Az module is installed
if (-not (Get-Module -ListAvailable -Name Az)) {
    Write-Host "Installing Az PowerShell module..."
    Install-Module -Name Az -AllowClobber -Force -Scope CurrentUser
}
Import-Module Az

# Connect to Azure
$context = Get-AzContext
if (-not $context) {
    Write-Host "Connecting to Azure..."
    Connect-AzAccount
    $context = Get-AzContext
}
Write-Host "Connected to Azure subscription: $($context.Subscription.Name)`n"

# ============================================================================
# Load user assignments from file
# ============================================================================
Write-Host "[Step 1] Loading user assignments from file..." -ForegroundColor Yellow

$userAssignments = @()
$fileContent = Get-Content $UserListFile

foreach ($line in $fileContent) {
    $line = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
        continue  # Skip empty lines and comments
    }
    
    # Parse CSV format: Username,RITMNumber,OldVMName
    $parts = $line -split '[,;\t]'  # Support comma, semicolon, or tab delimiters
    if ($parts.Count -ge 3) {
        $username = $parts[0].Trim()
        $ritmNumber = $parts[1].Trim() -replace '^RITM', ''  # Remove RITM prefix if present
        $oldVMName = $parts[2].Trim()
        
        if ($ritmNumber -match '^\d+$') {
            $newVMName = "AVDRITM$ritmNumber-0"
            $userAssignments += [PSCustomObject]@{
                Username    = $username
                RITMNumber  = $ritmNumber
                OldVMName   = $oldVMName
                NewVMName   = $newVMName
            }
        }
        else {
            Write-Warning "Invalid RITM number on line: $line (skipping)"
        }
    }
    else {
        Write-Warning "Invalid format on line: $line (expected: Username,RITMNumber,OldVMName)"
    }
}

if ($userAssignments.Count -eq 0) {
    Write-Error "No valid user assignments found in file."
    exit 1
}

Write-Host "✓ Loaded $($userAssignments.Count) user assignments`n" -ForegroundColor Green

# ============================================================================
# Retrieve SMTP credentials from Key Vault (if needed)
# ============================================================================
if ($smtpUseCredentials) {
    Write-Host "[Step 2] Retrieving SMTP credentials from Key Vault..." -ForegroundColor Yellow
    try {
        $smtpUsername = (Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "smtpUsername" -AsPlainText -ErrorAction Stop)
        $smtpPassword = (Get-AzKeyVaultSecret -VaultName $keyVaultName -Name "smtpPassword" -AsPlainText -ErrorAction Stop)
        $smtpSecurePassword = ConvertTo-SecureString $smtpPassword -AsPlainText -Force
        $smtpCredential = New-Object System.Management.Automation.PSCredential($smtpUsername, $smtpSecurePassword)
        Write-Host "✓ SMTP credentials retrieved successfully`n" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to retrieve SMTP credentials from Key Vault: $_"
        exit 1
    }
}

# ============================================================================
# Switch to old VM subscription and check tags
# ============================================================================
Write-Host "[Step 3] Switching to old VM subscription..." -ForegroundColor Yellow
try {
    Set-AzContext -SubscriptionId $oldVMSubscriptionId -ErrorAction Stop | Out-Null
    Write-Host "✓ Context switched to old VM subscription`n" -ForegroundColor Green
}
catch {
    Write-Error "Failed to switch to old VM subscription: $_"
    exit 1
}

# ============================================================================
# Check migration deadlines and prepare reminder list
# ============================================================================
Write-Host "[Step 4] Checking migration deadlines..." -ForegroundColor Yellow

$reminderList = @()
$today = Get-Date
$noTagCount = 0
$notDueCount = 0

foreach ($assignment in $userAssignments) {
    Write-Host "  Checking: $($assignment.OldVMName)..." -NoNewline
    
    try {
        $vm = Get-AzVM -ResourceGroupName $oldVMResourceGroup -Name $assignment.OldVMName -ErrorAction Stop
        
        if ($vm.Tags -and $vm.Tags.ContainsKey($migrationDeadlineTag)) {
            $deadlineString = $vm.Tags[$migrationDeadlineTag]
            $deadline = [DateTime]::Parse($deadlineString)
            $daysRemaining = ($deadline - $today).Days
            
            Write-Host " Deadline: $($deadline.ToString('yyyy-MM-dd')) ($daysRemaining days)" -ForegroundColor Cyan
            
            # Check if reminder should be sent
            if ($daysRemaining -le $ReminderDaysThreshold -and $daysRemaining -ge 0) {
                $reminderList += [PSCustomObject]@{
                    Username       = $assignment.Username
                    RITMNumber     = $assignment.RITMNumber
                    OldVMName      = $assignment.OldVMName
                    NewVMName      = $assignment.NewVMName
                    Deadline       = $deadline
                    DeadlineString = $deadline.ToString('MMMM dd, yyyy')
                    DaysRemaining  = $daysRemaining
                    EmailSent      = $false
                    Success        = $false
                    ErrorMessage   = ""
                }
                Write-Host "    → Will send reminder" -ForegroundColor Yellow
            }
            else {
                $notDueCount++
                Write-Host "    → Not yet due for reminder" -ForegroundColor Green
            }
        }
        else {
            $noTagCount++
            Write-Host " ⚠️  No migration deadline tag found" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host " ✗ Failed to retrieve VM: $_" -ForegroundColor Red
    }
}

Write-Host "`n✓ Checked $($userAssignments.Count) VMs" -ForegroundColor Green
Write-Host "  - Reminders to send: $($reminderList.Count)" -ForegroundColor Yellow
Write-Host "  - Not yet due: $notDueCount" -ForegroundColor Green
Write-Host "  - No tag found: $noTagCount`n" -ForegroundColor $(if ($noTagCount -gt 0) { 'Yellow' } else { 'Green' })

if ($reminderList.Count -eq 0) {
    Write-Host "✅ No reminder emails need to be sent at this time." -ForegroundColor Green
    exit 0
}

# Display reminder list
Write-Host "Users to be notified:" -ForegroundColor Cyan
$reminderList | Format-Table -AutoSize Username, OldVMName, DeadlineString, DaysRemaining
Write-Host ""

if ($WhatIf) {
    Write-Host "WhatIf mode: No emails will be sent`n" -ForegroundColor Yellow
}

# ============================================================================
# Send reminder emails
# ============================================================================
Write-Host "[Step 5] Sending reminder emails..." -ForegroundColor Yellow

$sentCount = 0
$failCount = 0

foreach ($reminder in $reminderList) {
    Write-Host "  Sending to: $($reminder.Username)..." -NoNewline
    
    try {
        # Personalize email body
        $personalizedBody = $emailBodyTemplate `
            -replace '{{USERNAME}}', $reminder.Username `
            -replace '{{OLDVMNAME}}', $reminder.OldVMName `
            -replace '{{NEWVMNAME}}', $reminder.NewVMName `
            -replace '{{RITM}}', $reminder.RITMNumber `
            -replace '{{DEADLINE}}', $reminder.DeadlineString `
            -replace '{{DAYSREMAINING}}', $reminder.DaysRemaining
        
        if (-not $WhatIf) {
            $mailParams = @{
                From       = $smtpFrom
                To         = $reminder.Username
                Subject    = $emailSubject
                Body       = $personalizedBody
                BodyAsHtml = $true
                SmtpServer = $smtpServer
                Port       = $smtpPort
                UseSsl     = $smtpUseSsl
            }
            
            if ($smtpUseCredentials) {
                $mailParams.Credential = $smtpCredential
            }
            
            Send-MailMessage @mailParams -ErrorAction Stop
            Write-Host " ✓ Email sent" -ForegroundColor Green
            $reminder.EmailSent = $true
            $reminder.Success = $true
            $sentCount++
        }
        else {
            Write-Host " [WhatIf] Would send email" -ForegroundColor Cyan
            $reminder.EmailSent = $true
            $reminder.Success = $true
            $sentCount++
        }
    }
    catch {
        Write-Host " ✗ Failed: $_" -ForegroundColor Red
        $reminder.ErrorMessage = $_.Exception.Message
        $failCount++
    }
}

# ============================================================================
# SUMMARY REPORT
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "REMINDER EMAIL SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total VMs Checked:      $($userAssignments.Count)"
Write-Host "Reminders Needed:       $($reminderList.Count)"
Write-Host "Emails Sent:            $sentCount" -ForegroundColor $(if ($sentCount -gt 0) { 'Green' } else { 'Yellow' })
Write-Host "Failed:                 $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "========================================`n" -ForegroundColor Cyan

# Display detailed results
if ($reminderList.Count -gt 0) {
    Write-Host "Detailed Results:" -ForegroundColor Cyan
    $reminderList | Format-Table -AutoSize Username, OldVMName, DaysRemaining, EmailSent, Success
}

# Show failures with details
$failures = $reminderList | Where-Object { -not $_.Success }
if ($failures.Count -gt 0) {
    Write-Host "`nFailure Details:" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host "  ❌ $($failure.Username) ($($failure.OldVMName)): $($failure.ErrorMessage)" -ForegroundColor Red
    }
    Write-Host ""
}

# Export results to CSV
if ($reminderList.Count -gt 0) {
    $resultFile = "migration-reminders-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    $reminderList | Export-Csv -Path $resultFile -NoTypeInformation
    Write-Host "Results exported to: $resultFile`n" -ForegroundColor Yellow
}

if (-not $WhatIf) {
    Write-Host "✅ Reminder email process completed!" -ForegroundColor Green
}
else {
    Write-Host "ℹ️  WhatIf mode completed. No emails were sent." -ForegroundColor Yellow
    Write-Host "   Run without -WhatIf to send the reminder emails.`n" -ForegroundColor Yellow
}

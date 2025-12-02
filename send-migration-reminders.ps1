param(
    [Parameter(Mandatory=$true)]
    [string]$UserListFile,
    
    [Parameter(Mandatory=$false)]
    [int]$ReminderDaysThreshold = 7,  # Send reminder if deadline is within this many days
    
    [Parameter(Mandatory=$false)]
    [int]$RemovalGracePeriod = 1,  # Remove user access this many days after deadline
    
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

.PARAMETER RemovalGracePeriod
    Remove user access this many days after deadline (default: 1)

.PARAMETER WhatIf
    Preview the emails without sending them

.EXAMPLE
    .\send-migration-reminders.ps1 -UserListFile "users.csv"
    
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

# AVD Host Pool Configuration
$hostPoolName = "your-hostpool-name"  # Name of the AVD host pool
$hostPoolResourceGroup = "current-rg"  # Resource group where host pool is located

# Tag Configuration
$migrationDeadlineTag = "W11MigrationDeadline"

# SMTP Configuration
$smtpServer = "smtp.contoso.com"
$smtpPort = 25
$smtpFrom = "AVD-Support@contoso.com"
$smtpUseSsl = $false
$smtpUseCredentials = $false  # Set to $true if SMTP requires authentication

# Email Subject
$emailSubject = "Reminder: Windows 11 Migration Deadline Approaching"

# Email Body Template (HTML)
$emailBodyTemplate = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 0; background-color: #e6ecf0; font-family: 'Segoe UI', Arial, sans-serif;">
    <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #e6ecf0; margin: 0; padding: 0;">
        <tr>
            <td align="center" style="padding: 30px 15px;">
                <table width="650" cellpadding="0" cellspacing="0" border="0" style="max-width: 650px; background-color: #ffffff; border-radius: 12px; box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);">
                    <!-- Header -->
                    <tr>
                        <td style="background-color: #d83b01; padding: 40px 20px; text-align: center; border-radius: 12px 12px 0 0;">
                            <h1 style="margin: 0; font-size: 28px; font-weight: 600; color: #ffffff;">Migration Deadline Reminder</h1>
                        </td>
                    </tr>
                    
                    <!-- Content -->
                    <tr>
                        <td style="padding: 40px 30px; line-height: 1.8; color: #1a1a1a;">
                            <table width="590" cellpadding="0" cellspacing="0" border="0" style="width: 590px;">
                                <tr>
                                    <td>
                                        <p style="font-size: 16px; margin: 10px 0;">Hello <strong>{{USERNAME}}</strong>,</p>
                                        
                                        <p style="font-size: 16px; margin: 10px 0;">This is a friendly reminder that your Windows 11 migration deadline is approaching.</p>
                                    </td>
                                </tr>
                            </table>
                            
                            <!-- Warning Box -->
                            <table width="590" cellpadding="0" cellspacing="0" border="0" style="width: 590px; margin: 20px 0;">
                                <tr>
                                    <td style="background-color: #fff4ce; padding: 20px; border-left: 4px solid #d83b01;">
                                        <h2 style="color: #d83b01; font-size: 22px; margin: 0 0 10px 0; font-weight: 600;">Action Required</h2>
                                        <p style="font-size: 16px; margin: 10px 0;">Your current virtual machine <strong>{{OLDVMNAME}}</strong> is scheduled for migration.</p>
                                        <p style="font-size: 20px; font-weight: bold; color: #d83b01; margin: 10px 0;">Migration Deadline: {{DEADLINE}}</p>
                                        <p style="font-size: 16px; margin: 10px 0;">Days Remaining: <strong>{{DAYSREMAINING}}</strong></p>
                                    </td>
                                </tr>
                            </table>
                            
                            <!-- Info Box -->
                            <table width="590" cellpadding="0" cellspacing="0" border="0" style="width: 590px; margin: 20px 0;">
                                <tr>
                                    <td style="background-color: #f0f6ff; padding: 20px; border-left: 4px solid #0078d4;">
                                        <h2 style="color: #d83b01; font-size: 22px; margin: 0 0 10px 0; font-weight: 600;">What You Need to Know</h2>
                                        <ul style="margin: 15px 0; padding-left: 25px;">
                                            <li style="margin-bottom: 12px; font-size: 16px;"><strong>New VM Name:</strong> {{NEWVMNAME}}</li>
                                            <li style="margin-bottom: 12px; font-size: 16px;"><strong>RITM Number:</strong> {{RITM}}</li>
                                            <li style="margin-bottom: 12px; font-size: 16px;"><strong>Old VM:</strong> {{OLDVMNAME}}</li>
                                        </ul>
                                    </td>
                                </tr>
                            </table>
                            
                            <!-- Warning Box 2 -->
                            <table width="590" cellpadding="0" cellspacing="0" border="0" style="width: 590px; margin: 20px 0;">
                                <tr>
                                    <td style="background-color: #fff4ce; padding: 20px; border-left: 4px solid #d83b01;">
                                        <h2 style="color: #d83b01; font-size: 22px; margin: 0 0 10px 0; font-weight: 600;">Important: System Deactivation</h2>
                                        <p style="font-size: 16px; margin: 10px 0;"><strong>Your old virtual desktop ({{OLDVMNAME}}) will be disabled after the deadline.</strong></p>
                                        <p style="font-size: 16px; margin: 10px 0;">After {{DEADLINE}}, you will no longer be able to access your current system. Please ensure you have transitioned to your new Windows 11 desktop before this date.</p>
                                    </td>
                                </tr>
                            </table>
                            
                            <!-- Info Box 2 -->
                            <table width="590" cellpadding="0" cellspacing="0" border="0" style="width: 590px; margin: 20px 0;">
                                <tr>
                                    <td style="background-color: #f0f6ff; padding: 20px; border-left: 4px solid #0078d4;">
                                        <p style="color: #107c10; font-weight: 600; font-size: 16px; margin: 10px 0;">If you have already started using your new Windows 11 desktop, you can safely ignore this reminder. The migration process is automated.</p>
                                    </td>
                                </tr>
                            </table>
                            
                            <table width="590" cellpadding="0" cellspacing="0" border="0" style="width: 590px;">
                                <tr>
                                    <td>
                                        <h2 style="color: #d83b01; font-size: 22px; margin: 20px 0 10px 0; font-weight: 600; border-left: 4px solid #d83b01; padding-left: 10px;">Need Help?</h2>
                                        <p style="font-size: 16px; margin: 10px 0;">If you have questions or concerns about the migration, please contact IT Support:</p>
                                        <ul style="margin: 15px 0; padding-left: 25px;">
                                            <li style="margin-bottom: 12px; font-size: 16px;"><strong>Email:</strong> support@contoso.com</li>
                                            <li style="margin-bottom: 12px; font-size: 16px;"><strong>Phone:</strong> 1-800-123-4567</li>
                                            <li style="margin-bottom: 12px; font-size: 16px;"><strong>ServiceNow:</strong> Reference RITM {{RITM}}</li>
                                        </ul>
                                        
                                        <p style="font-size: 16px; margin: 10px 0;"><strong>Important:</strong> Please ensure you save any work and log off from your current desktop before the deadline to ensure a smooth transition.</p>
                                    </td>
                                </tr>
                            </table>
                        </td>
                    </tr>
                    
                    <!-- Footer -->
                    <tr>
                        <td style="background-color: #f8fafc; padding: 20px; text-align: center; font-size: 14px; color: #4a4a4a; border-top: 1px solid #e0e0e0; border-radius: 0 0 12px 12px;">
                            <p style="margin: 5px 0;">This is an automated reminder. Please do not reply to this email.</p>
                            <p style="margin: 5px 0;">&copy; 2025 Contoso Corporation. All rights reserved.</p>
                        </td>
                    </tr>
                </table>
            </td>
        </tr>
    </table>
</body>
</html>
"@

# ============================================================================
# FUNCTIONS
# ============================================================================

function Remove-UserFromSessionHost {
    param(
        [string]$VMName,
        [string]$HostPoolName,
        [string]$HostPoolResourceGroup,
        [string]$Username,
        [bool]$WhatIfMode
    )
    
    try {
        # Construct the session host name (hostpool/vmname.domain)
        $sessionHostName = "$HostPoolName/$VMName"
        
        # Get the session host to verify it exists
        $sessionHost = Get-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $HostPoolResourceGroup -Name $sessionHostName -ErrorAction SilentlyContinue
        
        if (-not $sessionHost) {
            Write-Host "    Session host not found in host pool: $sessionHostName" -ForegroundColor Yellow
            return $false
        }
        
        # Get active user sessions on this session host
        $userSessions = Get-AzWvdUserSession -HostPoolName $HostPoolName -ResourceGroupName $HostPoolResourceGroup -SessionHostName $sessionHostName -ErrorAction SilentlyContinue |
            Where-Object { $_.UserPrincipalName -eq $Username -or $_.ActiveDirectoryUserName -like "*$Username*" }
        
        if ($WhatIfMode) {
            if ($userSessions) {
                Write-Host "    [WhatIf] Would disconnect $($userSessions.Count) active session(s) and unassign user from $VMName" -ForegroundColor Cyan
            } else {
                Write-Host "    [WhatIf] Would unassign user from $VMName (no active sessions)" -ForegroundColor Cyan
            }
            return $true
        }
        
        # Disconnect any active sessions
        $disconnectedSessions = 0
        if ($userSessions) {
            foreach ($session in $userSessions) {
                try {
                    # Extract session ID from the full resource ID
                    $sessionId = $session.Name.Split('/')[-1]
                    Remove-AzWvdUserSession -HostPoolName $HostPoolName -ResourceGroupName $HostPoolResourceGroup -SessionHostName $sessionHostName -Id $sessionId -Force -ErrorAction Stop
                    $disconnectedSessions++
                    Write-Host "    Disconnected session: $sessionId" -ForegroundColor Green
                }
                catch {
                    Write-Host "    Warning: Failed to disconnect session $sessionId : $_" -ForegroundColor Yellow
                }
            }
        }
        
        # Update the session host to set it to drain mode or remove user assignment
        # For personal desktops, we need to unassign the user
        try {
            Update-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $HostPoolResourceGroup -Name $sessionHostName -AllowNewSession:$false -ErrorAction Stop
            Write-Host "    Set session host to drain mode (no new sessions allowed)" -ForegroundColor Green
        }
        catch {
            Write-Host "    Warning: Could not set drain mode: $_" -ForegroundColor Yellow
        }
        
        # For personal host pools, unassign the user
        if ($sessionHost.AssignedUser) {
            try {
                Update-AzWvdSessionHost -HostPoolName $HostPoolName -ResourceGroupName $HostPoolResourceGroup -Name $sessionHostName -AssignedUser "" -ErrorAction Stop
                Write-Host "    Unassigned user from personal desktop" -ForegroundColor Green
            }
            catch {
                Write-Host "    Warning: Could not unassign user: $_" -ForegroundColor Yellow
            }
        }
        
        if ($disconnectedSessions -gt 0 -or $sessionHost.AssignedUser) {
            return $true
        } else {
            Write-Host "    User had no active sessions or assignments on this host" -ForegroundColor Yellow
            return $true  # Still consider it successful if there was nothing to remove
        }
    }
    catch {
        Write-Host "    Failed to remove user from session host: $_" -ForegroundColor Red
        return $false
    }
}

# ============================================================================
# SCRIPT EXECUTION - Do not modify below this line unless needed
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Windows 11 Migration Reminder System" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Mode: $(if ($WhatIf) { 'What-If (Preview)' } else { 'Execute' })"
Write-Host "User List File: $UserListFile"
Write-Host "Reminder Threshold: $ReminderDaysThreshold days"
Write-Host "Removal Grace Period: $RemovalGracePeriod day(s) after deadline"
Write-Host "========================================`n" -ForegroundColor Cyan

# Validate file exists
if (-not (Test-Path $UserListFile)) {
    Write-Error "User list file not found: $UserListFile"
    exit 1
}

# Ensure required modules are installed
if (-not (Get-Module -ListAvailable -Name Az.Compute)) {
    Write-Host "Installing Az.Compute module..."
    Install-Module -Name Az.Compute -AllowClobber -Force -Scope CurrentUser
}
if (-not (Get-Module -ListAvailable -Name Az.DesktopVirtualization)) {
    Write-Host "Installing Az.DesktopVirtualization module..."
    Install-Module -Name Az.DesktopVirtualization -AllowClobber -Force -Scope CurrentUser
}
Import-Module Az.Compute
Import-Module Az.DesktopVirtualization

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
# Check migration deadlines and prepare reminder/removal lists
# ============================================================================
Write-Host "[Step 4] Checking migration deadlines..." -ForegroundColor Yellow

$reminderList = @()
$removalList = @()
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
            
            # Check if user should be removed (deadline passed + grace period)
            if ($daysRemaining -lt -$RemovalGracePeriod) {
                $removalList += [PSCustomObject]@{
                    Username       = $assignment.Username
                    RITMNumber     = $assignment.RITMNumber
                    OldVMName      = $assignment.OldVMName
                    NewVMName      = $assignment.NewVMName
                    Deadline       = $deadline
                    DeadlineString = $deadline.ToString('MMMM dd, yyyy')
                    DaysOverdue    = [Math]::Abs($daysRemaining)
                    Removed        = $false
                    Success        = $false
                    ErrorMessage   = ""
                }
                Write-Host "    → User access will be removed (deadline passed)" -ForegroundColor Red
            }
            # Check if reminder should be sent
            elseif ($daysRemaining -le $ReminderDaysThreshold -and $daysRemaining -ge 0) {
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
Write-Host "  - Users to remove: $($removalList.Count)" -ForegroundColor Red
Write-Host "  - Not yet due: $notDueCount" -ForegroundColor Green
Write-Host "  - No tag found: $noTagCount`n" -ForegroundColor $(if ($noTagCount -gt 0) { 'Yellow' } else { 'Green' })

# ============================================================================
# Remove user access for overdue migrations
# ============================================================================
if ($removalList.Count -gt 0) {
    Write-Host "[Step 4a] Removing user access for overdue migrations..." -ForegroundColor Red
    Write-Host "Users with overdue migrations:" -ForegroundColor Red
    $removalList | Format-Table -AutoSize Username, OldVMName, DeadlineString, DaysOverdue
    Write-Host ""
    
    if ($WhatIf) {
        Write-Host "WhatIf mode: No users will be removed`n" -ForegroundColor Yellow
    }
    
    $removedCount = 0
    $removeFailCount = 0
    
    foreach ($removal in $removalList) {
        Write-Host "  Removing access: $($removal.Username) from $($removal.OldVMName)..."
        
        $removed = Remove-UserFromSessionHost -VMName $removal.OldVMName -HostPoolName $hostPoolName -HostPoolResourceGroup $hostPoolResourceGroup -Username $removal.Username -WhatIfMode $WhatIf
        
        if ($removed) {
            $removal.Removed = $true
            $removal.Success = $true
            $removedCount++
            if (-not $WhatIf) {
                Write-Host "  ✓ Access removed from session host" -ForegroundColor Green
            }
        }
        else {
            $removeFailCount++
            if (-not $WhatIf) {
                Write-Host "  ✗ Failed to remove access" -ForegroundColor Red
            }
        }
    }
    
    Write-Host "`n✓ User removal completed" -ForegroundColor Green
    Write-Host "  - Successfully removed: $removedCount" -ForegroundColor Green
    Write-Host "  - Failed: $removeFailCount`n" -ForegroundColor $(if ($removeFailCount -gt 0) { 'Red' } else { 'Green' })
}

if ($reminderList.Count -eq 0 -and $removalList.Count -eq 0) {
    Write-Host "✅ No actions needed at this time." -ForegroundColor Green
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
Write-Host "MIGRATION MANAGEMENT SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total VMs Checked:      $($userAssignments.Count)"
Write-Host ""
Write-Host "User Removals:"
Write-Host "  - Processed:          $($removalList.Count)" -ForegroundColor $(if ($removalList.Count -gt 0) { 'Red' } else { 'Green' })
Write-Host "  - Successful:         $removedCount" -ForegroundColor $(if ($removedCount -gt 0) { 'Green' } else { 'Gray' })
Write-Host "  - Failed:             $removeFailCount" -ForegroundColor $(if ($removeFailCount -gt 0) { 'Red' } else { 'Gray' })
Write-Host ""
Write-Host "Reminder Emails:"
Write-Host "  - Needed:             $($reminderList.Count)" -ForegroundColor $(if ($reminderList.Count -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "  - Sent:               $sentCount" -ForegroundColor $(if ($sentCount -gt 0) { 'Green' } else { 'Gray' })
Write-Host "  - Failed:             $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Gray' })
Write-Host "========================================`n" -ForegroundColor Cyan

# Display detailed results
if ($removalList.Count -gt 0) {
    Write-Host "User Removal Details:" -ForegroundColor Red
    $removalList | Format-Table -AutoSize Username, OldVMName, DaysOverdue, Removed, Success
}

if ($reminderList.Count -gt 0) {
    Write-Host "Reminder Email Details:" -ForegroundColor Cyan
    $reminderList | Format-Table -AutoSize Username, OldVMName, DaysRemaining, EmailSent, Success
}

# Show failures with details
$removalFailures = $removalList | Where-Object { -not $_.Success }
if ($removalFailures.Count -gt 0) {
    Write-Host "`nUser Removal Failures:" -ForegroundColor Red
    foreach ($failure in $removalFailures) {
        Write-Host "  ❌ $($failure.Username) ($($failure.OldVMName)): $($failure.ErrorMessage)" -ForegroundColor Red
    }
    Write-Host ""
}

$emailFailures = $reminderList | Where-Object { -not $_.Success }
if ($emailFailures.Count -gt 0) {
    Write-Host "`nEmail Failures:" -ForegroundColor Red
    foreach ($failure in $emailFailures) {
        Write-Host "  ❌ $($failure.Username) ($($failure.OldVMName)): $($failure.ErrorMessage)" -ForegroundColor Red
    }
    Write-Host ""
}

# Export results to CSV
if ($removalList.Count -gt 0) {
    $removalFile = "migration-removals-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    $removalList | Export-Csv -Path $removalFile -NoTypeInformation
    Write-Host "Removal results exported to: $removalFile" -ForegroundColor Yellow
}

if ($reminderList.Count -gt 0) {
    $resultFile = "migration-reminders-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
    $reminderList | Export-Csv -Path $resultFile -NoTypeInformation
    Write-Host "Reminder results exported to: $resultFile" -ForegroundColor Yellow
}

if ($removalList.Count -gt 0 -or $reminderList.Count -gt 0) {
    Write-Host ""
}

if (-not $WhatIf) {
    Write-Host "✅ Migration management process completed!" -ForegroundColor Green
}
else {
    Write-Host "ℹ️  WhatIf mode completed. No changes were made." -ForegroundColor Yellow
    Write-Host "   Run without -WhatIf to apply changes (remove users and send emails).`n" -ForegroundColor Yellow
}

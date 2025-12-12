param(
    [Parameter(Mandatory=$true)]
    [string]$UserListFile,
    
    [Parameter(Mandatory=$false)]
    [string]$TagName = "AssignedUser",  # Generic placeholder - customize as needed
    
    [Parameter(Mandatory=$false)]
    [hashtable]$AdditionalTags = @{},  # Add more tags via hashtable: @{Tag1="Value1"; Tag2="Value2"}
    
    [switch]$WhatIf
)

<#
.SYNOPSIS
    Updates Azure VM tags for AVD host pool VMs based on user assignments

.DESCRIPTION
    This script processes a CSV file containing user assignments and updates
    metadata tags on the corresponding Azure VMs in the AVD host pool.
    
.PARAMETER UserListFile
    Path to CSV or text file with user assignments.
    Format: Username,RITMNumber,OldVMName (one per line)
    Example:
        john.doe@contoso.com,1234567,OLDVM-0
        jane.smith@contoso.com,7654321,OLDVM2-0

.PARAMETER TagName
    The name of the tag to set with the assigned username (default: AssignedUser)

.PARAMETER AdditionalTags
    Hashtable of additional tags to set on all VMs
    Example: -AdditionalTags @{Environment="Production"; Department="IT"}

.PARAMETER WhatIf
    Preview the tag changes without applying them

.EXAMPLE
    .\Update-AVDVMTags.ps1 -UserListFile "users.csv"
    
.EXAMPLE
    .\Update-AVDVMTags.ps1 -UserListFile "users.csv" -TagName "Owner" -WhatIf
    
.EXAMPLE
    .\Update-AVDVMTags.ps1 -UserListFile "users.csv" -AdditionalTags @{Department="Finance"; CostCenter="12345"}
#>

# ============================================================================
# CONFIGURATION - Update these values for your environment
# ============================================================================

# AVD Configuration
$avdResourceGroup = "current-rg"  # Resource group where AVD VMs are located
$avdSubscriptionId = "00000000-0000-0000-0000-000000000000"  # Subscription ID for AVD VMs
$hostPoolName = "your-hostpool-name"  # Name of the AVD host pool

# VM Naming Pattern
# Script assumes new VM names are: AVDRITM{RITMNumber}-0
# Modify this pattern if your naming convention differs
$vmNamePrefix = "AVDRITM"
$vmNameSuffix = "-0"

# ============================================================================
# SCRIPT EXECUTION
# ============================================================================

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "AVD VM Tag Update Utility" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Mode: $(if ($WhatIf) { 'What-If (Preview)' } else { 'Execute' })"
Write-Host "User List File: $UserListFile"
Write-Host "Primary Tag Name: $TagName"
if ($AdditionalTags.Count -gt 0) {
    Write-Host "Additional Tags: $($AdditionalTags.Count)"
    foreach ($key in $AdditionalTags.Keys) {
        Write-Host "  - $key = $($AdditionalTags[$key])"
    }
}
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

# Switch to AVD subscription
Write-Host "[Step 1] Switching to AVD subscription..." -ForegroundColor Yellow
try {
    Set-AzContext -SubscriptionId $avdSubscriptionId -ErrorAction Stop | Out-Null
    Write-Host "✓ Context switched to AVD subscription`n" -ForegroundColor Green
}
catch {
    Write-Error "Failed to switch to AVD subscription: $_"
    exit 1
}

# ============================================================================
# Load user assignments from file
# ============================================================================
Write-Host "[Step 2] Loading user assignments from file..." -ForegroundColor Yellow

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
            $newVMName = "$vmNamePrefix$ritmNumber$vmNameSuffix"
            $userAssignments += [PSCustomObject]@{
                Username    = $username
                RITMNumber  = $ritmNumber
                OldVMName   = $oldVMName
                NewVMName   = $newVMName
                Tagged      = $false
                Success     = $false
                ErrorMessage = ""
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
# Update VM tags
# ============================================================================
Write-Host "[Step 3] Updating VM tags..." -ForegroundColor Yellow

$successCount = 0
$failCount = 0
$notFoundCount = 0

foreach ($assignment in $userAssignments) {
    Write-Host "  Processing: $($assignment.NewVMName)..." -NoNewline
    
    try {
        # Try to find the VM in the resource group
        $vm = Get-AzVM -ResourceGroupName $avdResourceGroup -Name $assignment.NewVMName -ErrorAction SilentlyContinue
        
        if (-not $vm) {
            Write-Host " ⚠️  VM not found" -ForegroundColor Yellow
            $assignment.ErrorMessage = "VM not found in resource group"
            $notFoundCount++
            continue
        }
        
        # Build tag hashtable
        $tagsToSet = @{}
        
        # Start with existing tags
        if ($vm.Tags) {
            $vm.Tags.Keys | ForEach-Object {
                $tagsToSet[$_] = $vm.Tags[$_]
            }
        }
        
        # Add/update primary tag (assigned user)
        $tagsToSet[$TagName] = $assignment.Username
        
        # Add/update additional tags
        foreach ($key in $AdditionalTags.Keys) {
            $tagsToSet[$key] = $AdditionalTags[$key]
        }
        
        if ($WhatIf) {
            Write-Host " [WhatIf]" -ForegroundColor Cyan
            Write-Host "    Would set tags:" -ForegroundColor Cyan
            Write-Host "      $TagName = $($assignment.Username)" -ForegroundColor Cyan
            foreach ($key in $AdditionalTags.Keys) {
                Write-Host "      $key = $($AdditionalTags[$key])" -ForegroundColor Cyan
            }
            $assignment.Tagged = $true
            $assignment.Success = $true
            $successCount++
        }
        else {
            # Update VM tags
            Update-AzVM -ResourceGroupName $avdResourceGroup -VM $vm -Tag $tagsToSet -ErrorAction Stop | Out-Null
            
            Write-Host " ✓ Tags updated" -ForegroundColor Green
            Write-Host "    $TagName = $($assignment.Username)" -ForegroundColor Gray
            foreach ($key in $AdditionalTags.Keys) {
                Write-Host "    $key = $($AdditionalTags[$key])" -ForegroundColor Gray
            }
            
            $assignment.Tagged = $true
            $assignment.Success = $true
            $successCount++
        }
    }
    catch {
        Write-Host " ✗ Failed: $_" -ForegroundColor Red
        $assignment.ErrorMessage = $_.Exception.Message
        $failCount++
    }
}

# ============================================================================
# SUMMARY REPORT
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "TAG UPDATE SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Assignments:     $($userAssignments.Count)"
Write-Host "Successfully Tagged:   $successCount" -ForegroundColor $(if ($successCount -gt 0) { 'Green' } else { 'Gray' })
Write-Host "Failed:                $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Gray' })
Write-Host "VMs Not Found:         $notFoundCount" -ForegroundColor $(if ($notFoundCount -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "========================================`n" -ForegroundColor Cyan

# Display detailed results
if ($userAssignments.Count -gt 0) {
    Write-Host "Detailed Results:" -ForegroundColor Cyan
    $userAssignments | Format-Table -AutoSize Username, NewVMName, Tagged, Success, ErrorMessage
}

# Show failures with details
$failures = $userAssignments | Where-Object { -not $_.Success }
if ($failures.Count -gt 0) {
    Write-Host "`nFailures and Issues:" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host "  ❌ $($failure.NewVMName): $($failure.ErrorMessage)" -ForegroundColor Red
    }
    Write-Host ""
}

# Export results to CSV
$resultFile = "vm-tag-updates-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$userAssignments | Export-Csv -Path $resultFile -NoTypeInformation
Write-Host "Results exported to: $resultFile" -ForegroundColor Yellow
Write-Host ""

if (-not $WhatIf) {
    if ($failCount -eq 0 -and $notFoundCount -eq 0) {
        Write-Host "✅ All VM tags updated successfully!" -ForegroundColor Green
    }
    else {
        Write-Host "⚠️  Tag update completed with some issues. Review the details above." -ForegroundColor Yellow
    }
}
else {
    Write-Host "ℹ️  WhatIf mode completed. No changes were made." -ForegroundColor Yellow
    Write-Host "   Run without -WhatIf to apply tag changes.`n" -ForegroundColor Yellow
}
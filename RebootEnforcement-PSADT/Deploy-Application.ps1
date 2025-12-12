<#
.SYNOPSIS
    PSADT wrapper for Reboot Enforcement with modern toast notifications

.DESCRIPTION
    This is the main deployment script that uses PSAppDeployToolkit to enforce
    periodic workstation reboots while showing modern toast notifications to users.
    
    Features:
    - Runs as SYSTEM (has reboot privileges)
    - Shows toast notifications to interactive users via ServiceUI
    - Progressive warnings (hourly, then 15-min intervals)
    - User can schedule reboot before deadline
    - JSON-based state management
    - AD group exemption support
    
.PARAMETER DeploymentType
    The type of deployment to perform. Default is: Install.

.PARAMETER DeployMode
    Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode.
    Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent

.EXAMPLE
    Deploy-Application.ps1
    Deploy-Application.ps1 -DeployMode 'Silent'

.NOTES
    Toolkit Exit Code Ranges:
    - 60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
    - 69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
    - 70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory=$false)]
    [ValidateSet('Install','Uninstall','Repair')]
    [String]$DeploymentType = 'Install',
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('Interactive','Silent','NonInteractive')]
    [String]$DeployMode = 'Interactive',
    
    [Parameter(Mandatory=$false)]
    [Switch]$AllowRebootPassThru = $false,
    
    [Parameter(Mandatory=$false)]
    [Switch]$TerminalServerMode = $false,
    
    [Parameter(Mandatory=$false)]
    [Switch]$DisableLogging = $false,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('Off', 'Standard', 'Urgent', 'Deadline', 'OutsideWindow')]
    [String]$DemoMode = 'Off'
)

Try {
    ## Set the script execution policy for this process
    Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop' } Catch {}

    ##*===============================================
    ##* VARIABLE DECLARATION
    ##*===============================================
    
    ## Variables: Application
    [String]$appVendor = 'IT Operations'
    [String]$appName = 'Reboot Enforcement'
    [String]$appVersion = '1.0'
    [String]$appArch = ''
    [String]$appLang = 'EN'
    [String]$appRevision = '01'
    [String]$appScriptVersion = '1.0.0'
    [String]$appScriptDate = '12/03/2025'
    [String]$appScriptAuthor = 'IT Operations'
    
    ##* Do not modify section below
    #region DoNotModify
    
    ## Variables: Exit Code
    [Int32]$mainExitCode = 0
    
    ## Variables: Script
    [String]$deployAppScriptFriendlyName = 'Deploy Application'
    [Version]$deployAppScriptVersion = [Version]'3.9.3'
    [String]$deployAppScriptDate = '02/05/2023'
    [Hashtable]$deployAppScriptParameters = $PsBoundParameters
    
    ## Variables: Environment
    If (Test-Path -LiteralPath 'variable:HostInvocation') { $InvocationInfo = $HostInvocation } Else { $InvocationInfo = $MyInvocation }
    [String]$scriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent
    
    ## Dot source the required App Deploy Toolkit Functions
    Try {
        [String]$moduleAppDeployToolkitMain = "$scriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
        If (-not (Test-Path -LiteralPath $moduleAppDeployToolkitMain -PathType 'Leaf')) { Throw "Module does not exist at the specified location [$moduleAppDeployToolkitMain]." }
        . $moduleAppDeployToolkitMain
    }
    Catch {
        If ($mainExitCode -eq 0){ [Int32]$mainExitCode = 60008 }
        Write-Error -Message "Module [$moduleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'
        Exit $mainExitCode
    }
    
    #endregion
    ##* Do not modify section above
    
    ##*===============================================
    ##* CUSTOM VARIABLES
    ##*===============================================
    
    # Reboot Enforcement Configuration
    [String]$exemptionADGroup = "RebootExemption"
    [Int32]$uptimeThresholdDays = 7
    [Int32]$rebootHour = 22  # 10 PM
    [Int32]$rebootWindowEnd = 5  # 5 AM
    
    # Build paths using PSADT environment variables (now available after toolkit loads)
    [String]$stateFilePath = Join-Path $envProgramData "RebootEnforcement\state.json"
    [String]$helperScriptPath = Join-Path $scriptDirectory "SupportFiles\Show-RebootToast.ps1"
    
    ##*===============================================
    ##* END VARIABLE DECLARATION
    ##*===============================================
    
    If ($deploymentType -ine 'Uninstall' -and $deploymentType -ine 'Repair') {
        ##*===============================================
        ##* PRE-INSTALLATION
        ##*===============================================
        [String]$installPhase = 'Pre-Installation'
        
        ## Show Welcome Message (if Interactive)
        If ($deployMode -ne 'Silent') {
            # Not showing welcome - this runs frequently
        }
        
        ## Show Progress Message (Disabled - using modern toast notifications instead)
        # Show-InstallationProgress -StatusMessage "Checking system uptime..."
        
        ##*===============================================
        ##* INSTALLATION
        ##*===============================================
        [String]$installPhase = 'Installation'
        
        Write-Log -Message "========================================" -Severity 1
        Write-Log -Message "Reboot Enforcement - Starting Check" -Severity 1
        if ($DemoMode -ne 'Off') {
            Write-Log -Message "DEMO MODE: $DemoMode - Simulating $DemoMode scenario" -Severity 2
        }
        Write-Log -Message "========================================" -Severity 1
        
        #region Helper Functions
        
        function Get-RebootState {
            try {
                if (Test-Path $stateFilePath) {
                    Write-Log -Message "Loading state from: $stateFilePath" -Severity 1
                    $json = Get-Content $stateFilePath -Raw -ErrorAction Stop | ConvertFrom-Json
                    return @{
                        LastNotificationTime = if ($json.LastNotificationTime) { [DateTime]::Parse($json.LastNotificationTime) } else { $null }
                        ScheduledRebootTime = if ($json.ScheduledRebootTime) { [DateTime]::Parse($json.ScheduledRebootTime) } else { $null }
                        NotificationCount = if ($json.NotificationCount) { $json.NotificationCount } else { 0 }
                    }
                }
                else {
                    Write-Log -Message "No existing state file found" -Severity 1
                }
            }
            catch {
                Write-Log -Message "Error loading state: $($_.Exception.Message)" -Severity 2
            }
            
            return @{
                LastNotificationTime = $null
                ScheduledRebootTime = $null
                NotificationCount = 0
            }
        }
        
        function Set-RebootState {
            param(
                [Nullable[DateTime]]$LastNotificationTime,
                [Nullable[DateTime]]$ScheduledRebootTime,
                [Int32]$NotificationCount
            )
            
            try {
                $stateDir = Split-Path $stateFilePath -Parent
                if (-not (Test-Path $stateDir)) {
                    Write-Log -Message "Creating state directory: $stateDir" -Severity 1
                    New-Item -Path $stateDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
                }
                
                $state = @{
                    LastNotificationTime = if ($LastNotificationTime) { $LastNotificationTime.ToString("o") } else { $null }
                    ScheduledRebootTime = if ($ScheduledRebootTime) { $ScheduledRebootTime.ToString("o") } else { $null }
                    NotificationCount = $NotificationCount
                }
                
                Write-Log -Message "Writing state to: $stateFilePath" -Severity 1
                $state | ConvertTo-Json | Set-Content $stateFilePath -Force -ErrorAction Stop
                Write-Log -Message "State saved successfully" -Severity 1
            }
            catch {
                Write-Log -Message "Error saving state: $($_.Exception.Message)" -Severity 3
                Write-Log -Message "Inner exception: $($_.Exception.InnerException.Message)" -Severity 3
            }
        }
        
        function Test-RebootExemption {
            param([string]$GroupName)
            
            try {
                $computerName = $env:COMPUTERNAME
                Write-Log -Message "Checking exemption for computer: $computerName" -Severity 1
                
                # Get domain information using ADSI
                $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
                $domainDN = $domain.GetDirectoryEntry().distinguishedName
                Write-Log -Message "Domain DN: $domainDN" -Severity 1
                
                # Search for the computer object using ADSI
                $searcher = New-Object System.DirectoryServices.DirectorySearcher
                $searcher.SearchRoot = "LDAP://$domainDN"
                $searcher.Filter = "(&(objectClass=computer)(cn=$computerName))"
                $searcher.PropertiesToLoad.Add("memberOf") | Out-Null
                
                $result = $searcher.FindOne()
                
                if ($null -eq $result) {
                    Write-Log -Message "Computer object not found in AD" -Severity 2
                    return $false
                }
                
                $memberOf = $result.Properties["memberOf"]
                
                if ($memberOf.Count -gt 0) {
                    Write-Log -Message "Computer is member of $($memberOf.Count) groups" -Severity 1
                    
                    foreach ($groupDN in $memberOf) {
                        # Extract CN from DN (e.g., "CN=RebootExemption,OU=Groups,DC=domain,DC=com")
                        if ($groupDN -match "CN=([^,]+)") {
                            $groupCN = $matches[1]
                            
                            if ($groupCN -eq $GroupName) {
                                Write-Log -Message "Computer is exempt (member of $GroupName)" -Severity 1
                                return $true
                            }
                        }
                    }
                }
                else {
                    Write-Log -Message "Computer is not a member of any groups" -Severity 1
                }
                
                # In demo mode, log the result but always return false to continue demo
                if ($DemoMode -ne 'Off') {
                    Write-Log -Message "DEMO MODE - Ignoring exemption status for demo purposes" -Severity 2
                    return $false
                }
                
                return $false
            }
            catch {
                Write-Log -Message "Error checking exemption via ADSI: $($_.Exception.Message)" -Severity 2
                
                # In demo mode, log the error but continue with demo
                if ($DemoMode -ne 'Off') {
                    Write-Log -Message "DEMO MODE - Ignoring exemption error for demo purposes" -Severity 2
                    return $false
                }
                
                return $false
            }
        }
        
        function Get-SystemUptimeDays {
            if ($DemoMode -ne 'Off') {
                Write-Log -Message "DEMO MODE - Simulating 8 days uptime" -Severity 1
                return 8
            }
            
            try {
                $os = Get-CimInstance -ClassName Win32_OperatingSystem
                $uptime = (Get-Date) - $os.LastBootUpTime
                return [Math]::Floor($uptime.TotalDays)
            }
            catch {
                Write-Log -Message "Error getting uptime: $_" -Severity 3
                return 0
            }
        }
        
        function Get-NextRebootDeadline {
            if ($DemoMode -ne 'Off') {
                # Simulate different scenarios based on demo mode
                switch ($DemoMode) {
                    'Standard' {
                        # Simulate 5 hours until deadline (300 minutes)
                        $deadline = (Get-Date).AddMinutes(300)
                        Write-Log -Message "DEMO MODE (Standard) - Deadline set to 5 hours from now: $($deadline.ToString('HH:mm:ss'))" -Severity 1
                    }
                    'Urgent' {
                        # Simulate 45 minutes until deadline (within 90-minute window)
                        $deadline = (Get-Date).AddMinutes(45)
                        Write-Log -Message "DEMO MODE (Urgent) - Deadline set to 45 minutes from now: $($deadline.ToString('HH:mm:ss'))" -Severity 1
                    }
                    'Deadline' {
                        # Simulate deadline reached (in maintenance window)
                        $deadline = (Get-Date).AddMinutes(-5)
                        Write-Log -Message "DEMO MODE (Deadline) - Deadline was 5 minutes ago, inside maintenance window" -Severity 1
                    }
                    'OutsideWindow' {
                        # Simulate deadline reached but outside maintenance window
                        $deadline = (Get-Date).AddMinutes(-5)
                        Write-Log -Message "DEMO MODE (OutsideWindow) - Deadline was 5 minutes ago, outside maintenance window" -Severity 1
                    }
                }
                return $deadline
            }
            
            $now = Get-Date
            $todayDeadline = Get-Date -Hour $rebootHour -Minute 0 -Second 0
            
            if ($now -lt $todayDeadline) {
                return $todayDeadline
            }
            else {
                return $todayDeadline
            }
        }
        
        function Test-InRebootWindow {
            # Override for OutsideWindow demo mode
            if ($DemoMode -eq 'OutsideWindow') {
                Write-Log -Message "DEMO MODE (OutsideWindow) - Simulating outside maintenance window" -Severity 1
                return $false
            }
            
            # Override for Deadline demo mode (simulate inside window)
            if ($DemoMode -eq 'Deadline') {
                Write-Log -Message "DEMO MODE (Deadline) - Simulating inside maintenance window" -Severity 1
                return $true
            }
            
            $currentHour = (Get-Date).Hour
            return ($currentHour -ge $rebootHour -or $currentHour -lt $rebootWindowEnd)
        }
        
        #endregion
        
        # Check exemption
        if (Test-RebootExemption -GroupName $exemptionADGroup) {
            Write-Log -Message "Computer is exempt from reboot enforcement" -Severity 1
            Exit-Script -ExitCode 0
        }
        
        # Get uptime
        $uptimeDays = Get-SystemUptimeDays
        Write-Log -Message "System uptime: $uptimeDays days" -Severity 1
        
        # Check threshold
        if ($uptimeDays -lt $uptimeThresholdDays) {
            Write-Log -Message "Uptime below threshold ($uptimeThresholdDays days) - no action needed" -Severity 1
            Exit-Script -ExitCode 0
        }
        
        Write-Log -Message "Uptime exceeds threshold - enforcement active" -Severity 2
        
        # Calculate deadline
        $deadline = Get-NextRebootDeadline
        $minutesUntilDeadline = ($deadline - (Get-Date)).TotalMinutes
        Write-Log -Message "Deadline: $($deadline.ToString('yyyy-MM-dd HH:mm:ss')) ($([Math]::Round($minutesUntilDeadline/60, 1)) hours)" -Severity 1
        
        # Load state
        $state = Get-RebootState
        
        # Check deadline
        if ($minutesUntilDeadline -le 0) {
            if (Test-InRebootWindow) {
                Write-Log -Message "Deadline reached and in reboot window - forcing reboot" -Severity 2
                Show-InstallationRestartPrompt -CountdownSeconds 60 -CountdownNoHideSeconds 60
                Exit-Script -ExitCode 1641
            }
            else {
                Write-Log -Message "Deadline reached but outside window - waiting" -Severity 2
                Exit-Script -ExitCode 0
            }
        }
        
        # Within final 90 minutes?
        if ($minutesUntilDeadline -le 90) {
            # Final warning - show PSADT prompt with countdown and restart option
            Write-Log -Message "Final warning period - showing countdown prompt" -Severity 2
            
            if ($DemoMode -eq 'Urgent') {
                # In urgent demo mode, allow dismissing the urgent warning
                $promptResult = Show-InstallationPrompt `
                    -Title "URGENT: Restart Required Now" `
                    -Message "Your system must restart in $([Math]::Ceiling($minutesUntilDeadline)) minutes (at $($deadline.ToString('h:mm tt'))).`n`nSave all work immediately. Your computer will restart automatically if you do not take action." `
                    -ButtonRightText "Restart Now" `
                    -ButtonLeftText "OK (Demo Only)" `
                    -Icon Exclamation `
                    -Timeout 300 `
                    -ExitOnTimeout $false
                
                if ($promptResult -eq "Restart Now") {
                    Write-Log -Message "User chose to restart now" -Severity 1
                    Show-InstallationRestartPrompt -CountdownSeconds 60 -CountdownNoHideSeconds 60
                    Exit-Script -ExitCode 1641
                }
                else {
                    Write-Log -Message "DEMO MODE - User dismissed urgent warning" -Severity 1
                }
            }
            else {
                # Production mode - only allow restart or remind
                $promptResult = Show-InstallationPrompt `
                    -Title "URGENT: Restart Required Now" `
                    -Message "Your system must restart in $([Math]::Ceiling($minutesUntilDeadline)) minutes (at $($deadline.ToString('h:mm tt'))).`n`nSave all work immediately. Your computer will restart automatically if you do not take action." `
                    -ButtonRightText "Restart Now" `
                    -ButtonMiddleText "Remind Me in 15 Minutes" `
                    -Icon Exclamation `
                    -Timeout 300 `
                    -ExitOnTimeout $false
                
                if ($promptResult -eq "Restart Now") {
                    Write-Log -Message "User chose to restart now" -Severity 1
                    Show-InstallationRestartPrompt -CountdownSeconds 60 -CountdownNoHideSeconds 60
                    Exit-Script -ExitCode 1641
                }
            }
            
            $state.LastNotificationTime = Get-Date
            $state.NotificationCount++
            Set-RebootState -LastNotificationTime $state.LastNotificationTime -ScheduledRebootTime $state.ScheduledRebootTime -NotificationCount $state.NotificationCount
        }
        else {
            # Standard notification - inform user about reboot requirement
            $hoursSinceLastNotification = if ($state.LastNotificationTime) { ((Get-Date) - $state.LastNotificationTime).TotalHours } else { 999 }
            
            # Show notification every 4 hours (or always in demo mode)
            if ($DemoMode -eq 'Standard' -or $hoursSinceLastNotification -ge 4) {
                Write-Log -Message "Showing reboot notification" -Severity 1
                
                $hoursRemaining = [Math]::Round($minutesUntilDeadline / 60, 1)
                Show-InstallationPrompt `
                    -Title "Proactive System Maintenance" `
                    -Message "Your computer has been online for $uptimeDays days. We perform proactive reboots on systems running over 7 days to maintain optimal performance and stability.`n`nPlease restart at your convenience, or your system will automatically restart at $($deadline.ToString('h:mm tt')) today." `
                    -ButtonRightText "OK" `
                    -Icon Information `
                    -Timeout 300 `
                    -ExitOnTimeout $false
                
                Write-Log -Message "User acknowledged notification" -Severity 1
                $state.LastNotificationTime = Get-Date
                $state.NotificationCount++
                Set-RebootState -LastNotificationTime $state.LastNotificationTime -ScheduledRebootTime $null -NotificationCount $state.NotificationCount
            }
        }
        
        Write-Log -Message "Check completed - no immediate action required" -Severity 1
        
        ##*===============================================
        ##* POST-INSTALLATION
        ##*===============================================
        [String]$installPhase = 'Post-Installation'
    }
    
    ##*===============================================
    ##* END SCRIPT BODY
    ##*===============================================
    
    ## Call the Exit-Script function to perform final cleanup operations
    Exit-Script -ExitCode $mainExitCode
}
Catch {
    [Int32]$mainExitCode = 60001
    [String]$mainErrorMessage = "$(Resolve-Error)"
    Write-Log -Message $mainErrorMessage -Severity 3 -Source $deployAppScriptFriendlyName
    Show-DialogBox -Text $mainErrorMessage -Icon 'Stop'
    Exit-Script -ExitCode $mainExitCode
}

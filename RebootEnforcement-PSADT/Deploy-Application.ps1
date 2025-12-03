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
    [Switch]$DisableLogging = $false
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
    [String]$stateFilePath = "$envProgramData\RebootEnforcement\state.json"
    [String]$helperScriptPath = "$scriptDirectory\SupportFiles\Show-RebootToast.ps1"
    
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
        
        ## Show Progress Message
        Show-InstallationProgress -StatusMessage "Checking system uptime..."
        
        ##*===============================================
        ##* INSTALLATION
        ##*===============================================
        [String]$installPhase = 'Installation'
        
        Write-Log -Message "========================================" -Severity 1
        Write-Log -Message "Reboot Enforcement - Starting Check" -Severity 1
        Write-Log -Message "========================================" -Severity 1
        
        #region Helper Functions
        
        function Get-RebootState {
            try {
                if (Test-Path $stateFilePath) {
                    $json = Get-Content $stateFilePath -Raw | ConvertFrom-Json
                    return @{
                        LastNotificationTime = if ($json.LastNotificationTime) { [DateTime]::Parse($json.LastNotificationTime) } else { $null }
                        ScheduledRebootTime = if ($json.ScheduledRebootTime) { [DateTime]::Parse($json.ScheduledRebootTime) } else { $null }
                        NotificationCount = if ($json.NotificationCount) { $json.NotificationCount } else { 0 }
                    }
                }
            }
            catch {
                Write-Log -Message "Error loading state file: $_" -Severity 2
            }
            
            return @{
                LastNotificationTime = $null
                ScheduledRebootTime = $null
                NotificationCount = 0
            }
        }
        
        function Set-RebootState {
            param(
                [DateTime]$LastNotificationTime,
                [DateTime]$ScheduledRebootTime,
                [Int32]$NotificationCount
            )
            
            try {
                $stateDir = Split-Path $stateFilePath -Parent
                if (-not (Test-Path $stateDir)) {
                    New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
                }
                
                $state = @{
                    LastNotificationTime = if ($LastNotificationTime) { $LastNotificationTime.ToString("o") } else { $null }
                    ScheduledRebootTime = if ($ScheduledRebootTime) { $ScheduledRebootTime.ToString("o") } else { $null }
                    NotificationCount = $NotificationCount
                }
                
                $state | ConvertTo-Json | Set-Content $stateFilePath -Force
                Write-Log -Message "State saved to JSON file" -Severity 1
            }
            catch {
                Write-Log -Message "Error saving state: $_" -Severity 3
            }
        }
        
        function Test-RebootExemption {
            param([string]$GroupName)
            
            try {
                $computerName = $env:COMPUTERNAME
                
                if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
                    Write-Log -Message "ActiveDirectory module not available - skipping exemption check" -Severity 2
                    return $false
                }
                
                Import-Module ActiveDirectory -ErrorAction Stop
                $computer = Get-ADComputer -Identity $computerName -Properties MemberOf -ErrorAction Stop
                
                if ($computer.MemberOf) {
                    foreach ($group in $computer.MemberOf) {
                        if ($group -like "*$GroupName*") {
                            Write-Log -Message "Computer is exempt (member of $GroupName)" -Severity 1
                            return $true
                        }
                    }
                }
                
                return $false
            }
            catch {
                Write-Log -Message "Error checking exemption: $_" -Severity 2
                return $false
            }
        }
        
        function Get-SystemUptimeDays {
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
            $currentHour = (Get-Date).Hour
            return ($currentHour -ge $rebootHour -or $currentHour -lt $rebootWindowEnd)
        }
        
        function Show-ToastToUser {
            param(
                [string]$NotificationType,
                [int]$UptimeDays,
                [DateTime]$Deadline,
                [int]$MinutesRemaining
            )
            
            try {
                # Build arguments for helper script
                $arguments = "-NotificationType `"$NotificationType`" -UptimeDays $UptimeDays -Deadline `"$($Deadline.ToString('o'))`" -MinutesRemaining $MinutesRemaining -StateFilePath `"$stateFilePath`""
                
                # Use PSADT's Execute-ProcessAsUser to show toast in user session
                Write-Log -Message "Showing toast notification: $NotificationType" -Severity 1
                Execute-ProcessAsUser -Path "$PSHOME\powershell.exe" -Parameters "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$helperScriptPath`" $arguments" -Wait $false
                
                return $true
            }
            catch {
                Write-Log -Message "Error showing toast: $_" -Severity 3
                return $false
            }
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
        
        # Check for scheduled reboot
        if ($state.ScheduledRebootTime) {
            Write-Log -Message "User scheduled reboot: $($state.ScheduledRebootTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Severity 1
            
            # Validate scheduled time
            if ($state.ScheduledRebootTime -le (Get-Date)) {
                Write-Log -Message "Scheduled time reached - initiating reboot" -Severity 2
                
                Show-InstallationRestartPrompt -CountdownSeconds 60 -CountdownNoHideSeconds 60
                Exit-Script -ExitCode 1641  # Reboot exit code
            }
            elseif ($state.ScheduledRebootTime -gt $deadline) {
                Write-Log -Message "Scheduled time after deadline - clearing" -Severity 2
                $state.ScheduledRebootTime = $null
                Set-RebootState -LastNotificationTime $state.LastNotificationTime -ScheduledRebootTime $null -NotificationCount $state.NotificationCount
            }
            else {
                # Check for countdown warnings
                $minutesUntilScheduled = ($state.ScheduledRebootTime - (Get-Date)).TotalMinutes
                
                if ($minutesUntilScheduled -le 10 -and $minutesUntilScheduled -gt 5) {
                    if (-not $state.LastNotificationTime -or ((Get-Date) - $state.LastNotificationTime).TotalMinutes -ge 4) {
                        Show-ToastToUser -NotificationType "ScheduledCountdown" -UptimeDays $uptimeDays -Deadline $state.ScheduledRebootTime -MinutesRemaining 10
                        $state.LastNotificationTime = Get-Date
                        Set-RebootState -LastNotificationTime $state.LastNotificationTime -ScheduledRebootTime $state.ScheduledRebootTime -NotificationCount $state.NotificationCount
                    }
                }
                elseif ($minutesUntilScheduled -le 5 -and $minutesUntilScheduled -gt 1) {
                    if (-not $state.LastNotificationTime -or ((Get-Date) - $state.LastNotificationTime).TotalMinutes -ge 3) {
                        Show-ToastToUser -NotificationType "ScheduledCountdown" -UptimeDays $uptimeDays -Deadline $state.ScheduledRebootTime -MinutesRemaining 5
                        $state.LastNotificationTime = Get-Date
                        Set-RebootState -LastNotificationTime $state.LastNotificationTime -ScheduledRebootTime $state.ScheduledRebootTime -NotificationCount $state.NotificationCount
                    }
                }
                elseif ($minutesUntilScheduled -le 1) {
                    Show-ToastToUser -NotificationType "ScheduledCountdown" -UptimeDays $uptimeDays -Deadline $state.ScheduledRebootTime -MinutesRemaining 1
                    Start-Sleep -Seconds 60
                    Show-InstallationRestartPrompt -CountdownSeconds 60 -CountdownNoHideSeconds 60
                    Exit-Script -ExitCode 1641
                }
                
                Exit-Script -ExitCode 0
            }
        }
        
        # No scheduled reboot - check deadline
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
            if (-not $state.LastNotificationTime -or ((Get-Date) - $state.LastNotificationTime).TotalMinutes -ge 15) {
                Show-ToastToUser -NotificationType "FinalWarning" -UptimeDays $uptimeDays -Deadline $deadline -MinutesRemaining ([Math]::Ceiling($minutesUntilDeadline))
                $state.LastNotificationTime = Get-Date
                $state.NotificationCount++
                Set-RebootState -LastNotificationTime $state.LastNotificationTime -ScheduledRebootTime $state.ScheduledRebootTime -NotificationCount $state.NotificationCount
            }
        }
        else {
            # Hourly reminders
            $hoursSinceLastNotification = if ($state.LastNotificationTime) { ((Get-Date) - $state.LastNotificationTime).TotalHours } else { 999 }
            
            if ($hoursSinceLastNotification -ge 1) {
                $notificationType = if (-not $state.LastNotificationTime) { "InitialWarning" } else { "HourlyReminder" }
                Show-ToastToUser -NotificationType $notificationType -UptimeDays $uptimeDays -Deadline $deadline -MinutesRemaining ([Math]::Ceiling($minutesUntilDeadline))
                $state.LastNotificationTime = Get-Date
                $state.NotificationCount++
                Set-RebootState -LastNotificationTime $state.LastNotificationTime -ScheduledRebootTime $state.ScheduledRebootTime -NotificationCount $state.NotificationCount
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

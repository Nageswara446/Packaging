param (
    [string]$AdminUser,
    [string]$AdminPassword
)


# Define Task Parameters
$TaskName = "Add-UserToAdminGroup"
$TaskDescription = "Adds the user from registry to the local Administrators group"
$ScriptPath = "C:\Windows\AVC\Scripts\BUILD\Add-UserToAdminGroup.ps1"
$LogFile = "C:\Windows\Installer\ScheduledTask.log"

# Ensure the log file exists
if (!(Test-Path $LogFile)) {
    New-Item -Path $LogFile -ItemType File -Force | Out-Null
}

# Example: Password already stored as SecureString in $AdminPassword
#$AdminPassword = ConvertTo-SecureString $AdminPassword -AsPlainText -Force

# Convert SecureString to plain text for Task Scheduler (this will be a temporary plain text version)
#$PasswordPlainText = [System.Net.NetworkCredential]::new('', $AdminPassword).Password


# Define Task Actions
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$ScriptPath`""

# Define Task Triggers (Run at User Logon)
$Trigger = New-ScheduledTaskTrigger -AtLogOn

# Define Task Settings
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# Register the Scheduled Task with Stored Credentials
Register-ScheduledTask -TaskName $TaskName -Description $TaskDescription -Action $Action -Trigger $Trigger -Settings $Settings -User $AdminUser -Password $AdminPassword -RunLevel Highest -Force

Write-Output "Scheduled Task '$TaskName' has been created successfully." | Out-File -Append $LogFile

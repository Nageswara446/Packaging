$logFile = "C:\Windows\Installer\Add-UserToAdminGroup.log"

# Function to log messages
function Write-Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -Append -FilePath $logFile
}

Write-Log "==== Script Execution Started ===="

# Define the base registry path where dynamic keys are located
$baseRegistryPath = "HKLM:\SOFTWARE\Microsoft\Security Center\Provider\CBP"

$UPN = $null  # Initialize UPN variable

# Check if the base registry path exists
if (Test-Path $baseRegistryPath) {
    Write-Log "Registry path exists: $baseRegistryPath"
    
    # Get all subkeys (GUIDs) under the base path
    $subKeys = Get-ChildItem -Path $baseRegistryPath

    # Loop through each subkey to search for ACCOUNTNAME
    foreach ($subKey in $subKeys) {
        $currentKeyPath = $subKey.PSPath

        try {
            # Attempt to retrieve the ACCOUNTNAME property
            $accountNameProperty = Get-ItemProperty -Path $currentKeyPath -ErrorAction Stop
            if ($accountNameProperty.PSObject.Properties.Name -contains "ACCOUNTNAME") {
                $UPN = $accountNameProperty.ACCOUNTNAME
                Write-Log "Found ACCOUNTNAME: $UPN in Key: $currentKeyPath"
                break
            }
        }
        catch {
            Write-Log "Failed to read ACCOUNTNAME from key: $currentKeyPath - $_"
        }
    }
} else {
    Write-Log "Registry path does not exist: $baseRegistryPath"
}

# If UPN is found, add the user to the Local Admin group
if ($UPN) {
    try {
        $LocalAdminGroup = Get-LocalGroup -SID "S-1-5-32-544"
        $LocalAdminGroupName = $LocalAdminGroup.Name

        Add-LocalGroupMember -Group $LocalAdminGroupName -Member "AzureAD\$UPN" -ErrorAction Stop
        Write-Log "Successfully added $UPN to $LocalAdminGroupName"
    } catch {
        Write-Log "Failed to add user $UPN to Admin Group: $_"
    }
} else {
    Write-Log "No valid user found in registry."
}

Write-Log "==== Script Execution Completed ===="

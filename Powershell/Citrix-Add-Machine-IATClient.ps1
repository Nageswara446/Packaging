param(
    [string]$CitrixCustomerId,
    [string]$CatalogName,
    [int]$VDICount,
    [string]$Tenant,
    [string]$SubscriptionId,
    [string]$resourceGroupName,
    [string]$clientId,
    [string]$clientSecret,
    [string]$citrixClientId,
    [String]$citrixPassword,
    [string]$DeliveryGroupName,
    [string]$EmailAddress,
    [string]$Datacenter,
    [string]$CitrixIdpInstanceId
)

asnp citrix.*


# Connct to Citrix Cloud
Set-XDCredentials -CustomerId $CitrixCustomerId -APIKey $citrixClientId -SecretKey $citrixPassword -ProfileType CloudApi -StoreAs "CitrixEUConnection"
#Set-XDCredentials -CustomerId $CustomerID -SecureClientFile "C:\temp\secureclient.csv" -ProfileType CloudApi -StoreAs "citrixconnection"
Get-XDAuthentication -ProfileName "CitrixEUConnection"
Write-Host "Successfully logged in to the Citrix Cloud" -ForegroundColor Green

# Create a SecureString from your plain text password
Write-host "Creating AAD Account Identities for the machines."

#OutputCatalog Name for Troubleshooting
Write-Host "Catalog Name $CatalogName"

$adaccounts = New-AcctADAccount -IdentityPoolName $CatalogName -Count $VDICount -UseServiceAccount
$adaccounts

# Creating the VM(s) using the names list from the previous command
Write-Host "Creating the virtual machine(s)... " -NoNewline
$provTaskId = New-ProvVM -AdAccountName $adAccounts.SuccessfulAccounts -ProvisioningSchemeName $CatalogName -RunAsynchronously -ErrorAction Stop

# Display a progress bar in case of a large number of VMs creation
$provtask = Get-ProvTask -TaskId $provTaskId
$totalpercent = 0

While ($provtask.Active -eq $true) {
    try {
        $totalpercent = If ($provTask.TaskProgress) { $provTask.TaskProgress } else { 0 }
    }
    catch {
    }
    Write-Progress -Activity "Tracking progress" -status "$totalpercent% Complete:" -percentComplete $totalpercent
    Start-Sleep 3
    $provtask = Get-ProvTask -TaskId $provTaskId
}

Write-Host "OK" -ForegroundColor Green

# Get the ProvisioningSchemeUid to add the VM(s) to the catalog
Write-Host "Getting Provisioning Scheme Uid... " -NoNewline
$ProvSchemeUid = (Get-ProvScheme -ProvisioningSchemeName $CatalogName).ProvisioningSchemeUid.Guid
Write-Host "$ProvSchemeUid found" -ForegroundColor Green

# Finding the catalog UID to attach the VM(s) to
Write-Host "Finding Catalog's UId... " -NoNewline
$Uid = (Get-BrokerCatalog -CatalogName $CatalogName).Uid
Write-Host "$Uid found" -ForegroundColor Green

# Listing the newly created VM(s) in order to add them to the catalog. "Brokered" tag means the VM is created but not attached
# We are listing those
$ProvVMS = Get-ProvVM -ProvisioningSchemeUid $ProvSchemeUid -MaxRecordCount 10000 | Where-Object { $_.Tag -ne "Brokered" }
Write-Host "Assigning newly created machines to $CatalogName..."
Write-Host "Virtual machines are as follows" -ForegroundColor Green
$ProvVMS.VMName


#Provising Actual VM's
$ProvVMS | Lock-ProvVM -ProvisioningSchemeUid $ProvSchemeUid -Tag 'Brokered'
$ProvVMS | ForEach-Object { New-BrokerMachine -CatalogUid $Uid -MachineName $_.ADAccountSid }

Write-Host "$count VDIs created in $CatalogName" -ForegroundColor Green

#Fetching Delivery Group Since the Folder Arrangement inside DaaS Console messes up the script...

$dg = Get-BrokerDesktopGroup -DesktopGroupName $DeliveryGroupName

#adding machines to the delivery Group
Write-Host "Adding Machines to the Delivery Group" -ForegroundColor Green
foreach ($vm in $ProvVMS.ADAccountName) 
{ Add-BrokerMachine -MachineName $vm -DesktopGroup $dg.Name }

#Once the Machines are added into the Delivery Group, need to put into Maintenance mode for Intune Policies to Push

# Write-Host "Putting Machines into the Maintenance Mode"

#  foreach ($vm in $ProvVMS.ADAccountName) 
#  { Set-BrokerMachine -MachineName $vm -InMaintenanceMode $true}

#Giving 1 Minute sleep time to sync the machines' power state with Studio and PowerON the machine.

Write-Host "1 Minute Sleep time to let machines sync their power states with Citrix DaaS"

Start-Sleep -Seconds 60

Write-Host "Turning ON the newly created Machines..."

foreach ($vm in $ProvVMS.ADAccountName) 
{ New-BrokerHostingPowerAction -Action TurnOn -MachineName $vm }

Write-Host "OK..."

Write-Host "Assigning Users to the VDIs based on the Email Addresses Provided..."

#Assigning VDIs to the Users

# Parse and clean email addresses
$emailList = $EmailAddress -replace '[\[\]"]' -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

Write-Host "Emails to be added: $EmailAddress"
Write-Host "Email Count: $($emailList.Count)"
Write-Host "Emails Parsed: $($emailList -join ', ')"

$machines = $ProvVMS.VMName

# Validate count matches
if ($emailList.Count -ne $VDICount) {
    throw "Mismatch in email and VDI count. Emails: $($emailList.Count), VDIs: $VDICount"
}

# Ensure email list and VM list are treated as arrays
$emailList = @($EmailAddress -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
$machines = @($ProvVMS.VMName)

Write-Host "Emails to be added: $($emailList -join ', ')"
Write-Host "Email Count: $($emailList.Count)"
Write-Host "Machine Count: $($machines.Count)"

# Assign users to VMs and record email-machine mapping

# Regex for matching a GUID (used for OID)
$guidRegex = '[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}'

# Map to track user-machine assignments
$vmEmailMap = @{}

# Loop through VMs and emails
for ($i = 0; $i -lt $VDICount; $i++) {
    $machine = $machines[$i]
    $userEmail = $emailList[$i]

    Write-Host "Assigning user $userEmail to machine $machine"

    try {
        $PrimaryClaimRaw = (Get-BrokerUser -Name $userEmail).PrimaryClaim
        $oidMatch = [regex]::Match($PrimaryClaimRaw, $guidRegex)

        if ($oidMatch.Success) {
            $PrimaryClaim = $oidMatch.Value
            $userClaim = "AzureAD:$CitrixIdpInstanceId\$Tenant\$PrimaryClaim"

            Add-BrokerUser -Name $userClaim -PrivateDesktop $machine -ErrorAction Stop

            $vmEmailMap[$machine] = $userEmail
            Write-Host "Assigned: $userEmail to $machine with OID $PrimaryClaim"
        }
        else {
            Write-Warning "Skipping user $userEmail - Could not extract OID from PrimaryClaim: $PrimaryClaimRaw"
            exit 1
        }
    }
    catch {
        Write-Error "Failed to assign $userEmail to $machine - $_"
        exit 1  # This will stop the script and signal failure to Jenkins
    }
}
#Import Azure Modules
Import-Module Az.Accounts -Force
# Wait for sync with Azure
Write-Host "Waiting for Azure sync before tagging..."
Start-Sleep -Seconds 30

# Azure login
$secureKey = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force
$AzureCredential = New-Object System.Management.Automation.PSCredential($clientId, $secureKey)

Disable-AzContextAutosave
Connect-AzAccount -Credential $AzureCredential -Tenant $Tenant -Subscription $SubscriptionId -ServicePrincipal
Write-Host "Successfully logged in to Azure" -ForegroundColor Green

# Tagging with expiration and owner
$currentDate = Get-Date
$expirationDate = $currentDate.AddDays(5).ToString('yyyy-MM-dd')

foreach ($vmName in $vmEmailMap.Keys) {
    $owner = $vmEmailMap[$vmName]

    try {
        $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -ErrorAction Stop
        $tags = $vm.Tags
        if (-not $tags) { $tags = @{} }

        $tags["ExpirationDate"] = $expirationDate
        $tags["Owner"] = $owner
        $tags["ExtendCount"] = "0"

        Set-AzResource -ResourceId $vm.Id -Tag $tags -Force -ErrorAction Stop
        Write-Host "$($vm.Name) tagged with Owner=$owner and ExpirationDate=$expirationDate"
    }
    catch {
        Write-Error "Failed to tag $vmName $_"
        exit 1  # This will stop the script and signal failure to Jenkins
    }
}

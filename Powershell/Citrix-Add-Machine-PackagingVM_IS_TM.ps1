param(
    [string]$CitrixCustomerId,
    [string]$CatalogName,
    [string]$expirationDate,
    [string]$Tenant,
    [string]$SubscriptionId,
    [string]$resourceGroupName,
    [string]$clientId,
    [string]$clientSecret,
    [string]$citrixClientId,
    [string]$citrixPassword,
    [string]$DeliveryGroupName,
    [string]$EmailAddress,
    [string]$CitrixIdpInstanceId,
    [int]$VDICount
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


Write-Host "1 Minute Sleep time to let machines sync their power states with Citrix DaaS"

Start-Sleep -Seconds 60

Write-Host "Turning ON the newly created Machines..."

foreach ($vm in $ProvVMS.ADAccountName) 
{ New-BrokerHostingPowerAction -Action TurnOn -MachineName $vm }

Write-Host "OK..."

Write-Host "Assigning Users to the VDIs based on the Email Addresses Provided..."


# Assign user to the VDI
$userEmail = $EmailAddress
# $PrimaryClaimRaw = (Get-BrokerUser -Name $userEmail).PrimaryClaim
# $userClaim = "AzureAD:$CitrixIdpInstanceId\$Tenant\$PrimaryClaimRaw"
# Add-BrokerUser -Name $userClaim -PrivateDesktop $vm -ErrorAction Stop
# Write-Host "Assigned: $userEmail to $vm with OID $PrimaryClaim"

$guidRegex = '[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}'

Write-Host "Assigning user $userEmail to machine $vm"

try {
    $PrimaryClaimRaw = (Get-BrokerUser -Name $userEmail).PrimaryClaim
    $oidMatch = [regex]::Match($PrimaryClaimRaw, $guidRegex)

    if ($oidMatch.Success) {
        $PrimaryClaim = $oidMatch.Value
        $userClaim = "AzureAD:$CitrixIdpInstanceId\$Tenant\$PrimaryClaim"
        Add-BrokerUser -Name $userClaim -PrivateDesktop $vm -ErrorAction Stop
        Write-Host "Assigned: $userEmail to $vm with OID $PrimaryClaim"
    } else {
        Write-Warning "OID not found in PrimaryClaim: $PrimaryClaimRaw"
        exit 1
    }
} catch {
    Write-Error "Failed to assign $userEmail to $vm - $_"
    exit 1
}

# Azure Login
Write-Host "Waiting for Azure sync before tagging..."
Start-Sleep -Seconds 30

$secureKey = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force
$AzureCredential = New-Object System.Management.Automation.PSCredential($clientId, $secureKey)

Disable-AzContextAutosave
Connect-AzAccount -Credential $AzureCredential -Tenant $Tenant -Subscription $SubscriptionId -ServicePrincipal
Write-Host "Successfully logged in to Azure" -ForegroundColor Green


try {
    $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $vm -ErrorAction Stop
    $tags = $vm.Tags
    if (-not $tags) { $tags = @{} }

    $tags["ExpirationDate"] = $expirationDate
    $tags["Owner"] = $userEmail
    $tags["ExtendCount"] = "0"

    Set-AzResource -ResourceId $vm.Id -Tag $tags -Force -ErrorAction Stop
    Write-Host "$($vm.Name) tagged with Owner=$userEmail and ExpirationDate=$expirationDate"
} catch {
    Write-Error "Failed to tag $machine $_"
    exit 1
}

# Get private IP
$nicId = $vm.NetworkProfile.NetworkInterfaces[0].Id
$nicName = ($nicId -split "/")[-1]
$nic = Get-AzNetworkInterface -ResourceGroupName $resourceGroupName -Name $nicName
$ipAddress = $nic.IpConfigurations[0].PrivateIpAddress

Write-Host "Private IP address of VM $($vm.Name): $ipAddress"

# Output for Jenkins
$machine | Out-File -FilePath "$env:WORKSPACE\vmName.txt" -Encoding utf8
$ipAddress | Out-File -FilePath "$env:WORKSPACE\vmIP.txt" -Encoding utf8

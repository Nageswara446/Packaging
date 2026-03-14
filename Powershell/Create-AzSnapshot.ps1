param(
    [string]$VMName,
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$TenantId,
    [string]$SubscriptionId
)


try {
    Write-Host "Connecting to Azure using Service Principal"

    $SecureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
    $Credential   = New-Object System.Management.Automation.PSCredential ($ClientId, $SecureSecret)

    Connect-AzAccount `
        -ServicePrincipal `
        -Tenant $TenantId `
        -Credential $Credential `
        -ErrorAction Stop | Out-Null

    if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
        throw "SubscriptionId is missing"
    }

    $SubscriptionId = $SubscriptionId.Trim()
    Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop

    Write-Host "Azure login successful. Subscription set: $SubscriptionId"
    Write-Host "Locating VM: $VMName"

    # Get VM across subscription (auto-detect RG)
    $vm = Get-AzVM | Where-Object { $_.Name -eq $VMName }

    if (-not $vm) {
        throw "VM '$VMName' not found in the current subscription"
    }

    $VmResourceGroup = $vm.ResourceGroupName
    $Location        = $vm.Location
    $VmTags          = $vm.Tags

    Write-Host "VM found in Resource Group: $VmResourceGroup"

    # Mandatory Owner tag check
    $OwnerName = $null
    if ($VmTags -and $VmTags.ContainsKey("Owner")) {
        $OwnerName = $VmTags["Owner"]
    }

    if ([string]::IsNullOrWhiteSpace($OwnerName)) {
        throw "Mandatory tag 'Owner' is missing or empty on VM '$VMName'. Snapshot creation aborted."
    }

    # Get OS Disk ID
    $OsDiskId = $vm.StorageProfile.OsDisk.ManagedDisk.Id

    if (-not $OsDiskId) {
        throw "OS disk not found for VM '$VMName'"
    }

    # Ensure Snapshot RG exists
	$SnapshotResourceGroup = "$VmResourceGroup-snapshots"
    if (-not (Get-AzResourceGroup -Name $SnapshotResourceGroup -ErrorAction SilentlyContinue)) {
        Write-Host "Creating snapshot resource group: $SnapshotResourceGroup"
        New-AzResourceGroup -Name $SnapshotResourceGroup -Location $Location | Out-Null
    }

    # Snapshot name
    $Timestamp    = Get-Date -Format "yyyyMMddHHmmss"
    $SnapshotName = "$VMName-SP-$Timestamp"

    # Snapshot tags (ONLY required)
    $SnapshotTags = @{
        Owner        = $OwnerName
        SourceVM     = $VMName
        SnapshotType = "OSDisk"
        CreatedBy    = "Jenkins"
        ExpiryDate   = (Get-Date).AddDays(3).ToString("yyyy-MM-dd HH:mm:ss")
    }

    Write-Host "Creating snapshot: $SnapshotName"
    Write-Host "Snapshot Resource Group: $SnapshotResourceGroup"

    # Snapshot configuration
    $snapshotConfig = New-AzSnapshotConfig `
        -SourceUri $OsDiskId `
        -Location $Location `
        -CreateOption Copy `
        -Tag $SnapshotTags

    # Create snapshot
    New-AzSnapshot `
        -Snapshot $snapshotConfig `
        -SnapshotName $SnapshotName `
        -ResourceGroupName $SnapshotResourceGroup `
        -ErrorAction Stop

    Write-Host "Snapshot created successfully: $SnapshotName"
      
	# Perist Jenkins Post-build
    "OWNER_EMAIL=$OwnerName" | Out-file "$env:WORKSPACE\env.properties" -Force
}
catch {
    Write-Error "Snapshot creation failed"
    Write-Error $_.Exception.Message
    throw   # Ensures Jenkins marks build as FAILED
}
finally {
    Write-Host "Snapshot job execution completed"
}



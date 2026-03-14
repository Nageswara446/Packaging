param(
    [string]$clientId,
    [string]$clientSecret,
    [string]$tenantId,
    [string]$resourceGroupName,
    [string]$subscriptionId,
    [string]$MasterVMName
)

# Authenticate using service principal
$securePassword = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$credential = New-Object PSCredential($clientId, $securePassword)

Disable-AzContextAutosave
Connect-AzAccount -Credential $credential -Tenant $tenantId -Subscription $subscriptionId -ServicePrincipal

try {
    # Get the VM in the specified resource group
    $vm = Get-AzVM -ResourceGroupName $resourceGroupName -Name $MasterVMName

    if ($vm -ne $null) {
        # Set deletion options for OS disk
        $vm.StorageProfile.OsDisk.DeleteOption = 'Delete'

        # Set deletion options for data disks
        $vm.StorageProfile.DataDisks | ForEach-Object {
            $_.DeleteOption = 'Delete'
        }

        # Set deletion options for network interfaces
        $vm.NetworkProfile.NetworkInterfaces | ForEach-Object {
            $_.DeleteOption = 'Delete'
        }

        # Update the VM with modified configuration
        Update-AzVM -ResourceGroupName $resourceGroupName -VM $vm

        # Remove the VM
        Remove-AzVM -ResourceGroupName $resourceGroupName -Name $vm.Name -Force

        Write-Output "Azure Virtual Machine '$($vm.Name)' successfully deleted."
    } else {
        Write-Output "Azure Virtual Machine '$MasterVMName' not found. No deletion needed."
    }
}
catch {
    # Handle errors
    Write-Error "An error occurred: $_"
}

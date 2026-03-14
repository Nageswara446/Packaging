$ClientId = $env:AZURE_CLIENT_ID
$ClientSecret = $env:AZURE_CLIENT_SECRET
$TenantId =  $env:AZURE_TENANT_ID
$VMName        = $env:vm_name
$TMUusername = $env:TMUusername
$TMUpassword  = $env:TMUpassword
$SnapshotName = $env:snapshot_name
$SubscriptionId = "a8f5ec46-78cf-4fba-a263-de3015560eff"

# -------------------------------
# Email Function
# -------------------------------
function Send-ScriptNotificationEmail {
    param(
        [Parameter(Mandatory)]$TMUusername,
        [Parameter(Mandatory)]$TMUpassword,
        [Parameter(Mandatory)]$Subject,
        [Parameter(Mandatory)]$Body,
        [Parameter(Mandatory)]$Recipient
    )

    $smtpServer = "tmu-cs.mail.allianz"
    $smtpFrom   = "wpsavcautomation@allianz.de"
    $timestamp  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    $Password   = ConvertTo-SecureString $TMUpassword -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential($TMUusername, $Password)

    Send-MailMessage `
        -SmtpServer $smtpServer `
        -Credential $Credential `
        -Port 587 `
        -From $smtpFrom `
        -To $Recipient `
        -Subject "$Subject - $timestamp" `
        -Body $Body `
        -BodyAsHtml `
        -UseSsl `
        -Priority High
}

# -------------------------------
# Azure Login
# -------------------------------
$SecureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
$Credential   = New-Object System.Management.Automation.PSCredential ($ClientId, $SecureSecret)

Connect-AzAccount `
    -ServicePrincipal `
    -Tenant $TenantId `
    -Credential $Credential `
    -ErrorAction Stop | Out-Null

Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop

# -------------------------------
# Locate Snapshot
# -------------------------------
$snapshot = Get-AzSnapshot | Where-Object { $_.Name -eq $SnapshotName }

$SnapshotOwner = $null
if ($snapshot -and $snapshot.Tags.ContainsKey("Owner")) {
    $SnapshotOwner = $snapshot.Tags["Owner"]
}

# -------------------------------
# Locate VM
# -------------------------------
$vm = Get-AzVM | Where-Object { $_.Name -eq $VMName }

# -------------------------------
# Validation & Email Logic
# -------------------------------
if (-not $vm -or -not $snapshot) {

    if (-not $SnapshotOwner) {
        throw "Owner tag not found on snapshot. Cannot send notification."
    }

    $errorMessage = @()
    if (-not $vm)       { $errorMessage += "VM '$VMName' not found." }
    if (-not $snapshot) { $errorMessage += "Snapshot '$SnapshotName' not found." }

    $emailBody = @"
Snapshot Restore Failed

Reason:
$($errorMessage -join "`n")

Requested VM: $VMName
Requested Snapshot: $SnapshotName
"@

    Send-ScriptNotificationEmail `
        -TMUusername $TMUusername `
        -TMUpassword $TMUpassword `
        -Subject "Snapshot Restore Failed" `
        -Body $emailBody `
        -Recipient $SnapshotOwner

    throw ($errorMessage -join " ")
}

# -------------------------------
# Extract VM Details
# -------------------------------
$VmRG      = $vm.ResourceGroupName
$Location  = $vm.Location
$OldOsDisk = $vm.StorageProfile.OsDisk.ManagedDisk.Id
$OldDiskName = ($OldOsDisk -split "/")[-1]

$VmZone = $vm.Zones

if (-not $VmZone) {
    throw "VM is non-zonal. Zone mismatch error should not occur."
}

$Zone =  $VmZone[0]
Write-Host "VM Zone detected: $Zone"

# -------------------------------
# Deallocate VM
# -------------------------------
Write-Host "Deallocating VM $VMName"
Stop-AzVM -Name $VMName -ResourceGroupName $VmRG -Force -ErrorAction Stop

# -------------------------------
# Create New OS Disk from Snapshot
# -------------------------------
$timestamp   = Get-Date -Format "yyyyMMddHHmmss"
$newDiskName = "$VMName-SPDisk-$timestamp"

Write-Host "Creating new OS disk: $newDiskName"

$diskConfig = New-AzDiskConfig `
    -Location $Location `
    -CreateOption Copy `
    -SourceResourceId $snapshot.Id `
  	-Zone $Zone `
  	-SkuName StandardSSD_LRS

$newDisk = New-AzDisk `
    -DiskName $newDiskName `
    -Disk $diskConfig `
    -ResourceGroupName $VmRG

# -------------------------------
# Update VM OS Disk
# -------------------------------
Write-Host "Updating VM OS disk"

$vm = Set-AzVMOSDisk `
    -VM $vm `
    -ManagedDiskId $newDisk.Id `
    -Name $newDiskName

Update-AzVM `
    -VM $vm `
    -ResourceGroupName $VmRG

# -------------------------------
# Start VM
# -------------------------------
Write-Host "Starting VM $VMName"
Start-AzVM -Name $VMName -ResourceGroupName $VmRG

# -------------------------------
# Delete Old OS Disk
# -------------------------------
Write-Host "Deleting old OS disk: $OldDiskName"
Remove-AzDisk `
    -ResourceGroupName $VmRG `
    -DiskName $OldDiskName `
    -Force

# -------------------------------
# Success Email
# -------------------------------
$successBody = @"
Snapshot Restore Completed Successfully

VM Name: $VMName
Snapshot Used: $SnapshotName
New OS Disk: $newDiskName
Old OS Disk Deleted: $OldDiskName
"@

Send-ScriptNotificationEmail `
    -TMUusername $TMUusername `
    -TMUpassword $TMUpassword `
    -Subject "Snapshot Restore Successful" `
    -Body $successBody `
    -Recipient $SnapshotOwner

Write-Host "Snapshot restore completed successfully."

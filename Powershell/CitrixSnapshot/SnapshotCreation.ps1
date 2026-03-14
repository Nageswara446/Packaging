$ClientId = $env:AZURE_CLIENT_ID
$ClientSecret = $env:AZURE_CLIENT_SECRET
$TenantId =  $env:AZURE_TENANT_ID
$VMName        = $env:vm_name
$TMUusername = $env:TMUusername
$TMUpassword  = $env:TMUpassword
$SubscriptionId = "a8f5ec46-78cf-4fba-a263-de3015560eff"

# -------------------------------
# Function: Get Business Expiry Date
# -------------------------------

function Get-BusinessExpiryDate {
    param (
        [Parameter(Mandatory)]
        [int]$BusinessDays
    )

    $date = Get-Date
    $addedDays = 0

    while ($addedDays -lt $BusinessDays) {
        $date = $date.AddDays(1)

        # Skip Saturday (6) and Sunday (0)
        if ($date.DayOfWeek -ne 'Saturday' -and $date.DayOfWeek -ne 'Sunday') {
            $addedDays++
        }
    }

    return $date
}



# -------------------------------
# Function: Send notification email
# -------------------------------
function Send-ScriptNotificationEmail {
    param(
        [Parameter(Mandatory = $true)]$TMUusername,
        [Parameter(Mandatory = $true)]$TMUpassword,
        [Parameter(Mandatory = $true)]$Subject,
        [Parameter(Mandatory = $true)]$Body,
        [Parameter(Mandatory = $true)]$Recipient
    )

    $smtpServer = "tmu-cs.mail.allianz"
    $smtpFrom   = "wpsavcautomation@allianz.de"
    $timestamp  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $messageSubject = "$Subject - $timestamp"

    # Convert password to secure string
    $Password = ConvertTo-SecureString $TMUpassword -AsPlainText -Force
    $credentials = New-Object System.Management.Automation.PSCredential($TMUusername, $Password)

    try {
        Send-MailMessage -SmtpServer $smtpServer `
                         -Credential $credentials `
                         -Port 587 `
                         -From $smtpFrom `
                         -To $Recipient `
                         -Subject $messageSubject `
                         -Body $Body `
                         -BodyAsHtml `
                         -UseSsl `
                         -Priority High
        Write-Host "Email sent successfully to $Recipient"
    }
    catch {
        Write-Host "Email failed: $($_.Exception.Message)"
        throw
    }
}

# -------------------------------
# Main script: Snapshot creation
# -------------------------------
try {
    Write-Host "Connecting to Azure using Service Principal"

    # Convert SP secret to secure string
    $SecureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
    $Credential   = New-Object System.Management.Automation.PSCredential ($ClientId, $SecureSecret)

    # Connect to Azure
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

    # Get VM
    $vm = Get-AzVM | Where-Object { $_.Name -eq $VMName }

    if (-not $vm) {
        throw "VM '$VMName' not found in the current subscription"
    }

    $VmResourceGroup = $vm.ResourceGroupName
    $Location        = $vm.Location
    $VmTags          = $vm.Tags

    Write-Host "VM found in Resource Group: $VmResourceGroup"

    # Check Owner tag
    if ($VmTags -and $VmTags.ContainsKey("Owner")) {
        $OwnerName = $VmTags["Owner"]
    }

    $OwnerName

    if ([string]::IsNullOrWhiteSpace($OwnerName)) {
        throw "Mandatory tag 'Owner' is missing or empty on VM '$VMName'. Snapshot creation aborted."
    }

    # Convert Owner username to email if needed
    $OwnerEmail = $OwnerName
    Write-Host "Email recipient: $OwnerEmail"

    # Get OS Disk ID
    $OsDiskId = $vm.StorageProfile.OsDisk.ManagedDisk.Id
    if (-not $OsDiskId) {
        throw "OS disk not found for VM '$VMName'"
    }

    # Snapshot Resource Group
    $SnapshotResourceGroup = "$VmResourceGroup-snapshots"
    if (-not (Get-AzResourceGroup -Name $SnapshotResourceGroup -ErrorAction SilentlyContinue)) {
        Write-Host "Creating snapshot resource group: $SnapshotResourceGroup"
        New-AzResourceGroup -Name $SnapshotResourceGroup -Location $Location | Out-Null
    }

    # Snapshot name
    $Timestamp    = Get-Date -Format "yyyyMMddHHmmss"
    $SnapshotName = "$VMName-SP-$Timestamp"

    $BusinessDays = "5"
    $ExpiryDate = Get-BusinessExpiryDate -BusinessDays $BusinessDays

    # Snapshot tags
    $SnapshotTags = @{
        Owner        = $OwnerName
        SourceVM     = $VMName
        SnapshotType = "OSDisk"
        CreatedBy    = "Jenkins"
        ExpiryDate   = $ExpiryDate.ToString("yyyy-MM-dd HH:mm:ss")
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

    # Email HTML body
    $htmlBody = @"
<html>
<body style='font-family: Arial, sans-serif; line-height: 1.5; color: #333333;'>
<p>The snapshot <strong>$SnapshotName</strong> for virtual machine <strong>$VMName</strong> has been created successfully.</p>
<p>Resource Group: <strong>$SnapshotResourceGroup</strong></p>
<p>Owner: <strong>$OwnerEmail</strong></p>
</body>
</html>
"@

    # Send email
    Send-ScriptNotificationEmail -TMUusername $TMUusername -TMUpassword $TMUpassword -Subject "VM Snapshot Created" -Body $htmlBody -Recipient $OwnerEmail

}
catch {
    Write-Error "Snapshot creation failed"
    Write-Error $_.Exception.Message
    throw
}




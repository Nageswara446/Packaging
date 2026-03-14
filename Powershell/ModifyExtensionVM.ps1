param(
    [string]$clientId,
    [string]$clientSecret,
    [string]$tenantId,
    [string]$resourceGroupName,
    [string]$subscriptionId,
    [string]$TMUusername,
    [string]$TMUpassword,
    [string]$vmName,
    [string]$emailRecipient
)

# Authenticate using service principal
$securePassword = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$credential = New-Object PSCredential($clientId, $securePassword)

Disable-AzContextAutosave

Connect-AzAccount -Credential $credential -Tenant $tenantId -Subscription $subscriptionId -ServicePrincipal

Get-AzContext

Write-Host "VMName: $vmName"
Write-Host "emailaddress: $emailRecipient"

# Function to send email
function Send-ScriptNotificationEmail {
    param(
        [Parameter(Mandatory = $true)]$TMUusername,
        [Parameter(Mandatory = $true)]$TMUpassword,
        [Parameter(Mandatory = $true)]$Subject,
        [Parameter(Mandatory = $true)]$Body,
        [Parameter(Mandatory = $true)]$Recipient
    )

    $smtpServer = "tmu-cs.mail.allianz"
    $smtpFrom = "wpsavcautomation@allianz.de"
    $timestamp = (Get-Date).ToString("yyyy-MM-dd")  # Add timestamp to subject
    $messageSubject = "$Subject - $timestamp"

    $UserName = $TMUusername
    $Password = ConvertTo-SecureString $TMUpassword -AsPlainText -Force

    $credentials = New-Object System.Management.Automation.PSCredential($UserName, $Password)

    Send-MailMessage -SmtpServer $smtpServer -Credential $credentials -Port "587" -From $smtpFrom -To $Recipient -Subject $messageSubject -Body $Body -BodyAsHtml -UseSsl -Priority High
}

# Get the VM
$vm = Get-AzVM -ResourceGroupName $resourceGroupName -VMName $vmName

# Get the current expiration date and extend count from tags
$currentExpirationDate = $vm.Tags["ExpirationDate"]
$extendCount = [int]$vm.Tags["ExtendCount"]

# Check if extend count is less than 5
if ($extendCount -lt 5) {
    # Get the current date and time
    $currentDateTime = Get-Date
    $currentDateTimeFormatted = $currentDateTime.ToString('yyyy-MM-dd')
    Write-Host "CurrentDateTime : $currentDateTimeFormatted"

    # Calculate the new expiration date (current date + 24 hours)
    $newExpirationDate = $currentDateTime.AddHours(24)
    $newExpirationDateFormatted = $newExpirationDate.ToString('yyyy-MM-dd')

    # Update the VM tags
    $vm.Tags["ExpirationDate"] = $newExpirationDateFormatted
    $vm.Tags["ExtendCount"] = $extendCount + 1

    # Update the VM in Azure
    Update-AzVM -VM $vm -ResourceGroupName $resourceGroupName

    Write-Host "VM expiration date extended successfully. New Expiration Date: $newExpirationDateFormatted"

    # Send an email notification for the new expiration date
    $emailSubject = "VM Expiration Date Extended for: $vmName"
    $emailBody = "The expiration date for VM $vmName has been extended to $newExpirationDateFormatted."
    Send-ScriptNotificationEmail -TMUusername $TMUusername -TMUpassword $TMUpassword -Subject $emailSubject -Body $emailBody -Recipient $emailRecipient
    Write-Host "Email notification sent."
} else {
    # Send an email notification for the extension count exceeding the limit
    $emailSubject = "Extension Count Exceeded for VM: $vmName"
    $emailBody = "The extension count for VM $vmName has exceeded the limit of 5. Cannot extend the VM expiration date further."
    Send-ScriptNotificationEmail -TMUusername $TMUusername -TMUpassword $TMUpassword -Subject $emailSubject -Body $emailBody -Recipient $emailRecipient
    Write-Host "Email notification sent: Extension count exceeded."
}

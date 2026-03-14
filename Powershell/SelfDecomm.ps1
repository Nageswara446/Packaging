param(
    [string]$clientId,
    [string]$clientSecret,
    [string]$tenantId,
    [string]$resourceGroupName,
    [string]$subscriptionId,
    [string]$TMUusername,
    [string]$TMUpassword
)

# Authenticate using service principal
$securePassword = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$credential = New-Object PSCredential($clientId, $securePassword)

Disable-AzContextAutosave

Connect-AzAccount -Credential $credential -Tenant $tenantId -Subscription $subscriptionId -ServicePrincipal

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
    $messageSubject = "$Subject"

    $UserName = $TMUusername
    $Password = ConvertTo-SecureString $TMUpassword -AsPlainText -Force

    $credentials = New-Object System.Management.Automation.PSCredential($UserName, $Password)

    Send-MailMessage -SmtpServer $smtpServer -Credential $credentials -Port "587" -From $smtpFrom -To $Recipient -Subject $messageSubject -Body $Body -BodyAsHtml -UseSsl -Priority High
}

# Get VMs in the specified resource group
$vms = Get-AzVM -ResourceGroupName $resourceGroupName

# Check if there are no VMs
if ($null -eq $vms) {
    Write-Host "No VMs found in the resource group: $resourceGroupName"
} else {
    # Get the current date and time
    $currentDateTime = Get-Date
    $currentDateTimeFormatted = $currentDateTime.ToString('yyyy-MM-dd')
    Write-Host "CurrentDateTime : $currentDateTimeFormatted"

    # Display information about each VM and check the expiration date
    foreach ($vm in $vms) {
        $vm.StorageProfile.OsDisk.DeleteOption = 'Delete'
        $vm.StorageProfile.DataDisks | ForEach-Object { $_.DeleteOption = 'Delete' }
        $vm.NetworkProfile.NetworkInterfaces | ForEach-Object { $_.DeleteOption = 'Delete' }

        Update-AzVM -ResourceGroupName $resourceGroupName -VM $vm

        Write-Host "VM Name: $($vm.Name)"
        Write-Host "Resource Group: $($vm.ResourceGroupName)"

        # Get VM tags
        $tags = (Get-AzResource -ResourceGroupName $resourceGroupName -ResourceName $vm.Name -ResourceType Microsoft.Compute/virtualMachines).Tags

        # Check if the 'expirationdate' and 'Owner' tags exist and contain data
        if ($tags -and $tags.ExpirationDate -ne $null -and $tags.Owner -ne $null -and $tags.ExpirationDate.Trim() -ne "" -and $tags.Owner.Trim() -ne "") {
            # Continue processing only if both tags contain data

            # Check if VM is scheduled for decommission in the future
            if ($tags.ExpirationDate -ge $currentDateTimeFormatted) {
                Write-Host "Expiration Date: $($tags.ExpirationDate) - VM is scheduled for decommission."

                # Calculate days until decommission
                $daysUntilDecommission = $tags.ExpirationDate

                $Subject1 = "Information - Packaging VM Decommission Scheduled on $daysUntilDecommission"

                # Construct the URL for the hyperlink
                $baseUrl = "https://avc-prod-jenkins.srv.allianz/generic-webhook-trigger/invoke"
                $token = "PackageVM-Extension"
                $VMName = $vm.Name
                $EmailAddress = $tags.Owner
                $postponeUrl = "$baseUrl" + "?" + "token=$token&VMName=$VMName&EmailAddress=$EmailAddress"

    # Create the HTML body with the refined language
    $htmlBody = @"
    <html>
    <body>
    <p>The virtual machine $($vm.Name) is scheduled for decommission on $daysUntilDecommission.</p>
    <p>If you wish to postpone the decommission, kindly click <a href="$postponeUrl" alt="Postpone Decommission">here</a>. In case no further packaging VM is needed, feel free to disregard this notification.</p>
    <p style="color: red;">Important: Please note that this action should be performed only once.</p>
    <p style="color: red;">After clicking the link, automatically open a new browser window or tab and navigate to the Jenkins URL. Please wait for 5 minutes to receive an extension email notification.</p>
    </body>
    </html>
"@

                # Send Type 2 email with the calculated days
                #$htmlBody = "The VM Name: $($vm.Name) is scheduled for decommission on $daysUntilDecommission."
                Send-ScriptNotificationEmail -TMUusername $TMUusername -TMUpassword $TMUpassword -Subject $Subject1 -Body $htmlBody -Recipient $tags.Owner
            }

            # Check if VM has already been decommissioned or expiration date is less than or equal to the current date
            if ($tags.ExpirationDate -le $currentDateTimeFormatted) {
                Write-Host "Expiration Date: $($tags.ExpirationDate) - VM has been decommissioned!"

                $Subject2 = "Alert - Packaging VM Decommissioned"

                # Send Type 1 email
                $htmlBody = "The VM Name: $($vm.Name) has been decommissioned."
                Send-ScriptNotificationEmail -TMUusername $TMUusername -TMUpassword $TMUpassword -Subject $Subject2 -Body $htmlBody -Recipient $tags.Owner

                # Remove the VM
                Remove-AzVM -ResourceGroupName $resourceGroupName -Name $vm.Name -Force
            }
        } else {
            Write-Host "Owner or ExpirationDate tags are null or empty for VM $($vm.Name). Removing the VM."

            $Subject3 = "Alert - Packaging VM Removed"

            # Send email to admin
            $htmlBody = "Owner or ExpirationDate tags are null or empty for VM Name: $($vm.Name). The VM has been removed."
            Send-ScriptNotificationEmail -TMUusername $TMUusername -TMUpassword $TMUpassword -Subject $Subject3 -Body $htmlBody -Recipient "extern.allam_nageshwara@allianz.de"

            # Remove the VM
            Remove-AzVM -ResourceGroupName $resourceGroupName -Name $vm.Name -Force
        }
    }
}


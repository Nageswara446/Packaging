
param(
    [string]$clientId,
    [string]$clientSecret,
    [string]$tenantId,
    [string]$resourceGroupName,
    [string]$subscriptionId,
    [string]$CitrixCustomerId,
    [string]$CatalogName,
    [string]$DeliveryGroupName,
    [string]$citrixClientId,
    [string]$citrixPassword,
    [string]$TMUusername,
    [string]$TMUpassword
)

# Authenticate using service principal
$securePassword = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$credential = New-Object PSCredential($clientId, $securePassword)



Disable-AzContextAutosave

Connect-AzAccount -Credential $credential -Tenant $tenantId -Subscription $subscriptionId -ServicePrincipal

#Connecting to Citrix Cloud
Set-XDCredentials -CustomerId $CitrixCustomerId -APIKey $citrixClientId -SecretKey $citrixPassword -ProfileType CloudApi -StoreAs "CitrixEUPackagingConnection"
Get-XDAuthentication -ProfileName "CitrixEUPackagingConnection"
Write-Host "Successfully logged in to the Citrix Cloud" -ForegroundColor Green


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
}
else {
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

            # Parse the expiration date
            $expirationDate = [datetime]::ParseExact($tags.ExpirationDate, 'yyyy-MM-dd', $null)
            $currentDate = (Get-Date).Date
            $daysUntilDecommission = ($expirationDate - $currentDate).Days

            # Trigger email only if 1 days are left
            if ($daysUntilDecommission -eq 1) {
                Write-Host "Expiration Date: $($tags.ExpirationDate) - VM is scheduled for decommission."        

                $Subject1 = "Information - TestMachine VM Decommission Scheduled on $expirationdate "

                # Construct the URL for the hyperlink
                $baseUrl = "https://avc-prod-jenkins.srv.allianz/generic-webhook-trigger/invoke"
                $token = "TMVM-Extension"
                $VMName = $vm.Name
                $EmailAddress = $tags.Owner
                $postponeUrl = "$baseUrl" + "?" + "token=$token&VMName=$VMName&EmailAddress=$EmailAddress"

                # Create the HTML body with the refined language
                $htmlBody = @"
    <html>
    <body style='font-family: Arial, sans-serif; line-height: 1.5; color: #333333;'>
        <p>The virtual machine <strong>$($vm.Name)</strong> is scheduled for decommission in <strong>$daysUntilDecommission day(s)</strong>.</p>
        <p>If you wish to postpone the decommission, kindly click 
        <a href='$postponeUrl' style='color: #1a73e8; text-decoration: none;' alt='Postpone Decommission'>here</a>. 
        If no further Test Machine VM is needed, feel free to disregard this notification.</p>
        <p style='color: #d9534f; font-weight: bold;'>Important:</p>
        <ul style='color: #d9534f;'>
        <li>Please perform this action only once.</li>
        <li>After clicking the link, a new browser window or tab will automatically open and navigate to the Jenkins URL.</li>
        <li>Please wait for 5 minutes to receive the extension email notification.</li>
        </ul>
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

                $Subject2 = "Alert - TestMachine VM Decommissioned"

                # Send Type 1 email
                $htmlBody = "The VM Name: $($vm.Name) has been decommissioned."
                Send-ScriptNotificationEmail -TMUusername $TMUusername -TMUpassword $TMUpassword -Subject $Subject2 -Body $htmlBody -Recipient $tags.Owner

                # Get the BrokerMachine once
                $brokerMachines = Get-BrokerMachine -MachineName $vm.Name
                $brokercatalog = (get-brokercatalog -CatalogName $CatalogName).CatalogName


                Write-Host "CatalogName is $brokercatalog "
                

                if ($brokerMachines) {
                    foreach ($vdi in $brokerMachines) {
                        $machineName = $vdi.MachineName

                        Write-Host "Setting machine $machineName into Maintenance mode"
                        Set-BrokerMachine -MachineName $machineName -InMaintenanceMode $true

                        Write-Host "Powering off machine $machineName"
                        New-BrokerHostingPowerAction -Action TurnOff -MachineName $machineName


                        if ($vdi.DesktopGroupName) {
                            Write-Host "Removing $($vdi.MachineName) from Delivery Group $($vdi.DesktopGroupName)"
                            Write-Host "Removing Machine from Delivery Group"
                            Remove-BrokerMachine -InputObject $vdi -DesktopGroup $vdi.DesktopGroupName -Force
                        }
                        else {
                            Write-Host "$($vdi.MachineName) is not part of any Delivery Group, removing from Broker DB"
                        }


                        $adsid = $vdi.Sid
                        Remove-AcctADAccount -IdentityPoolName $brokercatalog -ADAccountSid $adsid -RemovalOption None -UseServiceAccount -Force

                        Write-Host "Unlocking and removing VM $machineName from provisioning"
                        Get-ProvVM -VMName $machineName | Unlock-ProvVM
                        Get-ProvVM -VMName $machineName | Remove-ProvVM

                        Remove-BrokerMachine $machineName

                        Write-Host "Machine $machineName has been fully decommissioned."
                    }
                }
                else {
                    Write-Warning "Broker machine for $($vm.Name) not found. Skipping decommissioning steps."
                }


            }
        }
        else {
            Write-Host "Owner or ExpirationDate tags are null or empty for VM $($vm.Name). Removing the VM."

            $Subject3 = "Alert - TestMachine VM Removed"

            # Send email to admin
            $htmlBody = "Owner or ExpirationDate tags are null or empty for VM Name: $($vm.Name). The VM has been removed."
            Send-ScriptNotificationEmail -TMUusername $TMUusername -TMUpassword $TMUpassword -Subject $Subject3 -Body $htmlBody -Recipient "extern.allam_nageshwara@allianz.de"

            # Get the BrokerMachine once
            $brokerMachines = Get-BrokerMachine -MachineName $vm.Name
            $brokercatalog = (get-brokercatalog -CatalogName $CatalogName).CatalogName

            Write-Host "CatalogName is $brokercatalog "

            if ($brokerMachines) {
                foreach ($vdi in $brokerMachines) {
                    $machineName = $vdi.MachineName

                    Write-Host "Setting machine $machineName into Maintenance mode"
                    Set-BrokerMachine -MachineName $machineName -InMaintenanceMode $true

                    Write-Host "Powering off machine $machineName"
                    New-BrokerHostingPowerAction -Action TurnOff -MachineName $machineName


                    if ($vdi.DesktopGroupName) {
                        Write-Host "Removing $($vdi.MachineName) from Delivery Group $($vdi.DesktopGroupName)"
                        Write-Host "Removing Machine from Delivery Group"
                        Remove-BrokerMachine -InputObject $vdi -DesktopGroup $vdi.DesktopGroupName -Force
                    }
                    else {
                        Write-Host "$($vdi.MachineName) is not part of any Delivery Group, removing from Broker DB"
                    }

                    $adsid = $vdi.Sid
                    Remove-AcctADAccount -IdentityPoolName $CatalogName -ADAccountSid $adsid -RemovalOption None -UseServiceAccount -Force

                    Write-Host "Unlocking and removing VM $machineName from provisioning"
                    Get-ProvVM -VMName $machineName | Unlock-ProvVM
                    Get-ProvVM -VMName $machineName | Remove-ProvVM

                    Remove-BrokerMachine $machineName

                    Write-Host "Machine $machineName has been fully decommissioned."
                }
            }
            else {
                Write-Warning "Broker machine for $($vm.Name) not found. Skipping decommissioning steps."
            }
        }
    }
}


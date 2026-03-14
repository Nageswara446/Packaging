param(
    [string]$clientId,
    [string]$clientSecret,
    [string]$tenantId,
    [string]$subscriptionId,
    [string]$SnapshotResourceGroup,
    [string]$TMUusername,
    [string]$TMUpassword
)

# -------------------------------------------------
# AUTHENTICATION
# -------------------------------------------------
$securePassword = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$credential = New-Object PSCredential($clientId, $securePassword)

Disable-AzContextAutosave
Connect-AzAccount -Credential $credential `
                  -Tenant $tenantId `
                  -Subscription $subscriptionId `
                  -ServicePrincipal

# -------------------------------------------------
# EMAIL FUNCTION
# -------------------------------------------------
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

    $securePwd = ConvertTo-SecureString $TMUpassword -AsPlainText -Force
    $cred      = New-Object PSCredential($TMUusername, $securePwd)

    Send-MailMessage `
        -SmtpServer $smtpServer `
        -Credential $cred `
        -Port 587 `
        -From $smtpFrom `
        -To $Recipient `
        -Subject $Subject `
        -Body $Body `
        -BodyAsHtml `
        -UseSsl `
        -Priority High
}

# -------------------------------------------------
# SNAPSHOT PROCESSING
# -------------------------------------------------
$currentDateTime = Get-Date
Write-Host "Current DateTime: $currentDateTime"

$snapshots = Get-AzSnapshot -ResourceGroupName $SnapshotResourceGroup

if (-not $snapshots) {
    Write-Host "No snapshots found in RG: $SnapshotResourceGroup"
    return
}

foreach ($snap in $snapshots) {

    Write-Host "-----------------------------------------"
    Write-Host "Snapshot Name: $($snap.Name)"

    $tags = $snap.Tags

    # -------------------------------------------------
    # TAG VALIDATION
    # -------------------------------------------------
    if (-not $tags -or
        -not $tags.ExpiryDate -or
        -not $tags.Owner -or
        $tags.ExpiryDate.Trim() -eq "" -or
        $tags.Owner.Trim() -eq "") {

        Write-Host "Missing Owner or ExpiryDate tag"

        $htmlBody = "Snapshot <b>$($snap.Name)</b> has missing Owner or ExpiryDate tags and will be deleted."

        Send-ScriptNotificationEmail `
            -TMUusername $TMUusername `
            -TMUpassword $TMUpassword `
            -Subject "Alert - Snapshot Removed (Invalid Tags)" `
            -Body $htmlBody `
            -Recipient "extern.allam_nageshwara@allianz.de"

        Remove-AzSnapshot -ResourceGroupName $SnapshotResourceGroup -SnapshotName $snap.Name -Force
        continue
    }

    # -------------------------------------------------
    # PARSE EXPIRY DATE (yyyy-MM-dd HH:mm:ss)
    # -------------------------------------------------
    try {
        $expiryDateTime = [datetime]::ParseExact(
            $tags.ExpiryDate,
            'yyyy-MM-dd HH:mm:ss',
            $null
        )
    }
    catch {
        Write-Host "Invalid ExpiryDate format on snapshot $($snap.Name)"

        Remove-AzSnapshot -ResourceGroupName $SnapshotResourceGroup -SnapshotName $snap.Name -Force
        continue
    }

    $ownerEmail = $tags.Owner

    # -------------------------------------------------
    # FUTURE EXPIRY → INFO EMAIL
    # -------------------------------------------------
    if ($expiryDateTime -gt $currentDateTime) {

        $subject = "Information - Snapshot Expiry Scheduled on $($expiryDateTime.ToString('yyyy-MM-dd HH:mm:ss'))"

        $htmlBody = @"
        <html>
        <body>
        <p>The snapshot <b>$($snap.Name)</b> is scheduled for deletion on:</p>
        <p><b>$($expiryDateTime.ToString('yyyy-MM-dd HH:mm:ss'))</b></p>
        <p style="color:red;">This snapshot will be automatically deleted after expiry.</p>
        </body>
        </html>
"@

        Send-ScriptNotificationEmail `
            -TMUusername $TMUusername `
            -TMUpassword $TMUpassword `
            -Subject $subject `
            -Body $htmlBody `
            -Recipient $ownerEmail
    }

    # -------------------------------------------------
    # EXPIRED → DELETE + ALERT
    # -------------------------------------------------
    if ($expiryDateTime -le $currentDateTime) {

        Write-Host "Snapshot expired. Deleting..."

        Remove-AzSnapshot -ResourceGroupName $SnapshotResourceGroup -SnapshotName $snap.Name -Force

        $subject = "Alert - Snapshot Deleted"

        $htmlBody = @"
        <html>
        <body>
        <p>The snapshot <b>$($snap.Name)</b> has been deleted as per expiration policy.</p>
        <p>Deletion Date: $($currentDateTime.ToString('yyyy-MM-dd HH:mm:ss'))</p>
        </body>
        </html>
"@

        Send-ScriptNotificationEmail `
            -TMUusername $TMUusername `
            -TMUpassword $TMUpassword `
            -Subject $subject `
            -Body $htmlBody `
            -Recipient $ownerEmail
    }
}

Write-Host "Snapshot decommission process completed."

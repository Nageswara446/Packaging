function Invoke-JenkinsSnapshotWebhook {
    param (
        [Parameter(Mandatory)]
        [string]$JenkinsWebhookUrl,

        [Parameter(Mandatory)]
        [string]$JenkinsToken
    )

    $hostname = $env:COMPUTERNAME

    $payload = @{
        HOSTNAME = $hostname
    } | ConvertTo-Json

    Invoke-RestMethod `
        -Uri "$JenkinsWebhookUrl?token=$JenkinsToken" `
        -Method POST `
        -Body $payload `
        -ContentType "application/json" `
        -TimeoutSec 15
}

# Example call
Invoke-JenkinsSnapshotWebhook `
    -JenkinsWebhookUrl "https://jenkins.company.com/generic-webhook-trigger/invoke" `
    -JenkinsToken "SNAPSHOT_TRIGGER_TOKEN"

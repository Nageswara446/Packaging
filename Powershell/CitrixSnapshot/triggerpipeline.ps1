# PowerShell Script: TriggerJenkins.ps1

# Variables
$jenkinsUrl = "https://avc-prod-jenkins.srv.allianz/generic-webhook-trigger/invoke"
$hostname = $env:COMPUTERNAME  # Automatically gets the hostname of the VM
# Construct the URL for the hyperlink
$baseUrl = "https://avc-prod-jenkins.srv.allianz/generic-webhook-trigger/invoke"
$token = "PackagingTestVMSnapshot"
$postponeUrl = "$baseUrl" + "?" + "token=$token&vm_name=$hostname"


# Trigger Jenkins Job
try {
    Write-Host "Triggering Jenkins job for VM: $hostname"
    Invoke-RestMethod -Uri $postponeUrl -Method Post -ContentType "application/json"
    Write-Host "Jenkins job triggered successfully."
} catch {
    Write-Host "Failed to trigger Jenkins job: $_" -ForegroundColor Red
}

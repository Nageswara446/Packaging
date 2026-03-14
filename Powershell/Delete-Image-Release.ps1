param(
    [string]$clientId,
    [string]$clientSecret,
    [string]$tenantId,
    [string]$resourceGroupName,
    [string]$subscriptionId,
    [string]$galleryName,
    [string]$imageName,
    [string]$imageVersion
)

# Authenticate using service principal
$securePassword = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$credential = New-Object PSCredential($clientId, $securePassword)

Disable-AzContextAutosave
Connect-AzAccount -Credential $credential -Tenant $tenantId -Subscription $subscriptionId -ServicePrincipal

# Check if the compute gallery image version exists in the current region
$versionExists = Get-AzGalleryImageVersion -GalleryName $galleryName -GalleryImageDefinitionName $imageName -GalleryImageVersionName $imageVersion -ResourceGroupName $resourceGroupName | Select -ExpandProperty Name -ErrorAction SilentlyContinue
Write-Host "Image(s) to be deleted $versionExists"
if ($versionExists) {
    # Remove the compute gallery image version in the current region
    foreach ($version in $versionExists) {
    Remove-AzGalleryImageVersion -GalleryName $galleryName -GalleryImageDefinitionName $imageName -Name $version -ResourceGroupName $resourceGroupName -Force
    Write-Host "Deleted Image version $version"}
} else {
    Write-Host "Version $imageVersion does not exist. No deletion needed."
}

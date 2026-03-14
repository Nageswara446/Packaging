param(
    [string]$CitrixCustomerId,
    [string]$NamingSchemeType,
    [string]$citrixClientId,
    [string]$EmailAddress,
    [string]$Datacenter,
    [string]$citrixPassword
)


# Static mapping for each Datacenter
switch ($Datacenter.ToUpper()) {
    "CE1" {
        $CatalogName = "1_DEV_AVCAOCLIENTS_CE1AO"
        $DeliveryGroupName = "1_DEV_AVCAOCLIENTS_CE1AO"
        $NamingScheme = "VDDW-AOE1####"
    }
    "CE2" {
        $CatalogName = "1_DEV_AVCAOCLIENTS_CE2AO"
        $DeliveryGroupName = "1_DEV_AVCAOCLIENTS_CE2AO"
        $NamingScheme = "VDDW-AOE2####"
    }
    "CAP1" {
        $CatalogName = "1_DEV_AVCAOCLIENTS_CAP1AO"
        $DeliveryGroupName = "1_DEV_AVCAOCLIENTS_CAP1AO"
        $NamingScheme = "VDDW-AOA1####"
    }
    "CAP2" {
        $CatalogName = "1_DEV_AVCAOCLIENTS_CAP2AO"
        $DeliveryGroupName = "1_DEV_AVCAOCLIENTS_CAP2AO"
        $NamingScheme = "VDDW-AOA2####"
    }
    "CNA1" {
        $CatalogName = "1_DEV_AVCAOCLIENTS_CNA1AO"
        $DeliveryGroupName = "1_DEV_AVCAOCLIENTS_CNA1AO"
        $NamingScheme = "VDDW-AON1####"
    }
    "CNA2" {
        $CatalogName = "1_DEV_AVCAOCLIENTS_CNA2AO"
        $DeliveryGroupName = "1_DEV_AVCAOCLIENTS_CNA2AO"
        $NamingScheme = "VDDW-AON2####"
    }
    Default {
        throw "Invalid Datacenter '$Datacenter'"
    }
}



# #  Get bearer token

# get bearer token
$CitrixAuthAPIBaseURL = 'api.cloud.com'

$ErrorActionPreference = 'Stop'

$URL = "https://${CitrixAuthAPIBaseURL}/cctrustoauth2/${CitrixCustomerId}/tokens/clients"
$Body = "grant_type=client_credentials&client_id=${citrixClientId}&client_secret=${citrixPassword}"
$Response = Invoke-RestMethod -Method 'Post' -Uri $URL -Body $Body -ContentType 'application/x-www-form-urlencoded'
$BearerToken = $Response.access_token
if ([string]::IsNullOrEmpty($BearerToken))
{
    throw 'Cannot retrieve bearer token.'
}
Write-Host "Retrieved bearer token successfully."


#  Get Site ID 
function Get-SiteId {
    param([string]$bearerToken, [string]$CitrixCustomerId)
    $headers = @{
        "Accept"            = "application/json"
        "Authorization"     = "CWSAuth Bearer=$bearerToken"
        "Citrix-CustomerId" = $CitrixCustomerId
    }
    $uri = "https://${CitrixAuthAPIBaseURL}/cvad/manage/me"
    $me = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers
    return $me.Customers[0].Sites[0].Id
}

$siteId = Get-SiteId -bearerToken $bearerToken -CitrixCustomerId $CitrixCustomerId
Write-Host "Fetched Site ID: $siteId" -ForegroundColor Green

# Get Catalog ID 
$headers = @{
    "Accept"            = "application/json"
    "Authorization"     = "CWSAuth Bearer=$bearerToken"
    "Citrix-CustomerId" = $CitrixCustomerId
    "Citrix-InstanceId" = $siteId
}
Write-Host "Looking up catalog $CatalogName..."
$catalogs = Invoke-RestMethod -Uri "https://${CitrixAuthAPIBaseURL}/cvad/manage/MachineCatalogs" -Headers $headers
$catalog = $catalogs.Items | Where-Object { $_.Name -eq $CatalogName }

if (-not $catalog) {
    Write-Error "Catalog $CatalogName not found"
    exit 1
}
$catalogId = $catalog.Id
Write-Host "Found catalog: $($catalog.Name) (Id: $catalogId)" -ForegroundColor Green

# Build inner and batch body
$innerBody = @{
    MachineAccountCreationRules = @{
        NamingScheme     = $NamingScheme
        NamingSchemeType = $NamingSchemeType
    }
}

# Convert the inner body to a stringified JSON (this is critical!)
$innerJson = ($innerBody | ConvertTo-Json -Compress -Depth 5)

# Build batch body (Citrix requires Body as string, not nested object)
$batchBody = @{
    Items = @(
        @{
            Reference   = "0"
            Method      = "POST"
            RelativeUrl = "/MachineCatalogs/$catalogId/Machines"
            Headers     = @(
                @{ Name = "X-CC-Locale"; Value = "en" },
                @{ Name = "Citrix-CustomerId"; Value = $CitrixCustomerId },
                @{ Name = "Citrix-InstanceId"; Value = $siteId }
            )
            Body        = $innerJson    
            ObjectCount = $VDICount
        }
    )
}

$jsonBody = $batchBody | ConvertTo-Json -Compress -Depth 10



# Submit batch request ===
$batchUri = "https://${CitrixAuthAPIBaseURL}/cvad/manage/`$batch?async=true"
$response = Invoke-WebRequest -Uri $batchUri -Method POST -Body $jsonBody -Headers @{
    "Content-Type"      = "application/json"
    "Authorization"     = "CWSAuth Bearer=$bearerToken"
    "Citrix-CustomerId" = $CitrixCustomerId
    "Citrix-InstanceId" = $siteId
} -UseBasicParsing

if ($response.StatusCode -ne 202) {
    Write-Error "Batch request failed. Response: $($response.Content)"
    exit 1
}

#  Poll job status ===
$jobId = $response.Headers["Location"] -replace ".*/Jobs/", ""
if (-not $jobId) {
    Write-Error "No Job ID returned."
    exit 1
}

Write-Host "Job submitted successfully. Job ID: $jobId" -ForegroundColor Yellow

do {
    Start-Sleep -Seconds 10
    $jobStatus = Invoke-RestMethod -Uri "https://${CitrixAuthAPIBaseURL}/cvad/manage/Jobs/$jobId" -Headers $headers
    Write-Host "Job Status: $($jobStatus.Status)"
} until ($jobStatus.Status -in @("Succeeded", "Failed", "Complete"))

if ($jobStatus.Status -eq "Complete") {
    Write-Host "Successfully submitted job to add machine(s) to catalog $CatalogName" -ForegroundColor Green
    Write-Host "Adding Machines in the catalog... Please wait... This will take around 2 Minutes " -ForegroundColor Yellow
}
else {
    Write-Error "Job failed. Details: $($jobStatus | ConvertTo-Json -Depth 10)"
}

#Putting a Long 2 minute Sleep Timer to ensure machines provisioned in Citrix and gets synched to Database Properly.

Start-Sleep -Seconds 120

$machines = (Invoke-RestMethod -Uri "https://${CitrixAuthAPIBaseURL}/cvad/manage/MachineCatalogs/$catalogId/Machines" -Headers $headers).Items

$newMachines = $machines | Where-Object { -not $_.IsAssigned -and -not $_.DeliveryGroup -and -not $_.AssignedUsers -and -not $_.AssociatedUsers } | Sort-Object Name

if ($newMachines) {
    Write-Host "Provisioned Below Machines..."   
    $newMachines | ForEach-Object { $_.Name }
}
else {
    Write-Host "No New Machines Provisioned or the Job is taking long time, please try again"
    exit 1
}

$latestMachine = $newMachines | Select-Object -First 1  # or -Last 1 if you prefer

# Get its ID
$MachineId = $latestMachine.Id
$MachineName = $latestMachine.Name

Write-Host "Machine to assign user: $MachineName (Id: $MachineId)"


#  Assign Machines to Delivery Group


# Get Delivery Group ID
$deliveryGroups = Invoke-RestMethod -Uri "https://${CitrixAuthAPIBaseURL}/cvad/manage/DeliveryGroups" -Headers $headers
$deliveryGroup = $deliveryGroups.Items | Where-Object { $_.Name -eq $DeliveryGroupName }

if (-not $deliveryGroup) {
    Write-Error "Delivery Group '$DeliveryGroupName' not found."
    exit 1
}

$deliveryGroupId = $deliveryGroup.Id

# Assign each new machine to Delivery Group
foreach ($machine in $newMachines) {
    $machineName = $machine.Name
    Write-Host "Assigning $machineName to Delivery Group $DeliveryGroupName and user $EmailAddress" -ForegroundColor Yellow

    $body = @{
        MachineCatalog = $catalogId
        Count          = 1
        AssignMachinesToUsers = @(
            @{
                Machine = $machineName
            }
        )
    } | ConvertTo-Json -Depth 6

    $uri = "https://${CitrixAuthAPIBaseURL}/cvad/manage/DeliveryGroups/$deliveryGroupId/Machines?detailResponseRequired=false&async=true"

    $assignResponse = Invoke-WebRequest -Uri $uri -Method POST -Body $body -Headers @{
        "Content-Type"      = "application/json"
        "Authorization"     = "CWSAuth Bearer=$bearerToken"
        "Citrix-CustomerId" = $CitrixCustomerId
        "Citrix-InstanceId" = $siteId
    } -UseBasicParsing

    if ($assignResponse.StatusCode -eq 202) {
        Write-Host "Successfully Assigned $machineName to Delivery Group $DeliveryGroupName and user $EmailAddress" -ForegroundColor Green
    } else {
        Write-Host "DeliveryGroup Assignment API failed for $machineName, please assign it manually or retrigger the fresh build" -ForegroundColor Red
    }
}

 #Assign Users to Machines based on the email input

    # === GET user info by email ===
    Write-Host "Looking up user for $EmailAddress ..." -ForegroundColor Cyan

    $userUri = "https://${CitrixAuthAPIBaseURL}/cvad/manage/Identity/Users?provider=AzureAD&idpInstanceId=$IdpInstanceId&includeIdentityClaims=false&startsWith=$EmailAddress&recursive=true&userType=User&limit=100"

    $userResp = Invoke-RestMethod -Uri $userUri -Headers $headers -Method GET

    # Match by substring (case-insensitive)
    $user = $userResp.Items | Where-Object { $_.Mail -match [regex]::Escape($EmailAddress) }


    if ($user) {
        Write-Host " Found user:" ($user | Select-Object -First 1 -Property Mail, Oid | ConvertTo-Json -Compress)
    }
    else {
        Write-Error " User not found for $EmailAddress"
        exit 1
    }

    $UserIdentity = $user.UserIdentity

    if (-not $UserIdentity) {
        Write-Error "UserIdentity not found for $EmailAddress"
        exit 1
    }

    Write-Host " UserIdentity fetched: $UserIdentity" -ForegroundColor Green


    # === PATCH machine to assign user ===
    $assignUri = "https://${CitrixAuthAPIBaseURL}/cvad/manage/Machines/$MachineName"
    $assignBody = @{
        "AssignedUsers" = @("$UserIdentity")
    } | ConvertTo-Json -Depth 3

    $response = Invoke-RestMethod -Uri $assignUri -Headers $headers -Method PATCH -Body $assignBody -ContentType "application/json"

    Write-Host "Assigned user $EmailAddress to machine $MachineName successfully." -ForegroundColor Green





#mailboxfolder.read.all
$tenantID = $env:AZURE_TENANT_ID

#Mail.ReadBasic.All
$clientSecret = $env:GETMAILFOLDERS_CLIENT_SECRET
$clientID = $env:GETMAILFOLDERS_CLIENT_ID


#Microsoft teannt

$ObjectID = "152e1002-411d-467b-9f6d-982f95638a30"

$TokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
$TokenBody = @{
    client_id     = $ClientId
    client_secret = $ClientSecret
    scope         = "https://graph.microsoft.com/.default"
    grant_type    = "client_credentials"
}

Write-Host "Fetching Access Token..." -ForegroundColor Cyan
$TokenResponse = Invoke-RestMethod -Uri $TokenUrl -Method Post -Body $TokenBody
$AccessToken   = $TokenResponse.access_token

# 2. Query Microsoft Graph API for Mailbox Folder Information
$Headers = @{
    Authorization = "Bearer $AccessToken"
    "Content-Type" = "application/json"
}
$targetUser = "shmbx1@uccloud.uk"
# Graph Endpoint to list top-level mailbox folders
$GraphUrl = "https://graph.microsoft.com/v1.0/users/$TargetUser/mailFolders"

Write-Host "Retrieving mailbox folder information for $TargetUser..." -ForegroundColor Cyan
try {
    $Result = Invoke-RestMethod -Uri $GraphUrl -Headers $Headers -Method Get

    # 3. Output Folder Details
    $Result.value | Select-Object id, displayName, totalItemCount, unreadItemCount | Format-Table -AutoSize
}
catch {
    Write-Error "Failed to retrieve mailbox folders: $_"
}
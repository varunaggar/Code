#MAPV2
$tenantID = $env:AZURE_TENANT_ID
$clientSecret = $env:MAPV2_CLIENT_SECRET
$clientID = $env:MAPV2_CLIENT_ID

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

$ApiUrl = "https://outlook.office365.com/adminapi/v2.0/$TenantId/MailboxFolderPermission"

$Headers = @{
    "Authorization"   = "Bearer $AccessToken"
    "Content-Type"    = "application/json"
    "X-AnchorMailbox" = $TargetUser  # Routing hint recommended by Microsoft
}

$RequestBody = @{
    CmdletInput = @{
        CmdletName = "Get-MailboxFolderPermission"
        Parameters = @{
            Identity   = "${TargetUser}:\$TargetFolder"
            ResultSize = 100
        }
    }
} | ConvertTo-Json -Depth 3

# 3. Call Endpoint
Write-Host "Querying Admin API for folder permissions on ${TargetUser}:\$TargetFolder..." -ForegroundColor Cyan
try {
    $Response = Invoke-RestMethod -Uri $ApiUrl -Method Post -Headers $Headers -Body $RequestBody

    # Extract and display returned permission objects
    $Response.value | Select-Object FolderName, User, AccessRights | Format-Table -AutoSize
}
catch {
    Write-Error "Failed to call Exchange Admin API: $_"
}


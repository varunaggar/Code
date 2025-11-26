# Load untracked secrets/config if present
$varsPath = Join-Path $PSScriptRoot 'psvariables.ps1'
if (Test-Path $varsPath) { . $varsPath } else { Write-Verbose "psvariables.ps1 not found in $PSScriptRoot; ensure required variables are provided via environment or secure vault." }

# Define the parameters (sourced from psvariables.ps1)
$tenantId = $Graph_TenantId
$clientId = $Graph_ClientId
$clientSecret = $Graph_ClientSecret
$scope = "https://graph.microsoft.com/.default"

# Construct the URL
$tokenUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"

# Create the body for the request
$body = @{
    client_id     = $clientId
    scope         = $scope
    client_secret = $clientSecret
    grant_type    = "client_credentials"
}

# Make the request
$response = Invoke-RestMethod -Method Post -Uri $tokenUrl -ContentType "application/x-www-form-urlencoded" -Body $body

# Output the token
$token = $response.access_token
#$secureToken = ConvertTo-SecureString $token -AsPlainText -Force
$headers = @{
    "Authorization" = "Bearer $Token"
    "Content-Type"  = "application/json"
}

$uri = "https://graph.microsoft.com/beta/admin/exchange/mailboxes/$($response.primaryMailboxId)/mailFolders"    
$settings = "https://graph.microsoft.com/beta/users/bharati@uccloud.uk/settings/exchange"

$folders = "https://graph.microsoft.com/beta/users/bharati@uccloud.uk/mailFolders"

$response = Invoke-RestMethod -Uri $folders -Headers $headers -Method Get

$inbox = "AQMkAGI0ODc4NzcAMC1hMjM2LTRmYzktOGUxMy0wYzdmYjliODA1MDIALgAAA1PRFTPudDRPsJBiUujqnmwBAJWaqMWxnFtKhKK0biaujjoAAAIBDAAAAA=="
param($Timer)

# 1. FORCE MODULE LOAD
# This fixes the 'Upsert-AzTableRow' not recognized error
#Import-Module Az.Tables -Force -ErrorAction SilentlyContinue

# 2. SANITIZE CONFIGURATION
$tenantId     = "c2efc329-9485-4475-bdc6-267f4b9954ef"
$clientId     = "29aacb3a-c35b-4f76-a071-835936475a48"
$clientSecret = ""
$storageConn  = "DefaultEndpointsProtocol=https;AccountName=ori19storageaccount;AccountKey=<REDACTED>;EndpointSuffix=core.windows.net"

# Strip any https:// or trailing slashes from the namespace
$nsName  = "ori19ehns"
$hubName = "users"

# Construct the exact URL Graph requires
$notificationUrl = "EventHub:https://$($nsName).servicebus.windows.net/eventhubname/$($hubName)?tenantId=$($tenantId)"

Write-Host "Action: Attempting to use Notification URL: $notificationUrl"

# 3. GET GRAPH TOKEN
$tokenBody = @{
    client_id     = $clientId
    client_secret = $clientSecret
    scope         = "https://graph.microsoft.com/.default"
    grant_type    = "client_credentials"
}
$tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Method Post -Body $tokenBody
$headers = @{
    "Authorization" = "Bearer $($tokenResponse.access_token)"
    "Content-Type"  = "application/json"
}

# 4. STORAGE CHECK
$tableName = "GraphSubscriptions"
$subId = $null
try {
    $entity = Get-AzTableRow -ConnectionString $storageConn -TableName $tableName -PartitionKey "UserChanges" -RowKey "CurrentSubscription" -ErrorAction Stop
    $subId = $entity.SubscriptionId
    Write-Host "Status: Found existing ID in storage: $subId"
} catch {
    Write-Host "Status: No existing subscription in storage."
}

# 5. EXPIRATION LOGIC (Set for 4200 minutes / ~2.9 days)
$expiryDate = (Get-Date).AddMinutes(4200).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# 6. RENEW OR CREATE
$success = $false

if ($subId) {
    try {
        $patchBody = @{ expirationDateTime = $expiryDate } | ConvertTo-Json
        Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/subscriptions/$subId" -Method Patch -Headers $headers -Body $patchBody
        Write-Host "Success: Subscription $subId renewed."
        $success = $true
    } catch {
        Write-Warning "Renewal failed for $subId. Creating new one..."
    }
}

if (-not $success) {
    $createBody = @{
        changeType         = "created,updated,deleted"
        notificationUrl    = $notificationUrl
        resource           = "/users"
        expirationDateTime = $expiryDate
        clientState        = "Secret123"
    } | ConvertTo-Json

    try {
        $newSub = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/subscriptions" -Method Post -Headers $headers -Body $createBody
        
        $subId = $newSub.id
        
        # SAVE TO STORAGE
        $newEntity = @{
            PartitionKey   = "UserChanges"
            RowKey         = "CurrentSubscription"
            SubscriptionId = $subId
        }
        
        # Use explicit module prefix if necessary
        Az.Tables\Upsert-AzTableRow -ConnectionString $storageConn -TableName $tableName -Entity $newEntity
        Write-Host "Success: New Subscription created and saved: $subId"
    } catch {
        $errorDetails = $_.ErrorDetails.Message | ConvertFrom-Json
        Write-Error "Graph Error: $($errorDetails.error.message)"
    }
}
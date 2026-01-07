# Requires: PowerShell 7+
# Purpose: Send events to Azure Event Hubs using HTTPS with SAS token
# Docs: https://learn.microsoft.com/azure/event-hubs/event-hubs-rest

param(
    [Parameter(Mandatory=$true)]
    [string] $Namespace,            # e.g., my-namespace

    [Parameter(Mandatory=$true)]
    [string] $EventHubName,         # e.g., my-eventhub

    [Parameter(Mandatory=$true)]
    [string] $SharedAccessKeyName,  # e.g., RootManageSharedAccessKey or a policy with Send rights

    [Parameter(Mandatory=$true)]
    [string] $SharedAccessKey,      # the SAS key value

    [Parameter(Mandatory=$false)]
    [string] $MessageBody = "Hello from PowerShell",

    [Parameter(Mandatory=$false)]
    [string] $PartitionKey,         # optional: partition key for routing

    [Parameter(Mandatory=$false)]
    [int] $TTLMinutes = 15,         # SAS token lifetime

    [Parameter(Mandatory=$false)]
    [switch] $VerboseOutput
)

function New-SasToken {
    param(
        [string] $ResourceUri,
        [string] $KeyName,
        [string] $Key,
        [datetime] $Expiry
    )
    $epochStart = [DateTime]::UtcNow
    $ttl = [int]([DateTimeOffset]$Expiry).ToUnixTimeSeconds()
    $encodedResourceUri = [System.Web.HttpUtility]::UrlEncode($ResourceUri)
    $stringToSign = "$encodedResourceUri\n$ttl"
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [Text.Encoding]::UTF8.GetBytes($Key)
    $signature = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($stringToSign))
    $signature = [Convert]::ToBase64String($signature)
    $encodedSignature = [System.Web.HttpUtility]::UrlEncode($signature)
    return "SharedAccessSignature sr=$encodedResourceUri&sig=$encodedSignature&se=$ttl&skn=$KeyName"
}

function Send-EventHubMessage {
    param(
        [string] $Namespace,
        [string] $EventHubName,
        [string] $SasToken,
        [string] $Body,
        [string] $PartitionKey
    )
    $baseUri = "https://$Namespace.servicebus.windows.net/$EventHubName/messages"
    $uri = if ($PartitionKey) { "$baseUri?partitionKey=$([System.Web.HttpUtility]::UrlEncode($PartitionKey))" } else { $baseUri }

    $headers = @{ Authorization = $SasToken }
    $contentType = 'application/json'
    $payload = $Body

    if ($VerboseOutput) {
        Write-Host "POST $uri" -ForegroundColor Cyan
        Write-Host "Payload length: $(([Text.Encoding]::UTF8.GetByteCount($payload))) bytes" -ForegroundColor Cyan
    }

    # Use HttpClient for better control
    $handler = New-Object System.Net.Http.HttpClientHandler
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.DefaultRequestHeaders.ExpectContinue = $false
    $client.DefaultRequestHeaders.Remove('Authorization') | Out-Null
    $client.DefaultRequestHeaders.Add('Authorization', $SasToken)

    $content = New-Object System.Net.Http.StringContent($payload, [System.Text.Encoding]::UTF8, $contentType)
    $response = $client.PostAsync($uri, $content).GetAwaiter().GetResult()
    $status = [int]$response.StatusCode
    $text = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $client.Dispose()

    if ($status -ge 200 -and $status -lt 300) {
        return [pscustomobject]@{ Success = $true; StatusCode = $status; Message = 'Sent' }
    } else {
        return [pscustomobject]@{ Success = $false; StatusCode = $status; Message = ($text ?? 'Failed') }
    }
}

# Build resource URI: namespace + event hub path (lowercase host; resource must match exactly)
$resourceUri = "https://$Namespace.servicebus.windows.net/$EventHubName"
$expiry = [DateTime]::UtcNow.AddMinutes($TTLMinutes)
$sas = New-SasToken -ResourceUri $resourceUri -KeyName $SharedAccessKeyName -Key $SharedAccessKey -Expiry $expiry

if ($VerboseOutput) { Write-Host "SAS token expires at: $expiry (UTC)" -ForegroundColor Yellow }

# If MessageBody looks like JSON (starts with { or [), send as-is; else wrap into a simple JSON
if ($MessageBody -match '^(\s*\{|\s*\[)') {
    $payload = $MessageBody
} else {
    $payload = (ConvertTo-Json -Depth 5 -InputObject @{ message = $MessageBody; ts = (Get-Date).ToString('o') })
}

$result = Send-EventHubMessage -Namespace $Namespace -EventHubName $EventHubName -SasToken $sas -Body $payload -PartitionKey $PartitionKey

if ($result.Success) {
    Write-Host "Event sent. Status: $($result.StatusCode)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Send failed. Status: $($result.StatusCode)" -ForegroundColor Red
    Write-Host $result.Message
    exit 2
}
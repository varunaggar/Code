param(
  [Parameter(Mandatory=$true)][string]$AccountName,
  [Parameter(Mandatory=$true)][string]$DatabaseName,
  [Parameter(Mandatory=$true)][string]$ContainerName = 'Mailboxes',
  [Parameter(Mandatory=$true)][string]$MasterKey,
  [Parameter(Mandatory=$false)][string]$MailboxId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-CosmosAuthHeader {
  param(
    [string]$Verb,
    [string]$ResourceType,
    [string]$ResourceId,
    [string]$Date,
    [string]$Key
  )
  $keyBytes = [Convert]::FromBase64String($Key)
  $payload = (
    ($Verb.ToLower()) + "\n" +
    ($ResourceType.ToLower()) + "\n" +
    ($ResourceId) + "\n" +
    ($Date.ToLower()) + "\n" +
    "\n"
  )
  $hm = New-Object System.Security.Cryptography.HMACSHA256($keyBytes)
  $sigBytes = $hm.ComputeHash([Text.Encoding]::UTF8.GetBytes($payload))
  $sig = [Convert]::ToBase64String($sigBytes)
  "type=master&ver=1.0&sig=$sig"
}

function Invoke-CosmosGet {
  param([string]$Path,[hashtable]$Headers)
  $endpoint = "https://$AccountName.documents.azure.com:443"
  Invoke-RestMethod -Method GET -Uri "$endpoint$Path" -Headers $Headers -ContentType 'application/json'
}

$now = [DateTime]::UtcNow.ToString('r')

# List documents or fetch one by id
if ($MailboxId) {
  # Docs resource path: dbs/{db}/colls/{coll}/docs/{docId}
  $resType = 'docs'
  $resId = "dbs/$DatabaseName/colls/$ContainerName/docs/$MailboxId"
  $auth = New-CosmosAuthHeader -Verb 'GET' -ResourceType $resType -ResourceId $resId -Date $now -Key $MasterKey
  $pk = ('["{0}"]' -f $MailboxId)
  $headers = @{ 'Authorization' = $auth; 'x-ms-date' = $now; 'x-ms-version' = '2018-12-31'; 'x-ms-documentdb-partitionkey' = $pk }
  $path = "/dbs/$DatabaseName/colls/$ContainerName/docs/$MailboxId"
  $doc = Invoke-CosmosGet -Path $path -Headers $headers
  $doc | ConvertTo-Json -Depth 6
} else {
  # Query all (limited): use docs feed
  $resType = 'docs'
  $resId = "dbs/$DatabaseName/colls/$ContainerName"
  $auth = New-CosmosAuthHeader -Verb 'GET' -ResourceType $resType -ResourceId $resId -Date $now -Key $MasterKey
  $headers = @{ 'Authorization' = $auth; 'x-ms-date' = $now; 'x-ms-version' = '2018-12-31' }
  $path = "/dbs/$DatabaseName/colls/$ContainerName/docs"
  $result = Invoke-CosmosGet -Path $path -Headers $headers
  $result.Documents | Select-Object -First 5 | ConvertTo-Json -Depth 5
}

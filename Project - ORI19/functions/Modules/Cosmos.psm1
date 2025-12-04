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

function Invoke-Cosmos {
  param(
    [ValidateSet('GET','POST','PUT','DELETE')][string]$Method,
    [Parameter(Mandatory)][string]$AccountName,
    [Parameter(Mandatory)][string]$DatabaseName,
    [Parameter(Mandatory)][string]$ContainerName,
    [Parameter(Mandatory)][string]$MasterKey,
    [Parameter(Mandatory)][string]$ResourceType,
    [Parameter(Mandatory)][string]$ResourceId,
    [Parameter()][string]$Path,
    [Parameter()][hashtable]$Headers,
    [Parameter()][object]$Body
  )
  $endpoint = "https://$AccountName.documents.azure.com:443"
  $now = [DateTime]::UtcNow.ToString('r')
  $auth = New-CosmosAuthHeader -Verb $Method -ResourceType $ResourceType -ResourceId $ResourceId -Date $now -Key $MasterKey
  if (-not $Path) { $Path = "/$ResourceId" }
  $reqHeaders = @{ 'Authorization' = $auth; 'x-ms-date' = $now; 'x-ms-version' = '2018-12-31' }
  if ($Headers) { $Headers.GetEnumerator() | ForEach-Object { $reqHeaders[$_.Key] = $_.Value } }
  $uri = "$endpoint$Path"
  if ($Body) {
    $json = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 6 }
    Invoke-RestMethod -Method $Method -Uri $uri -Headers $reqHeaders -ContentType 'application/json' -Body $json
  } else {
    Invoke-RestMethod -Method $Method -Uri $uri -Headers $reqHeaders -ContentType 'application/json'
  }
}

Export-ModuleMember -Function New-CosmosAuthHeader,Invoke-Cosmos

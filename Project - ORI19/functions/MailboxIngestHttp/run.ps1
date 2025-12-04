using namespace System.Net
param($req,$TriggerMetadata)

Import-Module "$PSScriptRoot/../Modules/Cosmos.psm1"

$account = $env:COSMOS_ACCOUNT
$db = $env:COSMOS_DB
$container = $env:COSMOS_CONTAINER
$key = $env:COSMOS_MASTER_KEY
$tenantId = $env:TENANT_ID
$geo = $env:GEO

function New-MailboxId {
  param([string]$ExchangeGuid,[string]$ExternalDirectoryObjectId,[string]$PrimarySmtpAddress)
  if ($ExchangeGuid -and $ExchangeGuid -match '^[0-9a-fA-F-]{36}$') { return $ExchangeGuid.ToLower() }
  if ($ExternalDirectoryObjectId -and $ExternalDirectoryObjectId -match '^[0-9a-fA-F-]{36}$') { return $ExternalDirectoryObjectId.ToLower() }
  $ns = [Guid]'6ba7b810-9dad-11d1-80b4-00c04fd430c8'
  $bytes = [Text.Encoding]::UTF8.GetBytes($PrimarySmtpAddress.ToLower())
  $nsBytes = $ns.ToByteArray(); [Array]::Reverse($nsBytes)
  $data = $nsBytes + $bytes
  $sha1 = [System.Security.Cryptography.SHA1]::Create()
  $hash = $sha1.ComputeHash($data)
  $hash[6] = ($hash[6] -band 0x0F) -bor 0x50; $hash[8] = ($hash[8] -band 0x3F) -bor 0x80
  $guidBytes = $hash[0..15]
  [Array]::Reverse($guidBytes[0..3]); [Array]::Reverse($guidBytes[4..5]); [Array]::Reverse($guidBytes[6..7])
  (New-Object Guid (,$guidBytes)).ToString().ToLower()
}

try {
  $body = (Get-Content -Raw -InputObject $req.Body | ConvertFrom-Json)
  if (-not $body) { throw "Invalid JSON" }
  $docs = @()
  foreach ($r in $body) {
    $mid = New-MailboxId -ExchangeGuid $r.exchangeGuid -ExternalDirectoryObjectId $r.externalDirectoryObjectId -PrimarySmtpAddress $r.primarySmtpAddress
    $doc = [pscustomobject]@{
      id = $mid; mailboxId = $mid; tenantId = $tenantId; geo = $geo
      primarySmtpAddress = $r.primarySmtpAddress; userPrincipalName = $r.userPrincipalName
      proxyAddresses = @(); exchangeGuid = $r.exchangeGuid; externalDirectoryObjectId = $r.externalDirectoryObjectId
      resolutionMethod = if ($r.exchangeGuid) { 'ExchangeGuid' } elseif ($r.externalDirectoryObjectId) { 'ExternalDirectoryObjectId' } else { 'HashedPrimarySmtpAddress' }
      createdUtc = [DateTime]::UtcNow.ToString('o'); modifiedUtc = [DateTime]::UtcNow.ToString('o')
    }
    $docs += ,$doc
  }
  foreach ($d in $docs) {
    $pk = ('["{0}"]' -f $d.mailboxId)
    Invoke-Cosmos -Method 'POST' -AccountName $account -DatabaseName $db -ContainerName $container -MasterKey $key 
      -ResourceType 'docs' -ResourceId "dbs/$db/colls/$container" -Path "/dbs/$db/colls/$container/docs" -Headers @{ 'x-ms-documentdb-partitionkey' = $pk } -Body $d | Out-Null
  }
  $res = [HttpResponseContext]::new(); $res.StatusCode = [HttpStatusCode]::OK
  $res.Body = (ConvertTo-Json -Depth 4 @{ upserted = $docs.Count })
  return $res
} catch {
  $res = [HttpResponseContext]::new(); $res.StatusCode = [HttpStatusCode]::BadRequest
  $res.Body = (ConvertTo-Json -Depth 3 @{ error = $_.Exception.Message })
  return $res
}

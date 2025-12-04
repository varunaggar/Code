param(
  [Parameter(Mandatory=$true)][string]$AccountName,
  [Parameter(Mandatory=$true)][string]$DatabaseName,
  [Parameter(Mandatory=$true)][string]$ContainerName = 'Mailboxes',
  [Parameter(Mandatory=$true)][string]$Key, # Cosmos DB primary key
  [Parameter(Mandatory=$true)][string]$TenantId,
  [Parameter(Mandatory=$true)][string]$Geo,
  [Parameter(Mandatory=$true)][string]$CsvPath # CSV with columns: primarySmtpAddress,userPrincipalName,exchangeGuid,externalDirectoryObjectId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-MailboxId {
  param([string]$ExchangeGuid,[string]$ExternalDirectoryObjectId,[string]$PrimarySmtpAddress)
  if ($ExchangeGuid -and $ExchangeGuid -match '^[0-9a-fA-F-]{36}$') { return $ExchangeGuid.ToLower() }
  if ($ExternalDirectoryObjectId -and $ExternalDirectoryObjectId -match '^[0-9a-fA-F-]{36}$') { return $ExternalDirectoryObjectId.ToLower() }
  # Fallback: UUID v5 using DNS namespace and email
  $ns = [Guid]'6ba7b810-9dad-11d1-80b4-00c04fd430c8'
  $bytes = [Text.Encoding]::UTF8.GetBytes($PrimarySmtpAddress.ToLower())
  $nsBytes = $ns.ToByteArray()
  [Array]::Reverse($nsBytes)
  $data = $nsBytes + $bytes
  $sha1 = [System.Security.Cryptography.SHA1]::Create()
  $hash = $sha1.ComputeHash($data)
  $hash[6] = ($hash[6] -band 0x0F) -bor 0x50
  $hash[8] = ($hash[8] -band 0x3F) -bor 0x80
  $guidBytes = $hash[0..15]
  [Array]::Reverse($guidBytes[0..3])
  [Array]::Reverse($guidBytes[4..5])
  [Array]::Reverse($guidBytes[6..7])
  (New-Object Guid (,$guidBytes)).ToString().ToLower()
}

function Invoke-CosmosUpsert {
  param([object]$Document)
  $endpoint = "https://$AccountName.documents.azure.com:443/"
  $url = "$endpoint/dbs/$DatabaseName/colls/$ContainerName/docs"
  $json = $Document | ConvertTo-Json -Depth 6
  $headers = @{ 'Authorization' = $Key; 'x-ms-version' = '2020-07-15'; 'x-ms-date' = ([DateTime]::UtcNow.ToString('r')) }
  # Note: For simplicity using key in Authorization; for production use proper auth signature (MasterKey auth) or Az.Cosmos SDK
  Invoke-RestMethod -Method Post -Uri $url -Body $json -ContentType 'application/json' -Headers $headers | Out-Null
}

if (-not (Test-Path $CsvPath)) { throw "CSV not found: $CsvPath" }
$rows = Import-Csv -Path $CsvPath

foreach ($r in $rows) {
  $mailboxId = New-MailboxId -ExchangeGuid $r.exchangeGuid -ExternalDirectoryObjectId $r.externalDirectoryObjectId -PrimarySmtpAddress $r.primarySmtpAddress
  $doc = [pscustomobject]@{
    id = $mailboxId
    mailboxId = $mailboxId
    tenantId = $TenantId
    geo = $Geo
    primarySmtpAddress = $r.primarySmtpAddress
    userPrincipalName = $r.userPrincipalName
    proxyAddresses = @()
    exchangeGuid = $r.exchangeGuid
    externalDirectoryObjectId = $r.externalDirectoryObjectId
    resolutionMethod = if ($r.exchangeGuid) { 'ExchangeGuid' } elseif ($r.externalDirectoryObjectId) { 'ExternalDirectoryObjectId' } else { 'HashedPrimarySmtpAddress' }
    createdUtc = [DateTime]::UtcNow.ToString('o')
    modifiedUtc = [DateTime]::UtcNow.ToString('o')
  }
  Invoke-CosmosUpsert -Document $doc
}

Write-Host "Ingestion complete: $($rows.Count) mailboxes upserted."
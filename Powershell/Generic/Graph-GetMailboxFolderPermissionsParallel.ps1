# Requires: PowerShell 7+, Azure AD app with Graph permissions
# Purpose: Fetch mailbox folder permissions via Microsoft Graph (Exchange Online Admin API)
# Endpoint: https://graph.microsoft.com/beta/users/{userId}/mailFolders/{folderId}/permissions
# Notes:
# - This uses Microsoft Graph beta API for mail folder permissions.
# - App must have appropriate permissions (Application: "Mail.ReadBasic.All" + Exchange-specific admin permissions; or Delegated with admin consent). Commonly requires EWS-like access via Graph and the Exchange Online admin API.
# - Use with caution in production; beta APIs can change.

param(
    [Parameter(Mandatory=$true)]
    [string[]] $Mailboxes,

    [Parameter(Mandatory=$false)]
    [string] $FolderPath = "Inbox",

    [Parameter(Mandatory=$true)]
    [string] $TenantId,

    [Parameter(Mandatory=$true)]
    [string] $ClientId,

    [Parameter(Mandatory=$true)]
    [string] $ClientSecret,

    [Parameter(Mandatory=$false)]
    [int] $ThrottleLimit = 6,

    [Parameter(Mandatory=$false)]
    [string] $OutputCsv = "./graph-folder-permissions.csv",

    [Parameter(Mandatory=$false)]
    [switch] $VerboseOutput
)

$ErrorActionPreference = 'Stop'

function Get-GraphToken {
    param(
        [string] $TenantId,
        [string] $ClientId,
        [string] $ClientSecret,
        [string] $Scope = "https://graph.microsoft.com/.default"
    )
    $body = @{
        client_id     = $ClientId
        scope         = $Scope
        client_secret = $ClientSecret
        grant_type    = 'client_credentials'
    }
    $uri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $resp = Invoke-RestMethod -Method Post -Uri $uri -Body $body -ContentType 'application/x-www-form-urlencoded'
    return $resp.access_token
}

function Invoke-GraphGet {
    param(
        [string] $AccessToken,
        [string] $Uri
    )
    $headers = @{ Authorization = "Bearer $AccessToken" }
    return Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers
}

function Get-MailFolderId {
    param(
        [string] $AccessToken,
        [string] $UserId,
        [string] $FolderPath
    )
    # Resolve the folder by path. Graph supports child traversal; here we split by '/' and walk.
    $parts = $FolderPath -split '/'
    $currentId = 'root'
    foreach ($p in $parts) {
        $listUri = "https://graph.microsoft.com/v1.0/users/$UserId/mailFolders/$currentId/childFolders?$select=id,displayName&$top=100"
        $list = Invoke-GraphGet -AccessToken $AccessToken -Uri $listUri
        $match = $list.value | Where-Object { $_.displayName -eq $p }
        if (-not $match) { throw "Folder segment not found: $p for user $UserId" }
        $currentId = $match.id
    }
    return $currentId
}

function Get-MailFolderPermissions {
    param(
        [string] $AccessToken,
        [string] $UserId,
        [string] $FolderId
    )
    $uri = "https://graph.microsoft.com/beta/users/$UserId/mailFolders/$FolderId/permissions"
    $resp = Invoke-GraphGet -AccessToken $AccessToken -Uri $uri
    return $resp.value
}

# Normalize mailbox list (expand from file if a single path is passed)
if ($Mailboxes.Count -eq 1 -and (Test-Path -LiteralPath $Mailboxes[0])) {
    if ($VerboseOutput) { Write-Host "Loading mailboxes from file: $($Mailboxes[0])" -ForegroundColor Cyan }
    $Mailboxes = Get-Content -LiteralPath $Mailboxes[0] | Where-Object { $_ -and $_.Trim() -ne '' }
}

if (-not $Mailboxes -or $Mailboxes.Count -eq 0) { throw 'No mailboxes provided.' }

if ($VerboseOutput) { Write-Host "Acquiring Graph token..." -ForegroundColor Cyan }
$token = Get-GraphToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
if ($VerboseOutput) { Write-Host "Token acquired." -ForegroundColor Green }

$results = $Mailboxes | ForEach-Object -Parallel {
    param($FolderPath, $TenantId, $ClientId, $ClientSecret, $Token)

    function Invoke-GraphGetLocal {
        param([string] $AccessToken, [string] $Uri)
        $headers = @{ Authorization = "Bearer $AccessToken" }
        return Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers
    }
    function Get-MailFolderIdLocal {
        param([string] $AccessToken, [string] $UserId, [string] $FolderPath)
        $parts = $FolderPath -split '/'
        $currentId = 'root'
        foreach ($p in $parts) {
            $listUri = "https://graph.microsoft.com/v1.0/users/$UserId/mailFolders/$currentId/childFolders?$select=id,displayName&$top=100"
            $list = Invoke-GraphGetLocal -AccessToken $AccessToken -Uri $listUri
            $match = $list.value | Where-Object { $_.displayName -eq $p }
            if (-not $match) { throw "Folder segment not found: $p for user $UserId" }
            $currentId = $match.id
        }
        return $currentId
    }
    function Get-MailFolderPermissionsLocal {
        param([string] $AccessToken, [string] $UserId, [string] $FolderId)
        $uri = "https://graph.microsoft.com/beta/users/$UserId/mailFolders/$FolderId/permissions"
        $resp = Invoke-GraphGetLocal -AccessToken $AccessToken -Uri $uri
        return $resp.value
    }

    $mbx = $_
    try {
        $accessToken = $Token
        $folderId = Get-MailFolderIdLocal -AccessToken $accessToken -UserId $mbx -FolderPath $FolderPath
        $perms = Get-MailFolderPermissionsLocal -AccessToken $accessToken -UserId $mbx -FolderId $folderId
        foreach ($p in $perms) {
            [pscustomobject]@{
                Mailbox        = $mbx
                FolderPath     = $FolderPath
                Id             = $p.id
                AllowedRoles   = ($p.allowedRoles -join ',')
                EmailAddress   = $p.grantedTo.user.emailAddress
                UserId         = $p.grantedTo.user.id
                Type           = $p.grantedTo['@odata.type']
            }
        }
    } catch {
        [pscustomobject]@{
            Mailbox        = $mbx
            FolderPath     = $FolderPath
            Id             = "(error)"
            AllowedRoles   = ""
            EmailAddress   = ""
            UserId         = ""
            Type           = ""
            Error          = $_.Exception.Message
        }
    }
} -ThrottleLimit $ThrottleLimit -ArgumentList $FolderPath, $TenantId, $ClientId, $ClientSecret, $token

if ($VerboseOutput) { Write-Host ("Writing {0} rows to {1}" -f $results.Count, (Resolve-Path -LiteralPath $OutputCsv)) -ForegroundColor Cyan }
$results | Export-Csv -NoTypeInformation -Path $OutputCsv

Write-Host "Done. Output: $OutputCsv" -ForegroundColor Green

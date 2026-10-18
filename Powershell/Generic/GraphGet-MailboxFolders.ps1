<#
.SYNOPSIS
Fetches mailbox folder information from a user's mailbox using an Azure AD app (client credentials) and Microsoft Graph.

.DESCRIPTION
This script obtains an app-only access token using the client credentials flow and calls Microsoft Graph
to list mail folders for the specified user. Ensure the Azure AD application has the required application
permissions (for example: Mail.Read or Mail.ReadWrite, or MailboxFolder.Read.All if available) and that
an administrator has granted consent.

USAGE
.
    .\GraphGet-MailboxFolders.ps1 -TenantId <tenant-id> -ClientId <app-id> -ClientSecret <secret> -UserPrincipalName user@domain.com

#>

param(
    [Parameter(Mandatory=$true)] [string]$TenantId,
    [Parameter(Mandatory=$true)] [string]$ClientId,
    [Parameter(Mandatory=$true)] [string]$ClientSecret,
    [Parameter(Mandatory=$true)] [string]$UserPrincipalName
)

Write-Host "Acquiring access token..."
$tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
$body = @{ grant_type='client_credentials'; client_id=$ClientId; client_secret=$ClientSecret; scope='https://graph.microsoft.com/.default' }
try {
    $tokenResp = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -ContentType 'application/x-www-form-urlencoded' -Body $body -ErrorAction Stop
    $accessToken = $tokenResp.access_token
}
catch {
    Write-Error "Failed to acquire token: $_"
    exit 1
}

if (-not $accessToken) { Write-Error "No access token returned"; exit 1 }

$headers = @{ Authorization = "Bearer $accessToken"; Accept = 'application/json' }

# Build initial queue with top-level mail folders (paged)
$queue = @()
$topUri = "https://graph.microsoft.com/v1.0/users/$UserPrincipalName/mailFolders?`$top=50"
try {
    do {
        $topResp = Invoke-RestMethod -Method Get -Uri $topUri -Headers $headers -ErrorAction Stop
        if ($null -ne $topResp.value) {
            foreach ($f in $topResp.value) {
                $queue += [pscustomobject]@{ Folder = $f; ParentName = $null; Path = $f.displayName }
            }
        }
        $topUri = $topResp.'@odata.nextLink'
    } while ($topUri)
}
catch {
    Write-Error "Failed to fetch top-level folders: $_"
    exit 1
}

$results = @()
$index = 0
while ($index -lt $queue.Count) {
    $item = $queue[$index]
    $index++
    $f = $item.Folder
    $parent = $item.ParentName
    $path = $item.Path

    $results += [pscustomobject]@{
        DisplayName = $f.displayName
        ParentDisplayName = $parent
        Path = $path
        Id = $f.id
        ChildFolderCount = $f.childFolderCount
        TotalItemCount = $f.totalItemCount
    }

    if ($f.childFolderCount -gt 0) {
        $childUri = "https://graph.microsoft.com/v1.0/users/$UserPrincipalName/mailFolders/$($f.id)/childFolders?`$top=50"
        try {
            do {
                $childResp = Invoke-RestMethod -Method Get -Uri $childUri -Headers $headers -ErrorAction Stop
                if ($null -ne $childResp.value) {
                    foreach ($c in $childResp.value) {
                        $queue += [pscustomobject]@{ Folder = $c; ParentName = $f.displayName; Path = "$path/$($c.displayName)" }
                    }
                }
                $childUri = $childResp.'@odata.nextLink'
            } while ($childUri)
        }
        catch {
            Write-Error "Failed to fetch child folders for $($f.displayName): $_"
        }
    }
}

if ($results.Count -eq 0) {
    Write-Host "No mail folders returned for $UserPrincipalName"
    return @()
}

Write-Host "Fetched $($results.Count) folders for $UserPrincipalName"
$results | Select-Object Path,DisplayName,ParentDisplayName,Id,ChildFolderCount,TotalItemCount | Format-Table -AutoSize

return $results

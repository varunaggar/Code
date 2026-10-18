<#
Simple script: get mailbox folders (no modules, no functions)

Usage:
  pwsh ./GraphGet-MailboxFolders.simple.ps1 -TenantId '<TENANT>' -ClientId '<APPID>' -ClientSecret '<SECRET>' -UserPrincipalName 'user@domain.com'

Requires an Azure AD app with application permissions (Mail.Read or Mail.ReadWrite) and admin consent.
#>

param(
    [Parameter(Mandatory=$true)][string]$TenantId,
    [Parameter(Mandatory=$true)][string]$ClientId,
    [Parameter(Mandatory=$true)][string]$ClientSecret,
    [Parameter(Mandatory=$true)][string]$UserPrincipalName
)

Write-Host "Acquiring app-only token for tenant $TenantId..."
$tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
$body = @{ grant_type='client_credentials'; client_id=$ClientId; client_secret=$ClientSecret; scope='https://graph.microsoft.com/.default' }
try {
    $t = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -ContentType 'application/x-www-form-urlencoded' -Body $body -ErrorAction Stop
} catch {
    Write-Error "Token request failed: $($_.Exception.Message)"
    exit 1
}

if (-not $t.access_token) { Write-Error 'No access token returned'; exit 1 }
$headers = @{ Authorization = "Bearer $($t.access_token)"; Accept = 'application/json' }
write-host $t.access_token
# Seed queue with top-level mail folders (paged)
$queue = @()
$topUri = "https://graph.microsoft.com/v1.0/users/$UserPrincipalName/mailFolders?`$top=50"
try {
    do {
        $topResp = Invoke-RestMethod -Method Get -Uri $topUri -Headers $headers -ErrorAction Stop
        foreach ($f in $topResp.value) {
            $queue += [pscustomobject]@{ folder = $f; parent = $null; path = $f.displayName }
        }
        $topUri = $topResp.'@odata.nextLink'
    } while ($topUri)
} catch {
    Write-Error "Failed to fetch top-level folders: $($_.Exception.Message)"
    exit 1
}

$results = @()
$i = 0
while ($i -lt $queue.Count) {
    $item = $queue[$i]
    $i++
    $f = $item.folder
    $parent = $item.parent
    $path = $item.path

    $results += [pscustomobject]@{
        DisplayName = $f.displayName
        Parent = $parent
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
                foreach ($c in $childResp.value) {
                    $queue += [pscustomobject]@{ folder = $c; parent = $f.displayName; path = "$path/$($c.displayName)" }
                }
                $childUri = $childResp.'@odata.nextLink'
            } while ($childUri)
        } catch {
            Write-Warning "Failed fetching children for folder '$($f.displayName)': $($_.Exception.Message)"
        }
    }
}

if ($results.Count -eq 0) { Write-Host "No folders found for $UserPrincipalName"; exit 0 }

$results | Select-Object Path, DisplayName, Parent, Id, ChildFolderCount, TotalItemCount | Format-Table -AutoSize

# End

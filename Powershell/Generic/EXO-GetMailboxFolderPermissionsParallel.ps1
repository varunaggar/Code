# Requires: PowerShell 7+, ExchangeOnlineManagement module (v3+), EXO modern REST cmdlets
# Purpose: Fetch mailbox folder permissions in parallel using ForEach-Object -Parallel
# Notes:
# - Uses Get-EXOMailboxFolderPermission (REST-backed, PS7-compatible)
# - Connect once with Connect-ExchangeOnline; parallel runspaces reuse the REST context in most environments.
# - If you see auth context issues in parallel, set -ThrottleLimit 1 (serial) or connect inside the parallel block.

param(
    [Parameter(Mandatory=$true)]
    [string[]] $Mailboxes,

    [Parameter(Mandatory=$false)]
    [string] $FolderPath = "Inbox",

    [Parameter(Mandatory=$false)]
    [int] $ThrottleLimit = 6,

    [Parameter(Mandatory=$false)]
    [string] $OutputCsv = "./exo-folder-permissions.csv",

    [Parameter(Mandatory=$false)]
    [switch] $VerboseOutput
)

# Ensure module
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Error "ExchangeOnlineManagement module not found. Install with: pwsh -Command 'Install-Module ExchangeOnlineManagement -Scope CurrentUser'"
    exit 1
}
Import-Module ExchangeOnlineManagement -ErrorAction Stop

# Connect (interactive by default). For app-only, supply -AppId/-Organization/-CertificateThumbprint.
if ($VerboseOutput) { Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan }
try {
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
} catch {
    Write-Error "Failed to connect to Exchange Online: $($_.Exception.Message)"
    exit 1
}

# Normalize mailbox list (expand from file if a single path is passed)
if ($Mailboxes.Count -eq 1 -and (Test-Path -LiteralPath $Mailboxes[0])) {
    if ($VerboseOutput) { Write-Host "Loading mailboxes from file: $($Mailboxes[0])" -ForegroundColor Cyan }
    $Mailboxes = Get-Content -LiteralPath $Mailboxes[0] | Where-Object { $_ -and $_.Trim() -ne '' }
}

if (-not $Mailboxes -or $Mailboxes.Count -eq 0) {
    Write-Error "No mailboxes provided. Pass UPNs or a file path containing one UPN per line."
    exit 1
}

if ($VerboseOutput) { Write-Host ("Processing {0} mailboxes against folder '{1}' with ThrottleLimit={2}" -f $Mailboxes.Count, $FolderPath, $ThrottleLimit) -ForegroundColor Cyan }

$results = @()
$results = $Mailboxes | ForEach-Object -Parallel {
    param($FolderPath)
    $mbx = $_
    try {
        # Identity format: mailboxUPN:\FolderPath
        $identity = ("{0}:{1}" -f $mbx, $FolderPath)
        $perms = Get-EXOMailboxFolderPermission -Identity $identity -ErrorAction Stop
        foreach ($p in $perms) {
            [pscustomobject]@{
                Mailbox        = $mbx
                FolderPath     = $FolderPath
                User           = $p.User
                AccessRights   = ($p.AccessRights -join ',')
                Deny           = $p.Deny
                InheritanceType= $p.InheritanceType
            }
        }
    } catch {
        [pscustomobject]@{
            Mailbox        = $mbx
            FolderPath     = $FolderPath
            User           = "(error)"
            AccessRights   = ""
            Deny           = $false
            InheritanceType= ""
            Error          = $_.Exception.Message
        }
    }
} -ThrottleLimit $ThrottleLimit -ArgumentList $FolderPath

# Disconnect
Disconnect-ExchangeOnline -Confirm:$false | Out-Null

# Output
if ($VerboseOutput) { Write-Host ("Writing {0} rows to {1}" -f $results.Count, (Resolve-Path -LiteralPath $OutputCsv)) -ForegroundColor Cyan }
$results | Export-Csv -NoTypeInformation -Path $OutputCsv

Write-Host "Done. Output: $OutputCsv" -ForegroundColor Green

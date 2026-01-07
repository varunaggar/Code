param(
    [Parameter(HelpMessage = "Start of time range (UTC). Default: 7 days ago)")]
    [datetime] $StartTime = (Get-Date).ToUniversalTime().AddDays(-7),

    [Parameter(HelpMessage = "End of time range (UTC). Default: now")]
    [datetime] $EndTime = (Get-Date).ToUniversalTime(),

    [Parameter(HelpMessage = "Tenant ID (GUID). Optional if single-tenant context")]
    [string] $TenantId,

    [Parameter(HelpMessage = "Output CSV path. If omitted, writes to console only")]
    [string] $OutputCsv,

    [Parameter(HelpMessage = "Use device code flow (handy on headless/macOS)")]
    [switch] $DeviceCode,

    [Parameter(HelpMessage = "Silently install missing modules for current user")]
    [switch] $SilentInstallModules
    ,
    [Parameter(HelpMessage = "Fallback to REST API if module/cmdlets unavailable")]
    [switch] $UseApiFallback,
    [Parameter(HelpMessage = "Client ID for app (required for API fallback)")]
    [string] $ClientId,
    [Parameter(HelpMessage = "Client Secret for app-only auth (optional)")]
    [string] $ClientSecret,
    [Parameter(HelpMessage = "Use app-only auth (requires secret and app permissions)")]
    [switch] $AppOnly,
    [Parameter(HelpMessage = "Microsoft Defender API base URI")]
    [string] $ApiBaseUri = 'https://api.security.microsoft.com'
)

$ErrorActionPreference = 'Stop'

function Ensure-Module {
    param(
        [Parameter(Mandatory)] [string] $Name
    )
    if (-not (Get-Module -ListAvailable -Name $Name)) {
        if (-not $SilentInstallModules) {
            Write-Host "Module '$Name' not found. Installing for CurrentUser..." -ForegroundColor Yellow
        }
        Install-Module -Name $Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }
    Import-Module $Name -ErrorAction Stop | Out-Null
}

# 1) Ensure Microsoft 365 Defender module is available (only when not using REST fallback)
if (-not $UseApiFallback) {
    try {
        Ensure-Module -Name Microsoft365Defender
    }
    catch {
        Write-Warning "Microsoft365Defender module not available from PSGallery. Re-run with -UseApiFallback to call the REST API."
        throw
    }
}

# Resolve cmdlet names across possible module versions
$connectCmdName = $null
if (-not $UseApiFallback) {
    $connectCmdName = @('Connect-Microsoft365Defender','Connect-MicrosoftDefender') |
        Where-Object { Get-Command -Name $_ -ErrorAction SilentlyContinue } |
        Select-Object -First 1
}

if (-not $connectCmdName -and -not $UseApiFallback) {
    throw "Neither 'Connect-Microsoft365Defender' nor 'Connect-MicrosoftDefender' is available. Use -UseApiFallback to call the REST API instead."
}

$invokeAhCmdName = $null
if (-not $UseApiFallback) {
    $invokeAhCmdName = @('Invoke-AdvancedHunting','Invoke-M365AdvancedHuntingQuery') |
        Where-Object { Get-Command -Name $_ -ErrorAction SilentlyContinue } |
        Select-Object -First 1
}

if (-not $invokeAhCmdName -and -not $UseApiFallback) {
    throw "Advanced Hunting cmdlet not found. Expected 'Invoke-AdvancedHunting' or fallback via -UseApiFallback to REST API."
}

# 2) Connect to Microsoft 365 Defender (Advanced Hunting) or prepare REST fallback
if ($connectCmdName) {
    try {
        $connectParams = @{}
        if ($TenantId) { $connectParams.TenantId = $TenantId }
        if ($DeviceCode.IsPresent) { $connectParams.UseDeviceCode = $true }
        & $connectCmdName @connectParams | Out-Null
    }
    catch {
        if (-not $UseApiFallback) { throw "Failed to connect to Microsoft 365 Defender. $_" }
    }
}

# Normalize times to ISO 8601 UTC
$startIso = $StartTime.ToUniversalTime().ToString("o")
$endIso   = $EndTime.ToUniversalTime().ToString("o")

# 3) Build KQL query
$kql = @"
let start = datetime($startIso);
let end   = datetime($endIso);
CloudAppEvents
| where Timestamp between (start .. end)
| where tolower(ActionType) in ("add-mailboxfolderpermission", "add-mailboxpermission") or tolower(ActivityType) in ("add-mailboxfolderpermission", "add-mailboxpermission")
| where Application has "Exchange"
| project Timestamp, Application, ActionType, ActivityType,
          AccountId, AccountDisplayName, AccountObjectId, AccountType, IsAdminOperation,
          IPAddress, CountryCode, City, Isp, UserAgent,
          ObjectType, ObjectName, ObjectId,
          AuditSource, OAuthAppId, ReportId,
          AdditionalFields, RawEventData
| order by Timestamp desc
"@

function Get-DefenderToken {
    param(
        [Parameter(Mandatory)] [string] $TenantId,
        [Parameter(Mandatory)] [string] $ClientId,
        [string] $ClientSecret,
        [switch] $AppOnly
    )
    Ensure-Module -Name MSAL.PS
    if ($AppOnly.IsPresent) {
        if (-not $ClientSecret) { throw "App-only requires -ClientSecret." }
        $secureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
        $tok = Get-MsalToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $secureSecret -Scopes "$ApiBaseUri/.default"
    }
    else {
        # Delegated interactive flow; requires your app to be granted user consent for Advanced Hunting scopes
        $tok = Get-MsalToken -TenantId $TenantId -ClientId $ClientId -Interactive -Scopes "$ApiBaseUri/AdvancedHunting.Read"
    }
    return $tok.AccessToken
}

# 4) Run Advanced Hunting query via cmdlet or REST fallback
if ($invokeAhCmdName) {
    try {
        $result = & $invokeAhCmdName -Query $kql -ErrorAction Stop
    }
    catch {
        if (-not $UseApiFallback) { throw "Advanced Hunting query failed. $_" }
    }
}

if (-not $result -and $UseApiFallback) {
    if (-not $TenantId -or -not $ClientId) {
        throw "REST fallback requires -TenantId and -ClientId. Optionally add -ClientSecret and -AppOnly for app-only auth."
    }
    $token = Get-DefenderToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -AppOnly:$AppOnly
    $headers = @{ Authorization = "Bearer $token" }
    $body = @{ Query = $kql } | ConvertTo-Json -Depth 5
    $uri = "$ApiBaseUri/advancedhunting/run"
    try {
        $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json' -Body $body -ErrorAction Stop
        # Response shape: { Results: [ ... ] }
        $result = $resp.Results
    }
    catch {
        throw "REST API call failed. $_"
    }
}

if (-not $result) {
    Write-Host "No results returned for the specified time window." -ForegroundColor Yellow
    return
}

# 5) Prepare output: serialize dynamic fields for CSV friendliness
$output = $result | ForEach-Object {
    $row = $_ | Select-Object *
    foreach ($dyn in @('AdditionalFields','RawEventData')) {
        if ($row.PSObject.Properties.Name -contains $dyn) {
            $val = $row.$dyn
            if ($null -ne $val -and $val -isnot [string]) {
                try { $row.$dyn = ($val | ConvertTo-Json -Compress -Depth 10) } catch { $row.$dyn = "$val" }
            }
        }
    }
    $row
}

# 6) Emit to console and optional CSV
$output | Format-Table -AutoSize

if ($OutputCsv) {
    $dir = [System.IO.Path]::GetDirectoryName($OutputCsv)
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $output | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Saved results to: $OutputCsv" -ForegroundColor Green
}

<#
USAGE EXAMPLES

1) Interactive sign-in, last 7 days (default):
   pwsh ./Get-CloudAppEvents-EXO-AddPermissions.ps1

2) Specify time range and device code flow (macOS/headless friendly):
   pwsh ./Get-CloudAppEvents-EXO-AddPermissions.ps1 \
     -StartTime (Get-Date).AddDays(-14) -EndTime (Get-Date) -DeviceCode

3) Export to CSV and specify Tenant ID:
   pwsh ./Get-CloudAppEvents-EXO-AddPermissions.ps1 \
     -TenantId "00000000-0000-0000-0000-000000000000" \
     -OutputCsv ./out/exo_add_permissions.csv

Required permissions: Advanced Hunting (Microsoft 365 Defender). The account/app used must have rights to run advanced hunting queries.
#>

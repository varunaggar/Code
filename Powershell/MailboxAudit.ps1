<#
.SYNOPSIS
  Orchestrates large-scale mailbox audit across on-prem AD and Exchange Online.

.DESCRIPTION
  Reads mailboxes from CSV (Alias,Email). For each mailbox, collects:
  - AD custom attributes + whenCreated/whenChanged (on-prem AD)
  - Mailbox created/modified (EXO)
  - $Alias-mfc group member count (on-prem AD)
  - Oldest/Newest item in Inbox and Sent (via EXO folder statistics)

  Parallelized with runspace pool for 50k scale. Uses Common module for logging, retries, and module handling.
#>

param(
  [Parameter()][string]$InputCsv = (Join-Path $PSScriptRoot 'mailboxes.csv'),
  [Parameter()][int]$MinThreads = 4,
  [Parameter()][int]$MaxThreads = 16
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Modules/Common') -ErrorAction Stop
Start-FastLog | Out-Null

# Load local, untracked secrets if present
$varsPath = Join-Path $PSScriptRoot 'psvariables.ps1'
if (Test-Path $varsPath) { . $varsPath } else { Write-Verbose "psvariables.ps1 not found in $PSScriptRoot" }

# Ensure required modules and import Exchange Online
Ensure-Modules -ModuleNames @('ActiveDirectory','ExchangeOnlineManagement') -InstallMissing -ScopeCurrentUser
Import-Module ExchangeOnlineManagement -ErrorAction Stop

# Connect to Exchange Online (cert-based app preferred if variables provided)
try {
  if ($EXO_AppId -and $EXO_TenantId -and $EXO_CertificateThumbprint) {
    Write-FastLog -Level INFO -Message "Connecting to EXO (app cert)." -Context 'EXO'
    Connect-ExchangeOnline -AppId $EXO_AppId -Organization $EXO_TenantId -CertificateThumbprint $EXO_CertificateThumbprint -ShowBanner:$false -ErrorAction Stop
  } else {
    Write-FastLog -Level INFO -Message "Connecting to EXO (interactive)." -Context 'EXO'
    Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
  }
  Write-FastLog -Level INFO -Message "EXO connected." -Context 'EXO'
} catch {
  Write-FastLog -Level ERROR -Message "EXO connection failed: $($_.Exception.Message)" -Context 'EXO'
  throw
}

# No Graph dependency; oldest/newest will be retrieved via EXO folder statistics

# Input
if (-not (Test-Path $InputCsv)) { throw "Input CSV not found: $InputCsv" }
$rows = Import-Csv -Path $InputCsv
Write-FastLog -Level INFO -Message "Loaded $($rows.Count) mailboxes from CSV." -Context 'Input'

# Prepare runspace pool
Add-Type -AssemblyName System.Management.Automation
$iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
$pool = [runspacefactory]::CreateRunspacePool([int]$MinThreads, [int]$MaxThreads, $iss, $Host)
$pool.Open()

# Define worker
$worker = {
  param($Alias, $Email)
  Import-Module (Join-Path $PSScriptRoot 'Modules/Common') -ErrorAction Stop

  function Get-ADCustom { param($Email)
    Invoke-Retry -Action {
      Get-ADUser -Filter "mail -eq '$Email'" -Properties extensionAttribute1,extensionAttribute2,extensionAttribute3,extensionAttribute4,extensionAttribute5,extensionAttribute6,extensionAttribute7,extensionAttribute8,extensionAttribute9,extensionAttribute10,extensionAttribute11,extensionAttribute12,extensionAttribute13,extensionAttribute14,extensionAttribute15,whenCreated,whenChanged
    }
  }

  function Get-MailboxTimestamps { param($Email)
    try {
      $m = Invoke-Retry -Action { Get-EXOMailbox -Identity $Email -Properties WhenCreated,WhenChanged }
      if ($m) { return @{ WhenCreated=$m.WhenCreated; WhenChanged=$m.WhenChanged } }
    } catch {}
    try {
      $m2 = Invoke-Retry -Action { Get-Mailbox -Identity $Email }
      if ($m2) { return @{ WhenCreated=$m2.WhenCreated; WhenChanged=$m2.WhenChanged } }
    } catch {}
    return @{ WhenCreated=$null; WhenChanged=$null }
  }

  function Get-MfcCount { param($Alias)
    $groupName = "$Alias-mfc"
    try {
      $g = Get-ADGroup -Identity $groupName -ErrorAction Stop
      $cnt = (Get-ADGroupMember -Identity $g.DistinguishedName -Recursive | Measure-Object).Count
      return @{ GroupDN=$g.DistinguishedName; Count=$cnt }
    } catch { return @{ GroupDN=$null; Count=$null } }
  }

  function Get-FolderEdges { param($Email)
    # Prefer EXO V2 cmdlet if available
    $inboxOld = $null; $inboxNew = $null; $sentOld = $null; $sentNew = $null
    try {
      $exoCmd = Get-Command -Name Get-EXOMailboxFolderStatistics -ErrorAction SilentlyContinue
      $inclParam = $false
      if ($exoCmd) { $inclParam = $exoCmd.Parameters.ContainsKey('IncludeOldestAndNewestItems') }

      if ($exoCmd) {
        if ($inclParam) {
          Write-FastLog -Level VERBOSE -Message "Using Get-EXOMailboxFolderStatistics with -IncludeOldestAndNewestItems for $Email" -Context 'FolderStats'
          $inboxStats = Invoke-Retry -Action { Get-EXOMailboxFolderStatistics -Identity $Email -FolderScope Inbox -IncludeOldestAndNewestItems }
          $sentStats  = Invoke-Retry -Action { Get-EXOMailboxFolderStatistics -Identity $Email -FolderScope SentItems -IncludeOldestAndNewestItems }
        } else {
          $inboxStats = Invoke-Retry -Action { Get-EXOMailboxFolderStatistics -Identity $Email -FolderScope Inbox }
          $sentStats  = Invoke-Retry -Action { Get-EXOMailboxFolderStatistics -Identity $Email -FolderScope SentItems }
        }
      } else {
        $mbxCmd = Get-Command -Name Get-MailboxFolderStatistics -ErrorAction SilentlyContinue
        $inclParam = $false
        if ($mbxCmd) { $inclParam = $mbxCmd.Parameters.ContainsKey('IncludeOldestAndNewestItems') }
        if ($inclParam) {
          Write-FastLog -Level VERBOSE -Message "Using Get-MailboxFolderStatistics with -IncludeOldestAndNewestItems for $Email" -Context 'FolderStats'
          $inboxStats = Invoke-Retry -Action { Get-MailboxFolderStatistics -Identity $Email -FolderScope Inbox -IncludeOldestAndNewestItems }
          $sentStats  = Invoke-Retry -Action { Get-MailboxFolderStatistics -Identity $Email -FolderScope SentItems -IncludeOldestAndNewestItems }
        } else {
          $inboxStats = Invoke-Retry -Action { Get-MailboxFolderStatistics -Identity $Email -FolderScope Inbox }
          $sentStats  = Invoke-Retry -Action { Get-MailboxFolderStatistics -Identity $Email -FolderScope SentItems }
        }
      }

      # Choose the top-level folder row (Name 'Inbox'/'Sent Items' or FolderPath ends with that)
      $inboxRow = $inboxStats | Where-Object { $_.Name -eq 'Inbox' -or $_.FolderPath -match 'Inbox$' } | Select-Object -First 1
      $sentRow  = $sentStats  | Where-Object { $_.Name -like 'Sent*' -or $_.FolderPath -match 'Sent Items$' } | Select-Object -First 1

      $inboxOld = $inboxRow.OldestItemReceivedDate
      $inboxNew = $inboxRow.NewestItemReceivedDate
      $sentOld  = $sentRow.OldestItemReceivedDate
      $sentNew  = $sentRow.NewestItemReceivedDate
    } catch {
      Write-FastLog -Level WARN -Message "Folder stats failed for $Email: $($_.Exception.Message)" -Context 'FolderStats'
    }

    return @{
      InboxOldestDate = $inboxOld
      InboxNewestDate = $inboxNew
      SentOldestDate  = $sentOld
      SentNewestDate  = $sentNew
    }
  }

  try {
    Write-FastLog -Level INFO -Message "Processing $Email" -Context 'Worker'
    $ad   = Get-ADCustom -Email $Email
    $mbx  = Get-MailboxTimestamps -Email $Email
    $mfc  = Get-MfcCount -Alias $Alias
    $edge = Get-FolderEdges -Email $Email

    [pscustomobject]@{
      Alias            = $Alias
      Email            = $Email
      AD_Ext1          = $ad.extensionAttribute1
      AD_Ext2          = $ad.extensionAttribute2
      AD_Ext3          = $ad.extensionAttribute3
      AD_WhenCreated   = $ad.whenCreated
      AD_WhenChanged   = $ad.whenChanged
      MailboxCreated   = $mbx.WhenCreated
      MailboxModified  = $mbx.WhenChanged
      MFCGroupDN       = $mfc.GroupDN
      MFCMemberCount   = $mfc.Count
      InboxOldestDate  = $edge.InboxOldestDate
      # IDs not available via folder statistics without item queries
      InboxNewestDate  = $edge.InboxNewestDate
      
      SentOldestDate   = $edge.SentOldestDate
      
      SentNewestDate   = $edge.SentNewestDate
      
      Error            = $null
    }
  } catch {
    Write-FastLog -Level ERROR -Message $_.Exception.Message -Context 'Worker'
    [pscustomobject]@{ Alias=$Alias; Email=$Email; Error=$_.Exception.Message }
  }
}

$results = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
$jobs = @()
foreach ($row in $rows) {
  $ps = [powershell]::Create()
  $ps.RunspacePool = $pool
  [void]$ps.AddScript($worker).AddArgument($row.Alias).AddArgument($row.Email)
  $jobs += [pscustomobject]@{ Handle = $ps.BeginInvoke(); PS = $ps }
}

foreach ($j in $jobs) {
  $out = $j.PS.EndInvoke($j.Handle)
  foreach ($o in $out) { $results.Add($o) }
  $j.PS.Dispose()
}

$paths = Initialize-ScriptFolders -ScriptPath $PSCommandPath
$outFile = Join-Path $paths.OutputPath "mailbox-audit.csv"
$results | Export-Csv $outFile -NoTypeInformation
Write-FastLog -Level INFO -Message "Wrote results to $outFile" -Context 'Output'

try { Disconnect-ExchangeOnline -Confirm:$false } catch {}
Stop-FastLog
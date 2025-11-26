<#!
  .SYNOPSIS
    Parallel scan of Exchange Online mailboxes to get oldest/newest item dates in Inbox and Sent Items.
  .REQUIREMENTS
    - PowerShell 7+ (for ForEach-Object -Parallel)
    - ExchangeOnlineManagement module (v3+ recommended)
    - Permissions to read mailbox folder statistics
  .USAGE
    # Connect and scan all user mailboxes
    ./Get-EXO-InboxSent-OldestNewest.ps1 -Connect -AllMailboxes -OutputCsv ./out.csv -ThrottleLimit 24

    # Scan from CSV (header: UserPrincipalName)
    ./Get-EXO-InboxSent-OldestNewest.ps1 -Connect -InputCsv ./mailboxes.csv -OutputCsv ./out.csv -ThrottleLimit 32

    # Reuse existing EXO session (already connected)
    ./Get-EXO-InboxSent-OldestNewest.ps1 -AllMailboxes -OutputCsv ./out.csv
#>

param(
  [switch]$Connect,
  [switch]$AllMailboxes,
  [string]$InputCsv,
  [string]$OutputCsv = './InboxSent-OldestNewest.csv',
  [int]$ThrottleLimit = 16,
  [switch]$DebugMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import shared Common module for logging/helpers
$commonPath = Join-Path $PSScriptRoot '..' 'Modules' 'Common' 'Common.psm1'
if (-not (Test-Path $commonPath)) {
  # Fallback: relative to repo structure
  $commonPath = Join-Path $PSScriptRoot '..' '..' 'Modules' 'Common' 'Common.psm1'
}
Import-Module $commonPath -ErrorAction Stop
Write-Log -Level INFO -Message "Loaded Common module from: $commonPath" -Context 'Init' -DebugMode:$DebugMode

function Ensure-EXOReady {
  param([switch]$ForceConnect)

  # Ensure module present and imported
  Ensure-Modules -ModuleNames @('ExchangeOnlineManagement') -InstallMissing -ScopeCurrentUser | Out-Null
  Write-Log -Level INFO -Message 'ExchangeOnlineManagement ensured/loaded.' -Context 'Init' -DebugMode:$DebugMode

  # Determine connectivity by a quick probe
  $connected = $false
  if (-not $ForceConnect) {
    try {
      # Some environments may return connection info but still be unusable; probe a lightweight call
      if (Get-Command Get-EXOMailbox -ErrorAction SilentlyContinue) {
        Get-EXOMailbox -ResultSize 1 -ErrorAction Stop | Out-Null
      } else {
        Get-ConnectionInformation -ErrorAction Stop | Out-Null
      }
      $connected = $true
    } catch {
      $connected = $false
    }
  }

  if (-not $connected) {
    Write-Log -Level INFO -Message 'Connecting to Exchange Online…' -Context 'Connect' -DebugMode:$DebugMode
    try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
    Connect-ExchangeOnline -ShowProgress:$false
  } else {
    Write-Log -Level INFO -Message 'Existing usable EXO connection detected.' -Context 'Connect' -DebugMode:$DebugMode
  }
}

function Get-Targets {
  if ($AllMailboxes) {
    # Use EXO v3 REST cmdlet only
    if (-not (Get-Command Get-EXOMailbox -ErrorAction SilentlyContinue)) {
      throw 'Get-EXOMailbox not available. Ensure ExchangeOnlineManagement v3+ is installed and connected.'
    }
    return Get-EXOMailbox -ResultSize Unlimited | Select-Object -ExpandProperty UserPrincipalName
  }
  if ($InputCsv) {
    if (-not (Test-Path $InputCsv)) { throw "InputCsv not found: $InputCsv" }
    return (Import-Csv -Path $InputCsv | ForEach-Object { $_.UserPrincipalName })
  }
  throw 'Specify -AllMailboxes or -InputCsv.'
}

function Get-FolderStatsSafe {
  param(
    [Parameter(Mandatory)][string]$Identity,
    [Parameter(Mandatory)][ValidateSet('Inbox','SentItems')][string]$FolderType
  )
  if (-not (Get-Command Get-EXOMailboxFolderStatistics -ErrorAction SilentlyContinue)) {
    throw 'Get-EXOMailboxFolderStatistics not available. Ensure ExchangeOnlineManagement v3+ is installed and connected.'
  }
  $stats = Get-EXOMailboxFolderStatistics -Identity $Identity -FolderScope $FolderType -IncludeOldestAndNewestItems -ErrorAction Stop
  $root = $stats | Where-Object { $_.FolderType -eq $FolderType } | Select-Object -First 1
  if (-not $root) { $root = $stats | Select-Object -First 1 }
  return $root
}

function Collect-OneMailbox {
  param([Parameter(Mandatory)][string]$Upn)
  $inbox = Get-FolderStatsSafe -Identity $Upn -FolderType Inbox
  $sent  = Get-FolderStatsSafe -Identity $Upn -FolderType SentItems
  $inOld = if ($inbox.OldestItemReceivedDate) { (Get-Date -Date $inbox.OldestItemReceivedDate).ToString('yyyy-MM-dd') } else { '' }
  $inNew = if ($inbox.NewestItemReceivedDate) { (Get-Date -Date $inbox.NewestItemReceivedDate).ToString('yyyy-MM-dd') } else { '' }
  $sOld  = if ($sent.OldestItemReceivedDate)  { (Get-Date -Date $sent.OldestItemReceivedDate).ToString('yyyy-MM-dd') }  else { '' }
  $sNew  = if ($sent.NewestItemReceivedDate)  { (Get-Date -Date $sent.NewestItemReceivedDate).ToString('yyyy-MM-dd') }  else { '' }
  [PSCustomObject]@{
    UserPrincipalName     = $Upn
    InboxItems            = $inbox.ItemsInFolder
    InboxOldestReceived   = $inOld
    InboxNewestReceived   = $inNew
    SentItemsItems        = $sent.ItemsInFolder
    SentItemsOldestSent   = $sOld
    SentItemsNewestSent   = $sNew
  }
}

# --- Main ---
if ($Connect) { Ensure-EXOReady -ForceConnect } else { Ensure-EXOReady }
Write-Log -Level INFO -Message 'Gathering targets…' -Context 'Targets' -DebugMode:$DebugMode
$targets = Get-Targets | Where-Object { $_ } | Sort-Object -Unique
Write-Log -Level INFO -Message "Total mailboxes: $($targets.Count)" -Context 'Targets' -DebugMode:$DebugMode

$results = $targets | ForEach-Object -Parallel {
  try {
    # Single-attempt stats collection inside the parallel runspace
    $id = $_
    $inboxStats = Get-EXOMailboxFolderStatistics -Identity $id -FolderScope Inbox -IncludeOldestAndNewestItems -ErrorAction Stop
    $sentStats  = Get-EXOMailboxFolderStatistics -Identity $id -FolderScope SentItems -IncludeOldestAndNewestItems -ErrorAction Stop
    $inbox = $inboxStats | Where-Object { $_.FolderType -eq 'Inbox' } | Select-Object -First 1
    if (-not $inbox) { $inbox = $inboxStats | Select-Object -First 1 }
    $sent  = $sentStats  | Where-Object { $_.FolderType -eq 'SentItems' } | Select-Object -First 1
    if (-not $sent)  { $sent  = $sentStats  | Select-Object -First 1 }

    $inOld = if ($inbox.OldestItemReceivedDate) { (Get-Date -Date $inbox.OldestItemReceivedDate).ToString('yyyy-MM-dd') } else { '' }
    $inNew = if ($inbox.NewestItemReceivedDate) { (Get-Date -Date $inbox.NewestItemReceivedDate).ToString('yyyy-MM-dd') } else { '' }
    $sOld  = if ($sent.OldestItemReceivedDate)  { (Get-Date -Date $sent.OldestItemReceivedDate).ToString('yyyy-MM-dd') }  else { '' }
    $sNew  = if ($sent.NewestItemReceivedDate)  { (Get-Date -Date $sent.NewestItemReceivedDate).ToString('yyyy-MM-dd') }  else { '' }

    [PSCustomObject]@{
      UserPrincipalName     = $id
      InboxItems            = $inbox.ItemsInFolder
      InboxOldestReceived   = $inOld
      InboxNewestReceived   = $inNew
      SentItemsItems        = $sent.ItemsInFolder
      SentItemsOldestSent   = $sOld
      SentItemsNewestSent   = $sNew
    }
  } catch {
    [PSCustomObject]@{ UserPrincipalName = $_; Error = $_.Exception.Message }
  }
} -ThrottleLimit $ThrottleLimit

Write-Log -Level INFO -Message "Writing CSV: $OutputCsv" -Context 'Output' -DebugMode:$DebugMode
$results | Sort-Object UserPrincipalName | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
Write-Log -Level INFO -Message 'Done.' -Context 'Output' -DebugMode:$DebugMode

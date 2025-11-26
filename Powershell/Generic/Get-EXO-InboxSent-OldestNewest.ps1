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
  [string]$ProgressFile,
  [int]$ThrottleLimit = [Math]::Max(4, [Environment]::ProcessorCount * 2),
  [switch]$DebugMode,
  [switch]$ShowProgress
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
    Connect-ExchangeOnline -ShowProgress:$false -UseMultithreading:$true
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
$exoModule = Get-Module -Name ExchangeOnlineManagement -ErrorAction Stop
$exoModulePath = $exoModule.Path
Write-Log -Level INFO -Message 'Gathering targets…' -Context 'Targets' -DebugMode:$DebugMode
$targets = Get-Targets | Where-Object { $_ } | Sort-Object -Unique
Write-Log -Level INFO -Message "Total mailboxes: $($targets.Count)" -Context 'Targets' -DebugMode:$DebugMode

# Resolve progress file path and load processed set
if (-not $ProgressFile -or $ProgressFile.Trim() -eq '') {
  $ProgressFile = "$OutputCsv.progress"
}
Write-Log -Level INFO -Message "Using progress file: $ProgressFile" -Context 'Progress' -DebugMode:$DebugMode
$processed = New-Object System.Collections.Generic.HashSet[string]
if (Test-Path $ProgressFile) {
  try {
    foreach ($line in Get-Content -Path $ProgressFile -ErrorAction Stop) {
      $upn = $line.Split(',')[0].Trim()
      if ($upn) { $null = $processed.Add($upn) }
    }
    Write-Log -Level INFO -Message "Loaded $($processed.Count) processed mailboxes from progress file." -Context 'Progress' -DebugMode:$DebugMode
  } catch {
    Write-Log -Level WARN -Message "Failed to read progress file. Starting fresh. Error: $($_.Exception.Message)" -Context 'Progress' -DebugMode:$DebugMode
  }
}

# Compute remaining targets
$remaining = @($targets | Where-Object { -not $processed.Contains($_) })
Write-Log -Level INFO -Message "Remaining mailboxes: $($remaining.Count)" -Context 'Progress' -DebugMode:$DebugMode

# Ensure CSV exists or will be created with headers by first append
if (-not (Test-Path $OutputCsv)) {
  Write-Log -Level INFO -Message "Initializing CSV: $OutputCsv" -Context 'Output' -DebugMode:$DebugMode
  [PSCustomObject]@{
    UserPrincipalName   = ''
    InboxItems          = ''
    InboxOldestReceived = ''
    InboxNewestReceived = ''
    SentItemsItems      = ''
    SentItemsOldestSent = ''
    SentItemsNewestSent = ''
  } | Select-Object UserPrincipalName,InboxItems,InboxOldestReceived,InboxNewestReceived,SentItemsItems,SentItemsOldestSent,SentItemsNewestSent |
    Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
  # Remove the placeholder row
  (Get-Content $OutputCsv | Select-Object -SkipLast 1) | Set-Content $OutputCsv
}

Write-Log -Level INFO -Message "Processing and streaming results to CSV…" -Context 'Output' -DebugMode:$DebugMode
$total = [int]$remaining.Count
$processedCount = 0
if ($ShowProgress) { Write-Progress -Activity 'Preparing processing' -Status "0/$total" -PercentComplete 0 }
$logInterval = if ($total -gt 0) { [Math]::Max([int][Math]::Ceiling($total / 10), 1) } else { 1 }
$remaining |
  ForEach-Object -Parallel {
    $id = $_
    if ($using:exoModulePath -and -not (Get-Module -Name ExchangeOnlineManagement -ErrorAction SilentlyContinue)) {
      Import-Module $using:exoModulePath -ErrorAction Stop | Out-Null
    }
    $inboxItems = ''
    $inOld = ''
    $inNew = ''
    $sentItems = ''
    $sOld = ''
    $sNew = ''

    try {
      $inboxStats = Get-EXOMailboxFolderStatistics -Identity $id -FolderScope Inbox -IncludeOldestAndNewestItems -ErrorAction Stop
      $inbox = $inboxStats | Where-Object { $_.FolderType -eq 'Inbox' } | Select-Object -First 1
      if (-not $inbox) { $inbox = $inboxStats | Select-Object -First 1 }
      if ($inbox) {
        $inboxItems = $inbox.ItemsInFolder
        $inOld = if ($inbox.OldestItemReceivedDate) { (Get-Date -Date $inbox.OldestItemReceivedDate).ToString('yyyy-MM-dd') } else { '' }
        $inNew = if ($inbox.NewestItemReceivedDate) { (Get-Date -Date $inbox.NewestItemReceivedDate).ToString('yyyy-MM-dd') } else { '' }
      } else {
        $inboxItems = 'cmdlet failure'
        $inOld = 'cmdlet failure'
        $inNew = 'cmdlet failure'
      }
    } catch {
      $inboxItems = 'cmdlet failure'
      $inOld = 'cmdlet failure'
      $inNew = 'cmdlet failure'
    }

    try {
      $sentStats  = Get-EXOMailboxFolderStatistics -Identity $id -FolderScope SentItems -IncludeOldestAndNewestItems -ErrorAction Stop
      $sent  = $sentStats  | Where-Object { $_.FolderType -eq 'SentItems' } | Select-Object -First 1
      if (-not $sent)  { $sent  = $sentStats  | Select-Object -First 1 }
      if ($sent) {
        $sentItems = $sent.ItemsInFolder
        $sOld  = if ($sent.OldestItemReceivedDate)  { (Get-Date -Date $sent.OldestItemReceivedDate).ToString('yyyy-MM-dd') }  else { '' }
        $sNew  = if ($sent.NewestItemReceivedDate)  { (Get-Date -Date $sent.NewestItemReceivedDate).ToString('yyyy-MM-dd') }  else { '' }
      } else {
        $sentItems = 'cmdlet failure'
        $sOld = 'cmdlet failure'
        $sNew = 'cmdlet failure'
      }
    } catch {
      $sentItems = 'cmdlet failure'
      $sOld = 'cmdlet failure'
      $sNew = 'cmdlet failure'
    }

    [PSCustomObject]@{
      UserPrincipalName     = $id
      InboxItems            = $inboxItems
      InboxOldestReceived   = $inOld
      InboxNewestReceived   = $inNew
      SentItemsItems        = $sentItems
      SentItemsOldestSent   = $sOld
      SentItemsNewestSent   = $sNew
    }
  } -ThrottleLimit $ThrottleLimit |
  ForEach-Object {
    # Append each row to CSV and record progress
    $_ | Select-Object UserPrincipalName,InboxItems,InboxOldestReceived,InboxNewestReceived,SentItemsItems,SentItemsOldestSent,SentItemsNewestSent |
      Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8 -Append
    Add-Content -Path $ProgressFile -Value "$($_.UserPrincipalName),Written"
    $processedCount++
    $pct = if ($total -gt 0) { [int](($processedCount / $total) * 100) } else { 100 }
    if ($ShowProgress) {
      Write-Progress -Activity 'Processing mailboxes' -Status "$processedCount/$total" -PercentComplete $pct
    } else {
      if (($processedCount % $logInterval -eq 0) -or ($processedCount -eq $total)) {
        Write-Log -Level INFO -Message "Processed $processedCount/$total ($pct%)" -Context 'Progress' -DebugMode:$DebugMode
      }
    }
  }

if ($ShowProgress) { Write-Progress -Activity 'Processing mailboxes' -Status "$processedCount/$total" -PercentComplete 100 -Completed }
Write-Log -Level INFO -Message 'Streaming complete.' -Context 'Output' -DebugMode:$DebugMode

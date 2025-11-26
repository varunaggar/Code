<#
.SYNOPSIS
  Example script showing how to source shared functions from a module.

.DESCRIPTION
  Imports `Common` module and uses Write-Log, Load-Config, Invoke-Retry helpers.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$InputPath,
  [Parameter(Mandatory)][string]$OutputPath,
  [Parameter()][string]$ConfigPath,
  [Parameter()][switch]$DebugMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve module path relative to this script
$ScriptRoot = Split-Path -Parent $PSCommandPath
$ModulePath = Join-Path $ScriptRoot 'Modules/Common'
Import-Module $ModulePath -ErrorAction Stop

$Timestamp = Get-Timestamp
$LogDir = Ensure-Directory (Join-Path $ScriptRoot 'logs')
$LogPath = Join-Path $LogDir "Example-$Timestamp.log"

Write-Log -Level INFO -Message "Starting example script" -Context 'Init' -LogPath $LogPath -DebugMode:$DebugMode
$Config = Load-Config -ConfigPath $ConfigPath

Ensure-Directory -Path $OutputPath | Out-Null

try {
  $items = Invoke-Retry -MaxAttempts 3 -DelaySeconds 2 -Action { Get-ChildItem -Path $InputPath -ErrorAction Stop }
  $summary = $items | Select-Object Name, Length, LastWriteTime | Format-Table | Out-String
  $outFile = Join-Path $OutputPath "summary-$Timestamp.txt"
  Set-Content -Path $outFile -Value $summary
  Write-Log -Level INFO -Message "Wrote summary to $outFile" -Context 'Main' -LogPath $LogPath -DebugMode:$DebugMode
} catch {
  Write-Log -Level ERROR -Message $($_.Exception.Message) -Context 'Main' -LogPath $LogPath -DebugMode:$DebugMode
  exit 1
}

Write-Log -Level INFO -Message "Done" -Context 'End' -LogPath $LogPath -DebugMode:$DebugMode
exit 0
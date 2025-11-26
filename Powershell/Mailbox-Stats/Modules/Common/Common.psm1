Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Timestamp {
  Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
}

function Ensure-Directory {
  param([Parameter(Mandatory)][string]$Path)
  if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
  return (Resolve-Path $Path).Path
}

function Write-Log {
  param(
    [Parameter(Mandatory)][ValidateSet('INFO','WARN','ERROR','DEBUG','VERBOSE')][string]$Level,
    [Parameter(Mandatory)][string]$Message,
    [Parameter()][string]$Context,
    [Parameter()][string]$LogPath,
    [switch]$DebugMode
  )
  # Initialize default CSV log file once per session if none provided
  if (-not $LogPath) {
    if (-not (Get-Variable -Name Common_LogPath -Scope Script -ErrorAction SilentlyContinue)) {
      $folders = Initialize-ScriptFolders -ScriptPath $PSCommandPath
      $scriptName = Split-Path -Leaf $PSCommandPath
      $tsFile = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
      $Script:Common_LogPath = Join-Path $folders.LogsPath ("$($scriptName)-$tsFile.csv")
      # Write CSV header
      "Timestamp,Level,Context,Message" | Out-File -FilePath $Script:Common_LogPath -Encoding utf8 -Append
    }
    $LogPath = $Script:Common_LogPath
  }

  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
  # Console routing (human-friendly)
  $textEntry = if ($Context) { "$ts [$Level] [$Context] $Message" } else { "$ts [$Level] $Message" }
  switch ($Level) {
    'INFO'    { Write-Host $textEntry }
    'WARN'    { Write-Warning $textEntry }
    'ERROR'   { Write-Error $textEntry }
    'VERBOSE' { Write-Verbose $textEntry }
    'DEBUG'   { if ($DebugMode) { Write-Host $textEntry } }
  }

  # CSV line: Timestamp,Level,Context,Message (escape quotes)
  $ctx = if ($Context) { $Context } else { '' }
  $msgEsc = $Message.Replace('"','""')
  $ctxEsc = $ctx.Replace('"','""')
  $csvLine = '"{0}","{1}","{2}","{3}"' -f $ts, $Level, $ctxEsc, $msgEsc
  Add-Content -Path $LogPath -Value $csvLine
}

function Invoke-Retry {
  param(
    [Parameter(Mandatory)][scriptblock]$Action,
    [int]$MaxAttempts = 3,
    [int]$DelaySeconds = 2,
    [switch]$Jitter
  )
  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    try { return & $Action } catch {
      Write-Log -Level 'WARN' -Message "Attempt $attempt failed: $($_.Exception.Message)" -Context 'Retry'
      if ($attempt -eq $MaxAttempts) { throw }
      $sleep = $DelaySeconds
      if ($Jitter) { $sleep += Get-Random -Minimum 0 -Maximum [Math]::Max(1, [int]($DelaySeconds/2)) }
      Start-Sleep -Seconds $sleep
    }
  }
}

function Load-Config {
  param([Parameter()][string]$ConfigPath)
  $cfg = @{}
  if (-not $ConfigPath) { return $cfg }
  if (-not (Test-Path $ConfigPath)) { throw "ConfigPath '$ConfigPath' not found" }
  switch -regex ($ConfigPath) {
    '.*\.json$' { $cfg = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json }
    '.*\.psd1$' { $cfg = Import-PowerShellDataFile -Path $ConfigPath }
    default      { throw "Unsupported config format: $ConfigPath" }
  }
  return $cfg
}

function Ensure-Modules {
  param(
    [Parameter(Mandatory)][string[]]$ModuleNames,
    [switch]$InstallMissing,
    [switch]$ScopeCurrentUser
  )
  # Determine probable local Modules search roots
  $scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
  $localSearchRoots = @()
  $candidate1 = Join-Path $scriptRoot 'Modules'
  if (Test-Path $candidate1) { $localSearchRoots += $candidate1 }
  if ($PSCommandPath) {
    $moduleDir = Split-Path -Parent $PSCommandPath
    $maybeModules = Split-Path -Parent $moduleDir
    if ((Split-Path -Leaf $maybeModules) -eq 'Modules' -and (Test-Path $maybeModules)) { $localSearchRoots += $maybeModules }
  }
  $cwdModules = Join-Path (Get-Location).Path 'Modules'
  if (Test-Path $cwdModules) { $localSearchRoots += $cwdModules }
  $localSearchRoots = @($localSearchRoots | Select-Object -Unique)

  Write-Log -Level INFO -Message "Checking required modules: $($ModuleNames -join ', ')" -Context 'Ensure-Modules'
  Write-Log -Level INFO -Message "Local module search roots: $([string]::Join('; ', $localSearchRoots))" -Context 'Ensure-Modules'

  $missing = @()
  foreach ($name in $ModuleNames) {
    $loaded = Get-Module -Name $name
    $available = Get-Module -ListAvailable -Name $name
    if ($loaded) {
      Write-Log -Level INFO -Message "Module already loaded: $name ($($loaded.Version))" -Context 'Ensure-Modules'
      continue
    }
    if ($available) {
      try {
        Import-Module -Name $name -Scope Global -ErrorAction Stop
        Write-Log -Level INFO -Message "Imported available module: $name" -Context 'Ensure-Modules'
      } catch {
        Write-Log -Level WARN -Message "Failed to import available module '$name': $($_.Exception.Message)" -Context 'Ensure-Modules'
        $missing += $name
      }
    } else {
      # Try local Modules paths if present (support .psd1/.psm1 or module folder)
      if ($localSearchRoots.Count -gt 0) {
        $imported = $false
        foreach ($root in $localSearchRoots) {
          # First, look for manifest or module file named exactly like the module
          $manifest = Get-ChildItem -Path $root -Recurse -File -Include "$name.psd1","$name.psm1" -ErrorAction SilentlyContinue | Select-Object -First 1
          if (-not $manifest) {
            # Next, look for a directory named like the module
            $dirCandidate = Get-ChildItem -Path $root -Recurse -Directory -Filter $name -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($dirCandidate) {
              # If directory, see if it contains a matching manifest/module file
              $manifest = Get-ChildItem -Path $dirCandidate.FullName -File -Include "$name.psd1","$name.psm1" -ErrorAction SilentlyContinue | Select-Object -First 1
              if (-not $manifest) { $manifest = $dirCandidate }
            }
          }
          if ($manifest) {
            try {
              Import-Module $manifest.FullName -Scope Global -ErrorAction Stop
              Write-Log -Level INFO -Message "Imported local module: $name from $($manifest.FullName)" -Context 'Ensure-Modules'
              $imported = $true
              break
            } catch {
              Write-Log -Level WARN -Message "Failed to import local module '$name' from $($manifest.FullName): $($_.Exception.Message)" -Context 'Ensure-Modules'
            }
          }
        }
        if ($imported) { continue } else { Write-Log -Level VERBOSE -Message "Local module file/folder not found in any search root for '$name'" -Context 'Ensure-Modules' }
      }
      $missing += $name
    }
  }

  $missingList = @($missing)
  if ($missingList.Count -gt 0) {
    Write-Log -Level WARN -Message "Missing modules after import attempts: $($missing -join ', ')" -Context 'Ensure-Modules'
    if (-not $InstallMissing) {
      throw "Missing required modules: $($missing -join ', '). Set -InstallMissing to auto-install."
    }
    foreach ($m in $missingList) {
      $scope = if ($ScopeCurrentUser) { 'CurrentUser' } else { 'AllUsers' }
      try {
        if (-not (Get-Module -ListAvailable -Name PowerShellGet)) {
          Write-Log -Level WARN -Message "PowerShellGet not available; attempting install via PSGallery requires PowerShellGet." -Context 'Ensure-Modules'
        }
        Write-Log -Level INFO -Message "Installing module '$m' (Scope=$scope)" -Context 'Ensure-Modules'
        Install-Module -Name $m -Scope $scope -Force -ErrorAction Stop
        Import-Module -Name $m -Scope Global -ErrorAction Stop
        Write-Log -Level INFO -Message "Installed and imported: $m" -Context 'Ensure-Modules'
      } catch {
        Write-Log -Level ERROR -Message "Failed to install/import module '$m': $($_.Exception.Message)" -Context 'Ensure-Modules'
        throw
      }
    }
  }

  # Final validation
  $notLoaded = @()
  foreach ($name in $ModuleNames) {
    if (-not (Get-Module -Name $name)) { $notLoaded += $name }
  }
  if ($notLoaded.Count -gt 0) {
    Write-Log -Level ERROR -Message "Modules not loaded: $($notLoaded -join ', ')" -Context 'Ensure-Modules'
    throw "Modules not loaded: $($notLoaded -join ', ')"
  }
  Write-Log -Level INFO -Message "All required modules loaded successfully." -Context 'Ensure-Modules'
  return $true
}

function Initialize-ScriptFolders {
  <#
    .SYNOPSIS
      Ensures per-script Output and Logs folders exist.
    .DESCRIPTION
      Creates <ScriptBaseName>-Output and <ScriptBaseName>-Logs under the script root (derived from -ScriptPath or current context) if missing and returns their paths.
    .PARAMETER ScriptPath
      Full path to the invoking script. If omitted, attempts to derive from $PSCommandPath / $PSScriptRoot.
    .PARAMETER ScriptName
      Script file name (with or without extension). If not supplied, taken from -ScriptPath.
    .OUTPUTS
      PSCustomObject with ScriptRoot, OutputPath, LogsPath.
    .EXAMPLE
      $paths = Initialize-ScriptFolders -ScriptPath $PSCommandPath
      Write-Host "Output: $($paths.OutputPath) Logs: $($paths.LogsPath)"
  #>
  param(
    [Parameter()][string]$ScriptPath,
    [Parameter()][string]$ScriptName
  )
  if (-not $ScriptName) {
    if ($ScriptPath) { $ScriptName = Split-Path -Leaf $ScriptPath } elseif ($PSCommandPath) { $ScriptName = Split-Path -Leaf $PSCommandPath } else { throw 'Provide ScriptName or ScriptPath.' }
  }
  $baseName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptName)
  $scriptRoot = if ($ScriptPath) { Split-Path -Parent $ScriptPath } elseif ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
  $outputDir = Join-Path $scriptRoot ("$baseName-Output")
  $logsDir   = Join-Path $scriptRoot ("$baseName-Logs")
  foreach ($dir in @($outputDir,$logsDir)) { if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null } }
  return [PSCustomObject]@{ ScriptRoot = $scriptRoot; OutputPath = $outputDir; LogsPath = $logsDir }
}

Export-ModuleMember -Function Get-Timestamp, Ensure-Directory, Write-Log, Invoke-Retry, Load-Config, Ensure-Modules, Initialize-ScriptFolders

# Fast CSV logger using a single StreamWriter
function Start-FastLog {
  param(
    [Parameter()][string]$LogPath,
    [Parameter()][int]$BufferSize = 65536
  )
  if (-not $LogPath) {
    $folders = Initialize-ScriptFolders -ScriptPath $PSCommandPath
    $scriptName = Split-Path -Leaf $PSCommandPath
    $tsFile = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $LogPath = Join-Path $folders.LogsPath ("$($scriptName)-$tsFile-fast.csv")
  }
  $enc = [System.Text.Encoding]::UTF8
  $Script:Common_FastLogWriter = [System.IO.StreamWriter]::new($LogPath, $true, $enc, $BufferSize)
  $Script:Common_FastLogWriter.AutoFlush = $false
  if (-not (Get-Variable -Name Common_FastLogHeaderWritten -Scope Script -ErrorAction SilentlyContinue)) {
    $Script:Common_FastLogWriter.WriteLine('Timestamp,Level,Context,Message')
    $Script:Common_FastLogHeaderWritten = $true
  }
  $Script:Common_FastLogPath = $LogPath
  return $LogPath
}

function Write-FastLog {
  param(
    [Parameter(Mandatory)][ValidateSet('INFO','WARN','ERROR','DEBUG','VERBOSE')][string]$Level,
    [Parameter(Mandatory)][string]$Message,
    [Parameter()][string]$Context = ''
  )
  if (-not $Script:Common_FastLogWriter) { Start-FastLog | Out-Null }
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
  $msgEsc = $Message.Replace('"','""')
  $ctxEsc = $Context.Replace('"','""')
  $Script:Common_FastLogWriter.WriteLine('"{0}","{1}","{2}","{3}"' -f $ts,$Level,$ctxEsc,$msgEsc)
}

function Stop-FastLog {
  if ($Script:Common_FastLogWriter) {
    try { $Script:Common_FastLogWriter.Flush() } catch {}
    try { $Script:Common_FastLogWriter.Dispose() } catch {}
    Remove-Variable -Name Common_FastLogWriter -Scope Script -ErrorAction SilentlyContinue
  }
}

Export-ModuleMember -Function Start-FastLog, Write-FastLog, Stop-FastLog
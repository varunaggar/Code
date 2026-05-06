# profile.ps1
# Runs ONCE when a PowerShell worker starts.
# Authenticates the Managed Identity and imports shared helper modules
# so every function can use them without per-function setup.

# Authenticate via Managed Identity (works on Azure; skipped locally)
if ($env:MSI_SECRET) {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
}

# Import all shared helper modules
# Order matters: LoggingHelpers first (other modules may emit logs at import time
# in future), then GraphHelpers and SqlHelpers (independent of each other).
$sharedPath = Join-Path $PSScriptRoot 'shared'
if (Test-Path $sharedPath) {
    $loadOrder = @('LoggingHelpers.psm1', 'GraphHelpers.psm1', 'SqlHelpers.psm1')
    foreach ($file in $loadOrder) {
        $full = Join-Path $sharedPath $file
        if (Test-Path $full) {
            Import-Module $full -Force -ErrorAction Stop
            Write-Host "Imported $file"
        }
    }

    # Catch any other .psm1 files we add in future
    Get-ChildItem -Path $sharedPath -Filter '*.psm1' | Where-Object {
        $_.Name -notin $loadOrder
    } | ForEach-Object {
        Import-Module $_.FullName -Force -ErrorAction Stop
        Write-Host "Imported $($_.Name)"
    }
}

Write-Host "Function App worker initialised: $(Get-Date -Format 'o')"

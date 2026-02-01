# Get the current module path
$moduleRoot = $PSScriptRoot

# Define the functions directory
$functionsPath = Join-Path $moduleRoot "Functions"

# Dot-source all function files
if (Test-Path $functionsPath) {
    $functionFiles = Get-ChildItem -Path $functionsPath -Filter *.ps1 -File
    foreach ($file in $functionFiles) {
        try {
            . $file.FullName
        }
        catch {
            Write-Warning "Failed to load function file '$($file.Name)': $_"
        }
    }
}

# Export all functions
Export-ModuleMember -Function *

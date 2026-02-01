@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'Common.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.0'

    # ID used to uniquely identify this module
    GUID = 'a1b2c3d4-e5f6-7890-1234-567890abcdef'

    # Author of this module
    Author = 'Copilot'

    # Company or vendor of this module
    CompanyName = 'Generic'

    # Copyright statement for this module
    Copyright = '(c) 2026. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Common helper functions for M365, Authentication, Logging, and Data processing.'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Functions to export from this module, for best performance, do not use wildcards
    FunctionsToExport = @('Start-FastLog', 'Write-FastLog', 'Export-SimpleExcel', 'Merge-CsvFolder', 'Initialize-ModuleDependencies', 'Connect-Service', 'Invoke-GraphHuntingQuery')

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = '*'

    # Aliases to export from this module
    AliasesToExport = @()

    # List of all modules packaged with this module
    # NestedModules = @()
}

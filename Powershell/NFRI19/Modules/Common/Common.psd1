@{
    RootModule        = 'Common.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'ae1c4a7b-2d2a-4c64-9e3a-9f6f7e1bf111'
    Author            = 'Varun Aggarwal'
    CompanyName       = 'Internal'
    Copyright         = ''
    Description       = 'Common helper functions for scripts: logging, retry, config, timestamps, directory utils.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Get-Timestamp','Ensure-Directory','Write-Log','Invoke-Retry','Load-Config','Ensure-Modules','Initialize-ScriptFolders','Start-FastLog','Write-FastLog','Stop-FastLog')
    AliasesToExport   = @()
    CmdletsToExport   = @()
}
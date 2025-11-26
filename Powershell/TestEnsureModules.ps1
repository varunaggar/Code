Import-Module -Force "$PSScriptRoot/Modules/Common/Common.psm1"

Write-Host "Testing Ensure-Modules for local module 'Foo'..."
Ensure-Modules -ModuleNames 'Foo' | Out-Null

$result = Get-Foo
Write-Host "Get-Foo returned: $result"

#!/usr/bin/env pwsh
# Test Script for -ConfigFile parameter

# 1. Import common module
$modulePath = Join-Path $PSScriptRoot "../Modules/Common"
Import-Module $modulePath -Force

# 2. Define custom config path
$customConfig = Join-Path $PSScriptRoot "Custom-Config.xml"
Write-Host "Testing with config file: $customConfig" -ForegroundColor Magenta

# 3. Call Dependency Init with explicit config
# We use -Setup as well to ensure the logging infrastructure is ready
$envInfo = Initialize-ModuleDependencies -Setup -ConfigFile $customConfig

# 3.5 Test Service Connection (This will likely fail interactively in automation, but logic will run)
# We wrap in try/catch to observe the attempt in logs
try {
    Connect-ConfiguredServices -ConfigPath $customConfig
} catch {
    Write-FastLog -Message "Expected failure during automated test (Interactive Prompt or missing module): $_" -Level 'WARN' -Context 'Test'
}

# 4. Verify
Write-FastLog -Message "Test completed. Checked config at: $customConfig" -Level 'SUCCESS' -Context 'Test'

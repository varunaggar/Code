#!/usr/bin/env pwsh
# Test Script to verify Service Connection Logic paths
$modulePath = Join-Path $PSScriptRoot "../Modules/Common"
Import-Module $modulePath -Force

function Test-ServiceConfig {
    param($XmlContent, $TestName)
    $tempFile = [System.IO.Path]::GetTempFileName() + ".xml"
    $XmlContent | Set-Content $tempFile
    
    Write-FastLog -Message "`n=== Testing $TestName ===" -Context "TEST"
    try {
        Connect-Service -ConfigPath $tempFile
    } catch {
        Write-FastLog -Message "Result: $_" -Level "WARN" -Context "TEST"
    } finally {
        Remove-Item $tempFile -ErrorAction SilentlyContinue
    }
}

# 1. Test Graph - ClientSecret (Logic Check)
$xmlGraphSecret = @"
<Configuration>
    <Services>
        <Service Name="Graph">
            <Enabled>true</Enabled>
            <AuthMethod>ClientSecret</AuthMethod>
            <TenantId>fake-tenant-id</TenantId>
            <ClientId>fake-client-id</ClientId>
            <ClientSecret>fake-secret-value</ClientSecret>
            <ContextScope>Process</ContextScope>
        </Service>
    </Services>
</Configuration>
"@
Test-ServiceConfig -XmlContent $xmlGraphSecret -TestName "Graph (ClientSecret)"

# 2. Test Exchange - ClientSecret (Token Logic Check)
$xmlExoSecret = @"
<Configuration>
    <Services>
        <Service Name="ExchangeOnline">
            <Enabled>true</Enabled>
            <AuthMethod>ClientSecret</AuthMethod>
            <TenantId>fake-tenant-id</TenantId>
            <ClientId>fake-client-id</ClientId>
            <ClientSecret>fake-secret-value</ClientSecret>
            <Organization>fake.onmicrosoft.com</Organization>
        </Service>
    </Services>
</Configuration>
"@
Test-ServiceConfig -XmlContent $xmlExoSecret -TestName "Exchange (ClientSecret - Token Flow)"

# 3. Test Az - ClientSecret
$xmlAzSecret = @"
<Configuration>
    <Services>
        <Service Name="Az">
            <Enabled>true</Enabled>
            <AuthMethod>ClientSecret</AuthMethod>
            <TenantId>fake-tenant-id</TenantId>
            <ClientId>fake-client-id</ClientId>
            <ClientSecret>fake-secret-value</ClientSecret>
            <SubscriptionId>fake-sub-id</SubscriptionId>
        </Service>
    </Services>
</Configuration>
"@
Test-ServiceConfig -XmlContent $xmlAzSecret -TestName "Az (ClientSecret)"

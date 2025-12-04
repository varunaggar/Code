# Validates an SVG logo against DigiCert VMC/CMC format requirements.
# Uses the public Utilities endpoint: PUT https://www.digicert.com/services/v2/util/validate-vmc-logo
# Authentication: Not required. Send raw SVG data. Content-Type depends on XML declaration.

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string] $SvgPath,

    [switch] $VerboseOutput
)

function Get-ContentTypeForSvg {
    param([string] $SvgText)
    # If the SVG includes an XML declaration, use image/svg+xml; otherwise image/svg
    if ($SvgText -match "<\?xml[\s\S]*\?>") {
        return "image/svg+xml"
    } else {
        return "image/svg"
    }
}

function Validate-VmcSvg {
    param([string] $SvgText)

    $uri = "https://www.digicert.com/services/v2/util/validate-vmc-logo"
    $contentType = Get-ContentTypeForSvg -SvgText $SvgText

    if ($VerboseOutput) {
        Write-Host "Using Content-Type: $contentType" -ForegroundColor Cyan
        Write-Host "Endpoint: $uri" -ForegroundColor Cyan
        Write-Host ("Payload length: {0} bytes" -f ([Text.Encoding]::UTF8.GetByteCount($SvgText))) -ForegroundColor Cyan
    }

    try {
        function Invoke-ValidateRequest([string] $ctype) {
            $handler = New-Object System.Net.Http.HttpClientHandler
            $client = New-Object System.Net.Http.HttpClient($handler)
            $client.DefaultRequestHeaders.ExpectContinue = $false

            $content = New-Object System.Net.Http.StringContent($SvgText, [System.Text.Encoding]::UTF8, $ctype)
            $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Put, $uri)
            $request.Content = $content

            $response = $client.SendAsync($request).GetAwaiter().GetResult()
            $statusCode = [int]$response.StatusCode

            if ($statusCode -eq 204) {
                $client.Dispose()
                return [pscustomobject]@{ ok = $true; status = 204; content = $null; code = $null; message = $null; line = $null; column = $null }
            }

            $respContent = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $client.Dispose()

            $code = $null; $msg = $null; $line = $null; $col = $null
            $parsed = $null
            if ($respContent) { try { $parsed = $respContent | ConvertFrom-Json } catch { $parsed = $null } }
            if ($parsed) {
                if ($parsed.message) { $msg = [string]$parsed.message }
                if ($parsed.errors) {
                    $first = $parsed.errors | Select-Object -First 1
                    if ($first.code) { $code = [string]$first.code }
                    if ($first.message) { $msg = [string]$first.message }
                    if ($first.line) { $line = [int]$first.line }
                    if ($first.column) { $col = [int]$first.column }
                } else {
                    if ($parsed.code) { $code = [string]$parsed.code }
                    if ($parsed.line) { $line = [int]$parsed.line }
                    if ($parsed.column) { $col = [int]$parsed.column }
                }
            }
            return [pscustomobject]@{ ok = $false; status = $statusCode; content = $respContent; code = $code; message = $msg; line = $line; column = $col }
        }

        $primary = Invoke-ValidateRequest -ctype $contentType
        if ($primary.ok) {
            return [pscustomobject]@{
                Success     = $true
                StatusCode  = 204
                Message     = "Valid SVG: meets VMC/CMC format requirements."
                Details     = $null
            }
        }

        # Fallback: if server reports MIME type mismatch, retry with image/svg+xml
        if ($primary.status -eq 400 -and ($primary.code -eq 'mime_type_mismatch' -or $primary.message -match 'Content-Type header does not match') -and $contentType -ne 'image/svg+xml') {
            if ($VerboseOutput) { Write-Host "Retrying with Content-Type: image/svg+xml" -ForegroundColor Yellow }
            $retry = Invoke-ValidateRequest -ctype 'image/svg+xml'
            if ($retry.ok) {
                return [pscustomobject]@{
                    Success     = $true
                    StatusCode  = 204
                    Message     = "Valid SVG: meets VMC/CMC format requirements."
                    Details     = $null
                }
            } else {
                return [pscustomobject]@{
                    Success     = $false
                    StatusCode  = $retry.status
                    Message     = ($retry.message ?? 'Validation failed.')
                    Line        = $retry.line
                    Column      = $retry.column
                    Details     = $retry.content
                }
            }
        }

        return [pscustomobject]@{
            Success     = $false
            StatusCode  = $primary.status
            Message     = ($primary.message ?? 'Validation failed.')
            Line        = $primary.line
            Column      = $primary.column
            Details     = $primary.content
        }
    }
    catch {
        return [pscustomobject]@{
            Success     = $false
            StatusCode  = $null
            Message     = "Unexpected error: $($_.Exception.Message)"
            Details     = $null
        }
    }
}

# Entry point
if (-not (Test-Path -LiteralPath $SvgPath)) {
    Write-Error "File not found: $SvgPath"
    exit 1
}

# Read raw SVG as text; preserve exact bytes
$svgText = Get-Content -LiteralPath $SvgPath -Raw -ErrorAction Stop

$result = Validate-VmcSvg -SvgText $svgText

if ($result.Success) {
    Write-Host $result.Message -ForegroundColor Green
    exit 0
} else {
    $status = if ($result.StatusCode) { $result.StatusCode } else { "(none)" }
    Write-Host "Status: $status" -ForegroundColor Yellow
    Write-Host $result.Message -ForegroundColor Red
    if ($result.Line -or $result.Column) {
        Write-Host "Location: line $($result.Line), column $($result.Column)" -ForegroundColor Yellow
    }
    if ($VerboseOutput -and $result.Details) {
        Write-Host "Details:" -ForegroundColor Cyan
        Write-Output $result.Details
    }
    exit 2
}
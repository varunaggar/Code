function Ensure-ExchangeOnlineConnection {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$UserPrincipalName,

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential,

        [switch]$SkipLoadingCmdletHelp = $true,
        [switch]$UseMultithreading     = $true,
        [switch]$ShowProgress,
        [switch]$VerboseLogging,

        [int]$TokenRefreshThresholdMinutes = 5,
        [int]$MaxReconnectAttempts = 3,
        [int]$ThrottleDelaySeconds = 15,
        [switch]$ForceReconnect
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Verbose 'Ensuring ExchangeOnlineManagement module is loaded.'
    $module = Get-Module -Name ExchangeOnlineManagement -ErrorAction SilentlyContinue
    if (-not $module) {
        $module = Import-Module -Name ExchangeOnlineManagement -ErrorAction Stop -PassThru
    }

    if (-not $module) {
        throw 'ExchangeOnlineManagement module is not available. Install it before invoking this function.'
    }

    function Invoke-ConnectWithRetry {
        param(
            [Parameter(Mandatory)][hashtable]$ConnectParameters,
            [Parameter(Mandatory)][int]$Attempts,
            [Parameter(Mandatory)][int]$DelaySeconds
        )

        for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
            try {
                Write-Verbose "Connecting to Exchange Online (attempt $attempt of $Attempts)..."
                Connect-ExchangeOnline @ConnectParameters
                return
            } catch {
                $message = $_.Exception.Message
                $isThrottle = $message -match '(Too\s+Many\s+Requests|429|thrott|service is busy)'
                $isToken    = $message -match '(token|session).*(expire|expired)|AADSTS700082|AADSTS700084'

                if ($attempt -ge $Attempts) {
                    throw $_
                }

                $sleepSeconds = if ($isThrottle) {
                    [math]::Max($DelaySeconds * $attempt, 5)
                } elseif ($isToken) {
                    5
                } else {
                    3
                }

                Write-Verbose "Connect attempt $attempt failed: $message`nWaiting $sleepSeconds second(s) before retry..."
                Start-Sleep -Seconds $sleepSeconds
            }
        }
    }

    if ($TokenRefreshThresholdMinutes -lt 0) { $TokenRefreshThresholdMinutes = 0 }

    $connectionInfo   = $null
    $activeConnection = $null
    try {
        $connectionInfo = Get-ConnectionInformation -ErrorAction Stop
    } catch {
        Write-Verbose 'No existing connection information was found.'
    }

    if ($connectionInfo) {
        $brokenStates    = 'Disconnected','Unknown','Broken'
        $staleConnections = $connectionInfo | Where-Object { $brokenStates -contains $_.State }
        if ($staleConnections) {
            Write-Verbose 'Removing stale/broken Exchange Online sessions.'
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            $connectionInfo = $connectionInfo | Where-Object { $_.State -eq 'Connected' }
        }

        $activeConnection = $connectionInfo | Where-Object { $_.State -eq 'Connected' } | Select-Object -First 1
    }

    $needsReconnect = $ForceReconnect.IsPresent -or (-not $activeConnection)

    if (-not $needsReconnect -and $activeConnection) {
        $nowUtc       = (Get-Date).ToUniversalTime()
        $thresholdUtc = $nowUtc.AddMinutes($TokenRefreshThresholdMinutes)
        $tokenStatus  = $activeConnection.TokenStatus
        $expiryString = $activeConnection.TokenExpiryTimeUTC
        $expiryUtc    = $null

        if ($tokenStatus -and $tokenStatus -ne 'Active') {
            Write-Verbose "Token status '$tokenStatus' is not Active; reconnecting."
            $needsReconnect = $true
        } elseif (-not [string]::IsNullOrWhiteSpace($expiryString)) {
            try {
                $expiryUtc = ([datetime]$expiryString).ToUniversalTime()
            } catch {
                Write-Verbose 'Unable to parse token expiry; reconnecting defensively.'
                $needsReconnect = $true
            }

            if (-not $needsReconnect -and $expiryUtc) {
                Write-Verbose "Token expires at $expiryUtc (UTC); threshold is $thresholdUtc (UTC)."
                if ($expiryUtc -le $thresholdUtc) {
                    Write-Verbose 'Token nearing expiry; reconnecting early.'
                    $needsReconnect = $true
                }
            }
        } else {
            Write-Verbose 'Token expiry not provided; reconnecting defensively.'
            $needsReconnect = $true
        }
    }

    if (-not $needsReconnect -and $activeConnection) {
        Write-Verbose 'Existing Exchange Online session is healthy; no reconnect required.'
        return $activeConnection
    }

    Write-Verbose 'Establishing a fresh Exchange Online connection.'
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

    $connectParams = @{
        ShowBanner            = $false
        ShowProgress          = $ShowProgress.IsPresent
        UseMultithreading     = $UseMultithreading.IsPresent
        SkipLoadingCmdletHelp = $SkipLoadingCmdletHelp.IsPresent
    }

    if ($PSBoundParameters.ContainsKey('UserPrincipalName')) {
        $connectParams['UserPrincipalName'] = $UserPrincipalName
    }
    if ($PSBoundParameters.ContainsKey('Credential')) {
        $connectParams['Credential'] = $Credential
    }

    Invoke-ConnectWithRetry -ConnectParameters $connectParams -Attempts $MaxReconnectAttempts -DelaySeconds $ThrottleDelaySeconds

    return Get-ConnectionInformation -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq 'Connected' } |
        Select-Object -First 1
}

<#!
.SYNOPSIS
    Sample script: read unread Exchange Online mailbox messages via Microsoft Graph (app-only) and validate mailbox request format.
.DESCRIPTION
    Uses client-credentials flow (Azure AD app + secret) to read unread messages from a shared mailbox.
    Validates subject/body for required information and optionally replies when info is missing.
.NOTES
    Required Microsoft Graph Application permissions (admin consent):
      - Mail.Read
      - Mail.Send (only if replying)
    The target mailbox must be accessible to the app (application access policy if required).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $true)]
    [string]$MailboxUpn,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 200)]
    [int]$Top = 50,

    [Parameter(Mandatory = $false)]
    [switch]$ReplyIfMissing = $true,

    [Parameter(Mandatory = $false)]
    [string]$IncorrectInfoFolderName = 'Incorrect Information',

    [Parameter(Mandatory = $false)]
    [string]$CompletedFolderName = 'Completed',

    [Parameter(Mandatory = $false)]
    [string]$OnPremExchangeUri = 'https://exch-onprem.example.com/powershell',

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$OnPremCredential,

    [Parameter(Mandatory = $false)]
    [string]$DefaultUpnDomain
)

# Try to load local secrets (optional)
$psVarsPath = Join-Path $PSScriptRoot 'psvariables.ps1'
if (Test-Path $psVarsPath) {
    . $psVarsPath
}

# Allow environment variable fallbacks
if (-not $TenantId) { $TenantId = $env:GRAPH_TENANT_ID }
if (-not $ClientId) { $ClientId = $env:GRAPH_CLIENT_ID }
if (-not $ClientSecret) { $ClientSecret = $env:GRAPH_CLIENT_SECRET }

# Logging (use Common module when available)
$commonModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Modules/Common/Common.psd1'
$useFastLog = $false
if (Test-Path $commonModulePath) {
    try {
        Import-Module $commonModulePath -Force -ErrorAction Stop
        Start-FastLog
        $useFastLog = $true
    } catch {
        $useFastLog = $false
    }
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS')]
        [string]$Level = 'INFO',
        [string]$Context = 'NewMailboxRequest'
    )

    if ($useFastLog) {
        Write-FastLog -Message $Message -Level $Level -Context $Context
    } else {
        $prefix = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level]"
        Write-Host "$prefix $Message"
    }
}

if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
    throw 'TenantId, ClientId, and ClientSecret are required. Provide parameters or set GRAPH_TENANT_ID/GRAPH_CLIENT_ID/GRAPH_CLIENT_SECRET.'
}

$tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

function Get-AccessToken {
    param([string]$Scope)
    $body = @{ client_id = $ClientId; client_secret = $ClientSecret; grant_type = 'client_credentials'; scope = $Scope }
    $resp = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Body $body -ErrorAction Stop
    return $resp.access_token
}

function Invoke-GraphGet {
    param(
        [string]$Uri,
        [string]$Token
    )
    $headers = @{ Authorization = "Bearer $Token" }
    return Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers -ErrorAction Stop
}

function Invoke-GraphPost {
    param(
        [string]$Uri,
        [string]$Token,
        [object]$Body
    )
    $headers = @{ Authorization = "Bearer $Token"; 'Content-Type' = 'application/json' }
    $json = $Body | ConvertTo-Json -Depth 6
    return Invoke-RestMethod -Method Post -Uri $Uri -Headers $headers -Body $json -ErrorAction Stop
}

function Invoke-GraphPatch {
    param(
        [string]$Uri,
        [string]$Token,
        [object]$Body
    )
    $headers = @{ Authorization = "Bearer $Token"; 'Content-Type' = 'application/json' }
    $json = $Body | ConvertTo-Json -Depth 6
    return Invoke-RestMethod -Method Patch -Uri $Uri -Headers $headers -Body $json -ErrorAction Stop
}

function Ensure-MailFolder {
    param(
        [string]$Mailbox,
        [string]$Token,
        [string]$DisplayName,
        [hashtable]$Cache
    )

    if ($Cache.ContainsKey($DisplayName)) {
        return $Cache[$DisplayName]
    }

    $filterName = $DisplayName.Replace("'", "''")
    $query = "https://graph.microsoft.com/v1.0/users/$Mailbox/mailFolders?`$filter=displayName%20eq%20'$filterName'&`$select=id,displayName"
    $resp = Invoke-GraphGet -Uri $query -Token $Token
    $folder = $resp.value | Select-Object -First 1

    if (-not $folder) {
        $createUri = "https://graph.microsoft.com/v1.0/users/$Mailbox/mailFolders"
        $folder = Invoke-GraphPost -Uri $createUri -Token $Token -Body @{ displayName = $DisplayName }
    }

    $Cache[$DisplayName] = $folder.id
    return $folder.id
}

function Move-GraphMessage {
    param(
        [string]$Mailbox,
        [string]$MessageId,
        [string]$DestinationFolderId,
        [string]$Token
    )

    $moveUri = "https://graph.microsoft.com/v1.0/users/$Mailbox/messages/$MessageId/move"
    Invoke-GraphPost -Uri $moveUri -Token $Token -Body @{ destinationId = $DestinationFolderId } | Out-Null
}

function Send-GraphReply {
    param(
        [string]$Mailbox,
        [string]$MessageId,
        [string]$Token,
        [string]$ReplyText,
        [string[]]$CcRecipients
    )

    $createUri = "https://graph.microsoft.com/v1.0/users/$Mailbox/messages/$MessageId/createReply"
    $draft = Invoke-GraphPost -Uri $createUri -Token $Token -Body @{}

    $bodyObj = @{ body = @{ contentType = 'Text'; content = $ReplyText } }
    if ($CcRecipients -and $CcRecipients.Count -gt 0) {
        $bodyObj.ccRecipients = @(
            $CcRecipients | ForEach-Object { @{ emailAddress = @{ address = $_ } } }
        )
    }

    $patchUri = "https://graph.microsoft.com/v1.0/users/$Mailbox/messages/$($draft.id)"
    Invoke-GraphPatch -Uri $patchUri -Token $Token -Body $bodyObj | Out-Null

    $sendUri = "https://graph.microsoft.com/v1.0/users/$Mailbox/messages/$($draft.id)/send"
    Invoke-GraphPost -Uri $sendUri -Token $Token -Body @{} | Out-Null
}

function Normalize-Value {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return $Value.Trim().ToLowerInvariant()
}

function Ensure-ExchangeOnPremSession {
    param(
        [string]$ConnectionUri,
        [System.Management.Automation.PSCredential]$Credential
    )

    if ($script:ExchangeOnPremSession -and $script:ExchangeOnPremSession.State -eq 'Opened') {
        return $script:ExchangeOnPremSession
    }

    if (-not $Credential) {
        $Credential = Get-Credential -Message 'Enter Exchange on-prem credentials'
    }

    $script:ExchangeOnPremSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri $ConnectionUri -Authentication Kerberos -Credential $Credential
    Import-PSSession $script:ExchangeOnPremSession -DisableNameChecking | Out-Null
    return $script:ExchangeOnPremSession
}

function Convert-BodyToText {
    param([object]$Body)

    if (-not $Body) { return '' }
    $content = $Body.content
    if ($Body.contentType -and $Body.contentType -eq 'html') {
        # Simple HTML strip
        $content = [regex]::Replace($content, '<[^>]+>', ' ')
    }
    $content = $content -replace '\r', ''
    return $content
}

function Parse-RequestFromSubject {
    param([string]$Subject)

    $pattern = '^New\s+mailbox\s+in\s+(?<env>\S+)\s+M365\s+for\s+user\s+(?<tnumber>[A-Za-z]\d+)\b'
    $m = [regex]::Match($Subject, $pattern, 'IgnoreCase')
    if ($m.Success) {
        return [PSCustomObject]@{
            Source    = 'Subject'
            Environment = $m.Groups['env'].Value
            TNumber   = $m.Groups['tnumber'].Value
        }
    }
    return $null
}

function Parse-RequestFromBody {
    param([string]$BodyText)

    $fields = @{}
    foreach ($line in ($BodyText -split "`n")) {
        if ($line -match '^\s*(firstname|lastname|tnumber|gpn)\s*:\s*(.+)\s*$') {
            $fields[$matches[1].ToLower()] = $matches[2].Trim()
        }
    }

    if ($fields.ContainsKey('firstname') -and $fields.ContainsKey('lastname') -and $fields.ContainsKey('tnumber') -and $fields.ContainsKey('gpn')) {
        return [PSCustomObject]@{
            Source    = 'Body'
            FirstName = $fields['firstname']
            LastName  = $fields['lastname']
            TNumber   = $fields['tnumber']
            Gpn       = $fields['gpn']
        }
    }

    return $null
}

$replyText = @"
Hi,

I could not find required information in your email. I suggest to send a new email with the required information using the link below
"@

$replyTnumberMismatch = @"
Hi,

The tnumber in the subject does not match the tnumber in the email body. Please send a new email with matching information.
"@

$replyAdMismatch = @"
Hi,

The information in your email does not match the user record in Active Directory. Please send a new email with correct information.
"@

$replySuccess = @"
Hi,

Your mailbox request has been processed. The mailbox should be ready in Exchange Online in a few hours.
CC'd def@bab.com — please assign an E5 license.
"@

try {
    Write-Log -Message "Acquiring token for Microsoft Graph..." -Level 'INFO'
    $graphToken = Get-AccessToken -Scope 'https://graph.microsoft.com/.default'

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    } catch {
        Write-Log -Message "ActiveDirectory module not available: $($_.Exception.Message)" -Level 'ERROR'
        throw
    }

    $folderCache = @{}

    $select = 'id,subject,body,from,receivedDateTime'
    $uri = "https://graph.microsoft.com/v1.0/users/$MailboxUpn/mailFolders/inbox/messages?`$filter=isRead%20eq%20false&`$orderby=receivedDateTime%20asc&`$top=$Top&`$select=$select"

    Write-Log -Message "Fetching unread messages from $MailboxUpn (oldest to newest)..." -Level 'INFO'
    $resp = Invoke-GraphGet -Uri $uri -Token $graphToken
    $messages = @($resp.value)

    foreach ($msg in $messages) {
        $subject = $msg.subject
        $bodyText = Convert-BodyToText -Body $msg.body

        $subjectReq = Parse-RequestFromSubject -Subject $subject
        $bodyReq = Parse-RequestFromBody -BodyText $bodyText

        if (-not $subjectReq -or -not $bodyReq) {
            Write-Log -Message "Missing required info for message '$subject'" -Level 'WARN'
            if ($ReplyIfMissing) {
                Send-GraphReply -Mailbox $MailboxUpn -MessageId $msg.id -Token $graphToken -ReplyText $replyText
                Write-Log -Message "Replied to message '$subject'" -Level 'INFO'
            }
            continue
        }

        $tnumberSubject = $subjectReq.TNumber
        $tnumberBody = $bodyReq.TNumber
        if (Normalize-Value $tnumberSubject -ne Normalize-Value $tnumberBody) {
            Write-Log -Message "TNumber mismatch for message '$subject'" -Level 'WARN'
            if ($ReplyIfMissing) {
                Send-GraphReply -Mailbox $MailboxUpn -MessageId $msg.id -Token $graphToken -ReplyText $replyTnumberMismatch
            }
            $incorrectId = Ensure-MailFolder -Mailbox $MailboxUpn -Token $graphToken -DisplayName $IncorrectInfoFolderName -Cache $folderCache
            Move-GraphMessage -Mailbox $MailboxUpn -MessageId $msg.id -DestinationFolderId $incorrectId -Token $graphToken
            continue
        }

        $firstName = $bodyReq.FirstName
        $lastName = $bodyReq.LastName
        $tnumber = $bodyReq.TNumber
        $gpn = $bodyReq.Gpn

        $adUser = Get-ADUser -Filter "CustomAttribute5 -eq '$tnumber'" -Properties GivenName,Surname,CustomAttribute5,CustomAttribute9,Enabled,UserPrincipalName
        if (-not $adUser) {
            Write-Log -Message "No AD user found for tnumber $tnumber" -Level 'WARN'
            continue
        }

        $adFirst = Normalize-Value $adUser.GivenName
        $adLast = Normalize-Value $adUser.Surname
        $adT = Normalize-Value $adUser.CustomAttribute5
        $adGpn = Normalize-Value $adUser.CustomAttribute9

        if ((Normalize-Value $firstName) -ne $adFirst -or (Normalize-Value $lastName) -ne $adLast -or (Normalize-Value $tnumber) -ne $adT -or (Normalize-Value $gpn) -ne $adGpn) {
            Write-Log -Message "Email info does not match AD for tnumber $tnumber" -Level 'WARN'
            if ($ReplyIfMissing) {
                Send-GraphReply -Mailbox $MailboxUpn -MessageId $msg.id -Token $graphToken -ReplyText $replyAdMismatch
            }
            $incorrectId = Ensure-MailFolder -Mailbox $MailboxUpn -Token $graphToken -DisplayName $IncorrectInfoFolderName -Cache $folderCache
            Move-GraphMessage -Mailbox $MailboxUpn -MessageId $msg.id -DestinationFolderId $incorrectId -Token $graphToken
            continue
        }

        if (-not $adUser.Enabled) {
            Write-Log -Message "Enabling AD account for $($adUser.SamAccountName)" -Level 'INFO'
            Enable-ADAccount -Identity $adUser -ErrorAction Stop
            $adUser = Get-ADUser -Identity $adUser.DistinguishedName -Properties GivenName,Surname,CustomAttribute5,CustomAttribute9,Enabled,UserPrincipalName
        }

        $currentUpn = $adUser.UserPrincipalName
        $upnDomain = $null
        if ($currentUpn -and $currentUpn -match '@') {
            $upnDomain = ($currentUpn -split '@')[1]
        } elseif ($DefaultUpnDomain) {
            $upnDomain = $DefaultUpnDomain
        }

        $expectedLocal = "$(Normalize-Value $firstName).$(Normalize-Value $lastName)".ToLowerInvariant()
        $currentLocal = if ($currentUpn -and $currentUpn -match '@') { ($currentUpn -split '@')[0].ToLowerInvariant() } else { '' }

        if ($upnDomain -and $currentLocal -ne $expectedLocal) {
            $newUpn = "$expectedLocal@$upnDomain"
            Write-Log -Message "Updating UPN to $newUpn for $($adUser.SamAccountName)" -Level 'INFO'
            Set-ADUser -Identity $adUser -UserPrincipalName $newUpn -ErrorAction Stop
            $currentUpn = $newUpn
        }

        try {
            Ensure-ExchangeOnPremSession -ConnectionUri $OnPremExchangeUri -Credential $OnPremCredential | Out-Null
            Write-Log -Message "Enabling remote mailbox for $($adUser.SamAccountName)" -Level 'INFO'
            Enable-RemoteMailbox -Identity $adUser.DistinguishedName -RemoteRoutingAddress "$($adUser.SamAccountName)@tenant.mail.onmicrosoft.com" -ErrorAction Stop
        } catch {
            Write-Log -Message "Enable-RemoteMailbox failed for $($adUser.SamAccountName): $($_.Exception.Message)" -Level 'ERROR'
            throw
        }

        if ($ReplyIfMissing) {
            Send-GraphReply -Mailbox $MailboxUpn -MessageId $msg.id -Token $graphToken -ReplyText $replySuccess -CcRecipients @('def@bab.com')
            Write-Log -Message "Sent success reply for '$subject'" -Level 'INFO'
        }

        $completedId = Ensure-MailFolder -Mailbox $MailboxUpn -Token $graphToken -DisplayName $CompletedFolderName -Cache $folderCache
        Move-GraphMessage -Mailbox $MailboxUpn -MessageId $msg.id -DestinationFolderId $completedId -Token $graphToken
    }
}
catch {
    Write-Log -Message "Error: $($_.Exception.Message)" -Level 'ERROR'
    throw
}

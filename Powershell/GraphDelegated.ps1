# Reference the variables script
$scriptPath = Join-Path $PSScriptRoot "psvariables.ps1"
if (Test-Path $scriptPath) {
    . $scriptPath
    Write-Host "Variables loaded successfully"
} else {
    Write-Error "Required script not found: $scriptPath"
    exit 1
}

# Load required assemblies
try {
    $abstractionsPath = Join-Path (Split-Path $msalPath) "Microsoft.IdentityModel.Abstractions.dll"
    Add-Type -Path $abstractionsPath
    Add-Type -Path $msalPath
    Write-Host "MSAL assemblies loaded successfully"
} catch {
    Write-Error "Failed to load assemblies: $_"
    Write-Error "MSAL Path: $msalPath"
    Write-Error "Abstractions Path: $abstractionsPath"
    exit 1
}

$authority = "https://login.microsoftonline.com/$tenantId"
$redirectUri = $AppIDGraphDelegatedUri  # Using the URI from psvariables.ps1
$scopes = [string[]]@("https://graph.microsoft.com/Mail.Read")  # Cast as string array

Write-Host "Initializing authentication with:"
Write-Host "Authority: $authority"
Write-Host "Redirect URI: $redirectUri"
Write-Host "Requested Scope: $($scopes[0])"



# Create the MSAL client application
try {
    $builder = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($AppIDGraphDelegated)
    $builder = $builder.WithAuthority($authority)
    $builder = $builder.WithRedirectUri($redirectUri)
    $app = $builder.Build()

    Write-Host "`nAttempting to acquire token interactively..."
    $result = $app.AcquireTokenInteractive($scopes).ExecuteAsync().GetAwaiter().GetResult()
    
    Write-Host "Token acquired successfully!"
    Write-Host "Access Token: $($result.AccessToken.Substring(0,50))..."  # Show first 50 chars only
    Write-Host "Token Expires: $($result.ExpiresOn.LocalDateTime)`n"

    # Set up Graph API headers
    $headers = @{
        "Authorization" = "Bearer $($result.AccessToken)"
        "Content-Type" = "application/json"
    }

    # Simple function to call Graph API
    function Invoke-GraphAPI {
        param (
            [string]$Endpoint
        )
        $uri = "https://graph.microsoft.com/v1.0$Endpoint"
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        return $response
    }

    # Get user's messages in a loop
    $nextLink = "/me/messages?" + ($queryParams = @(
        "`$top=10",
        "`$select=subject,receivedDateTime,from,isRead",
        "`$orderby=receivedDateTime desc"
    ) -join '&')

    do {
        try {
            Write-Host "Fetching messages from your mailbox..."
            $messages = if ($nextLink.StartsWith('http')) {
                # Use full URL from nextLink
                Invoke-RestMethod -Uri $nextLink -Headers $headers -Method Get
            } else {
                # Use endpoint path
                Invoke-GraphAPI -Endpoint $nextLink
            }
            
            # Update nextLink for next iteration
            $nextLink = $messages.'@odata.nextLink'        # Display messages
        Write-Host "`nLatest emails:`n"
        foreach ($message in $messages.value) {
            $readStatus = if ($message.isRead) { "Read" } else { "Unread" }
            $sender = $message.from.emailAddress.address
            $subject = if ($message.subject) { $message.subject } else { "(No Subject)" }
            $received = try {
                [DateTime]::Parse($message.receivedDateTime).ToLocalTime().ToString("MM/dd/yyyy HH:mm")
            } catch {
                $message.receivedDateTime
            }

            Write-Host "[$readStatus] $received"
            Write-Host "From: $sender"
            Write-Host "Subject: $subject"
            Write-Host "-------------------"
        }

            # Display paging information
            if ($nextLink) {
                Write-Host "`nMore messages available in next page."
            } else {
                Write-Host "`nNo more messages available."
            }

        } catch {
            Write-Error "Error fetching messages: $_"
            break
        }

        # Ask to continue only if there are more messages
        if ($nextLink) {
            $continue = Read-Host -Prompt "Continue to iterate? (y/n)"
        } else {
            Write-Host "`nReached the end of messages."
            $continue = 'n'
        }
    } while ($continue -eq 'y')

} catch {
    Write-Error "Authentication Error: $_"
    Write-Host "`nDetailed error information:"
    Write-Host $_.Exception.Message
    if ($_.Exception.InnerException) {
        Write-Host "Inner Exception: $($_.Exception.InnerException.Message)"
    }
    exit 1
}


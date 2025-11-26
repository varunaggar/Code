# Reading Emails Using Microsoft Graph - Step by Step Guide

## Step 1: Register Application in Azure AD

1. Sign in to the [Azure Portal](https://portal.azure.com)
2. Navigate to **Azure Active Directory** → **App registrations** → **New registration**
3. Fill in the details:
   - Name: `Mail Reader App` (or your preferred name)
   - Supported account types: `Accounts in this organizational directory only`
   - Redirect URI: `Public client/native (mobile & desktop)` and URI: `http://localhost`
4. Click **Register**
5. Note down the following values from the overview page:
   - Application (client) ID
   - Directory (tenant) ID

## Step 2: Configure API Permissions

1. In your app registration, go to **API permissions**
2. Click **Add a permission**
3. Select **Microsoft Graph**
4. Choose **Delegated permissions**
5. Search for and select `Mail.Read`
6. Click **Add permissions**

## Step 3: Create PowerShell Script

Create a new file named `Read-UserMails.ps1` with the following code:

```powershell
# Download and load MSAL assembly
$msalUrl = "https://github.com/AzureAD/microsoft-authentication-library-for-dotnet/releases/download/4.37.0/Microsoft.Identity.Client.4.37.0.nupkg"
$msalPath = "Microsoft.Identity.Client.dll"

if (-not (Test-Path $msalPath)) {
    Invoke-WebRequest -Uri $msalUrl -OutFile "msal.nupkg"
    Expand-Archive -Path "msal.nupkg" -DestinationPath "temp"
    Copy-Item "temp/lib/net461/Microsoft.Identity.Client.dll" -Destination $msalPath
    Remove-Item -Path "temp" -Recurse
    Remove-Item -Path "msal.nupkg"
}

Add-Type -Path $msalPath

# App registration details
$tenantId = "YOUR_TENANT_ID"  # Replace with your tenant ID
$clientId = "YOUR_CLIENT_ID"  # Replace with your client ID

# Configure MSAL client
$authority = "https://login.microsoftonline.com/$tenantId"
$redirectUri = "http://localhost"
$scopes = @("https://graph.microsoft.com/Mail.Read")

$app = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($clientId)
    .WithAuthority($authority)
    .WithRedirectUri($redirectUri)
    .Build()

try {
    # Try to acquire token silently first (from cache)
    $accounts = $app.GetAccountsAsync().GetAwaiter().GetResult()
    if ($accounts.Count -gt 0) {
        $result = $app.AcquireTokenSilent($scopes, $accounts[0]).ExecuteAsync().GetAwaiter().GetResult()
    }
    else {
        # If no cached account, acquire token interactively
        $result = $app.AcquireTokenInteractive($scopes).ExecuteAsync().GetAwaiter().GetResult()
    }

    # Create headers for API calls
    $headers = @{
        "Authorization" = "Bearer $($result.AccessToken)"
        "Content-Type" = "application/json"
    }
}
catch {
    Write-Error "Failed to acquire token: $_"
    exit
}

# Function to get emails with automatic token refresh
function Get-UserEmails {
    param (
        [int]$Top = 10,  # Number of emails to retrieve
        [string]$Filter = "",  # Optional filter
        [string]$OrderBy = "receivedDateTime desc"
    )

    # Check if token needs refresh
    if ($result.ExpiresOn -le [DateTime]::UtcNow) {
        try {
            $result = $app.AcquireTokenSilent($scopes, $accounts[0]).ExecuteAsync().GetAwaiter().GetResult()
            $headers.Authorization = "Bearer $($result.AccessToken)"
        }
        catch {
            Write-Error "Failed to refresh token: $_"
            return
        }
    }

    $baseUrl = "https://graph.microsoft.com/v1.0"
    $endpoint = "/me/messages"
    
    # Build query parameters
    $queryParams = @(
        "`$top=$Top",
        "`$orderby=$OrderBy",
        "`$select=subject,from,receivedDateTime,isRead,importance"  # Optimize by selecting specific fields
    )
    if ($Filter) {
        $queryParams += "`$filter=$Filter"
    }
    
    $uri = "$baseUrl$endpoint`?$($queryParams -join '&')"
    
    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        return $response.value
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 401) {
            # Token expired during call, retry once
            try {
                $result = $app.AcquireTokenSilent($scopes, $accounts[0]).ExecuteAsync().GetAwaiter().GetResult()
                $headers.Authorization = "Bearer $($result.AccessToken)"
                $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
                return $response.value
            }
            catch {
                Write-Error "Failed to refresh token and retry: $_"
            }
        }
        else {
            Write-Error "Error retrieving emails: $_"
            if ($_.ErrorDetails.Message) {
                Write-Error $_.ErrorDetails.Message
            }
        }
    }
}

# Example usage: Get last 5 unread emails
$unreadFilter = "isRead eq false"
$emails = Get-UserEmails -Top 5 -Filter $unreadFilter

# Display emails
foreach ($email in $emails) {
    Write-Host "Subject: $($email.subject)" -ForegroundColor Green
    Write-Host "From: $($email.from.emailAddress.address)"
    Write-Host "Received: $($email.receivedDateTime)"
    Write-Host "Read: $($email.isRead)"
    Write-Host "-" * 50
}
```

## Step 4: Run the Script

1. Open PowerShell
2. Navigate to the directory containing your script
3. Run the script:
```powershell
.\Read-UserMails.ps1
```

4. A browser window will open for authentication
5. Log in with your Microsoft 365 account
6. Grant consent when prompted
7. The script will retrieve and display your emails

## Additional Examples

### Filter for Specific Sender
```powershell
$senderFilter = "from/emailAddress/address eq 'specific@email.com'"
Get-UserEmails -Filter $senderFilter
```

### Get Emails from Last 7 Days
```powershell
$dateFilter = "receivedDateTime ge '" + (Get-Date).AddDays(-7).ToString("yyyy-MM-dd") + "'"
Get-UserEmails -Filter $dateFilter
```

### Get Important Emails
```powershell
$importanceFilter = "importance eq 'high'"
Get-UserEmails -Filter $importanceFilter
```

## Common Issues and Solutions

1. **Authentication Failed**
   - Verify client ID and tenant ID
   - Ensure user has appropriate licenses
   - Check if consent was granted

2. **Permission Issues**
   - Verify Mail.Read permission is added in Azure AD
   - Ensure user has granted consent
   - Check if admin consent is required

3. **Token Expired**
   - Add token refresh logic:
```powershell
if ($msalToken.ExpiresOn <= (Get-Date)) {
    $msalToken = Get-MsalToken -ClientId $clientId -TenantId $tenantId -Interactive -Scopes $scopes
    $headers.Authorization = "Bearer $($msalToken.AccessToken)"
}
```

## Best Practices

1. **Error Handling**
   - Always implement try-catch blocks
   - Log errors appropriately
   - Handle token expiration

2. **Performance**
   - Use appropriate $top values
   - Implement paging for large result sets
   - Use specific filters to reduce data transfer

3. **Security**
   - Never store credentials in code
   - Use secure string for sensitive data
   - Implement proper token management

## Resources

- [Microsoft Graph Mail API Reference](https://docs.microsoft.com/en-us/graph/api/resources/mail-api-overview)
- [MSAL.PS Documentation](https://github.com/AzureAD/MSAL.PS)
- [Graph Explorer](https://developer.microsoft.com/en-us/graph/graph-explorer)
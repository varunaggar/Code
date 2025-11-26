# EWS to Microsoft Graph Migration Guide

## Table of Contents
1. [Background](#background)
   - [Exchange Web Services (EWS)](#exchange-web-services)
   - [Microsoft Graph](#microsoft-graph)
2. [EWS Retirement Information](#ews-retirement-information)
3. [Comparing EWS and Graph](#comparing-ews-and-graph)
4. [Benefits of Microsoft Graph](#benefits-of-microsoft-graph)
5. [Migration Strategy](#migration-strategy)
6. [Feature Comparison](#feature-comparison)
   - [What Stays the Same](#what-stays-the-same)
   - [What Changes](#what-changes)
   - [What's Missing in Graph](#whats-missing-in-graph)
7. [Authentication and Authorization](#authentication-and-authorization)
   - [EWS Impersonation vs. Graph Application Permissions](#ews-impersonation-vs-graph-application-permissions)
8. [Code Samples](#code-samples)
9. [Resources and References](#resources-and-references)

## Background

### Exchange Web Services
Exchange Web Services (EWS) is a legacy SOAP-based API that provides access to Exchange Server and Exchange Online mailbox data. EWS has been the primary API for custom applications to interact with Exchange since Exchange Server 2007.

Key characteristics of EWS:
- SOAP-based protocol
- XML request/response format
- Rich feature set for mailbox operations
- Supports both Exchange Online and On-premises
- Complex but powerful API set

### Microsoft Graph
Microsoft Graph is a unified API endpoint that provides access to data and intelligence across Microsoft 365 services. It's the strategic API platform for Microsoft 365 services.

Key characteristics of Graph:
- REST-based API
- JSON request/response format
- Modern authentication with OAuth 2.0
- Unified endpoint for multiple Microsoft services
- Continuous feature development and improvements

## EWS Retirement Information

Microsoft has announced the retirement of Basic Authentication in Exchange Online and the eventual deprecation of EWS for accessing Exchange Online:

- October 1, 2026: EWS will be retired for Exchange Online
- Applications using EWS will need to migrate to Microsoft Graph
- On-premises Exchange Server deployments can continue using EWS
- Basic Authentication has already been disabled for Exchange Online

## Comparing EWS and Graph

| Feature | EWS | Microsoft Graph |
|---------|-----|----------------|
| Protocol | SOAP | REST |
| Data Format | XML | JSON |
| Authentication | Basic Auth (deprecated), OAuth | OAuth 2.0 |
| SDK Support | EWS Managed API (deprecated) | Multiple SDKs, Graph SDK |
| Service Scope | Exchange only | All Microsoft 365 services |
| Deployment | Online and On-premises | Online primarily |
| Development Experience | Complex but powerful | Modern and streamlined |

## Benefits of Microsoft Graph

1. **Modern Development Experience**
   - RESTful API design
   - JSON data format
   - Modern authentication
   - Extensive SDK support

2. **Unified Access**
   - Single endpoint for multiple services
   - Consistent authentication model
   - Integrated permissions model

3. **Performance and Scalability**
   - Better throttling mechanisms
   - Improved performance
   - Better scaling capabilities

4. **Future-Proof**
   - Active development and updates
   - New features regularly added
   - Strategic Microsoft API platform

5. **Enhanced Security**
   - Modern OAuth 2.0 authentication
   - Granular permissions model
   - Better security controls

## Migration Strategy

### Phase 1: Assessment
1. **Inventory Current Applications**
   - List all applications using EWS
   - Document current EWS features used
   - Identify authentication methods

2. **Feature Analysis**
   - Map EWS features to Graph equivalents
   - Identify gaps and challenges
   - Document required changes

### Phase 2: Planning
1. **Technical Planning**
   - Choose appropriate Graph SDK
   - Plan authentication changes
   - Design new application architecture

2. **Project Planning**
   - Set timeline and milestones
   - Allocate resources
   - Plan testing strategy

### Phase 3: Implementation
1. **Development**
   - Update authentication
   - Implement Graph API calls
   - Handle response format changes

2. **Testing**
   - Unit testing
   - Integration testing
   - Performance testing

### Phase 4: Deployment
1. **Rollout Strategy**
   - Phased deployment
   - Monitoring and logging
   - Fallback plans

## Feature Comparison

### What Stays the Same
1. **Core Functionality**
   - Email operations
   - Calendar management
   - Contact management
   - Basic folder operations

2. **Basic Concepts**
   - Mailbox access
   - Folder hierarchy
   - Message properties
   - Calendar scheduling

### What Changes
1. **API Structure**
   - REST endpoints instead of SOAP
   - JSON instead of XML
   - Different query parameters
   - New pagination model

2. **Authentication**
   - OAuth 2.0 only
   - Different permission model
   - Application and delegated permissions

### What's Missing in Graph
1. **Some Advanced Features**
   - Extended MAPI properties
   - Some complex search operations
   - Certain notification patterns

2. **Specific EWS Operations**
   - Some specialized Exchange operations
   - Certain mailbox configuration settings
   - Some advanced folder permissions

## Authentication and Authorization

### EWS Impersonation vs. Graph Application Permissions

#### EWS Impersonation
EWS impersonation allows an application to impersonate users and perform operations on their behalf:
```powershell
# EWS Impersonation Example
$impersonatedUser = "user@domain.com"
$service.ImpersonatedUserId = New-Object Microsoft.Exchange.WebServices.Data.ImpersonatedUserId(
    [Microsoft.Exchange.WebServices.Data.ConnectingIdType]::SmtpAddress, 
    $impersonatedUser
)
```

#### Graph Application Permissions
Graph uses a different model with Application and Delegated permissions:

1. **Application Permissions**
   - Similar to EWS impersonation
   - Set at the application level
   - Requires admin consent
   - Examples: Mail.ReadWrite.All, Calendars.ReadWrite.All

2. **Delegated Permissions**
   - User signs in explicitly
   - App acts on behalf of signed-in user
   - Examples: Mail.ReadWrite, Calendars.ReadWrite

## Code Samples

### Authentication with MSAL
```powershell
# Install MSAL.PS module if not already installed
Install-Module -Name MSAL.PS -Scope CurrentUser

# App Registration details
$tenantId = "your-tenant-id"
$clientId = "your-client-id"
$clientSecret = "your-client-secret"  # For certificate auth, use certificate instead

# Define required scopes
$scopes = @(
    "https://graph.microsoft.com/.default"  # Use .default for application permissions
)

# Get access token using client credentials (app-only)
$msalParams = @{
    ClientId = $clientId
    TenantId = $tenantId
    ClientSecret = $ConvertTo-SecureString $clientSecret -AsPlainText -Force
    Scopes = $scopes
}
$authResult = Get-MsalToken @msalParams

# Store token for reuse
$token = $authResult.AccessToken
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

# Function to handle Graph API calls
function Invoke-GraphRequest {
    param (
        [string]$Method = "GET",
        [string]$Uri,
        [object]$Body
    )
    
    $params = @{
        Method = $Method
        Uri = "https://graph.microsoft.com/v1.0$Uri"
        Headers = $headers
    }
    
    if ($Body) {
        $params.Body = $Body | ConvertTo-Json -Depth 10
    }
    
    Invoke-RestMethod @params
}
```

### Sending Email with Graph API
```powershell
# Function to send email
function Send-GraphMail {
    param (
        [string]$Subject,
        [string]$Body,
        [string]$ToAddress,
        [string]$FromAddress
    )

    $messageBody = @{
        message = @{
            subject = $Subject
            body = @{
                contentType = "Text"
                content = $Body
            }
            toRecipients = @(
                @{
                    emailAddress = @{
                        address = $ToAddress
                    }
                }
            )
        }
    }

    # If sending from a specific mailbox (requires application permission)
    $uri = if ($FromAddress) {
        "/users/$FromAddress/sendMail"
    } else {
        "/me/sendMail"  # For delegated permissions
    }

    Invoke-GraphRequest -Method "POST" -Uri $uri -Body $messageBody
}

# Example usage
try {
    Send-GraphMail -Subject "Test Subject" `
                  -Body "Test Body" `
                  -ToAddress "recipient@domain.com" `
                  -FromAddress "sender@domain.com"
    Write-Host "Email sent successfully"
} catch {
    Write-Error "Failed to send email: $_"
}
```

### Calendar Operations with Graph API
```powershell
# Function to create calendar event
function New-GraphCalendarEvent {
    param (
        [string]$Subject,
        [datetime]$StartTime,
        [datetime]$EndTime,
        [string]$TimeZone = "UTC",
        [string[]]$Attendees,
        [string]$UserId
    )

    $eventBody = @{
        subject = $Subject
        start = @{
            dateTime = $StartTime.ToString("o")  # ISO 8601 format
            timeZone = $TimeZone
        }
        end = @{
            dateTime = $EndTime.ToString("o")
            timeZone = $TimeZone
        }
        attendees = @(
            foreach ($attendee in $Attendees) {
                @{
                    emailAddress = @{
                        address = $attendee
                    }
                    type = "required"
                }
            }
        )
    }

    # Create event for specific user or self
    $uri = if ($UserId) {
        "/users/$UserId/events"
    } else {
        "/me/events"
    }

    Invoke-GraphRequest -Method "POST" -Uri $uri -Body $eventBody
}

# Example usage
try {
    $eventParams = @{
        Subject = "Important Meeting"
        StartTime = (Get-Date).AddDays(1).AddHours(9)  # Tomorrow 9 AM
        EndTime = (Get-Date).AddDays(1).AddHours(10)   # Tomorrow 10 AM
        TimeZone = "UTC"
        Attendees = @("attendee1@domain.com", "attendee2@domain.com")
        UserId = "organizer@domain.com"
    }
    
    $newEvent = New-GraphCalendarEvent @eventParams
    Write-Host "Event created successfully: $($newEvent.id)"
} catch {
    Write-Error "Failed to create event: $_"
}
```

### Error Handling and Token Refresh
```powershell
# Function to check and refresh token if needed
function Get-ValidToken {
    param (
        [int]$ExpirationBuffer = 300  # 5 minutes buffer
    )
    
    # Check if current token is close to expiration
    if (!$global:authResult -or 
        $global:authResult.ExpiresOn.LocalDateTime.AddSeconds(-$ExpirationBuffer) -le (Get-Date)) {
        
        $global:authResult = Get-MsalToken @msalParams
        $global:headers.Authorization = "Bearer $($global:authResult.AccessToken)"
    }
    
    return $global:headers
}

# Example of function with automatic token refresh
function Get-GraphMailboxSettings {
    param (
        [string]$UserId
    )
    
    try {
        # Ensure token is valid
        $headers = Get-ValidToken
        
        $uri = if ($UserId) {
            "/users/$UserId/mailboxSettings"
        } else {
            "/me/mailboxSettings"
        }
        
        Invoke-GraphRequest -Method "GET" -Uri $uri
    } catch {
        if ($_.Exception.Response.StatusCode -eq 401) {
            Write-Error "Authentication failed. Please check credentials."
        } else {
            Write-Error "Error accessing mailbox settings: $_"
        }
    }
}
```

## Resources and References

1. **Microsoft Documentation**
   - [Microsoft Graph Overview](https://docs.microsoft.com/en-us/graph/overview)
   - [EWS to Graph Migration](https://docs.microsoft.com/en-us/graph/migrate-ews-to-graph)

2. **API References**
   - [Graph API Reference](https://docs.microsoft.com/en-us/graph/api/overview?view=graph-rest-1.0)
   - [EWS API Reference](https://docs.microsoft.com/en-us/exchange/client-developer/web-service-reference/ews-reference-for-exchange)

3. **SDKs and Tools**
   - [Microsoft Graph PowerShell SDK](https://github.com/microsoftgraph/microsoft-graph-powershell)
   - [Graph Explorer](https://developer.microsoft.com/en-us/graph/graph-explorer)

4. **Community Resources**
   - [Microsoft Q&A for Graph](https://docs.microsoft.com/en-us/answers/topics/microsoft-graph.html)
   - [Stack Overflow - microsoft-graph tag](https://stackoverflow.com/questions/tagged/microsoft-graph)
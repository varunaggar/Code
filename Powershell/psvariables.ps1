<#
Untracked local secrets/config placeholders.
Copy this file locally and populate values. This file is ignored by Git.
#>

# Graph (client credentials)
$Graph_TenantId = "<tenant-guid>"
$Graph_ClientId = "<app-client-id>"
$Graph_ClientSecret = "<client-secret>"  # or use cert

# Graph delegated (interactive samples)
$GraphDelegated_AppId = "<public-client-app-id>"
$GraphDelegated_RedirectUri = "http://localhost"

# EWS OAuth samples (per-script)
$OauthEws_ClientId = "<app-client-id>"
$OauthEws_ClientSecret = "<client-secret>"
$OauthEws_RedirectUri = "msal<app-id>://auth"
$OauthEws_TenantId = "<tenant-guid>"
$OauthEws_MailboxName = "<mailbox@domain>"

$WorkingEws_ClientId = "<app-client-id>"
$WorkingEws_ClientSecret = "<client-secret>"
$WorkingEws_RedirectUri = "msal<app-id>://auth"
$WorkingEws_TenantId = "<tenant-guid>"

$Runspaces_ClientId = "<app-client-id>"
$Runspaces_ClientSecret = "<client-secret>"
$Runspaces_RedirectUri = "msal<app-id>://auth"
$Runspaces_TenantId = "<tenant-guid>"

$EwsPermissions_ClientId = "<app-client-id>"
$EwsPermissions_ClientSecret = "<client-secret>"
$EwsPermissions_RedirectUri = "msal<app-id>://auth"
$EwsPermissions_TenantId = "<tenant-guid>"

# Misc
$SqlConnectionString = "<sql-connection-string>"
$GraphEndpoint = "https://graph.microsoft.com/"
$AzureADEndpoint = "https://login.microsoftonline.com/"
$mbxVarun = "varun.aggarwal@uccloud.uk"
$mbxBharati = "bharati.aggarwal@uccloud.uk"
$msalPath = "/Users/varunaggarwal/Documents/Code/Powershell/modules/MSAL/Microsoft.Identity.Client.dll"
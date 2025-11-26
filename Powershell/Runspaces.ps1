# Load untracked secrets/config if present
$varsPath = Join-Path $PSScriptRoot 'psvariables.ps1'
if (Test-Path $varsPath) { . $varsPath } else { Write-Verbose "psvariables.ps1 not found in $PSScriptRoot; ensure required variables are provided via environment or secure vault." }

#test for runspaces

# Load the EWS Managed API
#Add-Type -Path "C:\Program Files\Microsoft\Exchange\Web Services\2.2\Microsoft.Exchange.WebServices.dll"

# Define the service object and set the credentials
$EWSDLL = "/Users/varunaggarwal/Downloads/microsoft.exchange.webservices.2.2.0/lib/40/Microsoft.Exchange.WebServices.dll"
$MSALDLL = "/Users/varunaggarwal/.local/share/powershell/Modules/ExchangeOnlineManagement/3.4.0/netCore/Microsoft.Identity.Client.dll"
Import-Module $EWSDLL
Import-Module $MSALDLL

$ClientId = $Runspaces_ClientId
$MailboxName = $OauthEws_MailboxName
$RedirectUri = $Runspaces_RedirectUri
$ClientSecret = $Runspaces_ClientSecret
$Scope = "https://outlook.office365.com/.default"
$TenantId = $Runspaces_TenantId
$app =  [Microsoft.Identity.Client.ConfidentialClientApplicationBuilder]::Create($ClientId).WithClientSecret($ClientSecret).WithTenantId($TenantId).WithRedirectUri($RedirectUri).Build()
$Scopes = New-Object System.Collections.Generic.List[string]
$Scopes.Add($Scope)
$TokenResult = $app.AcquireTokenForClient($Scopes).ExecuteAsync().Result;

$Mbx = $OauthEws_MailboxName
$SMTP = $OauthEws_MailboxName
$service = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService -ArgumentList ([Microsoft.Exchange.WebServices.Data.ExchangeVersion]::ExchangeOnline)


# Set the URL to the EWS endpoint
$service.Url = new-object Uri("https://outlook.office365.com/EWS/Exchange.asmx")
$Service.Credentials = [Microsoft.Exchange.WebServices.Data.OAuthCredentials]$TokenResult.AccessToken
# Create a property set for the folder properties to retrieve
$propertySet = New-Object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
#$PR_Folder_Path = new-object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(26293, [Microsoft.Exchange.WebServices.Data.MapiPropertyType]::String);
#$PropertySet.Add($PR_Folder_Path)
# Define the SyncFolderHierarchy method parameters
$syncFolderId = [Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::MsgFolderRoot
$syncState = "H4sIAAAAAAAEAK2YfUxbVRiHTzcGwhwTGTAh6oKRbC5ld7TQFg2uLb2y0fHRbmxsoumgjUTWZZdiVhhT9qEhY0iWdMaN4CSbMYbBvpA55kecbAvTZFXEETQTGzeZESuZlsmM3mJM/MPbeX55b3KTpvc+z3vuOfe897yHsTlMPvQNWoNRq8kWjGqzzqhXa41mjdpkNpnVYpZJbzbpREN2ttC4zp5p97or7R6Hx2l2uB2Sl+Xyk+KWmiqntLKKGfjZMqdUW73FzQRzTbXT7Zn571mzTshfniNo1YLBolNr9QaX2rRcb1LnmzQanclg1IiCyHLMdZLdKb3glFY73NUuZ63n/3Ez/RPHWLLcjL9bXlDtlBxS5XPecKtYgnxZkM/M8H12f5JmwqMtPt62yfbDzY4aFfMdfHvgRPvGVbs7T7szultzw3ep7pFPFi+f8iH/ZnnhH9yWxLCFm5rH2Cx+ysJPdTQlpECxnoKoeMZm81OFEGWFKBtElUBUMUQVQZQBobZ/C729SRCVDFFxALV1WxE/Jc+UVChWMUSVQFQpRNmg3lgIUQ/wU4GXHU9C78Z8fqowp+MIFGslNCvToVj3QqNcCFFWiFoNUXaIWgNRayFqPUSVQdQ6fur6In8FP/Wdz7IZmsvY2uY+xqL5qQVQLHndN4efmssfK9rY2A6N19NQrENQb8RCsQ4jlGkKom5D1O8QNQ314f2MRfFTKVAsJEcxFZJFmQrIosGBll/CFFYYzZRX8prvP65OqH9rGC5/P4ZUGmxy+BvT1/RDxVgE6RdH0x77gFr6ZeBA4gJq6Vc7Axteoh0oberXadOXC6BCMMLonzx9pQdoaWTpqQxraRK19L241rPkj9/X2bu3nFr67vbQ54uopb3Wx/MOkUqDTSWlk5/1v0mcUEIxg/0hgTqhjGyYzG0H62PFPt0RKuwDEnjklo7+WeCLB6trRek3K4quDIHFt6L0WuWd/UeppWMFwvUusHRXlAZG7/RtBSt7Ren3ccEdn4CFv6L0xtBiIYt69Mf3xFvywG0DRemPjdFjg8QtdVU0W28EqGfUT22Dadeos9TVc4bepdRrqeO2+leAb1RkafOBrA89xH3qslqjul3gfoiidH1M8aWHwe0SxYHafX7+0rXgboqidM/A5iFgmkZ4fFm6138xMxfci1GUtlhU83TgVo2idN/0G6FnqKVtnoXHuD/Rd3v81oZlyRPU0ldveWcnEEunHh2JUn1M/EpNPfLRJl8PdZKuGl42QptQ5Cy1Tfy1nvcbddfMH3xn7hMidUu99TfzU6mltRttseepv1EXO6TuP4ilU+mLD4uvUbf0wqe1k7epR3/ywk6xmbqll8Z6dj1ELe2qm7WE95X6Z+dOUXrscunPddTS7s7xjApqaU/ZmdBb1KN/K/H18VHqafpiyi6jD9xUVJSeu9rV20ItPXtkRfl+aml/QON/kHrV93ze8JkWFsv+dfwFFACObEcjAAA=" # Use $null for the initial synchronization
$service.ImpersonatedUserId = New-Object Microsoft.Exchange.WebServices.Data.ImpersonatedUserId([Microsoft.Exchange.WebServices.Data.ConnectingIdType]::SmtpAddress,$Mbx)

# Create the folder view object
$folderView = New-Object Microsoft.Exchange.WebServices.Data.FolderView(100)
$folderView.PropertySet = $propertySet
$response=$null
# SyncFolderHierarchy method call
do {
    $response = $service.SyncFolderHierarchy($syncFolderId, $propertySet, $syncState1)
    $syncState2 = $response.SyncState

    # Process the folder changes
    foreach ($change in $response) {
        Write-Host $change.ChangeType
        switch ($change.ChangeType) {
            "Create" {
                Write-Host "Folder Created: $($change.Folder.DisplayName)"
            }
            "Update" {
                Write-Host "Folder Updated: $($change.Folder.DisplayName)"
            }
            "Delete" {
                Write-Host "Folder Deleted: $($change.FolderId.UniqueId)"
            }
        }
    }
} while ($response.MoreChangesAvailable)
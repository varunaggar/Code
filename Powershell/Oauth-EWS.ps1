# Load untracked secrets/config if present
$varsPath = Join-Path $PSScriptRoot 'psvariables.ps1'
if (Test-Path $varsPath) { . $varsPath } else { Write-Verbose "psvariables.ps1 not found in $PSScriptRoot; ensure required variables are provided via environment or secure vault." }

$EWSDLL = "/Users/varunaggarwal/Downloads/microsoft.exchange.webservices.2.2.0/lib/40/Microsoft.Exchange.WebServices.dll"
$MSALDLL = "/Users/varunaggarwal/.local/share/powershell/Modules/ExchangeOnlineManagement/3.4.0/netCore/Microsoft.Identity.Client.dll"
Import-Module $EWSDLL
Import-Module $MSALDLL

$ClientId = $OauthEws_ClientId
$MailboxName = $OauthEws_MailboxName
$RedirectUri = $OauthEws_RedirectUri
$ClientSecret = $OauthEws_ClientSecret
$Scope = "https://outlook.office365.com/.default"
$TenantId = $OauthEws_TenantId
$app =  [Microsoft.Identity.Client.ConfidentialClientApplicationBuilder]::Create($ClientId).WithClientSecret($ClientSecret).WithTenantId($TenantId).WithRedirectUri($RedirectUri).Build()
$Scopes = New-Object System.Collections.Generic.List[string]
$Scopes.Add($Scope)
$TokenResult = $app.AcquireTokenForClient($Scopes).ExecuteAsync().Result;

$Mbx = $OauthEws_MailboxName
$SMTP = $OauthEws_MailboxName
$ExchangeVersion = [Microsoft.Exchange.WebServices.Data.ExchangeVersion]::Exchange2016
$Service = [Microsoft.Exchange.WebServices.Data.ExchangeService]::new()
$Service.Url = "https://outlook.office365.com/EWS/Exchange.asmx"
$Service.Credentials = [Microsoft.Exchange.WebServices.Data.OAuthCredentials]$TokenResult.AccessToken

$SMTP = ‘varun.aggarwal@uccloud.uk’
$service.ImpersonatedUserId = New-Object Microsoft.Exchange.WebServices.Data.ImpersonatedUserId([Microsoft.Exchange.WebServices.Data.ConnectingIdType]::SmtpAddress,$SMTP);

#Get folder Inbox and its subfolders
$InboxFid = new-object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Inbox,$Mbx)
#Define Extended properties
#$PR_FOLDER_TYPE = new-object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(13825,[Microsoft.Exchange.WebServices.Data.MapiPropertyType]::Integer);
$folderidcnt = $InboxFid
#Define the FolderView used for Export should not be any larger then 1000 folders due to throttling
$fvFolderView =  New-Object Microsoft.Exchange.WebServices.Data.FolderView(1000)
#Deep Transval will ensure all folders in the search path are returned
$fvFolderView.Traversal = [Microsoft.Exchange.WebServices.Data.FolderTraversal]::Deep;
$psPropertySet = new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
$PR_Folder_Path = new-object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(26293, [Microsoft.Exchange.WebServices.Data.MapiPropertyType]::String);
#Add Properties to the Property Set
#$psPropertySet.Add($PR_Folder_Path);
$fvFolderView.PropertySet = $psPropertySet;
$sfSearchFilter = new-object Microsoft.Exchange.WebServices.Data.SearchFilter+IsEqualTo($PR_FOLDER_TYPE,"1")

$fiResult = $null
            #loop through folders, when more than 1000
            do {
                $fiResult = $Service.FindFolders($folderidcnt,$sfSearchFilter,$fvFolderView)
                # Add Properties for the Folder Property Set
                $PR_NT_SECURITY_DESCRIPTOR = new-object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(0x0E27, [Microsoft.Exchange.WebServices.Data.MapiPropertyType]::Binary);
                $folderPropset = new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
                $folderPropset.Add([Microsoft.Exchange.WebServices.Data.FolderSchema]::Permissions)
                
                $folderPropset.Add($PR_Folder_Path)

                # Anonymous
                $STANDARDUSER_ANONYMOUS = [Microsoft.Exchange.WebServices.Data.StandardUser]::Anonymous
                # Default
                $STANDARDUSER_DEFAULT = [Microsoft.Exchange.WebServices.Data.StandardUser]::Default

                $objcol = @()

                function ConvertToString($ipInputString){
                    $Val1Text = ""
                    for ($clInt=0;$clInt -lt $ipInputString.length;$clInt++){
                            $Val1Text = $Val1Text + [Convert]::ToString([Convert]::ToChar([Convert]::ToInt32($ipInputString.Substring($clInt,2),16)))
                            $clInt++
                    }
                    return $Val1Text
                }

                #helper function. Thanks to Danijel Klaric
                function BinToHex {
                    param(
                        [Parameter(
                            Position=0,
                            Mandatory=$true,
                            ValueFromPipeline=$true)
                    ]
                    [Byte[]]$Bin)
                    # assume pipeline input if we don't have an array (surely there must be a better way)
                    If ($bin.Length -eq 1) {
                        $bin = @($input)
                    }
                    $return = -join ($Bin | foreach {"{0:X2}" -f $_ })
                    Write-Output $return
                }

                function Get-SID {
                    param (
                        [parameter( Mandatory=$False, Position=0)]
                        [System.String]$Domain=$env:USERDOMAIN,
                        [parameter( Mandatory=$true, Position=1)]
                        [System.String]$User
                    )
                    try {
                        $objUser = New-Object System.Security.Principal.NTAccount("$Domain","$User")
                        [System.Security.Principal.SecurityIdentifier]$sid = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
                        $sid
                    }
                    catch {
                        #create object
                        $returnValue = New-Object -TypeName PSObject
                        #get all properties from last error
                        $ErrorProperties =$Error[0] | Get-Member -MemberType Property
                        #add existing properties to object
                        foreach ($Property in $ErrorProperties){
                            if ($Property.Name -eq 'InvocationInfo'){
                                $returnValue | Add-Member -Type NoteProperty -Name 'InvocationInfo' -Value $($Error[0].InvocationInfo.PositionMessage)
                            }
                            else {
                                $returnValue | Add-Member -Type NoteProperty -Name $($Property.Name) -Value $($Error[0].$($Property.Name))
                            }
                        }
                        #return object
                        $returnValue
                    }
                }

                function Get-UserForSID {
                    param (
                        [parameter( Mandatory=$true, Position=0)]
                        [System.String]$SID
                    )
                    try {
                        $objSID = New-Object System.Security.Principal.SecurityIdentifier("$SID")
                        $objUser = $objSID.Translate( [System.Security.Principal.NTAccount])
                        $objUser.Value
                    }
                    catch {
                        #create object
                        $returnValue = New-Object -TypeName PSObject
                        #get all properties from last error
                        $ErrorProperties =$Error[0] | Get-Member -MemberType Property
                        #add existing properties to object
                        foreach ($Property in $ErrorProperties){
                            if ($Property.Name -eq 'InvocationInfo'){
                                $returnValue | Add-Member -Type NoteProperty -Name 'InvocationInfo' -Value $($Error[0].InvocationInfo.PositionMessage)
                            }
                            else {
                                $returnValue | Add-Member -Type NoteProperty -Name $($Property.Name) -Value $($Error[0].$($Property.Name))
                            }
                        }
                        #return object
                        $returnValue
                    }
                }

                [System.Int32]$i='1'
                ForEach ($Folder in $fiResult) {
                    If (($Folder.Displayname -ne 'System') -and ($Folder.Displayname -ne 'Audits')) {
                        Write-Output "Working on $($Folder.Displayname)"
                        #Load Properties
                        $Folder.Load($folderPropset)
                        #$Folder.ExtendedProperties[0].Value

                        $foldpathval = $null
                        #Try to get the FolderPath Value and then covert it to a usable String
                        If ($Folder.TryGetProperty($PR_Folder_Path,[ref] $foldpathval)) {
                            $binarry = [Text.Encoding]::UTF8.GetBytes($foldpathval)
                            $hexArr = $binarry | ForEach-Object { $_.ToString("X2") }
                            $hexString = $hexArr -join ''
                            #$hexString
                            #$hexString = $hexString.Replace("FEFF", "5C00")
                            $hexString = $hexString.Replace("EFBFBE", "5C")
                            $fpath = ConvertToString($hexString)
                        }

                        ForEach ($Perm in $Folder.Permissions) {
                            $data = new-object PSObject
                            $data | add-member -type NoteProperty -Name Mailbox -Value $MailboxName
                            If ($Perm.UserId.StandardUser -eq $STANDARDUSER_ANONYMOUS){
                                #$data | add-member -type NoteProperty -Name User -Value "Anonymous"
                            }
                            ElseIf($Perm.UserId.StandardUser -eq $STANDARDUSER_DEFAULT){
                                #$data | add-member -type NoteProperty -Name User -Value "Default"
                            }
                            Else {
                                $data | add-member -type NoteProperty -Name User -Value $Perm.UserId.PrimarySmtpAddress
                            }
                            $data | add-member -type NoteProperty -Name Permissions -Value $Perm.DisplayPermissionLevel
                            $data | add-member -type NoteProperty -Name SID -Value $Perm.UserId.SID
                            $data | add-member -type NoteProperty -Name FolderName -Value $Folder.DisplayName
                            $data | add-member -type NoteProperty -Name FolderType -Value $Folder.FolderClass
                            $data | add-member -type NoteProperty -Name CanCreateItems -Value $Perm.CanCreateItems
                            $data | add-member -type NoteProperty -Name CanCreateSubFolders -Value $Perm.CanCreateSubFolders
                            $data | add-member -type NoteProperty -Name IsFolderOwner -Value $Perm.IsFolderOwner
                            $data | add-member -type NoteProperty -Name IsFolderVisible -Value $Perm.IsFolderVisible
                            $data | add-member -type NoteProperty -Name IsFolderContact -Value $Perm.IsFolderContact
                            $data | add-member -type NoteProperty -Name EditItems -Value $Perm.EditItems
                            $data | add-member -type NoteProperty -Name DeleteItems -Value $Perm.DeleteItems
                            $data | add-member -type NoteProperty -Name ReadItems -Value $Perm.ReadItems
                            $data | add-member -type NoteProperty -Name FolderPath -Value $fpath
                            $data | add-member -type NoteProperty -Name EwsID -Value $Folder.ID
                            $data | add-member -type NoteProperty -Name StoreID -Value ($service.ConvertId($alternateID,'StoreID')).UniqueId
                            $data | add-member -type NoteProperty -Name HexEntryID -Value ($service.ConvertId($alternateID,'HexEntryId')).UniqueId
                            $objcol += $data
                        }
                        }
                    }

            }
            
            while($fiResult.MoreAvailable -eq $true)



        




$rootFolderId = new-object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::MsgFolderRoot,$Mbx)
#Define Extended properties
#$PR_FOLDER_TYPE = new-object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(13825,[Microsoft.Exchange.WebServices.Data.MapiPropertyType]::Integer);
$folderidcnt = $rootFolderId
#Define the FolderView used for Export should not be any larger then 1000 folders due to throttling
$fvFolderView =  New-Object Microsoft.Exchange.WebServices.Data.FolderView(1000)
#Deep Transval will ensure all folders in the search path are returned
$fvFolderView.Traversal = [Microsoft.Exchange.WebServices.Data.FolderTraversal]::Deep;
$psPropertySet = new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
#$PR_Folder_Path = new-object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(26293, [Microsoft.Exchange.WebServices.Data.MapiPropertyType]::String);
#Add Properties to the Property Set
#$psPropertySet.Add($PR_Folder_Path);
$fvFolderView.PropertySet = $psPropertySet;
$sfSearchFilter = new-object Microsoft.Exchange.WebServices.Data.SearchFilter+IsEqualTo($PR_FOLDER_TYPE,"1")
$fiResult = $null
$fiResult = $Service.FindFolders($folderidcnt,$sfSearchFilter,$fvFolderView)







$ConnectToMailboxRootFolders = New-Object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.Webservices.Data.WellKnownFolderName]::MsgFolderRoot,$SMTP)
$EWSParentFolder = [Microsoft.Exchange.WebServices.Data.Folder]::Bind($service,$ConnectToMailboxRootFolders)
$FolderView = New-Object Microsoft.Exchange.WebServices.Data.FolderView(100)
$FolderView.Traversal = [Microsoft.Exchange.WebServices.Data.FolderTraversal]::Deep
#Uncomment the line below if you want to search for a specific folder name. Load $FolderName Variable with the name you are looking for.
#$SearchFilter = New-Object Microsoft.Exchange.WebServices.Data.SearchFilter+IsEqualTo([Microsoft.Exchange.WebServices.Data.FolderSchema]::Name,$FolderName)
$MailboxFolderList = @($EWSParentFolder.FindFolders($FolderView))
$MailboxFolderList | Select DisplayName,FolderClass,ChildFolderCount,TotalCount,UnreadCount,ID 

$SearchFilter = New-Object Microsoft.Exchange.WebServices.Data.SearchFilter+IsEqualTo([Microsoft.Exchange.WebServices.Data.FolderSchema]::Id,"AQMkAGI0ODc4NzcAMC1hMjM2LTRmYzktOGUxMy0wYzdmYjliODA1MDIALgAAA1PRFTPudDRPsJBiUujqnmwBAJWaqMWxnFtKhKK0biaujjoAAAIBVQAAAA==")
$MailboxFolderList = $EWSParentFolder.FindFolders($SearchFilter)

$folderPropset = new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
$folderPropset.Add([Microsoft.Exchange.WebServices.Data.FolderSchema]::Permissions)

foreach($Permission in $MailboxFolderList.Permissions){  
    if($null -eq $Permission.UserId.StandardUser){  
        "User : " + $Permission.UserId.PrimarySmtpAddress  
    }  
    else{  
        "User : " + $Permission.UserId.StandardUser.ToString()  
    }  
    $Permission  
}  









 
# Check EWS connection
$Service.Url = "https://outlook.office365.com/EWS/Exchange.asmx"
$RootFolder="MsgFolderRoot"
$rootFolderId = new-object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::$RootFolder,$MailboxName)
#Define Extended properties
$PR_FOLDER_TYPE = new-object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(13825,[Microsoft.Exchange.WebServices.Data.MapiPropertyType]::Integer);
$folderidcnt = $rootFolderId
#Define the FolderView used for Export should not be any larger then 1000 folders due to throttling
$fvFolderView =  New-Object Microsoft.Exchange.WebServices.Data.FolderView(1000)
#Deep Transval will ensure all folders in the search path are returned
$fvFolderView.Traversal = [Microsoft.Exchange.WebServices.Data.FolderTraversal]::Deep;
$psPropertySet = new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
$PR_Folder_Path = new-object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(26293, [Microsoft.Exchange.WebServices.Data.MapiPropertyType]::String);
#Add Properties to the Property Set
$psPropertySet.Add($PR_Folder_Path);
$fvFolderView.PropertySet = $psPropertySet;

$fiResult = $Service.FindFolders($folderidcnt,$sfSearchFilter,$fvFolderView)
# Add Properties for the Folder Property Set
$PR_NT_SECURITY_DESCRIPTOR = new-object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(0x0E27, [Microsoft.Exchange.WebServices.Data.MapiPropertyType]::Binary);
$folderPropset = new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)
$folderPropset.Add([Microsoft.Exchange.WebServices.Data.FolderSchema]::Permissions)
$folderPropset.Add($PR_Folder_Path)
$objcol = @()

function ConvertToString($ipInputString){
    $Val1Text = ""
    for ($clInt=0;$clInt -lt $ipInputString.length;$clInt++){
            $Val1Text = $Val1Text + [Convert]::ToString([Convert]::ToChar([Convert]::ToInt32($ipInputString.Substring($clInt,2),16)))
            $clInt++
    }
    return $Val1Text
}

[System.Int32]$i='1'
                ForEach ($Folder in $fiResult) {
                    Write-Progress `
                            -id $ProgressID `
                            -ParentId 1 `
                            -Activity "Processing mailbox - $($MailboxName) with $($fiResult.Folders.count) folders" `
                            -PercentComplete ( $i / $fiResult.Folders.count * 100) `
                            -Status "Remaining: $($fiResult.Folders.count - $i) processing folder: $($Folder.DisplayName)"
                    If (($Folder.Displayname -ne 'System') -and ($Folder.Displayname -ne 'Audits')) {
                        #Write-Output "Working on $($Folder.Displayname)"
                        #Load Properties
                        $Folder.Load($folderPropset)
                        #$Folder.ExtendedProperties[0].Value

                        $foldpathval = $null
                        #Try to get the FolderPath Value and then covert it to a usable String
                        If ($Folder.TryGetProperty($PR_Folder_Path,[ref] $foldpathval)) {
                            $binarry = [Text.Encoding]::UTF8.GetBytes($foldpathval)
                            $hexArr = $binarry | ForEach-Object { $_.ToString("X2") }
                            $hexString = $hexArr -join ''
                            #$hexString
                            #$hexString = $hexString.Replace("FEFF", "5C00")
                            $hexString = $hexString.Replace("EFBFBE", "5C")
                            $fpath = ConvertToString($hexString)
                        }








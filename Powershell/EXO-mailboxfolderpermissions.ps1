# Connect to Exchange Online PowerShell
Connect-ExchangeOnline

# Define an ArrayList to store mailbox permissions
$mailboxPermData = New-Object System.Collections.ArrayList

# Prompt the user for input
$choice = Read-Host "Do you want to get all mailboxes (A) or provide a list of email addresses (L)? (A/L)"

# Check the user's choice
switch ($choice.ToUpper()) {
    'A' {
        # Get all mailboxes in the Exchange Online tenant
        $mailboxes = Get-Mailbox -ResultSize Unlimited
    }
    'L' {
        # Prompt the user to provide a list of email addresses
        $emailAddresses = Read-Host "Enter the list of email addresses separated by commas"
        $emailList = $emailAddresses -split "," | ForEach-Object { $_.Trim() } # Trim any leading/trailing spaces
        
        # Initialize an array to store mailbox objects
        $mailboxes = @()
        
        # Fetch mailboxes corresponding to each email address
        foreach ($email in $emailList) {
            $mailbox = Get-Mailbox -Identity $email -ErrorAction SilentlyContinue
            if ($mailbox) {
                $mailboxes += $mailbox
            } else {
                Write-Warning "Mailbox with email address '$email' not found."
            }
        }
    }
    Default {
        Write-Host "Invalid choice. Exiting script."
        return
    }
}

# Define mailboxes excluded from permissions check
$excludedMailboxes = @(
    "DiscoverySearchMailbox{D919BA05-46A6-415f-80AD-7E09334BB852}@tenant.onmicrosoft.com",
    "mailbox@domain.com"
)

# Define excluded folders
# "\Foldername" excludes the specified folder but subfolders are not excluded.
# "\Foldername*" excludes the specified folder and subfolders.
# "\Foldername\*" excludes only subfolders.
$excludedFolders = @(
    "\Top of Information Store*",
    "\Archive*",
    "\Audits*",
    "\Calendar\*",
    "\Calendar Logging",
    "\Clutter",
    "\Contacts\*",
    "\Conversation Action Settings*",
    "\Conversation History*",
    "\Deleted Items\*",
    "\Deletions*",
    "\DiscoveryHolds*",
    "\Drafts\*",
    "\EventCheckPoints*",
    "\ExternalContacts*",
    "\Files*",
    "\Journal*",
    "\NFS\NFS Archive\*",
    "\PersonMetadata*",
    "\Purges*",
    "\Quick Step Settings*",
    "\Recoverable Items*",
    "\RSS Feeds*",
    "\Social Activity Notifications*",
    "\SubstrateHolds*",
    "\Sync Issues*",
    "\Tasks\*",
    "\Versions*",
    "\WebExtAddIns*",
    "\Yammer Root*"
)

# Iterate through each mailbox
foreach ($mailbox in $mailboxes) {

    #Get mailbox's email address
    $mailboxEmail = $mailbox.PrimarySmtpAddress
    Write-Host "Processing mailbox: $mailboxEmail"
    
    # Skip excluded mailbox as defined in the $excludedMailboxes array
    if ($excludedMailboxes -contains $mailboxEmail) {
        Write-Host "     Excluded"
        continue
    }

    # Get mailbox permissions for the current mailbox
    $mailboxPerm = Get-MailboxPermission -Identity $mailboxEmail | Where-Object { $_.User -ne "NT AUTHORITY\SELF" }
    
    # Iterate through each permission entry
    foreach ($perm in $mailboxPerm) {

        # Retrieve user email address if the user exists
        $userEmail = if ($perm.User -ne "Default" -and $perm.User -ne "Anonymous") { (Get-Recipient -Identity $perm.User -ErrorAction SilentlyContinue).PrimarySmtpAddress }

        # Export mailbox permissions
        $mailboxPermData.Add([PSCustomObject]@{
            Mailbox          = $mailboxEmail
            Path             = "\"
            ObjectType       = "Mailbox"
            UserDisplayName  = $perm.User
            UserEmailAddress = $userEmail
            UserAccessRights = $perm.AccessRights
        }) | Out-Null
    }

    # Get folder statistics for the mailbox
    $folderStats = Get-MailboxFolderStatistics -Identity $mailboxEmail

    # Iterate through each folder in the mailbox
    foreach ($folder in $folderStats) {

        # Reformat path names
        $folderPath = $folder.FolderPath.Replace('/', '\')
        Write-Host "          Processing folder: $folderPath"

        # Check if the folder is excluded as defined in the $excludedFolders array
        $excludeFolder = $false
        foreach ($excludedFolder in $excludedFolders) {
            if ($folderPath -like $excludedFolder) {
                $excludeFolder = $true
                Write-Host "               Excluded"
                break
            }
        }

        # Get folder permissions
        if (-not $excludeFolder) {
            $folderPermUsers = Get-MailboxFolderPermission -Identity ($mailboxEmail + ":" + $folderPath) | Select-Object Identity, User, AccessRights
        
            # Iterate through each permission entry
            foreach ($entryUser in $folderPermUsers) {

                # Retrieve user email address if the user exists
                $userEmail = if ($entryUser.User -ne "Default" -and $entryUser.User -ne "Anonymous") { (Get-Recipient -Identity $entryUser.User -ErrorAction SilentlyContinue).PrimarySmtpAddress }

                # Store folder permissions in the array
                $mailboxPermData.Add([PSCustomObject]@{
                    Mailbox          = $mailboxEmail
                    Path             = $folderPath
                    ObjectType       = "Folder"
                    UserDisplayName  = $entryUser.User
                    UserEmailAddress = $userEmail
                    UserAccessRights = $entryUser.AccessRights
                }) | Out-Null
            }
        }
    }
}


# Organize aggregated permissions by mailbox and export to separate CSV files
$mailboxesData = $mailboxPermData | Group-Object -Property Mailbox
foreach ($mailboxData in $mailboxesData) {
    $mailboxEmail = $mailboxData.Name
    if ($mailboxData.Group.Count -gt 0) {
        $mailboxData.Group | Export-Csv -Path "$mailboxEmail - Mailbox Sharing Permissions.csv" -NoTypeInformation
    }
}

# Organize aggregated permissions by user email and export to separate CSV files
$usersData = $mailboxPermData | Group-Object -Property UserEmailAddress
foreach ($userData in $usersData) {
    $userEmail = $userData.Name
    if (-not [string]::IsNullOrWhiteSpace($userEmail) -and $userData.Group.Count -gt 0) {
        $userData.Group | Export-Csv -Path "$userEmail - Mailbox Access Permissions.csv" -NoTypeInformation
    }
}

# Disconnect from Exchange Online PowerShell
Disconnect-ExchangeOnline -Confirm:$false
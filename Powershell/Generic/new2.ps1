# Import the necessary modules
#Import-Module ExchangeOnlineManagement

# Define the mailboxes
$mailboxes = @(get-mailbox)

# Define the folder to check permissions for (e.g., Inbox)
$folder = "Inbox"

# Function to get mailbox folder permissions
function Get-MailboxFolderPermissionsConcurrently {
    param (
        [string]$Mailbox,
        [string]$Folder
    )
    # Connect to Exchange Online (assumes you have a valid session, customize as necessary)
   # $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential (Get-Credential) -Authentication Basic -AllowRedirection
    #Import-PSSession $Session -DisableNameChecking
    
    # Get the folder permissions
    $permissions = Get-MailboxFolderPermission -Identity "$Mailbox`:\$Folder"
    
    # Return the results
    return $permissions
}

# Create the runspace pool
$runspacePool = [runspacefactory]::CreateRunspacePool(1, [int]$mailboxes.Count)
$runspacePool.Open()

# Create a collection to hold the runspaces
$runspaces = @()

foreach ($mailbox in $mailboxes) {
    $runspace = [powershell]::Create().AddScript({
        param ($mailbox, $folder)
        Get-MailboxFolderPermissionsConcurrently -Mailbox $mailbox -Folder $folder
    }).AddArgument($mailbox).AddArgument($folder)
    
    $runspace.RunspacePool = $runspacePool
    $runspaces += [pscustomobject]@{ Pipeline = $runspace; Status = $runspace.BeginInvoke() }
}

# Wait for all runspaces to complete and collect results
$results = @()
foreach ($runspace in $runspaces) {
    $runspace.Pipeline.EndInvoke($runspace.Status)
    $results += $runspace.Pipeline.Output
}

# Close the runspace pool
$runspacePool.Close()
$runspacePool.Dispose()

# Display the results
$results

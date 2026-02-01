#!/usr/bin/env pwsh
<#+
.SYNOPSIS
    Retrieve mailbox folder permissions using Microsoft Graph.
.DESCRIPTION
    Accepts input via pipeline or CSV and retrieves mail folder permissions in parallel.
    Uses the Common module (Connect-Service, Write-FastLog) for auth/logging.

    CSV columns supported:
      - Mailbox (or UserPrincipalName/UPN)
      - Folder (optional; defaults to Inbox)
.PARAMETER Mailbox
    Mailbox UPN or user ID. Accepts pipeline input.
.PARAMETER Folder
    Mail folder name or path. Examples: Inbox, Calendar, Inbox/Reports.
.PARAMETER CsvPath
    CSV file path with Mailbox and Folder columns.
.PARAMETER ConfigPath
    Path to Custom-Config.xml used by Connect-Service.
.PARAMETER ModulePath
    Path to the Common module (Modules/Common).
.PARAMETER ThrottleLimit
    Parallel throttle limit for ForEach-Object -Parallel.
#>

function Get-GraphMailboxFolderPermission {
    [CmdletBinding(DefaultParameterSetName = 'Pipeline')]
    param (
        [Parameter(ParameterSetName = 'Pipeline', ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$Mailbox,

        [Parameter(ParameterSetName = 'Pipeline', ValueFromPipelineByPropertyName = $true)]
        [string]$Folder = 'Inbox',

        [Parameter(ParameterSetName = 'Csv', Mandatory = $true)]
        [string]$CsvPath,

        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) "Template/Custom-Config.xml"),

        [Parameter(Mandatory = $false)]
        [string]$ModulePath = (Join-Path (Split-Path $PSScriptRoot -Parent) "Modules/Common"),

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 128)]
        [int]$ThrottleLimit = 5
    )

    begin {
        $items = @()
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Pipeline') {
            if (-not [string]::IsNullOrWhiteSpace($Mailbox)) {
                $items += [PSCustomObject]@{
                    Mailbox = $Mailbox
                    Folder  = $Folder
                }
            }
        }
    }

    end {
        if ($PSCmdlet.ParameterSetName -eq 'Csv') {
            if (-not (Test-Path $CsvPath)) {
                throw "CSV file not found: $CsvPath"
            }
            $items = Import-Csv -Path $CsvPath
        }

        if (-not $items -or $items.Count -eq 0) {
            Write-Warning "No input provided. Supply pipeline input or use -CsvPath."
            return
        }

        $items | ForEach-Object -Parallel {
            param($item, $modulePath, $configPath)

            function Resolve-FolderId {
                param(
                    [string]$Mailbox,
                    [string]$Folder
                )

                $wellKnown = @('inbox','calendar','sentitems','drafts','deleteditems','archive','junkemail')
                $normalized = $Folder.Trim()
                $normalizedLower = $normalized.ToLower()

                if ($wellKnown -contains $normalizedLower) {
                    return $normalizedLower
                }

                if ($normalizedLower.StartsWith('id:')) {
                    return $normalized.Substring(3)
                }

                $segments = $normalized -split '[\\/]'
                $currentId = $null

                foreach ($seg in $segments) {
                    if (-not $currentId) {
                        $uri = "https://graph.microsoft.com/v1.0/users/$Mailbox/mailFolders?`$filter=displayName eq '$seg'&`$select=id,displayName"
                    } else {
                        $uri = "https://graph.microsoft.com/v1.0/users/$Mailbox/mailFolders/$currentId/childFolders?`$filter=displayName eq '$seg'&`$select=id,displayName"
                    }

                    $resp = Invoke-MgGraphRequest -Method GET -Uri $uri
                    $match = $resp.value | Select-Object -First 1

                    if (-not $match) {
                        throw "Folder not found: $Folder (segment '$seg')"
                    }

                    $currentId = $match.id
                }

                return $currentId
            }

            try {
                Import-Module $modulePath -Force -ErrorAction Stop

                if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
                    Connect-Service -ConfigPath $configPath
                }

                $mailbox = $item.Mailbox
                if (-not $mailbox) { $mailbox = $item.UserPrincipalName }
                if (-not $mailbox) { $mailbox = $item.UPN }
                if (-not $mailbox) { throw "Mailbox is required (Mailbox/UserPrincipalName/UPN)." }

                $folder = if ($item.Folder) { $item.Folder } else { 'Inbox' }
                $folderId = Resolve-FolderId -Mailbox $mailbox -Folder $folder

                $uri = "https://graph.microsoft.com/v1.0/users/$mailbox/mailFolders/$folderId/permissions"
                $permResp = Invoke-MgGraphRequest -Method GET -Uri $uri

                foreach ($perm in $permResp.value) {
                    [PSCustomObject]@{
                        Mailbox         = $mailbox
                        Folder          = $folder
                        PermissionId    = $perm.id
                        GranteeType     = $perm.grantedTo?.user?.'@odata.type'
                        Grantee         = $perm.grantedTo?.user?.displayName
                        GranteeUPN      = $perm.grantedTo?.user?.emailAddress
                        Roles           = ($perm.roles -join ',')
                    }
                }
            }
            catch {
                Write-FastLog -Message "Failed for mailbox '$($item.Mailbox)': $($_.Exception.Message)" -Level 'ERROR' -Context 'GraphPerms'
            }
        } -ThrottleLimit $ThrottleLimit -ArgumentList $ModulePath, $ConfigPath
    }
}

# Example usage:
# Get-GraphMailboxFolderPermission -CsvPath "./mailboxes.csv" -ThrottleLimit 10
# "user@contoso.com" | Get-GraphMailboxFolderPermission -Folder "Inbox"

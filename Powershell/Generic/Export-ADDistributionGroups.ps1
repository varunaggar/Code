<#
.SYNOPSIS
  Export distribution groups from a specific OU (or search base) with key attributes and member counts.

.DESCRIPTION
  Queries Active Directory for distribution groups located under the provided SearchBase distinguished name.
  Captures commonly useful attributes plus any additional ones requested, counts group members (optionally
  including nested members), and writes the results to a CSV file.

.PARAMETER SearchBase
  Distinguished name of the OU (or any AD container) to use as the search base, e.g. "OU=Mail,DC=contoso,DC=com".

.PARAMETER OutputCsv
  Destination CSV path. Defaults to ./DistributionGroups.csv (relative paths are resolved from the current directory).

.PARAMETER AdditionalProperties
  AD group attributes to include beyond the defaults (DisplayName, Mail, ManagedBy, Description, GroupScope, MailEnabled).

.PARAMETER IncludeNested
  When specified, counts nested members using Get-ADGroupMember -Recursive. Otherwise counts only direct members using the "member" attribute.

.EXAMPLE
  ./Export-ADDistributionGroups.ps1 -SearchBase "OU=Mail,DC=contoso,DC=com" -OutputCsv ./mail-groups.csv

.EXAMPLE
  ./Export-ADDistributionGroups.ps1 -SearchBase "OU=Mail,DC=contoso,DC=com" -IncludeNested -AdditionalProperties department,info

.NOTES
  Requires the ActiveDirectory module (RSAT) and appropriate permissions.
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$SearchBase,

  [string]$OutputCsv = './DistributionGroups.csv',

  [string[]]$AdditionalProperties = @(),

  [switch]$IncludeNested,

  [switch]$VerboseLogging
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Write-LogInfo {
  param(
    [string]$Message
  )
  if ($VerboseLogging) {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
  }
}

# Ensure ActiveDirectory module is available.
if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
  throw 'ActiveDirectory module not found. Install RSAT (or use a domain controller) before running this script.'
}
Import-Module ActiveDirectory -ErrorAction Stop | Out-Null

Write-LogInfo "Searching for distribution groups under: $SearchBase"

$defaultProps = @(
  'SamAccountName',
  'Name',
  'DisplayName',
  'Mail',
  'MailEnabled',
  'ManagedBy',
  'Description',
  'GroupScope',
  'member'
)

$allProps = ($defaultProps + $AdditionalProperties) | Sort-Object -Unique

 $groups = Get-ADGroup -SearchBase $SearchBase -Filter "GroupCategory -eq 'Distribution'" -Properties $allProps |
   Where-Object { $_.Name -notmatch '(-mra|-mas|-mfc)$' }

Write-LogInfo "Found $($groups.Count) distribution groups. Processing..."

$result = foreach ($group in $groups) {
  $memberCount = 0
  if ($IncludeNested) {
    try {
      $memberCount = (Get-ADGroupMember -Identity $group.DistinguishedName -Recursive).Count
    } catch {
      Write-Warning "Failed to expand members for $($group.DistinguishedName): $($_.Exception.Message)"
      $memberCount = -1
    }
  } else {
    $memberList = @($group.member)
    $memberCount = $memberList.Count
  }

  $obj = [ordered]@{
    SamAccountName     = $group.SamAccountName
    Name               = $group.Name
    DisplayName        = $group.DisplayName
    Mail               = $group.Mail
    MailEnabled        = $group.MailEnabled
    GroupScope         = $group.GroupScope
    ManagedBy          = $group.ManagedBy
    Description        = $group.Description
    MemberCount        = $memberCount
    DistinguishedName  = $group.DistinguishedName
  }

  foreach ($prop in $AdditionalProperties) {
    if (-not $obj.Contains($prop)) {
      $obj[$prop] = $group.$prop
    }
  }

  [PSCustomObject]$obj
}

if (-not $result) {
  Write-LogInfo 'No groups matched the filter. Producing empty CSV (headers only).'
}

Write-LogInfo "Writing CSV: $OutputCsv"
$result | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
Write-LogInfo 'Done.'

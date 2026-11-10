[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [ValidateRange(1, 1000)]
    [int]$Count = 1000,

    [Parameter()]
    [ValidateRange(1, 999999)]
    [int]$StartNumber = 1,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Domain = 'x7m2c.onmicrosoft.com',

    [Parameter()]
    [ValidateRange(0, 60000)]
    [int]$DelayMilliseconds = 250,

    [Parameter()]
    [switch]$Execute
)

$firstWords = @(
    'Amber', 'Arctic', 'Bright', 'Calm', 'Cedar', 'Clear', 'Clever', 'Cosmic',
    'Crimson', 'Daring', 'Elegant', 'Fabled', 'Golden', 'Grand', 'Hidden', 'Ivory',
    'Jovial', 'Kind', 'Lively', 'Lucky', 'Mystic', 'Noble', 'Quiet', 'Rapid',
    'Silver', 'Sunny', 'Swift', 'Vivid', 'Warm', 'Witty', 'Zealous', 'Gentle'
)

$secondWords = @(
    'Aster', 'Badger', 'Beacon', 'Birch', 'Brook', 'Canyon', 'Comet', 'Coral',
    'Cypress', 'Delta', 'Ember', 'Falcon', 'Forest', 'Glacier', 'Harbor', 'Island',
    'Juniper', 'Kestrel', 'Lantern', 'Meadow', 'Meteor', 'Orchard', 'Pebble', 'Prairie',
    'Quartz', 'River', 'Summit', 'Timber', 'Valley', 'Willow', 'Zephyr', 'Zenith'
)

if (($StartNumber + $Count - 1) -gt 999999) {
    throw 'The requested alias range exceeds six digits.'
}

if ($Count -gt ($firstWords.Count * $secondWords.Count)) {
    throw 'The word lists do not contain enough unique combinations for this count.'
}

$wordPairs = @(
    foreach ($firstWord in $firstWords) {
        foreach ($secondWord in $secondWords) {
            [pscustomobject]@{
                First  = $firstWord
                Second = $secondWord
            }
        }
    }
)
$selectedPairs = @(Get-Random -InputObject $wordPairs -Count $Count)
$mailboxPlan = @(
    for ($index = 0; $index -lt $Count; $index++) {
        $displayName = "SH-$($selectedPairs[$index].First)-$($selectedPairs[$index].Second)"
        $sequenceNumber = $StartNumber + $index

        [pscustomobject]@{
            DisplayName        = $displayName
            Alias              = 'SH{0:D6}' -f $sequenceNumber
            PrimarySmtpAddress = "$displayName@$Domain"
        }
    }
)

if (-not $Execute) {
    Write-Information 'Preview only. Pass -Execute to create these shared mailboxes.' -InformationAction Continue
    $mailboxPlan
    return
}

if (-not (Get-Command New-Mailbox -ErrorAction SilentlyContinue)) {
    throw 'New-Mailbox is unavailable. Install/import ExchangeOnlineManagement and connect with Connect-ExchangeOnline first.'
}

$target = "$Count shared mailboxes at $Domain, aliases SH$('{0:D6}' -f $StartNumber) through SH$('{0:D6}' -f ($StartNumber + $Count - 1))"
if (-not $PSCmdlet.ShouldProcess($target, 'Create shared mailboxes')) {
    return
}

$results = [System.Collections.Generic.List[object]]::new()
for ($index = 0; $index -lt $mailboxPlan.Count; $index++) {
    $mailbox = $mailboxPlan[$index]
    try {
        New-Mailbox `
            -Shared `
            -Name $mailbox.DisplayName `
            -DisplayName $mailbox.DisplayName `
            -Alias $mailbox.Alias `
            -PrimarySmtpAddress $mailbox.PrimarySmtpAddress `
            -Confirm:$false `
            -ErrorAction Stop | Out-Null

        $results.Add([pscustomobject]@{
            DisplayName        = $mailbox.DisplayName
            Alias              = $mailbox.Alias
            PrimarySmtpAddress = $mailbox.PrimarySmtpAddress
            Status             = 'Created'
            Error              = $null
        })
    }
    catch {
        $results.Add([pscustomobject]@{
            DisplayName        = $mailbox.DisplayName
            Alias              = $mailbox.Alias
            PrimarySmtpAddress = $mailbox.PrimarySmtpAddress
            Status             = 'Failed'
            Error              = $_.Exception.Message
        })
        Write-Warning "Failed to create $($mailbox.PrimarySmtpAddress): $($_.Exception.Message)"
    }

    if ($DelayMilliseconds -gt 0 -and $index -lt ($mailboxPlan.Count - 1)) {
        Start-Sleep -Milliseconds $DelayMilliseconds
    }
}

$results
$createdCount = @($results | Where-Object Status -eq 'Created').Count
$failedCount = $results.Count - $createdCount
Write-Information "Completed. Created: $createdCount; failed: $failedCount." -InformationAction Continue
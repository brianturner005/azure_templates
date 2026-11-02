<#
.SYNOPSIS
    Lab only. Finishes the parts of the quickstart's setup that never ran because its
    MECM upgrade stage failed: distribution point, management point, and client install.

.DESCRIPTION
    Runs the quickstart's own install scripts (already on the site server) in order:
      1. InstallDP.ps1      - distribution point on <prefix>dpmp01
      2. InstallMP.ps1      - management point on <prefix>dpmp01
      3. InstallClient.ps1  - AD discovery, boundary group, client push to <prefix>cl01
    Run on the site server in Windows PowerShell 5.1 as Administrator.
    Takes about 15-30 minutes. Progress logs: C:\Windows\Temp\ProvisionScript\*log.txt
#>
[CmdletBinding()]
param(
    [string]$Prefix = 'cmlab',
    [string]$Domain = 'contoso.com',
    [string]$AdminUser = 'labadmin'
)
$ErrorActionPreference = 'Continue'

$tools  = 'C:\Windows\Temp\ProvisionScript'
$role   = 'PS1'
$dpmp   = "$($Prefix)dpmp01"
$client = "$($Prefix)cl01"
$cmUser = "$($Domain.Split('.')[0])\$AdminUser"

foreach ($f in 'InstallDP.ps1', 'InstallMP.ps1', 'InstallClient.ps1') {
    if (-not (Test-Path (Join-Path $tools $f))) { throw "$f not found in $tools." }
}

$here = Get-Location
try {
    Write-Host "1/3 Installing distribution point on $dpmp ..." -ForegroundColor Cyan
    & (Join-Path $tools 'InstallDP.ps1') $Domain $dpmp $role $tools

    Write-Host "2/3 Installing management point on $dpmp ..." -ForegroundColor Cyan
    & (Join-Path $tools 'InstallMP.ps1') $Domain $dpmp $role $tools

    Write-Host "3/3 Discovering and pushing the client to $client (the slowest part) ..." -ForegroundColor Cyan
    & (Join-Path $tools 'InstallClient.ps1') $Domain $cmUser $client $dpmp $role $tools
}
finally {
    Set-Location $here
}

Write-Host ""
(Get-Content (Join-Path $tools "$role.json") | ConvertFrom-Json).PSObject.Properties |
    ForEach-Object { "{0,-22} {1}" -f $_.Name, $_.Value.Status }
Write-Host ""
Write-Host "The client push is now queued. The client finishes installing on $client over the next 10-15 minutes." -ForegroundColor Yellow
Write-Host "Then run .\Deploy-LabTaskSequence.ps1"

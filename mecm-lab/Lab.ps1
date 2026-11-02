<#
.SYNOPSIS
    One helper for the MECM Azure lab. Run it from your own PC, in this folder.

.DESCRIPTION
    Needs the Azure CLI, signed in with "az login". Works in Windows PowerShell 5.1 or 7.

      .\Lab.ps1 check      Are the VM sizes available, with enough vCPU quota, in the region?
      .\Lab.ps1 deploy     Create the resource group and deploy the lab (asks for a password)
      .\Lab.ps1 status     Show setup progress on the site server
      .\Lab.ps1 rdp        Open Remote Desktop to a VM (default ps01; -Vm cl01 for the client)
      .\Lab.ps1 copy       Copy files onto a VM (-Path file1,file2; lands in C:\Lab)
      .\Lab.ps1 client     Install the MECM client on cl01 directly, if the client push didn't land
      .\Lab.ps1 start      Start the lab (domain controller first)
      .\Lab.ps1 stop       Stop (deallocate) every VM so compute billing stops
      .\Lab.ps1 updateip   Re-point the RDP rule at your current public IP
      .\Lab.ps1 delete     Delete the whole lab (asks you to confirm)

.EXAMPLE
    .\Lab.ps1 check -Location eastus2
.EXAMPLE
    .\Lab.ps1 copy -Path .\Complete-LabSetup.ps1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('check', 'deploy', 'status', 'rdp', 'copy', 'client', 'start', 'stop', 'updateip', 'delete')]
    [string]$Action,

    [string]$ResourceGroup = 'rg-mecm-lab',
    [string]$Location = 'eastus',
    [string]$Vm = 'ps01',
    [string[]]$Path,
    [string]$Destination = 'C:\Lab',
    [string]$SiteCode = 'PS1'
)

$ErrorActionPreference = 'Stop'
$paramFile = Join-Path $PSScriptRoot 'main.bicepparam'

# ---- helpers ---------------------------------------------------------------

function Get-LabSetting([string]$Name, [string]$Default) {
    # Reads "param <Name> = '<value>'" or "param <Name> = <number>" from main.bicepparam
    $line = Select-String -Path $paramFile -Pattern "^\s*param\s+$Name\s*=\s*'?([^'\s/]+)'?" | Select-Object -First 1
    if ($line) { return $line.Matches[0].Groups[1].Value }
    return $Default
}

function Invoke-Az {
    $out = & az @args
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI command failed: az $($args -join ' ')" }
    return $out
}

function Invoke-OnLabVm([string]$VmName, [string]$Script) {
    # Runs PowerShell on a lab VM through Azure (no RDP needed) and prints its output.
    $tmp = Join-Path $env:TEMP "lab-runcmd-$([guid]::NewGuid()).ps1"
    Set-Content -Path $tmp -Value $Script -Encoding UTF8
    try {
        $json = Invoke-Az vm run-command invoke -g $ResourceGroup -n $VmName --command-id RunPowerShellScript --scripts "@$tmp" -o json
        $result = ($json -join "`n") | ConvertFrom-Json
        foreach ($v in $result.value) {
            if ($v.message) { $v.message.TrimEnd() }
        }
    }
    finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

function Get-MyIp { (Invoke-RestMethod -Uri 'https://api.ipify.org').Trim() }

$prefix  = (Get-LabSetting 'prefix' 'cmlab').ToLower()
$admin   = Get-LabSetting 'adminUsername' 'labadmin'
$vmFull  = if ($Vm -like "$prefix*") { $Vm } else { "$prefix$Vm" }

# ---- actions ---------------------------------------------------------------

switch ($Action) {

    'check' {
        $vmSize  = Get-LabSetting 'vmSize' 'Standard_D2s_v5'
        $sqlSize = Get-LabSetting 'sqlVmSize' 'Standard_D2s_v5'
        $clients = [int](Get-LabSetting 'clientsCount' '1')
        $counts  = @{}
        $counts[$vmSize]  = 2 + $clients                       # DC, DP/MP, clients
        $counts[$sqlSize] = 1 + [int]($counts[$sqlSize])       # site server

        Write-Host "Checking $($counts.Keys -join ', ') in $Location ..." -ForegroundColor Cyan
        $query = '[?' + (($counts.Keys | ForEach-Object { "name=='$_'" }) -join ' || ') + ']'
        $skus  = (Invoke-Az vm list-skus --location $Location --resource-type virtualMachines --all --query $query -o json) -join "`n" | ConvertFrom-Json
        $usage = (Invoke-Az vm list-usage --location $Location -o json) -join "`n" | ConvertFrom-Json

        $ok = $true
        $needByFamily = @{}
        $needTotal = 0
        foreach ($size in $counts.Keys) {
            $sku = $skus | Where-Object { $_.name -eq $size } | Select-Object -First 1
            if (-not $sku) { Write-Host "  $size : not offered in $Location" -ForegroundColor Red; $ok = $false; continue }
            $vcpu = [int](($sku.capabilities | Where-Object { $_.name -eq 'vCPUs' }).value)
            $blocked = ($sku.restrictions | ForEach-Object { $_.reasonCode }) -join ','
            if ($blocked) { Write-Host "  $size : BLOCKED ($blocked)" -ForegroundColor Red; $ok = $false }
            else { Write-Host "  $size : available ($vcpu vCPUs, family $($sku.family))" -ForegroundColor Green }
            $needByFamily[$sku.family] = [int]$needByFamily[$sku.family] + $vcpu * $counts[$size]
            $needTotal += $vcpu * $counts[$size]
        }
        foreach ($fam in @($needByFamily.Keys) + 'cores') {
            $need = if ($fam -eq 'cores') { $needTotal } else { $needByFamily[$fam] }
            $u = $usage | Where-Object { $_.name.value -eq $fam } | Select-Object -First 1
            if (-not $u) { continue }
            $free = [int]$u.limit - [int]$u.currentValue
            $label = if ($fam -eq 'cores') { 'Total regional vCPUs' } else { $u.name.localizedValue }
            if ($free -ge $need) { Write-Host "  Quota $label : need $need, have $free free" -ForegroundColor Green }
            else { Write-Host "  Quota $label : need $need, only $free free (request an increase in the portal: Quotas > Compute)" -ForegroundColor Red; $ok = $false }
        }
        if ($ok) { Write-Host "Ready to deploy to $Location." -ForegroundColor Green }
        else { Write-Host "Pick another region (-Location) or size (edit main.bicepparam), then check again." -ForegroundColor Yellow }
    }

    'deploy' {
        $sub = Invoke-Az account show --query name -o tsv
        Write-Host "Subscription: $sub" -ForegroundColor Cyan
        $ip = Get-MyIp
        Write-Host "RDP will be allowed only from your current IP: $ip"

        $p1 = Read-Host 'Lab admin password (12+ chars, upper, lower, number, symbol)' -AsSecureString
        $p2 = Read-Host 'Confirm password' -AsSecureString
        $plain1 = [Net.NetworkCredential]::new('', $p1).Password
        $plain2 = [Net.NetworkCredential]::new('', $p2).Password
        if ($plain1 -ne $plain2) { throw 'Passwords did not match.' }

        $env:LAB_ADMIN_PASSWORD = $plain1
        $env:LAB_RDP_SOURCE = "$ip/32"
        try {
            $null = Invoke-Az group create --name $ResourceGroup --location $Location -o none
            Write-Host "Deploying to $ResourceGroup ($Location). This takes 15-30 minutes ..." -ForegroundColor Cyan
            $state = Invoke-Az deployment group create --resource-group $ResourceGroup --parameters $paramFile --name mecm-lab --query properties.provisioningState -o tsv
            Write-Host "Deployment: $state" -ForegroundColor Green
            Write-Host "MECM keeps installing for another 2-4 hours. Check with .\Lab.ps1 status (don't restart the VMs meanwhile)."
            Write-Host "Sign in to the VMs as contoso\$admin."
        }
        finally {
            Remove-Item Env:LAB_ADMIN_PASSWORD, Env:LAB_RDP_SOURCE -ErrorAction SilentlyContinue
        }
    }

    'status' {
        $script = @'
$f = 'C:\Windows\Temp\ProvisionScript\PS1.json'
if (Test-Path $f) {
    (Get-Content $f | ConvertFrom-Json).PSObject.Properties | ForEach-Object { '{0,-16} {1}' -f $_.Name, $_.Value.Status }
} else { 'Setup has not reached the MECM install yet (domain join and prerequisites run first).' }
$t = Get-ScheduledTask -TaskName ScriptWorkFlow -ErrorAction SilentlyContinue
if ($t) { 'Setup script    ' + $t.State }
$s = Get-Service SMS_EXECUTIVE -ErrorAction SilentlyContinue
if ($s) { 'SMS_EXECUTIVE   ' + $s.Status }
'@
        Invoke-OnLabVm "$($prefix)ps01" $script
    }

    'rdp' {
        $ip = Invoke-Az vm show -d -g $ResourceGroup -n $vmFull --query publicIps -o tsv
        if (-not $ip) { throw "$vmFull has no public IP. Is it running? Try .\Lab.ps1 start" }
        Write-Host "Connecting to $vmFull ($ip). Sign in as contoso\$admin." -ForegroundColor Cyan
        Start-Process mstsc.exe -ArgumentList "/v:$ip"
    }

    'copy' {
        if (-not $Path) { throw 'Give one or more files with -Path.' }
        foreach ($p in $Path) {
            $file = Get-Item $p
            if ($file.Length -gt 150KB) { throw "$($file.Name) is over 150 KB; copy large files over RDP instead." }
            $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($file.FullName))
            $script = "New-Item -ItemType Directory -Force '$Destination' | Out-Null; [IO.File]::WriteAllBytes('$Destination\$($file.Name)', [Convert]::FromBase64String('$b64')); 'Copied $($file.Name) to $Destination on ' + `$env:COMPUTERNAME"
            Invoke-OnLabVm $vmFull $script
        }
    }

    'client' {
        $cl = if ($Vm -eq 'ps01') { "$($prefix)cl01" } else { $vmFull }
        $script = "Start-Process '\\$($prefix)ps01.contoso.com\SMS_$SiteCode\Client\ccmsetup.exe' -ArgumentList 'SMSSITECODE=$SiteCode /mp:$($prefix)dpmp01.contoso.com' -Wait; 'ccmsetup started on ' + `$env:COMPUTERNAME + '. The client finishes installing in 5-10 minutes.'"
        Invoke-OnLabVm $cl $script
    }

    'start' {
        Write-Host "Starting $($prefix)dc01 first ..." -ForegroundColor Cyan
        $null = Invoke-Az vm start -g $ResourceGroup -n "$($prefix)dc01" -o none
        $others = (Invoke-Az vm list -g $ResourceGroup --query "[?name!='$($prefix)dc01'].name" -o tsv) | Where-Object { $_ }
        foreach ($n in $others) { $null = Invoke-Az vm start -g $ResourceGroup -n $n --no-wait -o none; Write-Host "  starting $n" }
        Write-Host 'Give it about 5 minutes before connecting.'
    }

    'stop' {
        $ids = (Invoke-Az vm list -g $ResourceGroup --query '[].id' -o tsv) | Where-Object { $_ }
        $null = Invoke-Az vm deallocate --ids $ids --no-wait -o none
        Write-Host "Stopping $($ids.Count) VMs. Compute billing ends once they show 'Stopped (deallocated)'." -ForegroundColor Green
    }

    'updateip' {
        $ip = Get-MyIp
        $null = Invoke-Az network nsg rule update -g $ResourceGroup --nsg-name "$prefix-nsg" -n default-allow-rdp --source-address-prefixes "$ip/32" -o none
        Write-Host "RDP now allowed from $ip." -ForegroundColor Green
    }

    'delete' {
        $answer = Read-Host "This permanently deletes resource group '$ResourceGroup' and everything in it. Type DELETE to confirm"
        if ($answer -ne 'DELETE') { Write-Host 'Cancelled.'; return }
        $null = Invoke-Az group delete --name $ResourceGroup --yes --no-wait -o none
        Write-Host 'Deleting. It finishes in the background in about 10 minutes.' -ForegroundColor Green
    }
}

// MECM lab in Azure: a throwaway Configuration Manager site for testing task sequences,
// scripts, and console changes. Unofficial; lab use only.
//
// Deploys Microsoft's "Install Configuration Manager Current Branch in Azure" quickstart
// (standalone primary site, pinned to a known commit, patched for Standard public IPs)
// and adds two things it lacks:
//   1. RDP locked to your own IP. The quickstart opens 3389 to the whole internet.
//   2. A daily auto-shutdown on every VM, so the lab doesn't bill overnight.
//
// What gets built (domain contoso.com, all Windows Server 2022 / SQL 2019):
//   <prefix>dc01    Domain controller
//   <prefix>ps01    Primary site server + SQL + ADK/WinPE   <- you work here
//   <prefix>dpmp01  Distribution point + management point
//   <prefix>cl01    Windows 11 Enterprise client (the quickstart requires at least one)
//
// Setup runs for 2-4 hours AFTER Azure reports the deployment succeeded. Don't restart
// the VMs during that time, and deploy early enough that auto-shutdown doesn't hit it.
// Progress: .\Lab.ps1 status (reads C:\Windows\Temp\ProvisionScript\PS1.json on ps01).

targetScope = 'resourceGroup'

@description('Lowercase name prefix for the VMs, 2-8 letters/digits, e.g. "cmlab".')
@minLength(2)
@maxLength(8)
param prefix string

@description('Local and domain admin username (sign in as contoso\\<this>).')
param adminUsername string

@description('Admin password. Must meet Azure VM password complexity rules.')
@secure()
param adminPassword string

@description('Your public IP or CIDR allowed to RDP in, e.g. "203.0.113.25/32". Find it by searching "what is my IP".')
param allowedRdpSource string

@description('Azure region. Defaults to the resource group\'s region.')
param location string = resourceGroup().location

@description('Number of client VMs. The quickstart requires 1-3.')
@allowed([1, 2, 3])
param clientsCount int = 1

@description('Size for the DC, DP/MP and client VMs. Must be available, with quota, in your region: run .\\Lab.ps1 check.')
param vmSize string = 'Standard_D2s_v5'

@description('Size for the site server (runs SQL). Needs at least 8 GB RAM; 16 GB (e.g. Standard_D4s_v5 or Standard_E2bds_v5) makes the console faster.')
param sqlVmSize string = 'Standard_D2s_v5'

@description('Daily auto-shutdown time, 24h HHmm. Set enableAutoShutdown=false to skip.')
param autoShutdownTime string = '2300'

@description('Windows time zone ID for the auto-shutdown time.')
param autoShutdownTimeZone string = 'Eastern Standard Time'

param enableAutoShutdown bool = true

// quickstart.json = Microsoft's template at commit 39f97840, patched to use Standard public IPs
// (Basic public IPs were retired in Sept 2025 and the original template fails on them).
// Its DSC install scripts are still downloaded from the same pinned commit.
var artifactsBase = 'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/39f97840bd59224cc92490b1b49c382c6fed6986/application-workloads/sccm/sccm-currentbranch/'

var lowerPrefix = toLower(prefix)
var serverNames = [
  '${lowerPrefix}dc01'
  '${lowerPrefix}ps01'
  '${lowerPrefix}dpmp01'
]
var clientNames = [for i in range(1, clientsCount): '${lowerPrefix}cl0${i}']
var vmNames = concat(serverNames, clientNames)

module lab 'quickstart.json' = {
  name: 'mecm-quickstart'
  params: {
    prefix: prefix
    ClientsCount: clientsCount
    configuration: 'Standalone'
    vmSize: vmSize
    SQLVmSize: sqlVmSize
    adminUsername: adminUsername
    adminPassword: adminPassword
    location: location
    _artifactsLocation: artifactsBase
    _artifactsLocationSasToken: '' // public GitHub URL, no token
  }
}

// The quickstart creates this NSG with RDP open to '*'. Overwrite that rule with your IP.
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' existing = {
  name: '${lowerPrefix}-nsg'
}

resource rdpRule 'Microsoft.Network/networkSecurityGroups/securityRules@2023-09-01' = {
  parent: nsg
  name: 'default-allow-rdp'
  properties: {
    priority: 1000
    direction: 'Inbound'
    access: 'Allow'
    protocol: 'Tcp'
    sourceAddressPrefix: allowedRdpSource
    sourcePortRange: '*'
    destinationAddressPrefix: '*'
    destinationPortRange: '3389'
  }
  dependsOn: [
    lab
  ]
}

resource vms 'Microsoft.Compute/virtualMachines@2023-09-01' existing = [for name in vmNames: {
  name: name
}]

resource shutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = [for (name, i) in vmNames: if (enableAutoShutdown) {
  name: 'shutdown-computevm-${name}'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTime
    }
    timeZoneId: autoShutdownTimeZone
    targetResourceId: vms[i].id
    notificationSettings: {
      status: 'Disabled'
    }
  }
  dependsOn: [
    lab
  ]
}]

output siteServer string = '${lowerPrefix}ps01'
output signInAs string = 'contoso\\${adminUsername}'
output vmNames array = vmNames
output nextStep string = 'Setup continues for 2-4 hours. Check progress with .\\Lab.ps1 status'

using './main.bicep'

// Lab settings. The password and your public IP are read from environment variables
// at deploy time, so nothing personal is saved in this file. ".\Lab.ps1 deploy" sets both.
param prefix = 'cmlab'            // VM names become cmlabdc01, cmlabps01, ...
param adminUsername = 'labadmin'  // sign in as contoso\labadmin
param adminPassword = readEnvironmentVariable('LAB_ADMIN_PASSWORD', '')
param allowedRdpSource = readEnvironmentVariable('LAB_RDP_SOURCE', '')

// VM sizes. Must be available, with vCPU quota, in your region: run ".\Lab.ps1 check".
// Total vCPUs = (3 servers + clients) x vCPUs per VM. With the defaults: 4 x 2 = 8.
param vmSize = 'Standard_D2s_v5'
param sqlVmSize = 'Standard_D2s_v5'
param clientsCount = 1

// Daily auto-shutdown. Setup takes 2-4 hours, so deploy early enough that this
// doesn't interrupt it on day one. Set enableAutoShutdown = false to turn it off.
param autoShutdownTime = '2300'
param autoShutdownTimeZone = 'Eastern Standard Time'
param enableAutoShutdown = true

# MECM Lab in Azure

A throwaway Configuration Manager (MECM) site in Azure for testing task sequences,
PowerShell against the ConfigMgr module, and console changes, without touching a real site.
**Unofficial and lab-only.** Use a personal or sandbox Azure subscription, never a
production or government one, and don't put real data in it.

It builds on Microsoft's own "Install Configuration Manager Current Branch in Azure"
quickstart, pinned to a known version and patched so it still deploys (Microsoft retired the
Basic public IPs it used). On top of that, it locks Remote Desktop to your IP and turns the
VMs off every night.

## What you get

| VM | Role |
| --- | --- |
| `cmlabdc01` | Domain controller for `contoso.com` |
| `cmlabps01` | Primary site server: MECM, SQL Server, ADK/WinPE, console. Most of your work happens here |
| `cmlabdpmp01` | Distribution point and management point |
| `cmlabcl01` | Windows 11 Enterprise client with the MECM client installed |

Everyone signs in as `contoso\labadmin` with the password chosen at deploy time.

## What's in this folder

| File | What it does |
| --- | --- |
| `Lab.ps1` | The one helper you run from your PC: check, deploy, status, rdp, copy, client, start, stop, updateip, delete |
| `main.bicep` | Deploys the lab: Microsoft's template, RDP locked to your IP, nightly auto-shutdown |
| `main.bicepparam` | Lab settings: names, VM sizes, shutdown time. Holds no passwords or IPs |
| `quickstart.json` | Microsoft's template, patched for Standard public IPs. Keep it next to `main.bicep` |
| `Complete-LabSetup.ps1` | Runs on the site server if setup stops partway (see Troubleshooting) |

## Before you start

- An Azure subscription where you're Owner or Contributor
- Azure CLI on your PC: `winget install Microsoft.AzureCLI`, then `az bicep install`
- Windows PowerShell 5.1 or PowerShell 7
- About 8 vCPUs of quota in your region (the check below confirms it)

If Windows blocks the scripts, run `Unblock-File .\*.ps1` in this folder, and if needed
`Set-ExecutionPolicy -Scope Process Bypass`.

## 1. Check the region (2 minutes)

```powershell
az login
.\Lab.ps1 check -Location eastus
```

It confirms the VM sizes are offered to your subscription in that region and that you have
enough vCPU quota. If anything shows red:

- **BLOCKED / not offered:** try another region (`-Location eastus2`, `centralus`, ...)
  or change `vmSize` / `sqlVmSize` in `main.bicepparam` to a size that shows available.
  New subscriptions are often blocked from older sizes such as the B-series.
- **Quota too low:** in the Azure portal, go to **Quotas > Compute**, filter to your region,
  find the family it names, and request a new limit. Small requests are often approved in
  minutes; some subscriptions need a support ticket instead.

## 2. Deploy (about 10 minutes of your time, then 2-4 hours unattended)

Deploy early in the day so setup finishes before the 11 PM auto-shutdown.

```powershell
.\Lab.ps1 deploy -Location eastus
```

It asks for the lab admin password, allows RDP only from your current public IP, and
returns after 15-30 minutes with `Deployment: Succeeded`. **MECM then keeps installing for
another 2-4 hours.** Don't restart any VM during that time.

## 3. Watch setup finish

```powershell
.\Lab.ps1 status
```

Run it every 30 minutes or so. Stages complete in this order:

| Stage | Typical time |
| --- | --- |
| `InstallSCCM` | ~45-60 min |
| `UpgradeSCCM` | 1-2 hrs (updates MECM to the newest build) |
| `InstallDP`, `InstallMP` | ~20-30 min |
| `InstallClient` | ~10-15 min, plus 5-10 min for the client to finish on cl01 |

It's done when every stage shows `Completed`. If it stops early, see Troubleshooting:
it's usually a two-minute fix.

## 4. Use it

```powershell
.\Lab.ps1 rdp              # site server (console, PowerShell, SQL)
.\Lab.ps1 rdp -Vm cl01     # the client (Software Center)
```

To get scripts onto a VM without copy and paste (lands in `C:\Lab`):

```powershell
.\Lab.ps1 copy -Path .\MyScript.ps1             # to the site server
.\Lab.ps1 copy -Path .\MyScript.ps1 -Vm cl01    # to the client
```

On the site server, the MECM console is on the Start menu, and the site code is `PS1`.
For PowerShell, open the console's top-left menu and choose **Connect via Windows PowerShell**.

**Azure VMs can't boot into WinPE**, so a task sequence that restarts into WinPE (any
wipe-and-load) can't run end to end here. You can build, edit, deploy and see task sequences
in Software Center, but **don't click Install on one that wipes the disk**: you'll lose the VM.

## 5. Day to day

```powershell
.\Lab.ps1 stop      # when you're done for the day (the nightly shutdown is a backstop)
.\Lab.ps1 start     # next time; give it ~5 minutes before connecting
.\Lab.ps1 updateip  # if RDP stops connecting because your home IP changed
```

Stopped VMs still bill for their disks, a few dollars a month. When you're finished:

```powershell
.\Lab.ps1 delete
```

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Deploy fails: `SkuNotAvailable` | That VM size isn't offered to your subscription in that region | `.\Lab.ps1 check` with other regions, or change sizes in `main.bicepparam` |
| Deploy fails: `QuotaExceeded` | vCPU quota for that VM family is too low (often 0 on new subscriptions) | Request an increase: portal > **Quotas > Compute** |
| `status` shows `UpgradeSCCM  Error`, and DP/MP/Client never ran | The optional MECM upgrade failed or was interrupted (for example by the nightly shutdown), which stops the rest of setup | The base site works fine. Run `.\Lab.ps1 copy -Path .\Complete-LabSetup.ps1`, then on the site server, in PowerShell as Administrator: `C:\Lab\Complete-LabSetup.ps1` |
| `InstallClient Completed`, but cl01 has no client after 20 minutes | The client push didn't land | `.\Lab.ps1 client`, then wait 5-10 minutes |
| RDP spins, then can't connect | Your public IP changed, or the VM is stopped | `.\Lab.ps1 updateip`, or `.\Lab.ps1 start` |
| Paste into the RDP window stops working | The Remote Desktop clipboard helper on the VM got stuck | On the VM: `taskkill /f /im rdpclip.exe; rdpclip`. Or use `.\Lab.ps1 copy` |
| Setup restarted after a shutdown | Normal: setup saves its progress and resumes after a restart | Check again with `.\Lab.ps1 status` |
| New driver package can't be used in a task sequence | MECM won't reference an empty driver package | Import at least one driver into it first |

## Notes

- `quickstart.json` comes from Microsoft's [Azure Quickstart Templates](https://github.com/Azure/azure-quickstart-templates/tree/master/application-workloads/sccm/sccm-currentbranch)
  (MIT license), pinned to commit `39f97840` (January 2025) so it builds the same way every time.
  The only change is Standard instead of Basic public IPs. Its install scripts download the latest MECM evaluation (180 days).
- Setup logs live on the site server in `C:\Windows\Temp\ProvisionScript\` (`*log.txt`,
  progress in `PS1.json`), and MECM's own logs in
  `C:\Program Files\Microsoft Configuration Manager\Logs\`.
- To rename the VMs or the admin account, change `prefix` / `adminUsername` in
  `main.bicepparam` before deploying. `Complete-LabSetup.ps1` assumes `cmlab` and `labadmin`
  unless you pass `-Prefix` / `-AdminUser`.

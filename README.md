# azure_templates

Reusable Azure tools and templates: Bicep deployments, helper scripts, and labs I've built
and found worth keeping. Each tool lives in its own folder and works on its own.

> These are personal, unofficial tools. Read a tool's README before deploying it, and use a
> subscription you're allowed to experiment in. Anything marked **lab** is not hardened for
> production.

## Tools

| Tool | Type | What it does |
| --- | --- | --- |
| [mecm-lab](mecm-lab/) | Lab | Throwaway Configuration Manager (MECM) site in Azure: DC, site server with SQL, DP/MP, and a Windows 11 client. One-command `Lab.ps1` helper for check, deploy, status, RDP, start/stop, and delete. |

## Layout

Every tool gets one folder at the root of the repo, named in lowercase with hyphens
(`mecm-lab`, `intune-test-tenant`, `storage-static-site`). Everything the tool needs lives
inside that folder, so it can be copied out and used without the rest of the repo.

```
azure_templates/
├── README.md              <- this index
├── _template/             <- copy this to start a new tool
│   └── README.md
└── mecm-lab/
    ├── README.md          <- what it is, prerequisites, how to deploy, how to remove
    ├── main.bicep         <- the deployment entry point
    ├── main.bicepparam    <- settings, with no secrets
    └── Lab.ps1            <- optional helper scripts
```

If the repo grows past a dozen or so tools, group them into category folders (`labs/`,
`modules/`, `scripts/`) and update the links in the table above.

## Conventions

- **One entry point per tool.** Name the main template `main.bicep`, with settings in
  `main.bicepparam`.
- **No secrets or personal details in the repo.** Read passwords, IPs, and subscription IDs
  at deploy time, with `readEnvironmentVariable()` in the `.bicepparam` file or a prompt in a
  helper script. Never commit `.env` files or filled-in parameter files.
- **Every tool can be removed.** Deploy into its own resource group, and document the one
  command that deletes it.
- **Pin what you depend on.** Reference external templates or modules at a specific commit
  or version, and note where they came from and their license.
- **Label labs clearly.** Anything that opens public endpoints or uses evaluation software
  says so at the top of its README.

## Adding a tool

1. Copy `_template/` to a new folder named after the tool.
2. Fill in its README: what it builds, prerequisites, deploy steps, cost notes, and how to
   tear it down.
3. Validate before committing: `az bicep build --file main.bicep` and `az bicep lint --file main.bicep`.
4. Add a row to the **Tools** table above.

## Prerequisites

Most tools here need:

- An Azure subscription where you can create resource groups
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) with Bicep (`az bicep install`)
- PowerShell 5.1 or 7 for the helper scripts

Each tool's README lists anything extra.

## License

[MIT](LICENSE). Some tools include third-party templates under their own licenses; each
tool's README says where they came from.

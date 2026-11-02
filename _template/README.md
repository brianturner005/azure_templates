# Tool name

One or two sentences: what this deploys or does, and when you'd use it.

> **Lab / Production-ready:** pick one and delete the other. Note any public endpoints or
> evaluation software here.

## What it builds

| Resource | Purpose |
| --- | --- |
| | |

## Prerequisites

- Azure CLI with Bicep (`az bicep install`)
- Anything specific to this tool (quota, licenses, roles)

## Deploy

```powershell
az group create --name rg-<tool> --location eastus
az deployment group create --resource-group rg-<tool> --parameters main.bicepparam
```

## Use it

How to connect, what to check, and what "done" looks like.

## Cost

Rough running cost and how to pause it (stop or deallocate, scale down).

## Remove

```powershell
az group delete --name rg-<tool> --yes
```

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| | | |

## Notes

Third-party sources (link, version or commit, license), and known limitations.

# LifeData NonProd CI OIDC Bootstrap

**Date:** 2026-06-17
**Phase:** 01-access / Plan 01-01
**Ops repo:** `github.com/LifeDataLLC/V2-Azure-Operations` (branch: `main`)

## What This Does

`bootstrap.ps1` provisions the secretless CI OIDC identity that allows GitHub Actions (in this
repo) to authenticate to Azure and deploy resources into the nonprod estate. It creates:

1. **Entra app registration** — display name `ld-iac-cicd-nonprod`
2. **Service principal (SPN)** — tied to the app registration
3. **Federated identity credential (FIC)** — from `fic-nonprod.json`; trusts GitHub Actions
   OIDC tokens for `repo:LifeDataLLC/V2-Azure-Operations:ref:refs/heads/main` only
4. **Contributor role assignment** — scoped **only** to resource group `LD-NonProd-EastUS-V3`

**No client secret is ever created.** Authentication is via GitHub Actions OIDC
(short-lived tokens exchanged through Entra), satisfying ACCESS-01. Role assignment is
RG-scoped only — the SPN has zero access to the existing V2 estate or subscription level,
satisfying ACCESS-02 and the build-new safety principle (D-03).

The script is idempotent: re-running it after a successful run is a no-op (each step guards
with an existence check).

## Who Runs It

An **Owner of `LD-NonProd-EastUS-V3`** — one privileged, one-time run on the operator
workstation. The SPN cannot create itself.

**Verified operator:** `damir.contractor@lifedatacorp.com` (Owner on `LD-NonProd-EastUS-V3`,
direct role assignment confirmed 2026-06-17).

## Prerequisites

- [ ] Azure CLI 2.61+ installed
- [ ] Logged in to Azure: `az login` or `az login --tenant b504d3d4-ffb7-40f4-b25a-97ccb238fde3`
- [ ] Active subscription is `e3e4d658-d924-4c2b-ad05-a4457e197527` (Pay-As-You-Go LifeData):
      `az account show --query id -o tsv`
- [ ] Caller is **Owner** of resource group `LD-NonProd-EastUS-V3`
- [ ] Tenant `allowedToCreateApps = true` (verified for this tenant; members can create app registrations)
- [ ] Run from the `V2-Azure-Operations/` repo root so `v3/bootstrap/fic-nonprod.json` resolves

## How to Run

```powershell
# From the V2-Azure-Operations/ repository root:
pwsh v3/bootstrap/bootstrap.ps1
```

On success the script prints:

```
=== Bootstrap complete ===

  ARM_CLIENT_ID       (appId)      : <guid>
  App object ID                    : <guid>
  SPN object ID                    : <guid>
  Role scope                       : /subscriptions/e3e4d658-.../resourceGroups/LD-NonProd-EastUS-V3
```

**Record the printed `ARM_CLIENT_ID` (appId)** — it is required by the Plan 01-02
verification script and later as a GitHub Actions repository variable.

## Idempotency Check

Re-run once to confirm no-op:

```powershell
pwsh v3/bootstrap/bootstrap.ps1
```

All four steps should print `SKIP:` — no duplicate apps, no duplicate role-assignment errors.

## Files

| File | Purpose |
|------|---------|
| `bootstrap.ps1` | Idempotent bootstrap script (run once by Owner/App-Admin) |
| `fic-nonprod.json` | Federated identity credential parameters (consumed by the script) |
| `README.md` | This document |

## Security Notes

- **No client secret is created.** The SPN authenticates exclusively via federated identity
  credential (OIDC). `az ad app credential list` should always return `[]`.
- **RG scope only.** The Contributor assignment is scoped to `LD-NonProd-EastUS-V3`.
  The SPN cannot read, modify, or delete anything in `LD-Prod-EastUS-V2` or `LD-NonProd-EastUS-V2`.
- **Exact FIC subject.** Entra validates the subject at token-exchange time. Wildcards are not
  supported; a mismatch fails the GitHub Actions login silently. The Phase-5 CI workflow must
  use the `main` branch trigger matching `ref:refs/heads/main`.

## Next Steps

After the bootstrap run:

1. Record `ARM_CLIENT_ID` from the script output.
2. Run Plan 01-02 (`verify.ps1`) to assert the identity is secretless and correctly scoped.
3. Phase 2 will configure remote Terraform state (Azure Blob backend, OIDC auth).
4. Phase 5 will finalize the GitHub Actions workflow and add further FIC subjects (PR, environments).

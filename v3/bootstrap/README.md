# LifeData IaC Bootstrap

**Date:** 2026-06-17 (Phase 1), 2026-06-18 (Phase 2 extension)
**Phases:** 01-access / Plan 01-01, 02-remote-state / Plan 02-01
**Ops repo:** `github.com/LifeDataLLC/V2-Azure-Operations` (branch: `main`)

## What This Does

`bootstrap.ps1` is the single idempotent Owner-run script for all out-of-band Azure
provisioning that cannot be performed by Terraform (chicken-and-egg problem) or by the CI
SPN (which cannot grant itself rights). It currently handles two phases:

### Phase 1 — CI OIDC Identity (Steps 1–4)

Provisions the secretless identity that allows GitHub Actions to authenticate to Azure:

1. **Entra app registration** — display name `ld-iac-cicd-nonprod`
2. **Service principal (SPN)** — tied to the app registration
3. **Federated identity credential (FIC)** — from `fic-nonprod.json`; trusts GitHub Actions
   OIDC tokens for `repo:LifeDataLLC/V2-Azure-Operations:ref:refs/heads/main` only
4. **Contributor role assignment** — scoped **only** to resource group `LD-NonProd-EastUS-V3`

No client secret is ever created. Authentication is via OIDC (satisfies ACCESS-01). Role is
RG-scoped only — zero V2 estate access (satisfies ACCESS-02 / D-03).

### Phase 2 — Terraform Remote State Backend (Steps 5–8)

Stands up the Azure Blob storage account and containers that Terraform uses as its remote
state backend (satisfies STATE-01 / STATE-02):

5. **Storage account `stldtfstateeastus`** in resource group `iac-shared` (eastus,
   Standard_LRS, StorageV2, TLS 1.2, shared-key disabled, blob-public disabled,
   public-network Enabled per D-208a)
6. **Blob data-protection** — versioning ON, blob soft-delete 90 days, container soft-delete
   90 days (separate `blob-service-properties update` call — these are not `create` flags)
7. **`Storage Blob Data Contributor` role** — granted to the CI SPN and the running operator
   on the SA, ordered before container creation (RBAC propagation)
8. **Containers `tfstate-nonprod` and `tfstate-prod`** — created via AAD (`--auth-mode login`;
   shared-key access is disabled so key auth is not available)

The script is idempotent end-to-end: re-running it after a successful run is a complete no-op
(existence checks guard every create; role assignments are idempotent on assignee/role/scope).

## Who Runs It

An **Owner / Contributor on `iac-shared`** (which also implies Owner on `LD-NonProd-EastUS-V3`
for Phase 1) — one privileged, one-time run on the operator workstation. The CI SPN cannot
provision itself or create its own backend.

**Verified operator:** `damir.contractor@lifedatacorp.com` (Owner on `LD-NonProd-EastUS-V3`,
Contributor on `iac-shared` required for Phase 2; confirmed 2026-06-17/18).

## Prerequisites

- [ ] Azure CLI 2.61+ installed
- [ ] Logged in to Azure: `az login` or `az login --tenant b504d3d4-ffb7-40f4-b25a-97ccb238fde3`
- [ ] Active subscription is `e3e4d658-d924-4c2b-ad05-a4457e197527` (Pay-As-You-Go LifeData):
      `az account show --query id -o tsv`
- [ ] Caller is **Owner** of resource group `LD-NonProd-EastUS-V3` (Phase 1)
- [ ] Caller holds **Contributor** (or Owner) on resource group `iac-shared` (Phase 2 — to
      create the storage account and grant the data-plane role)
- [ ] Tenant `allowedToCreateApps = true` (verified for this tenant; members can create app registrations)
- [ ] Run from the `V2-Azure-Operations/` repo root so `v3/bootstrap/fic-nonprod.json` resolves

## How to Run

```powershell
# From the V2-Azure-Operations/ repository root:
pwsh v3/bootstrap/bootstrap.ps1
```

On first run (Phase 1 + 2 fresh), the script prints:

```
=== Bootstrap complete ===

  ARM_CLIENT_ID       (appId)      : <guid>
  App object ID                    : <guid>
  SPN object ID                    : <guid>
  Role scope (Phase 1)             : /subscriptions/e3e4d658-.../resourceGroups/LD-NonProd-EastUS-V3

  === Phase 2: Remote State Backend ===
  State SA id                      : /subscriptions/e3e4d658-.../resourceGroups/iac-shared/providers/Microsoft.Storage/storageAccounts/stldtfstateeastus
  State SA name                    : stldtfstateeastus
  State RG                         : iac-shared
  Containers                       : tfstate-nonprod, tfstate-prod
  SPN data-plane role scope        : /subscriptions/e3e4d658-.../storageAccounts/stldtfstateeastus
  SPN objectId (role grantee)      : d199cf8a-c401-42c1-8a52-96d2ee2bf92c
```

**Record:**
- `ARM_CLIENT_ID` — required by `verify.ps1` and later as a GitHub Actions repository variable
- **State SA id** and **container names** — form the Phase 2 backend contract consumed by Plan 02-02

## Idempotency Check

Re-run once to confirm no-op:

```powershell
pwsh v3/bootstrap/bootstrap.ps1
```

All eight steps should print `SKIP:` or `OK:` (role assignments print `OK:` always — they are
idempotent on tuple). No duplicate resources or error messages should appear.

## Verification

After a successful bootstrap run, verify all assertions pass:

```powershell
# From the V2-Azure-Operations/ repository root, logged in as the human Owner identity:
pwsh v3/bootstrap/verify.ps1
```

`verify.ps1` asserts both **Phase 1 (ACCESS-01/02/03 + D-03-NEG + SEC-GREP)** and
**Phase 2 (STATE-01a/b/c + STATE-02)** checks. All lines should print `PASS`.

> **Note on STATE-02 (container-exists check):** if a `403` appears immediately after the
> first bootstrap run, wait a few minutes and re-run `verify.ps1` — Azure RBAC propagation
> can take up to ~30 minutes. This is not a misconfiguration; it is a known Azure delay.

## Files

| File | Purpose |
|------|---------|
| `bootstrap.ps1` | Idempotent bootstrap script (Owner-run: Phase 1 CI identity + Phase 2 state SA) |
| `verify.ps1` | Assertion script — Phase 1 ACCESS/D-03/SEC-GREP + Phase 2 STATE-01/02 checks |
| `fic-nonprod.json` | Federated identity credential parameters (consumed by the script) |
| `README.md` | This document |

## Security Notes

- **No client secret is created.** The SPN authenticates exclusively via federated identity
  credential (OIDC). `az ad app credential list` should always return `[]`.
- **RG scope only (Phase 1 role).** The Contributor assignment is scoped to `LD-NonProd-EastUS-V3`.
  The SPN cannot read, modify, or delete anything in `LD-Prod-EastUS-V2` or `LD-NonProd-EastUS-V2`.
- **Data-plane role only (Phase 2 role).** The SPN gets `Storage Blob Data Contributor` on the
  state storage account only — no control-plane rights on `iac-shared` (D-204). Zero V2 access
  is preserved (D-03), re-asserted by `verify.ps1 D-03-NEG`.
- **AAD-only state access.** The storage account has `allowSharedKeyAccess = false`; no
  access key is ever issued or stored. State reads/writes use AAD tokens (`use_azuread_auth`).
- **Public network access Enabled (M1).** D-208a: `public_network_access = Enabled` is required
  in M1 because no private endpoint / self-hosted runner exists yet. The data plane is locked
  by AAD-only + shared-key-disabled + Storage Blob Data Contributor RBAC + TLS 1.2. Full
  network lockdown is deferred to Milestone 3 (security hardening).
- **Exact FIC subject.** Entra validates the subject at token-exchange time. Wildcards are not
  supported; a mismatch fails the GitHub Actions login silently. The Phase-5 CI workflow must
  use the `main` branch trigger matching `ref:refs/heads/main`.

## Next Steps

After a clean bootstrap + verify run:

1. Record `ARM_CLIENT_ID` from the script output (if not already done from Plan 01-01).
2. Record the State SA id and container names for the Plan 02-02 backend contract.
3. Plan 02-02 will author `backend.tf` + `nonprod.backend.hcl` / `prod.backend.hcl` and prove
   `terraform init` reaches the state backend with no access-key prompt (STATE-03).
4. Phase 5 will finalize the GitHub Actions workflow and add further FIC subjects (PR, environments).

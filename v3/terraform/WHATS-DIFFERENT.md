# WHATS-DIFFERENT.md — Estate-Wide Configuration Differences

**Phase 3 Required Deliverable (D-313 / SC6)**
**Scope:** LifeData V3 Terraform estate — both scopes (nonprod + prod)
**Collected:** 2026-06-18

---

## Purpose and Scope

This document records **every intentional per-environment and per-scope difference** in the V3
Terraform configuration, across every module. Each difference is tied to a specific Terraform
variable, its nonprod and prod values, and the live-reference evidence behind the choice.

**Milestone posture:**
- **M1 (Phase 3/4):** This config *preserves current V2 posture* — including known security
  gaps — as explicit, evidence-backed variable values. No remediation is applied yet.
- **M3 (Security milestone):** Values marked "M3 flips" are the target changes. Remediation
  is a reviewed tfvars diff, not a code change, because every posture variable has `no default`
  (D-307).

This document doubles as the **M3 remediation map**: every row shows exactly which variable to
flip and what value to set.

> **AUTH-01 / D-311 note:** No `terraform import` or `aztfexport` state capture was performed
> against the live V2 RGs. The V2 estate contains zero Terraform-managed resources. This
> configuration creates a NEW side-by-side estate; the V2 resources are read-only authoring
> references only.

---

## 1. Scope Model

| Aspect | Nonprod scope | Prod scope | Variable | Evidence |
|--------|--------------|-----------|----------|----------|
| Resource group | `ld-nonprod-eastus-v3` | `ld-prod-eastus-v3` | `resource_group_name` | D-08 / D-12 |
| State container | `tfstate-nonprod` | `tfstate-prod` | `nonprod.backend.hcl` / `prod.backend.hcl` | D-205 |
| Active envs (M1) | dev=true, qa=false | staging=false, prod=false | `environments.*.enabled` | D-301a |
| VNet name | `vnet-common-nonproduction-eastus` | `vnet-production-eastus` | `networking.vnet_name` | vnets.json |
| VNet CIDR | `10.0.0.0/16` | `10.0.0.0/16` | `networking.vnet_address_space` | vnets.json (overlapping by design; M3 splits) |

### 1.1 Environment Enable Toggles (D-301a)

```
environments = {
  dev     = { enabled = true  }   # nonprod scope — DEV only active in M1
  qa      = { enabled = false }   # nonprod scope — off until Phase 4 / QA wave
  staging = { enabled = false }   # prod scope — prod scope idle in M1
  prod    = { enabled = false }   # prod scope — prod scope idle in M1
}
```

**M3 / Phase 4 action:** Set `staging.enabled = true` and `prod.enabled = true` in `prod.tfvars`
when the prod scope is brought live.

---

## 2. SQL Module (modules/sql)

All four SQL servers share the same insecure M1 posture — preserved from the live V2 estate.

| Variable | Nonprod value | Prod value | Evidence | M-milestone |
|----------|--------------|-----------|----------|-------------|
| `sql_public_network_access_enabled` | `true` | `true` | `sql_detail.json publicNetworkAccess="Enabled"` (all 4 servers); `FINDINGS-DATA.md §SQL F1` | M3: set both to `false` |
| `sql_allow_all_azure_ips` | `true` | `true` | `sql_detail.json firewallRules[0].name="AllowAllWindowsAzureIps"` (0.0.0.0–0.0.0.0, all 4); `FINDINGS-DATA.md §SQL F2` | M3: set both to `false` |
| `sql_auditing_enabled` | `false` | `false` | `sql_detail.json auditPolicy.state="Disabled"` (all 4); `FINDINGS-DATA.md §SQL F3`; `azurerm_mssql_server_extended_auditing_policy.enabled=false` (`res-3447/3500/1908/1963`) | M3: set both to `true` |
| `sql_azuread_only_auth` | `false` | `false` | `sql_detail.json aadAdmins.azureAdOnlyAuthentication=false` (all 4); `FINDINGS-DATA.md §SQL F4` | M3: set both to `true` |
| `environments.dev.sql_sku` | `S1` (10 DTU) | — | `sql_detail.json dev server currentServiceObjectiveName="S1"` | Stays S1 unless workload grows |
| `environments.qa.sql_sku` | `S1` (10 DTU) | — | `sql_detail.json qa server currentServiceObjectiveName="S1"` | — |
| `environments.staging.sql_sku` | — | `S2` (50 DTU) | `sql_detail.json staging server currentServiceObjectiveName="S2"` | — |
| `environments.prod.sql_sku` | — | `S3` (100 DTU) | `sql_detail.json prod server currentServiceObjectiveName="S3"` | — |

### 2.1 SQL VNet Rule State — M3 Prerequisite (D-315 / Pitfall 5)

`azurerm_mssql_virtual_network_rule` is explicitly authored for all 4 servers (reconstructed from
`data/sql_vnet_rules.json` — aztfexport omits these). The prod/staging rules are in `state=Failed`:

| Server | Rule name | State | Subnet |
|--------|-----------|-------|--------|
| sql-server-dev-eastus | newVnetRule1 | **Ready** | sql-nonproduction-eastus-subnet |
| sql-server-qa-eastus | newVnetRule1 | **Ready** | sql-nonproduction-eastus-subnet |
| sql-server-prod-eastus | DBVnetRule | **Failed** | sql-production-eastus-subnet |
| sql-server-staging-eastus | DBVnetRule | **Failed** | sql-production-eastus-subnet |

**M3 PREREQUISITE (Pitfall 5):** Before removing `AllowAllWindowsAzureIps` in M3, the
`state=Failed` VNet rules on prod and staging SQL servers must be resolved. The Failed state
indicates the service endpoint was not provisioned in `sql-production-eastus-subnet` at collection
time. Resolution: verify the service endpoint is active in the prod VNet subnet, then re-apply the
VNet rule. Removing `AllowAllWindowsAzureIps` *before* this fix would lock out all App Service
traffic to the prod SQL servers.

### 2.2 D-305 Dropped Firewall Rules

Developer-home and transient firewall rules (`Amalesh_Home`, `Ishtiaque*`, `Marcus`,
`ClientIPAddress_*`) are NOT cloned into the V3 module — click-ops noise per D-305. Only
`AllowAllWindowsAzureIps` is governed by a posture variable.

---

## 3. Storage Module (modules/storage)

### 3.1 Scope-Shared vs Per-Env Accounts

The module uses a hybrid D-302 pattern: one `module "storage_shared"` call (scope-shared, no
for_each) + one `module "storage_env"` call (per-env for_each over enabled_envs).

| Account | Scope | Env | Classification | Evidence |
|---------|-------|-----|----------------|----------|
| `ldfstnonproductioneastus` | Nonprod | Shared | B2C/func static assets | `storage_accounts.json` |
| `ldstdeveastus` | Nonprod | Dev | Dev primary storage | `storage_accounts.json` |
| `ldstqaeastus` | Nonprod | QA | QA primary storage | `storage_accounts.json` |
| `stqanonproductioneastus` | Nonprod | QA | QA secondary | `storage_accounts.json` |
| `lifelatapublic` | Prod | Shared | Public assets (West US — V1 legacy) | `storage_accounts.json` |
| `ststagingeastus` | Prod | Staging | Staging primary | `prod_storage_accounts.json` |
| `stldprodeastus` | Prod | Prod | Prod primary (East US) | `prod_storage_accounts.json` |
| `stldprodeastus2` | Prod | Prod | Prod secondary (East US 2) | `prod_storage_accounts.json` |

### 3.2 Per-Account Posture Variables

All values are per-account fields in the `storage_shared_accounts` / `storage_env_accounts` maps
(D-303 / D-307 — no module-level default).

| Account | `allow_nested_items_to_be_public` | `shared_access_key_enabled` | `min_tls_version` | `account_replication_type` | `network_default_action` |
|---------|----------------------------------|----------------------------|-------------------|---------------------------|--------------------------|
| `ldfstnonproductioneastus` | **false** | **false** | TLS1_2 | LRS | Allow |
| `ldstdeveastus` | true | true | TLS1_2 | LRS | Allow |
| `ldstqaeastus` | false | true | **TLS1_0** ⚠️ | LRS | Allow |
| `stqanonproductioneastus` | true | true | TLS1_2 | LRS | Allow |
| `lifelatapublic` | true | true | TLS1_2 | LRS | Allow |
| `ststagingeastus` | true | true | TLS1_2 | LRS | Allow |
| `stldprodeastus` | true | true | TLS1_2 | **RA-GRS** | Allow |
| `stldprodeastus2` | true | true | TLS1_2 | **RA-GRS** | Allow |

**Evidence:** `data/storage_accounts.json` (nonprod), `data/prod_storage_accounts.json` (prod);
`FINDINGS-DATA.md §Storage`.

**Notable differences:**
- `ldfstnonproductioneastus`: ONLY account with `shared_access_key_enabled=false` and
  `allow_nested_items_to_be_public=false` — stronger posture than all others (already secure).
- `ldstqaeastus` TLS exception: `min_tls_version="TLS1_0"` — **HIGH finding** per `FINDINGS-DATA.md`.
  This is the only account not at TLS1_2. Evidence: `storage_accounts.json minimumTlsVersion="TLS1_0"`.
  M3 action: flip to `TLS1_2`.
- Prod replication: `stldprodeastus` and `stldprodeastus2` use `RA-GRS` (read-access geo-redundant)
  for DR; all others use `LRS`. Evidence: `storage_accounts.json sku.name="Standard_RAGRS"` vs
  `"Standard_LRS"`.

**M3 actions:** Set `allow_nested_items_to_be_public=false`, `network_default_action="Deny"` on all
accounts. Fix `ldstqaeastus` TLS to `TLS1_2`. Consider setting `shared_access_key_enabled=false`
on all accounts after confirming managed identity role assignments (RBAC Blob Data Reader/Contributor).

---

## 4. Key Vault Module (modules/keyvault)

The D-306 divergence is the most significant KV difference between scopes.

| Variable | Nonprod value | Prod value | Evidence | M-milestone |
|----------|--------------|-----------|----------|-------------|
| `kv_enable_rbac_authorization` | **`true`** (RBAC mode) | **`false`** (access-policy mode) | `keyvaults_detail.json kvnonproductioneastus.properties.enableRbacAuthorization=true`; `kvproductioneastus.properties.enableRbacAuthorization=false`; `FINDINGS-DATA.md §KeyVault` | M3: flip prod to `true` (RBAC everywhere) |
| `kv_network_default_action` | `Allow` | `Allow` | `keyvaults_detail.json networkAcls.defaultAction="Allow"` (both vaults) | M3: flip both to `Deny` |
| `kv_public_network_access_enabled` | `true` | `true` | `keyvaults_detail.json publicNetworkAccess="Enabled"` (both vaults) | M3: flip both to `false` |
| `kv_name` | `kvnonproductioneastus` | `kvproductioneastus` | `keyvaults_detail.json name` (both vaults) | — |
| `kv_sku_name` | `standard` | `standard` | `keyvaults_detail.json properties.sku.name="Standard"` (both vaults) | — |
| `kv_access_policies` | `[]` (RBAC mode — unused) | 8 policies from live | `keyvaults_detail.json kvproductioneastus.accessPolicies` | M3: migrate prod to RBAC; remove access policies |

**Auth model summary:**
- **Nonprod (RBAC = true):** Access policies block produces zero blocks. Role assignments control
  access. This is the target state for both scopes.
- **Prod (RBAC = false):** 8 access policies authored from `keyvaults_detail.json`. This is the
  current live posture, preserved in M1. M3 migrates to RBAC by setting
  `kv_enable_rbac_authorization=true` and assigning `azurerm_role_assignment` blocks.

---

## 5. APIM Module (modules/apim)

### 5.1 SKU Differences (D-307 — apim_sku_name)

| Instance | Scope | SKU | VNet type | Evidence | M-milestone |
|----------|-------|-----|-----------|----------|-------------|
| `apim-common-nonproduction-eastus` | Nonprod | `Developer_1` | Internal | `apim_services.json sku.name=Developer, capacity=1; virtualNetworkType=Internal` | M4: consolidate |
| `ldapim-eastus-dev` | Nonprod | `Developer_1` | Internal | `apim_services.json sku.name=Developer, capacity=1; virtualNetworkType=Internal` | M4: consolidate |
| `apim-staging-eastus` | Prod | `Developer_1` | Internal | `apim_services.json sku.name=Developer, capacity=1; virtualNetworkType=Internal` | M4: consolidate |
| `ldapim-prod-eastus` | Prod | `Developer_1` | None | `apim_services.json sku.name=Developer, capacity=1; virtualNetworkType=None` (no SLA, no HA) | M4: retire |
| `ldapim-prod-stv2-eastus` | Prod | `StandardV2_1` | External | `apim_services.json sku.name=StandardV2, capacity=1; virtualNetworkType=External` | M4: keep as prod gateway |

**5-instance count:** The live estate is mid-migration from Developer-SKU to StandardV2.
Both Developer + StandardV2 instances are authored now (D-310). M4 consolidates 5 → 3
(retire `ldapim-prod-eastus`; keep nonprod shared + dev, staging, StandardV2 prod).

**Variable:** `apim_sku_name` — NO DEFAULT (D-307); set explicitly per instance in `apim_instances`
map in each tfvars.

### 5.2 Named Value Secret Posture (T-03-27)

All APIM instances: named values with `secret=true` are authored with `value=null` — no literal
value in HCL or tfvars. Post-apply, values are set via portal or M3 KV-backed named value migration.
Only `ldapim-eastus-dev` has all non-secret named values (plain values authored from
`apim_security.json`).

---

## 6. App Gateway Module (modules/app-gateway)

| Variable | Nonprod value | Prod value | Evidence | M-milestone |
|----------|--------------|-----------|----------|-------------|
| `appgw_sku_name` | `Standard_v2` | `Standard_v2` | `appgw.json sku.name="Standard_v2"` (both gateways); `FINDINGS-DATA.md §AppGateway` | M3: change to `WAF_v2` |
| `appgw_sku_tier` | `Standard_v2` | `Standard_v2` | `appgw.json sku.tier="Standard_v2"` (both gateways) | M3: change to `WAF_v2` |
| `appgw_min_capacity` | `1` | `1` | `appgw.json autoscaleConfiguration.minCapacity=1` | — |
| `appgw_max_capacity` | `2` | `2` | `appgw.json autoscaleConfiguration.maxCapacity=2` | — |

**No-WAF posture:** Both gateways are `Standard_v2` (no WAF). This is a **HIGH security finding**
(`FINDINGS-DATA.md §AppGateway`, `02-Security-Findings.md F-AGW-01`). M3 sets both to `WAF_v2`
and configures WAF rules.

**Variable:** `appgw_sku_tier` — NO DEFAULT (D-307). Both tfvars set `Standard_v2` with evidence
citation; M3 is a tfvars diff changing to `WAF_v2`.

---

## 7. App Service Module (modules/app-service)

### 7.1 Plan SKU Differences

| Env | Plan name | SKU | Evidence |
|-----|-----------|-----|----------|
| dev | `plan-dev-eastus` (web), `plan-common-nonproduction-eastus` (fapp) | B2 | `appservice_plans.json nonprod plans` |
| qa | `plan-common-nonproduction-eastus` (web), `plan-qa-eastus` (fapp) | B2 (web), B1 (fapp) | `appservice_plans.json nonprod plans` |
| staging | `plan-staging-eastus` (shared prod plan) | P2v3 | `appservice_plans.json prod plan` |
| prod | `plan-prod-eastus` | P2v3 | `appservice_plans.json prod plan` |

**Variable:** `app_service_plans` — NO DEFAULT (D-307); set per scope/env in each tfvars.

### 7.2 App Inventory per Environment

| Env | Web apps | Function apps | Always-on |
|-----|----------|---------------|-----------|
| dev | 6 (app-db, data-access, mobile-backend, study-module, user-module, web-frontend) | 1 (fapp-process-response-dev-eastus) | `false` (B2 plan — Basic SKU doesn't guarantee always-on) |
| qa | 7 (dev set + storage-service-qa) | 1 (fapp-process-response-qa-eastus) | `false` |
| staging | 7 (app-db, data-access, mobile-backend, storage-service, study-module, user-module, web-frontend) | 1 | mixed (most `true` on P2v3) |
| prod | 9 (staging set + app-db-data-access, data-access-ui) | 1 | `true` (P2v3 plan) |

**Evidence:** `terraform/LD-NonProd-EastUS-V2/main.tf` (nonprod app HCL shapes);
`data/prod_webapps_config/` (prod live read after ACCESS-03 cleared).

### 7.3 Dev-Only Redis Cache (No Prod Redis)

The live estate has `rediscache-dev-eastus` (Basic SKU, single-node) in nonprod only. There is
**no prod Redis** — this is a known anti-pattern (cache misses on every prod request).

- **Dev Redis:** `rediscache-dev-eastus`, Basic SKU, 1 GB. Evidence: `data/redis.json`.
- **Prod Redis:** Not provisioned in the live estate. Not cloned in M1 (preserved posture).
- **Variable:** No explicit Redis variable authored in v1 — the Redis resource is not yet in the
  V3 module set (Redis is a Phase 4 / M2 add, or M3 remediation if deemed security-relevant).
- **M2/M3 action:** Provision a Standard SKU Redis in the prod scope (Basic SKU is single-node;
  Standard provides replication). Add `rediscache-<env>-eastus` to an `redis` module.

---

## 8. Networking Module (modules/networking)

### 8.1 Prod-Only Resources

| Resource | Nonprod | Prod | Variable | Evidence |
|----------|---------|------|----------|----------|
| NAT gateway | — (empty string) | `nat-prod-eastus` | `networking.nat_gateway_name` | `public_ips.json pip-nat-prod-eastus` |
| APIM StV2 private endpoint | — | `pe-apim-stv2-prod-eastus` | `networking.apim_private_endpoint_name` | `terraform/LD-Prod-EastUS-V2/main.tf` private endpoint block |
| Prod NSGs | 1 (APIM inbound) | 2 (APIM inbound + second NSG) | `networking.nsgs` map | `nsgs.json` |
| Public IPs | 2 (agw_common, apim_dev) | 4 (agw_prod, agw_staging, pip_nat, apim_stv2) | `networking.public_ips` map | `public_ips.json` |

**Variable pattern:** `nat_gateway_name = ""` in nonprod (module conditionally skips via
`count = var.nat_gateway_name != "" ? 1 : 0`). Non-empty string in prod activates the resource.

### 8.2 Subnet Count

| Scope | Subnet count | Evidence |
|-------|-------------|----------|
| Nonprod | 10 (default, common, app_service, function_app, apim_legacy, agw, keyvault, storage, sql, apim) | `vnets.json nonprod VNet subnets` |
| Prod | 14 (above + common_prod, agw_staging, apim_stv2_inbound, apim_stv2_outbound) | `vnets.json prod VNet subnets` |

---

## 9. Observability Module (modules/observability)

| Aspect | Nonprod | Prod | Variable | Evidence |
|--------|---------|------|----------|----------|
| Log Analytics workspace | — (none in nonprod) | `log-analytics-prod-eastus` (1 workspace) | `log_analytics_workspace_name = ""` nonprod / `"log-analytics-prod-eastus"` prod | `terraform/LD-Prod-EastUS-V2/main.tf` LA workspace block |
| App Insights instances | 1 (dev) | 2 (data-access-prod, apim-stv2) | `app_insights_instances` map | `terraform/LD-Prod-EastUS-V2/main.tf` App Insights blocks |
| Metric alerts authored | 9 (nonprod) | 21 (representative set from 54 total) | `alerts` map | `terraform/LD-Prod-EastUS-V2/main.tf` metric alert blocks |
| Action groups | 1 (nonprod) | 7 (prod) | `action_groups` map | `terraform/LD-Prod-EastUS-V2/main.tf` action group blocks |

Additional prod alerts can be added as tfvars map entries — no code change required (D-305
for_each pattern).

---

## 10. No-Default Posture Variable Surface (D-307 Complete Map)

This table lists every variable declared with NO `default` in the root `variables.tf` or module
`variables.tf` files. Each must be explicitly set in both tfvars or Terraform fails at plan time.

| Variable | Module / Root | Nonprod value | Prod value | Evidence |
|----------|--------------|--------------|-----------|----------|
| `sql_public_network_access_enabled` | root | `true` | `true` | `sql_detail.json publicNetworkAccess="Enabled"` |
| `sql_allow_all_azure_ips` | root | `true` | `true` | `sql_detail.json AllowAllWindowsAzureIps` |
| `sql_auditing_enabled` | root | `false` | `false` | `sql_detail.json auditPolicy.state="Disabled"` |
| `sql_azuread_only_auth` | root | `false` | `false` | `sql_detail.json azureAdOnlyAuthentication=false` |
| `kv_enable_rbac_authorization` | root | `true` | `false` | `keyvaults_detail.json enableRbacAuthorization` |
| `kv_network_default_action` | root | `Allow` | `Allow` | `keyvaults_detail.json networkAcls.defaultAction` |
| `kv_public_network_access_enabled` | root | `true` | `true` | `keyvaults_detail.json publicNetworkAccess` |
| `appgw_sku_tier` | modules/app-gateway | `Standard_v2` | `Standard_v2` | `appgw.json sku.tier` |
| `appgw_sku_name` | modules/app-gateway | `Standard_v2` | `Standard_v2` | `appgw.json sku.name` |
| `apim_sku_name` (per instance) | modules/apim | `Developer_1` (×2) | `Developer_1` (×2) / `StandardV2_1` (×1) | `apim_services.json sku` per instance |
| `apim_vnet_type` (per instance) | modules/apim | `Internal` (×2) | `Internal` / `None` / `External` | `apim_services.json virtualNetworkType` |
| `environments.*.sql_sku` | root | S1 (dev), S1 (qa) | S2 (staging), S3 (prod) | `sql_detail.json currentServiceObjectiveName` |
| `environments.*.app_plan_sku` | root | B2 (dev+qa) | P2v3 (staging+prod) | `appservice_plans.json sku.name` |
| `environments.*.storage_replication` | root | LRS (dev+qa) | LRS (staging), RA-GRS (prod) | `storage_accounts.json sku.name` |
| Per-account `allow_nested_items_to_be_public` | modules/storage | see §3.2 | see §3.2 | `storage_accounts.json allowBlobPublicAccess` |
| Per-account `shared_access_key_enabled` | modules/storage | see §3.2 | see §3.2 | `storage_accounts.json allowSharedKeyAccess` |
| Per-account `min_tls_version` | modules/storage | TLS1_2 (except ldstqaeastus=TLS1_0) | TLS1_2 (all) | `storage_accounts.json minimumTlsVersion` |
| Per-account `network_default_action` | modules/storage | Allow (all) | Allow (all) | `storage_accounts.json networkRuleSet.defaultAction` |
| `networking` object | root | 10 subnets, 1 NSG, 2 PIPs | 14 subnets, 2 NSGs, 4 PIPs | vnets.json, nsgs.json, public_ips.json |

---

## 11. M3 Remediation Checklist

The following variables need to be flipped in M3 (Security milestone). All are currently set to
preserve the V2 posture. M3 is a reviewed tfvars diff — no module code changes required.

| Variable | Current value (both) | M3 target | Impact |
|----------|---------------------|-----------|--------|
| `sql_public_network_access_enabled` | `true` | `false` | Closes public SQL data plane (CRITICAL) |
| `sql_allow_all_azure_ips` | `true` | `false` | Removes 0.0.0.0 firewall rule (requires VNet rule fix first — §2.1) |
| `sql_auditing_enabled` | `false` | `true` | Enables HIPAA audit trail (CRITICAL) |
| `sql_azuread_only_auth` | `false` | `true` | Disables SQL password auth |
| `kv_enable_rbac_authorization` (prod) | `false` | `true` | Migrates prod KV to RBAC |
| `kv_network_default_action` | `Allow` | `Deny` | Closes public KV data plane |
| Per-account `allow_nested_items_to_be_public` | `true` | `false` | Closes public blob access (all accounts) |
| Per-account `network_default_action` | `Allow` | `Deny` | Closes public storage data plane |
| `appgw_sku_tier` + `appgw_sku_name` | `Standard_v2` | `WAF_v2` | Enables WAF on both gateways |
| `ldstqaeastus.min_tls_version` | `TLS1_0` | `TLS1_2` | Fixes TLS exception on QA storage |

**M3 GATE:** Resolve `state=Failed` VNet rules on prod/staging SQL servers BEFORE setting
`sql_allow_all_azure_ips=false`. Otherwise prod SQL becomes unreachable.

---

*Evidence files: `data/FINDINGS-DATA.md`, `data/sql_detail.json`, `data/sql_vnet_rules.json`,
`data/storage_accounts.json`, `data/prod_storage_accounts.json`, `data/keyvaults_detail.json`,
`data/apim_services.json`, `data/apim_security.json`, `data/appgw.json`, `data/public_ips.json`,
`data/redis.json`, `terraform/LD-Prod-EastUS-V2/main.tf` (prod HCL shape reference),
`terraform/LD-NonProd-EastUS-V2/main.tf` (nonprod HCL shape reference)*

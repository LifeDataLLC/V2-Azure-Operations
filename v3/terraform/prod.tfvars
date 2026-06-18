# prod.tfvars — Prod scope variable values for LifeData V3
#
# SCOPE:  ld-prod-eastus-v3  (D-08 / D-12)
# STATE:  tfstate-prod / prod/terraform.tfstate  (D-205)
# USAGE:
#   terraform init   -backend-config=prod.backend.hcl
#   terraform plan   -var-file=prod.tfvars
#   terraform apply  -var-file=prod.tfvars
#
# AUTHORING STATUS (D-312):
#   Both tfvars are FULLY VALUED at Phase 3 end even though the prod scope is
#   idle in M1 (D-301a / D-07). Prod = source of truth (STRUCT-03). Authoring
#   the values now ≠ applying them — prod is applied in Phase 4 / later M1.
#
# SECURITY (T-03-02 / HIPAA / PHI):
#   NO secrets, passwords, connection strings, or SAS tokens here.
#   All sensitive values are stored in Azure Key Vault and referenced at runtime
#   via system-assigned managed identity (Shared 3 / CLAUDE.md §Constraints).
#
# EVIDENCE CITATIONS:
#   All posture values are derived from live reference data:
#     data/FINDINGS-DATA.md    — canonical config briefing
#     data/sql_detail.json     — SQL firewall/audit/auth posture
#     data/storage_accounts.json — storage replication/TLS/public-access
#     data/keyvaults_detail.json — KV auth model (RBAC vs access policies)
#     01-Infrastructure-Overview.md §3 — app service plan inventory
#     Live: az webapp config show (ACCESS-03 cleared)
#
# ---------------------------------------------------------------------------
# § Scope-level
# ---------------------------------------------------------------------------

resource_group_name = "ld-prod-eastus-v3"
subscription_id     = "e3e4d658-d924-4c2b-ad05-a4457e197527"

# Environments (D-301a): STAGING and PROD both disabled in v1 (prod scope idle in M1).
# Prod values ARE authored now (D-312) — they just don't get applied until Phase 4.
environments = {
  staging = {
    enabled             = false  # D-301a: prod scope idle in M1; applied in Phase 4
    sql_sku             = "S2"   # Standard S2 (50 DTU). Evidence: sql_detail.json staging server currentServiceObjectiveName="S2"
    app_plan_sku        = "P2v3" # Premium P2v3. Evidence: appservice_plans.json prod/staging plan sku.name="P2v3"
    storage_replication = "LRS"  # Locally-redundant for staging. Evidence: storage_accounts.json ststagingeastus accountType="Standard_LRS"
  }
  prod = {
    enabled             = false    # D-301a: prod scope idle in M1; applied in Phase 4
    sql_sku             = "S3"     # Standard S3 (100 DTU). Evidence: sql_detail.json prod server currentServiceObjectiveName="S3"
    app_plan_sku        = "P2v3"   # Premium P2v3. Evidence: appservice_plans.json prod plan sku.name="P2v3"
    storage_replication = "RA-GRS" # Read-access geo-redundant for prod. Evidence: storage_accounts.json stldprodeastus accountType="Standard_RAGRS"
  }
}

# ---------------------------------------------------------------------------
# § networking values (Plan 03-02)
# ---------------------------------------------------------------------------

# --- networking values (Plan 03-02) ---
# (Plan 03-02 adds VNet/subnet CIDR and NSG rule values here)
# --- end networking values ---

# ---------------------------------------------------------------------------
# § sql values (Plan 03-03)
# ---------------------------------------------------------------------------

# --- sql values (Plan 03-03) ---
# (Plan 03-03 adds SQL posture + firewall + audit values here)
# --- end sql values ---

# ---------------------------------------------------------------------------
# § storage values (Plan 03-04)
# ---------------------------------------------------------------------------

# --- storage values (Plan 03-04) ---
# (Plan 03-04 adds storage account map + posture values here)
# --- end storage values ---

# ---------------------------------------------------------------------------
# § keyvault values (Plan 03-05)
# ---------------------------------------------------------------------------

# --- keyvault values (Plan 03-05) ---
# kv_enable_rbac_authorization = false  # prod uses legacy access policies (FINDINGS-DATA.md §Key Vaults; an F-finding; M3 flips to true)
# (Plan 03-05 fills in this value and adds related KV posture values)
# --- end keyvault values ---

# ---------------------------------------------------------------------------
# § app-service values (Plan 03-06)
# ---------------------------------------------------------------------------

# --- app-service values (Plan 03-06) ---
# (Plan 03-06 adds app map (prod ~16 web + 2 func apps, from live az webapp reads) and plan SKU values here)
# --- end app-service values ---

# ---------------------------------------------------------------------------
# § apim values (Plan 03-07)
# ---------------------------------------------------------------------------

# --- apim values (Plan 03-07) ---
# (Plan 03-07 adds APIM instance name/SKU values here; prod has Developer + StandardV2 mid-migration)
# --- end apim values ---

# ---------------------------------------------------------------------------
# § app-gateway values (Plan 03-08)
# ---------------------------------------------------------------------------

# --- app-gateway values (Plan 03-08) ---
# (Plan 03-08 adds Application Gateway name/SKU/capacity values here; prod = Standard_v2, no WAF in M1)
# --- end app-gateway values ---

# ---------------------------------------------------------------------------
# § observability values (Plan 03-09)
# ---------------------------------------------------------------------------

# --- observability values (Plan 03-09) ---
# (Plan 03-09 adds Log Analytics/App Insights/alert map values here)
# --- end observability values ---

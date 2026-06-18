# nonprod.tfvars — Nonprod scope variable values for LifeData V3
#
# SCOPE:  ld-nonprod-eastus-v3  (D-08 / D-12)
# STATE:  tfstate-nonprod / nonprod/terraform.tfstate  (D-205)
# USAGE:
#   terraform init   -backend-config=nonprod.backend.hcl
#   terraform plan   -var-file=nonprod.tfvars
#   terraform apply  -var-file=nonprod.tfvars
#
# SECURITY (T-03-02 / HIPAA):
#   NO secrets, passwords, connection strings, or SAS tokens here.
#   Sensitive values are stored in Azure Key Vault and referenced at runtime
#   via system-assigned managed identity (Shared 3 / CLAUDE.md §Constraints).
#
# EVIDENCE CITATIONS:
#   All posture values are derived from live reference data:
#     data/FINDINGS-DATA.md    — canonical config briefing
#     data/sql_detail.json     — SQL firewall/audit/auth posture
#     data/storage_accounts.json — storage replication/TLS/public-access
#     data/keyvaults_detail.json — KV auth model (RBAC vs access policies)
#     01-Infrastructure-Overview.md §3 — app service plan inventory
#
# ---------------------------------------------------------------------------
# § Scope-level
# ---------------------------------------------------------------------------

resource_group_name = "ld-nonprod-eastus-v3"
subscription_id     = "e3e4d658-d924-4c2b-ad05-a4457e197527"

# Environments (D-301a): DEV enabled; QA disabled in v1.
# Each downstream module plan adds per-env fields to the environments map objects
# in its own § section below — the types must extend what variables.tf declares.
environments = {
  dev = {
    enabled             = true  # D-301a: DEV is the only active env in M1
    sql_sku             = "S1"  # Standard S1 (10 DTU). Evidence: sql_detail.json dev server currentServiceObjectiveName="S1"
    app_plan_sku        = "B2"  # Basic B2. Evidence: appservice_plans.json nonprod plan sku.name="B2"
    storage_replication = "LRS" # Locally-redundant. Evidence: storage_accounts.json ldstdeveastus accountType="Standard_LRS"
  }
  qa = {
    enabled             = false # D-301a: QA off in v1
    sql_sku             = "S1"  # Standard S1. Evidence: sql_detail.json qa server currentServiceObjectiveName="S1"
    app_plan_sku        = "B2"  # Basic B2. Evidence: appservice_plans.json (same nonprod plan)
    storage_replication = "LRS" # Locally-redundant. Evidence: storage_accounts.json ldstqaeastus accountType="Standard_LRS"
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
# kv_enable_rbac_authorization = true  # nonprod uses RBAC (FINDINGS-DATA.md §Key Vaults; keyvaults_detail.json)
# (Plan 03-05 fills in this value and adds related KV posture values)
# --- end keyvault values ---

# ---------------------------------------------------------------------------
# § app-service values (Plan 03-06)
# ---------------------------------------------------------------------------

# --- app-service values (Plan 03-06) ---
# (Plan 03-06 adds app map (per-env ~13 nonprod apps) and plan SKU values here)
# --- end app-service values ---

# ---------------------------------------------------------------------------
# § apim values (Plan 03-07)
# ---------------------------------------------------------------------------

# --- apim values (Plan 03-07) ---
# (Plan 03-07 adds APIM instance name/SKU and child config values here)
# --- end apim values ---

# ---------------------------------------------------------------------------
# § app-gateway values (Plan 03-08)
# ---------------------------------------------------------------------------

# --- app-gateway values (Plan 03-08) ---
# (Plan 03-08 adds Application Gateway name/SKU/capacity values here)
# --- end app-gateway values ---

# ---------------------------------------------------------------------------
# § observability values (Plan 03-09)
# ---------------------------------------------------------------------------

# --- observability values (Plan 03-09) ---
# (Plan 03-09 adds Log Analytics/App Insights/alert map values here)
# --- end observability values ---

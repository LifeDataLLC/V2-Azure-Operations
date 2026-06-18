# variables.tf — Root variable surface for the LifeData V3 Terraform root
#
# DESIGN PRINCIPLES:
#   D-307: NO `default` on any risk-bearing, divergence-bearing, or posture variable.
#          Every such value must be set explicitly in nonprod.tfvars / prod.tfvars,
#          backed by live-reference evidence (data/*.json, FINDINGS-DATA.md).
#          An unset value fails fast at `terraform plan` time — no hidden posture.
#   D-308: Invariant constants (identical across ALL envs/scopes) MAY carry a module-
#          level default/constant — e.g. location from data.azurerm_resource_group.this.location,
#          https_only=true, min_tls_version="1.2" (where uniform). That exception is
#          in the module layer, NOT here at root.
#   D-301: The `environments` map(object) carries per-env toggles + sizing. Only DEV
#          is enabled in v1 (D-301a).
#
# ORGANISATION:
#   § Scope-level (root): resource_group_name, subscription_id, environments map
#   § Per-module placeholder sections (D-304): each downstream module plan adds its
#     own variables in its labelled region — no merge conflicts across module plans.
#
# ---------------------------------------------------------------------------
# § Scope-level variables
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  description = <<-EOT
    Name of the pre-created resource group for this scope (D-311 / D-08).
    The RG is manually pre-created (ACCESS-02) and NEVER managed by Terraform.
    Values: nonprod = "ld-nonprod-eastus-v3", prod = "ld-prod-eastus-v3".
    Set per-scope in nonprod.tfvars / prod.tfvars.
  EOT
  type        = string

  validation {
    condition     = can(regex("^ld-(nonprod|prod)-eastus-v3$", var.resource_group_name))
    error_message = "resource_group_name must be 'ld-nonprod-eastus-v3' or 'ld-prod-eastus-v3' (D-08 lowercase v3 naming)."
  }
}

variable "subscription_id" {
  description = <<-EOT
    Azure subscription ID for the LifeData Pay-As-You-Go subscription.
    Value: e3e4d658-d924-4c2b-ad05-a4457e197527 (CLAUDE.md §Critical context).
    Set per-scope in nonprod.tfvars / prod.tfvars (D-307 no-default — explicit per reviewed tfvars).
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "subscription_id must be a valid lowercase UUID."
  }
}

variable "environments" {
  description = <<-EOT
    Per-environment workload toggles and sizing for this scope (D-301 / D-303).
    Keys: "dev", "qa" (nonprod scope) | "staging", "prod" (prod scope).

    Each entry carries:
      enabled         — master toggle (D-301a: only dev=true in v1; all others false)
      sql_sku         — Azure SQL DB service objective. Evidence: sql_detail.json / FINDINGS-DATA.md §SQL.
      app_plan_sku    — App Service Plan SKU. Evidence: appservice_plans.json / 01-Infrastructure-Overview.md §3.
      storage_replication — Storage account replication type. Evidence: storage_accounts.json.
                            prod=RA-GRS, nonprod/staging=LRS (FINDINGS-DATA.md §Storage).

    NO DEFAULT (D-307) — every value set explicitly per tfvars with cited evidence.
    Module plans add further per-env fields via their § placeholder sections below.
  EOT
  type = map(object({
    enabled             = bool
    sql_sku             = string
    app_plan_sku        = string
    storage_replication = string
  }))
  # NO default — fails fast at plan time if not set in tfvars (D-307)

  validation {
    condition = alltrue([
      for env, cfg in var.environments :
      contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS", "RA-GRS"], cfg.storage_replication)
    ])
    error_message = "storage_replication must be a valid Azure storage replication type (e.g. LRS, RA-GRS)."
  }
}

# ---------------------------------------------------------------------------
# § networking module variables (Plan 03-02)
# ---------------------------------------------------------------------------

# --- networking posture vars (Plan 03-02) ---
# (Module plan 03-02 adds VNet/subnet/NSG variables here)
# --- end networking posture vars ---

# ---------------------------------------------------------------------------
# § sql module variables (Plan 03-03)
# ---------------------------------------------------------------------------

# --- sql posture vars (Plan 03-03) ---
# (Module plan 03-03 adds SQL posture/firewall/audit variables here)
# --- end sql posture vars ---

# ---------------------------------------------------------------------------
# § storage module variables (Plan 03-04)
# ---------------------------------------------------------------------------

# --- storage posture vars (Plan 03-04) ---
# (Module plan 03-04 adds storage account posture variables here)
# --- end storage posture vars ---

# ---------------------------------------------------------------------------
# § keyvault module variables (Plan 03-05)
# ---------------------------------------------------------------------------

# --- keyvault posture vars (Plan 03-05) ---
# (Module plan 03-05 adds KV auth-model and network posture variables here)
# --- end keyvault posture vars ---

# ---------------------------------------------------------------------------
# § app-service module variables (Plan 03-06)
# ---------------------------------------------------------------------------

# --- app-service posture vars (Plan 03-06) ---
# (Module plan 03-06 adds app service plan + app map variables here)
# --- end app-service posture vars ---

# ---------------------------------------------------------------------------
# § apim module variables (Plan 03-07)
# ---------------------------------------------------------------------------

# --- apim posture vars (Plan 03-07) ---
# (Module plan 03-07 adds APIM SKU/instance/child config variables here)
# --- end apim posture vars ---

# ---------------------------------------------------------------------------
# § app-gateway module variables (Plan 03-08)
# ---------------------------------------------------------------------------

# --- app-gateway posture vars (Plan 03-08) ---
# (Module plan 03-08 adds Application Gateway SKU/WAF/capacity variables here)
# --- end app-gateway posture vars ---

# ---------------------------------------------------------------------------
# § observability module variables (Plan 03-09)
# ---------------------------------------------------------------------------

# --- observability posture vars (Plan 03-09) ---
# (Module plan 03-09 adds Log Analytics/App Insights/alert variables here)
# --- end observability posture vars ---

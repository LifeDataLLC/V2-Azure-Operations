# modules/sql/variables.tf — Per-env SQL module variable surface
#
# DESIGN PRINCIPLES:
#   D-307: NO `default` on any risk-bearing or posture variable.
#          Every SQL security-posture value is set explicitly in the per-scope
#          tfvars (nonprod.tfvars / prod.tfvars) with evidence cited.
#          An unset value fails fast at `terraform plan` — no hidden posture.
#   D-308: Invariant constants (uniform across all envs) may carry a default
#          in the module body (e.g. server version = "12.0") — NOT here.
#   D-307 no-default surface: sql_public_network_access_enabled,
#          sql_allow_all_azure_ips, sql_auditing_enabled, sql_azuread_only_auth.
#   D-315: sql_subnet_id supplied by module.networking.sql_subnet_id — the VNet
#          rule is explicitly authored (aztfexport omits these).
#   T-03-11: NO administrator_login_password anywhere — AAD admin + identity path.
#
# EVIDENCE REFERENCES:
#   data/sql_detail.json          — firewall rules, audit policy, AAD admin per server
#   data/sql_vnet_rules.json      — VNet rule names/subnets/states (D-315 source)
#   data/FINDINGS-DATA.md §SQL    — canonical posture summary (lines 30-40)

# ---------------------------------------------------------------------------
# § Identity / placement
# ---------------------------------------------------------------------------

variable "env" {
  description = <<-EOT
    Environment name (key from var.environments map).
    Values: "dev" | "qa" (nonprod scope) | "staging" | "prod" (prod scope).
    Drives resource names (sql-server-<env>-eastus) and any per-env branching.
  EOT
  type        = string

  validation {
    condition     = contains(["dev", "qa", "staging", "prod"], var.env)
    error_message = "env must be one of: dev, qa, staging, prod."
  }
}

variable "config" {
  description = <<-EOT
    Per-environment configuration object from var.environments[each.key].
    Contains: enabled, sql_sku, app_plan_sku, storage_replication.
    The enabled flag is handled by root for_each — it is not re-checked here.
    sql_sku: the service objective for azurerm_mssql_database
      (S1 for dev/qa, S2 for staging, S3 for prod — evidence: sql_detail.json).
  EOT
  type = object({
    enabled             = bool
    sql_sku             = string
    app_plan_sku        = string
    storage_replication = string
  })
}

variable "resource_group_name" {
  description = <<-EOT
    Name of the pre-created V3 resource group for this scope (D-311).
    Fed from data.azurerm_resource_group.this.name at root.
    Values: "ld-nonprod-eastus-v3" | "ld-prod-eastus-v3".
  EOT
  type        = string
}

variable "location" {
  description = <<-EOT
    Azure region for all SQL resources in this env.
    Fed from data.azurerm_resource_group.this.location at root (always "eastus").
  EOT
  type        = string
}

# ---------------------------------------------------------------------------
# § Networking — SQL VNet rule wiring (D-315 / AUTH-03)
# ---------------------------------------------------------------------------

variable "sql_subnet_id" {
  description = <<-EOT
    Subnet ID for the azurerm_mssql_virtual_network_rule (D-315 / AUTH-03).
    Fed from module.networking.sql_subnet_id at root.
    nonprod subnet: sql-nonproduction-eastus-subnet (10.0.9.0/24)
    prod subnet:    sql-production-eastus-subnet    (10.0.9.0/24)
    Evidence: sql_vnet_rules.json virtualNetworkSubnetId per server;
              modules/networking/outputs.tf sql_subnet_id.
  EOT
  type        = string
}

# ---------------------------------------------------------------------------
# § No-default posture variables (D-307 — every value explicit per tfvars)
# ---------------------------------------------------------------------------

variable "sql_public_network_access_enabled" {
  description = <<-EOT
    Controls whether the SQL server is reachable over the public internet.
    M1 value: true (all 4 servers — Enabled). M3 flips to false.
    Evidence: sql_detail.json publicNetworkAccess="Enabled" on all servers;
              FINDINGS-DATA.md §SQL F1 (public data plane — CRITICAL finding).
    NO DEFAULT (D-307) — public exposure is an explicit risk decision.
  EOT
  type        = bool

  validation {
    condition     = var.sql_public_network_access_enabled == true || var.sql_public_network_access_enabled == false
    error_message = "sql_public_network_access_enabled must be explicitly set to true or false."
  }
}

variable "sql_allow_all_azure_ips" {
  description = <<-EOT
    When true, authors the AllowAllWindowsAzureIps firewall rule (0.0.0.0-0.0.0.0).
    This rule grants all Azure-hosted services access to the SQL server.
    M1 value: true (present on all 4 servers). M3 removes it (replace with VNet rules only).
    Evidence: sql_detail.json firewallRules[0].name="AllowAllWindowsAzureIps" on all servers;
              terraform/LD-NonProd-EastUS-V2/main.tf:1495-1500 (analog);
              FINDINGS-DATA.md §SQL F2 (open firewall — HIGH finding).
    NO DEFAULT (D-307) — lateral-movement risk decision.
  EOT
  type        = bool
}

variable "sql_auditing_enabled" {
  description = <<-EOT
    Controls whether server-level and database-level extended auditing is enabled.
    M1 value: false (all 4 servers — Disabled). M3 flips to true (HIPAA ≥365 days).
    Evidence: sql_detail.json auditPolicy.state="Disabled" on all 4 servers;
              terraform/LD-NonProd-EastUS-V2/main.tf:1490-1493 enabled=false;
              FINDINGS-DATA.md §SQL F3 (auditing disabled — HIGH/HIPAA finding).
    NO DEFAULT (D-307) — HIPAA compliance decision; unset = plan failure.
  EOT
  type        = bool
}

variable "sql_azuread_only_auth" {
  description = <<-EOT
    Controls whether Azure AD-only authentication is enforced on the SQL server
    (azuread_authentication_only in the azuread_administrator block).
    M1 value: false (all 4 servers — SQL login auth still enabled in parallel).
    M3 flips to true after confirming managed identity data-plane role assignments exist.
    Evidence: sql_detail.json aadAdmins.azureAdOnlyAuthentication=false on all servers;
              FINDINGS-DATA.md §SQL F4 (parallel secret auth paths — AUTH finding).
    NO DEFAULT (D-307) — auth model is a deliberate security decision.
  EOT
  type        = bool
}

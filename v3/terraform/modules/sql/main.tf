# modules/sql/main.tf — Per-env SQL stack for LifeData V3
#
# DESIGN PRINCIPLES:
#   D-303:  One module body consumed via root `for_each = local.enabled_envs`.
#           One SQL server + DB + all policies per enabled environment.
#   D-305:  Architectural fidelity — all resource TYPES reproduced; click-ops
#           noise (developer-home / transient firewall rules) DROPPED.
#           Dropped: Amalesh_Home, AmaleshHome, Ishtiaque*, Marcus, ClientIPAddress_*
#   D-307:  No-default posture variables gate every security-relevant attribute.
#   D-311:  resource_group_name = var.resource_group_name (fed from data source).
#           No azurerm_resource_group resource block anywhere in v3.
#   D-315:  azurerm_mssql_virtual_network_rule explicitly authored from
#           data/sql_vnet_rules.json (aztfexport omits these).
#   T-03-11 / Shared 3: NO administrator_login_password — AAD admin + system-
#           assigned identity is the auth path. SQL login exists in the live
#           estate (administrator_login = "amalesh") but no password literal
#           appears in HCL or tfvars (PHI/HIPAA).
#
# RESOURCE TYPES IN THIS MODULE:
#   azurerm_mssql_server
#   azurerm_mssql_database
#   azurerm_mssql_server_transparent_data_encryption   (TDE — always on)
#   azurerm_mssql_server_extended_auditing_policy      (D-307: enabled = var.sql_auditing_enabled)
#   azurerm_mssql_database_extended_auditing_policy    (master DB + user DB)
#   azurerm_mssql_server_microsoft_support_auditing_policy
#   azurerm_mssql_firewall_rule                        (AllowAllWindowsAzureIps — D-307 gated)
#   azurerm_mssql_virtual_network_rule                 (D-315 — explicit, reconstructed)
#   azurerm_mssql_server_security_alert_policy
#   azurerm_mssql_server_vulnerability_assessment
#
# VNet rule states from data/sql_vnet_rules.json:
#   dev   (newVnetRule1): state=Ready   — nonprod subnet
#   qa    (newVnetRule1): state=Ready   — nonprod subnet
#   prod  (DBVnetRule):   state=Failed  — prod subnet (WHATS-DIFFERENT Pitfall 5)
#   staging (DBVnetRule): state=Failed  — prod subnet (WHATS-DIFFERENT Pitfall 5)
# The Failed state is a live-estate condition (service endpoint not provisioned),
# not a config error — authored as-is; M3 prerequisite before removing
# AllowAllWindowsAzureIps.
#
# EVIDENCE:
#   data/sql_detail.json          — per-server firewall/audit/auth/TDE shape
#   data/sql_vnet_rules.json      — VNet rule names, subnets, states
#   data/FINDINGS-DATA.md §SQL    — canonical posture summary
#   terraform/LD-NonProd-EastUS-V2/main.tf:1449-1572 (dev analog)

# ---------------------------------------------------------------------------
# § SQL Server
# ---------------------------------------------------------------------------

resource "azurerm_mssql_server" "this" {
  # Semantic name: sql-server-<env>-eastus (live naming convention)
  # Evidence: sql_detail.json name="sql-server-dev-eastus" / "sql-server-qa-eastus" / etc.
  name                = "sql-server-${var.env}-eastus"
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = "12.0" # D-308: invariant across all 4 servers (sql_detail.json version=12.0)

  # D-307 no-default: current posture = Enabled (public) on all 4 servers.
  # M1 preserves. M3 flips to false.
  # Evidence: sql_detail.json publicNetworkAccess="Enabled"; FINDINGS-DATA.md §SQL F1.
  public_network_access_enabled = var.sql_public_network_access_enabled

  # AAD Administrator block (Shared 3 / T-03-11).
  # administrator_login present for backward-compat with existing connections but
  # NO password literal — PHI/HIPAA. D-307: azuread_authentication_only = var.sql_azuread_only_auth.
  # Evidence: sql_detail.json aadAdmins.login / sid / tenantId (uniform across all 4 servers).
  administrator_login = "amalesh" # existing login name; no password here (T-03-11)

  azuread_administrator {
    login_username              = "Amalesh.Debnath@lifedatacorp.com"
    object_id                   = "60915d49-12fd-4828-8d80-81fdf7d1c101" # evidence: sql_detail.json aadAdmins.sid
    tenant_id                   = "b504d3d4-ffb7-40f4-b25a-97ccb238fde3" # evidence: CLAUDE.md tenant
    azuread_authentication_only = var.sql_azuread_only_auth              # D-307: M1=false, M3 flips
  }

  # System-assigned managed identity (Shared 3 / D-304).
  # All 4 SQL servers use system-assigned identity in the live estate.
  # Evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1463-1465.
  identity {
    type = "SystemAssigned"
  }

  # express_vulnerability_assessment: enabled on all 4 servers in the live estate.
  # Evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1451 express_vulnerability_assessment_enabled=true.
  express_vulnerability_assessment_enabled = true
}

# ---------------------------------------------------------------------------
# § SQL Database
# ---------------------------------------------------------------------------

resource "azurerm_mssql_database" "this" {
  # Database name per env:
  #   dev     → sqldb-dev2   (evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1473)
  #   qa      → sqldb-qa     (evidence: terraform/LD-NonProd-EastUS-V2/main.tf qa analog)
  #   staging → sqldb-staging (evidence: terraform/LD-Prod-EastUS-V2/main.tf staging analog)
  #   prod    → sqldb-prod    (evidence: terraform/LD-Prod-EastUS-V2/main.tf prod analog)
  # The naming diverges from strict convention for dev (sqldb-dev2); preserved for fidelity (D-305).
  name      = var.env == "dev" ? "sqldb-dev2" : "sqldb-${var.env}"
  server_id = azurerm_mssql_server.this.id

  # SKU (service objective) is per-env via var.config.sql_sku — no-default (D-307).
  # dev=S1, qa=S1, staging=S2, prod=S3. Evidence: sql_detail.json currentServiceObjectiveName.
  sku_name = var.config.sql_sku

  # Local redundant storage for SQL backups (evidence: nonprod TDE analog uses Local).
  # Prod uses Local as well — TDE storage separate from replication type.
  storage_account_type = "Local"
}

# ---------------------------------------------------------------------------
# § TDE (Transparent Data Encryption) — always on (D-308 invariant)
# ---------------------------------------------------------------------------

resource "azurerm_mssql_server_transparent_data_encryption" "this" {
  # TDE is on (default) across all 4 servers — no toggle needed (D-308 constant).
  # Evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1487-1489 (res-1907).
  server_id = azurerm_mssql_server.this.id
}

# ---------------------------------------------------------------------------
# § Extended Auditing Policies (D-307: enabled = var.sql_auditing_enabled)
# ---------------------------------------------------------------------------

# Server-level extended auditing policy.
# M1: enabled=false (all 4). M3: flip to true + wire Log Analytics workspace.
# Evidence: sql_detail.json auditPolicy.state="Disabled"; analog main.tf:1490-1493.
resource "azurerm_mssql_server_extended_auditing_policy" "this" {
  server_id              = azurerm_mssql_server.this.id
  enabled                = var.sql_auditing_enabled # D-307: M1=false, M3 flips
  log_monitoring_enabled = false                    # wired to Log Analytics in M3
}

# Master database extended auditing policy.
# Evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1467-1471 (res-1883) — master DB policy.
resource "azurerm_mssql_database_extended_auditing_policy" "master" {
  # The master database ID is derived from the server ID (implicit in the live estate).
  # Reference: analog uses a hardcoded subscription path for the master DB;
  # we compute from server_id by convention. The master DB is always present.
  database_id            = "${azurerm_mssql_server.this.id}/databases/master"
  enabled                = var.sql_auditing_enabled
  log_monitoring_enabled = false
}

# User database extended auditing policy.
# Evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1477-1481 (res-1900).
resource "azurerm_mssql_database_extended_auditing_policy" "db" {
  database_id            = azurerm_mssql_database.this.id
  enabled                = var.sql_auditing_enabled
  log_monitoring_enabled = false
}

# Microsoft Support auditing policy (Defender for SQL).
# Evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1482-1486 (res-1906).
resource "azurerm_mssql_server_microsoft_support_auditing_policy" "this" {
  server_id              = azurerm_mssql_server.this.id
  enabled                = var.sql_auditing_enabled
  log_monitoring_enabled = false
}

# ---------------------------------------------------------------------------
# § Firewall Rule — AllowAllWindowsAzureIps (D-307 gated)
# ---------------------------------------------------------------------------

# AllowAllWindowsAzureIps: present on all 4 servers in M1; M3 removes it.
# Rule: start_ip=0.0.0.0, end_ip=0.0.0.0 (Azure convention for "all Azure services").
# This is gated so the config is explicit: var.sql_allow_all_azure_ips=true preserves
# the open firewall; false omits it (removing the risk).
# Evidence: sql_detail.json firewallRules[0].name="AllowAllWindowsAzureIps" all 4 servers;
#           FINDINGS-DATA.md §SQL F2; analog main.tf:1495-1500.
# D-305: All developer-home / transient rules (Amalesh_Home, AmaleshHome,
#        Ishtiaque*, Marcus, ClientIPAddress_*) are DROPPED — click-ops noise.

resource "azurerm_mssql_firewall_rule" "allow_all_azure_ips" {
  count = var.sql_allow_all_azure_ips ? 1 : 0

  name             = "AllowAllWindowsAzureIps"
  server_id        = azurerm_mssql_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# ---------------------------------------------------------------------------
# § VNet Rule — D-315 (explicit authoring; aztfexport omits these)
# ---------------------------------------------------------------------------

# Reconstructed from data/sql_vnet_rules.json (D-315 / AUTH-03).
# Rule names per scope:
#   dev/qa    → "newVnetRule1" (state=Ready, nonprod subnet)
#   staging/prod → "DBVnetRule" (state=Failed, prod subnet — Pitfall 5 WHATS-DIFFERENT)
# subnet_id is fed from module.networking.sql_subnet_id at root (scope-correct).
# Note: the state=Failed on prod/staging is a live-estate condition (service endpoint
# not yet provisioned in the prod VNet subnet). Author the rule config as-is;
# M3 resolves the Failed state before removing AllowAllWindowsAzureIps.
resource "azurerm_mssql_virtual_network_rule" "this" {
  # dev/qa use "newVnetRule1"; staging/prod use "DBVnetRule" — from sql_vnet_rules.json
  name = contains(["dev", "qa"], var.env) ? "newVnetRule1" : "DBVnetRule"

  server_id = azurerm_mssql_server.this.id
  subnet_id = var.sql_subnet_id # fed from module.networking.sql_subnet_id
}

# ---------------------------------------------------------------------------
# § Security Alert Policy
# ---------------------------------------------------------------------------

# Defender for SQL — server-level security alert policy.
# State=Enabled on all 4 servers in the live estate.
# Evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1556-1563 (res-1919).
resource "azurerm_mssql_server_security_alert_policy" "this" {
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mssql_server.this.name
  state               = "Enabled"

  depends_on = [azurerm_mssql_server.this]
}

# ---------------------------------------------------------------------------
# § Vulnerability Assessment
# ---------------------------------------------------------------------------

# Server-level vulnerability assessment (Defender for SQL VA).
# storage_container_path = "" in the live estate (Defender-managed storage, not custom).
# Evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1569-1572 (res-1922).
resource "azurerm_mssql_server_vulnerability_assessment" "this" {
  server_security_alert_policy_id = azurerm_mssql_server_security_alert_policy.this.id
  storage_container_path          = "" # Defender-managed (evidence: analog main.tf:1572)
}

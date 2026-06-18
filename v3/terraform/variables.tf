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

# --- networking posture vars (Plan 03-03) ---

variable "networking" {
  description = <<-EOT
    Networking configuration object for the scope's VNet, subnets, NSGs, public IPs,
    private DNS zones, and prod-only NAT gateway / APIM private endpoint.

    Passed directly to the networking module (module "networking"). Every field maps
    1:1 to a module variable — see modules/networking/variables.tf for per-field
    evidence citations.

    NO DEFAULT (D-307) — VNet/subnet shape is connectivity-critical and differs
    between scopes (vnet_name, subnet names). Values are set explicitly in
    nonprod.tfvars (vnet-common-nonproduction-eastus) and prod.tfvars
    (vnet-production-eastus) with evidence from data/vnets.json.
  EOT
  type = object({
    vnet_name          = string
    vnet_address_space = list(string)

    # Subnet map — key = logical role (sql, storage, keyvault, app_service, function_app,
    # apim, agw, and any scope-specific subnets).
    subnets = map(object({
      name                              = string
      address_prefix                    = string
      service_endpoints                 = list(string)
      delegation_name                   = string
      delegation_service                = string
      private_endpoint_network_policies = string
      default_outbound_access_enabled   = bool
    }))

    # NSG map — key = logical NSG role (apim, stv2_outbound, ...).
    nsgs = map(object({
      name       = string
      subnet_key = string
      security_rules = list(object({
        name                       = string
        priority                   = number
        direction                  = string
        access                     = string
        protocol                   = string
        source_port_range          = string
        destination_port_range     = string
        destination_port_ranges    = list(string)
        source_address_prefix      = string
        destination_address_prefix = string
        description                = string
      }))
    }))

    # Public IP map — key = logical role (agw_common, nat_stv2, ...).
    public_ips = map(object({
      name                    = string
      allocation_method       = string
      sku                     = string
      idle_timeout_in_minutes = number
      zones                   = list(string)
      domain_name_label       = string
    }))

    # Private DNS zone map — key = logical role (redis, apim_stv2, ...).
    private_dns_zones = map(object({
      zone_name = string
      link_name = string
    }))

    # NAT gateway (prod only — set to "" on nonprod).
    nat_gateway_name       = string
    nat_gateway_pip_key    = string
    nat_gateway_subnet_key = string

    # APIM StV2 private endpoint (prod only — set to "" on nonprod).
    apim_private_endpoint_name        = string
    apim_private_endpoint_subnet_key  = string
    apim_private_endpoint_resource_id = string
    apim_private_dns_zone_key         = string
  })
  # NO default — fails fast at plan time if not set in tfvars (D-307).
}

# --- end networking posture vars ---

# ---------------------------------------------------------------------------
# § sql module variables (Plan 03-03)
# ---------------------------------------------------------------------------

# --- sql posture vars (Plan 03-04) ---
# D-307: NO `default` on any of these — each value set explicitly in both tfvars
# with cited evidence from data/sql_detail.json and data/FINDINGS-DATA.md §SQL.
# M1 preserves current (insecure) posture; M3 flips values via reviewed tfvars diff.

variable "sql_public_network_access_enabled" {
  description = <<-EOT
    Controls public network access on all SQL servers in this scope.
    M1 value: true (Enabled on all 4 servers). M3 flips to false.
    Evidence: sql_detail.json publicNetworkAccess="Enabled" (all servers);
              FINDINGS-DATA.md §SQL F1 (public data plane — CRITICAL finding).
    NO DEFAULT (D-307) — public exposure is an explicit per-scope risk decision.
  EOT
  type        = bool
}

variable "sql_allow_all_azure_ips" {
  description = <<-EOT
    When true, the sql module authors the AllowAllWindowsAzureIps firewall rule
    (start/end IP = 0.0.0.0) on every SQL server in this scope.
    M1 value: true (rule present on all 4 servers). M3 removes it.
    Evidence: sql_detail.json firewallRules[0].name="AllowAllWindowsAzureIps" (all servers);
              FINDINGS-DATA.md §SQL F2 (open firewall — HIGH finding).
    NO DEFAULT (D-307) — lateral-movement risk decision.
  EOT
  type        = bool
}

variable "sql_auditing_enabled" {
  description = <<-EOT
    Controls server-level and database-level extended auditing on all SQL servers.
    M1 value: false (Disabled on all 4 servers). M3 flips to true (HIPAA ≥365 days).
    Evidence: sql_detail.json auditPolicy.state="Disabled" (all 4 servers);
              FINDINGS-DATA.md §SQL F3 (auditing disabled — HIGH/HIPAA finding).
    NO DEFAULT (D-307) — HIPAA compliance decision; unset = plan failure.
  EOT
  type        = bool
}

variable "sql_azuread_only_auth" {
  description = <<-EOT
    Controls whether Azure AD-only authentication is enforced (disables SQL login auth).
    M1 value: false (SQL login auth still enabled in parallel on all 4 servers).
    M3 flips to true after confirming managed identity data-plane roles exist.
    Evidence: sql_detail.json aadAdmins.azureAdOnlyAuthentication=false (all servers);
              FINDINGS-DATA.md §SQL F4 (parallel secret auth paths — AUTH finding).
    NO DEFAULT (D-307) — auth model is a deliberate security decision.
  EOT
  type        = bool
}

# --- end sql posture vars ---

# ---------------------------------------------------------------------------
# § storage module variables (Plan 03-04)
# ---------------------------------------------------------------------------

# --- storage posture vars (Plan 03-05) ---
# D-307: NO `default` on any of these — each value set explicitly in both tfvars
# with cited evidence from data/storage_accounts.json, data/prod_storage_accounts.json,
# and data/FINDINGS-DATA.md §Storage.
# M1 preserves current posture; M3 flips values via reviewed tfvars diff.
# T-03-16: posture vars ensure no silent blob-public / shared-key / Allow-default.
# T-03-18: min_tls_version is per-account (ldstqaeastus=TLS1_0 exception).

variable "storage_shared_accounts" {
  description = <<-EOT
    Map of scope-shared storage accounts (D-302 — deploy once per scope, no for_each).
    nonprod scope: ldfstnonproductioneastus (B2C/func scope-shared storage).
    prod scope:    lifelatapublic (public CDN storage, scope-shared).
    Key = logical account key; value = per-account config object.
    See modules/storage/variables.tf for the full object schema.
    NO DEFAULT (D-307) — posture settings are per-account evidence-backed decisions.
  EOT
  type = map(object({
    name                            = string
    location                        = string
    account_replication_type        = string
    allow_nested_items_to_be_public = bool
    shared_access_key_enabled       = bool
    min_tls_version                 = string
    network_default_action          = string
    large_file_shares_enabled       = bool
    sas_expiry_period               = string
    containers                      = list(string)
    container_access_types          = map(string)
    queues                          = list(string)
    tables                          = list(string)
    file_shares                     = map(number)
    queue_logging_enabled           = bool
  }))
  # NO default — set per scope in nonprod.tfvars / prod.tfvars (D-307)
}

variable "storage_env_accounts" {
  description = <<-EOT
    Map of per-environment storage account maps (D-301/D-303 — one entry per env key).
    Outer key = environment key (matching var.environments keys: "dev", "qa", "staging", "prod").
    Inner map = accounts map for that environment (same schema as storage_shared_accounts).
    Root calls module "storage_env" with for_each = local.enabled_envs, then passes
    lookup(var.storage_env_accounts, each.key, {}) to the accounts input.
    dev:     ldstdeveastus
    qa:      ldstqaeastus + stqanonproductioneastus
    staging: ststagingeastus
    prod:    stldprodeastus + stldprodeastus2
    Evidence: data/storage_accounts.json (nonprod), data/prod_storage_accounts.json (prod).
    NO DEFAULT (D-307) — posture settings are per-account evidence-backed decisions.
  EOT
  type = map(map(object({
    name                            = string
    location                        = string
    account_replication_type        = string
    allow_nested_items_to_be_public = bool
    shared_access_key_enabled       = bool
    min_tls_version                 = string
    network_default_action          = string
    large_file_shares_enabled       = bool
    sas_expiry_period               = string
    containers                      = list(string)
    container_access_types          = map(string)
    queues                          = list(string)
    tables                          = list(string)
    file_shares                     = map(number)
    queue_logging_enabled           = bool
  })))
  # NO default — set per scope in nonprod.tfvars / prod.tfvars (D-307)
}

# --- end storage posture vars ---

# ---------------------------------------------------------------------------
# § keyvault module variables (Plan 03-05)
# ---------------------------------------------------------------------------

# --- keyvault posture vars (Plan 03-05) ---
# D-306: kv_enable_rbac_authorization is THE divergence anchor (no-default bool).
# D-307: NO `default` on any of these — each value set explicitly in both tfvars
# with cited evidence from data/keyvaults_detail.json and data/FINDINGS-DATA.md §Key Vaults.
# T-03-17: kv_enable_rbac_authorization no-default; prod=false/nonprod=true explicit; M3 flips prod→true.

variable "kv_name" {
  description = <<-EOT
    Name of the scope's Key Vault (D-302 — one vault per scope).
    nonprod: "kvnonproductioneastus"  (evidence: keyvaults_detail.json)
    prod:    "kvproductioneastus"     (evidence: keyvaults_detail.json)
    NO DEFAULT (D-307) — vault name is connectivity-critical.
  EOT
  type        = string
}

variable "kv_sku_name" {
  description = <<-EOT
    SKU of the Key Vault. Both vaults use "standard".
    Evidence: keyvaults_detail.json properties.sku.name="Standard" (both vaults).
    NO DEFAULT (D-307) — explicit per tfvars even for uniform values.
  EOT
  type        = string

  validation {
    condition     = contains(["standard", "premium"], var.kv_sku_name)
    error_message = "kv_sku_name must be 'standard' or 'premium'."
  }
}

variable "kv_enable_rbac_authorization" {
  description = <<-EOT
    D-306 divergence anchor (T-03-17): KV authentication model.
    nonprod.tfvars = true  — kvnonproductioneastus uses RBAC.
                             Evidence: keyvaults_detail.json enableRbacAuthorization=true.
    prod.tfvars    = false — kvproductioneastus uses legacy access policies (F-finding).
                             Evidence: keyvaults_detail.json enableRbacAuthorization=false.
    M3 flips prod→true after confirming role assignments exist.
    NO DEFAULT (D-307) — auth model is a deliberate per-scope security decision.
  EOT
  type        = bool
}

variable "kv_network_default_action" {
  description = <<-EOT
    Network ACL default action for the Key Vault.
    M1 value: "Allow" on both scopes.
    Evidence: keyvaults_detail.json networkAcls.defaultAction="Allow" (both vaults).
    M3 flips to "Deny". NO DEFAULT (D-307).
  EOT
  type        = string

  validation {
    condition     = contains(["Allow", "Deny"], var.kv_network_default_action)
    error_message = "kv_network_default_action must be 'Allow' or 'Deny'."
  }
}

variable "kv_public_network_access_enabled" {
  description = <<-EOT
    Whether public network access is enabled for the Key Vault.
    M1 value: true on both scopes.
    Evidence: keyvaults_detail.json publicNetworkAccess="Enabled" (both vaults).
    M3 flips to false. NO DEFAULT (D-307).
  EOT
  type        = bool
}

variable "kv_access_policies" {
  description = <<-EOT
    Access policy objects for the Key Vault.
    Used only when kv_enable_rbac_authorization=false (prod scope, M1).
    Evidence: keyvaults_detail.json kvproductioneastus.properties.accessPolicies (8 entries).
    In RBAC mode (nonprod), set to []. NO DEFAULT (D-307).
  EOT
  type = list(object({
    object_id               = string
    tenant_id               = string
    secret_permissions      = list(string)
    key_permissions         = list(string)
    certificate_permissions = list(string)
  }))
}

# --- end keyvault posture vars ---

# ---------------------------------------------------------------------------
# § app-service module variables (Plan 03-06)
# ---------------------------------------------------------------------------

# --- app-service posture vars (Plan 03-06) ---
# D-307: NO `default` on any of these — each value set explicitly in both tfvars
# with cited evidence from data/appservice_plans.json and data/prod_webapps_config/.
# D-303: web_app_maps and function_app_maps are the per-env parameterization surface.
# T-03-19: web_app_map / function_app_map values MUST NOT contain literal secrets.
# T-03-22: per-app posture fields (always_on, min_tls_version) are no-default map fields.

variable "app_service_plans" {
  description = <<-EOT
    Per-environment App Service Plan names and SKUs (D-307 no-default).
    Key = environment key (matching var.environments keys: "dev", "qa", "staging", "prod").
    Each entry carries web_plan_name, web_plan_sku, function_plan_name, function_plan_sku.

    Evidence (appservice_plans.json):
      dev:     web=plan-dev-eastus(B2),      func=plan-common-nonproduction-eastus(B2)
      qa:      web=plan-common-nonproduction-eastus(B2), func=plan-qa-eastus(B1)
      staging: web=plan-staging-eastus(B2),  func=plan-staging-eastus(B2)
      prod:    web=plan-prod-eastus(P1mv3),  func=plan-prod-eastus(P1mv3)

    NO DEFAULT (D-307) — plan names and SKUs differ between envs and scopes.
  EOT
  type = map(object({
    web_plan_name      = string
    web_plan_sku       = string
    function_plan_name = string
    function_plan_sku  = string
  }))
  # NO default — set per scope in nonprod.tfvars / prod.tfvars (D-307)
}

variable "web_app_maps" {
  description = <<-EOT
    Per-environment web app maps (D-303 for_each — the per-env app surface).
    Outer key = environment key (matching var.environments keys).
    Inner map  = per-app config objects; key = Azure resource name (e.g. "app-db-dev-eastus").

    Each app object carries:
      always_on        — bool.   Evidence: data/prod_webapps_config/*.json alwaysOn.
      app_command_line — string. Startup command (pm2 for node, "" for dotnet).
      dotnet_version   — string or null. .NET version; null for node apps.
      node_version     — string or null. Node.js version; null for dotnet apps.

    NOTE: min_tls_version is NOT a valid azurerm_linux_web_app argument in azurerm v4.
    TLS posture is enforced via https_only=true (D-308 constant). Live-read values
    (all = "1.2") are documented in tfvars comments for audit trail only.

    D-303: Add/remove an app = a tfvars map edit; no code change required.
    D-305: hidden-link:/app-insights tags NOT present (dropped in module).
    T-03-19: NO literal secrets/connection strings in this map — KV references only.
    NO DEFAULT (D-307) — per-app posture and stack version are divergence-bearing.
  EOT
  type = map(map(object({
    always_on        = bool
    app_command_line = string
    dotnet_version   = string
    node_version     = string
  })))
  # NO default — set per scope in nonprod.tfvars / prod.tfvars (D-307)
}

variable "function_app_maps" {
  description = <<-EOT
    Per-environment function app maps (D-303 for_each hybrid).
    Outer key = environment key (matching var.environments keys).
    Inner map  = per-app config objects; key = Azure resource name
                 (e.g. "fapp-process-response-dev-eastus").

    Each app object carries:
      always_on                  — bool. Evidence: prod live read alwaysOn=true.
      node_version               — string. Node version for application_stack.
                                   Evidence: prod live read Node|22.
      storage_account_name       — string. Not sensitive; bound to function host.
      storage_access_key_kv_name — string. KV secret name for storage account access key.
                                   Module builds @Microsoft.KeyVault() reference. T-03-19.
      builtin_logging_enabled    — bool. false for all prod function apps (nonprod HCL evidence).
      client_certificate_mode    — string. "Required" for nonprod (HCL evidence).

    NOTE: min_tls_version is NOT a valid azurerm_linux_function_app argument in azurerm v4.
    TLS posture enforced via https_only=true. Live-read values (1.2 / 1.3 for stag fapp)
    are documented in tfvars comments for audit trail.

    T-03-19: storage_access_key_kv_name is a secret NAME, not the secret VALUE.
    NO DEFAULT (D-307) — per-app posture and storage binding are divergence-bearing.
  EOT
  type = map(map(object({
    always_on                  = bool
    node_version               = string
    storage_account_name       = string
    storage_access_key_kv_name = string
    builtin_logging_enabled    = bool
    client_certificate_mode    = string
  })))
  # NO default — set per scope in nonprod.tfvars / prod.tfvars (D-307)
}

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

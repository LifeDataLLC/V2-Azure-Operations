# main.tf — Root configuration for the LifeData V3 Terraform estate
#
# DESIGN PRINCIPLES:
#   D-311: The pre-created resource group is REFERENCED via a data source, never
#          managed. No `azurerm_resource_group` resource block exists anywhere in v3.
#   D-301: Four named environments (dev/qa/staging/prod) are toggled via the
#          `environments` map; `enabled_envs` filters to active ones for per-env
#          module instantiation.
#   D-302: Scope-shared resources (networking, keyvault, apim, observability,
#          app-gateway) are called ONCE — no for_each. Per-env workload resources
#          (sql, storage, app-service) use for_each over enabled_envs.
#   D-304: Module stubs are present now; each module plan un-comments and fills
#          its own delimited block. The scaffold validates with only the data source
#          and locals active.
#
# AUTH-01:
#   This config NEVER imports or manages existing V2 resources. The V2 RGs
#   (LD-Prod-EastUS-V2, LD-NonProd-EastUS-V2) are read-only authoring references.
#
# ---------------------------------------------------------------------------
# § Data sources
# ---------------------------------------------------------------------------

# Reference the pre-created V3 resource group (D-311 / Pattern 4).
# Supplies .name and .location to all module calls below.
# Requires the CI SPN (or human identity) to have read on the target RG (ACCESS-02).
data "azurerm_resource_group" "this" {
  name = var.resource_group_name # ld-nonprod-eastus-v3 | ld-prod-eastus-v3 (per tfvars)
}

# ---------------------------------------------------------------------------
# § Locals — environment toggle (D-301 / Pattern 2)
# ---------------------------------------------------------------------------

locals {
  # Filtered map of environments with enabled = true.
  # In v1: nonprod scope → only { dev = { ... } }; prod scope → {} (all off).
  # Per-env modules use for_each = local.enabled_envs so toggling an env on/off
  # adds/removes that env's resources without re-indexing others (stable addresses).
  enabled_envs = { for name, cfg in var.environments : name => cfg if cfg.enabled }
}

# ---------------------------------------------------------------------------
# § Scope-shared module calls (deploy once per scope — D-302)
# ---------------------------------------------------------------------------

# --- networking module call (Plan 03-03) ---
# Scope-shared: ONE call per scope, no for_each (D-302).
# var.networking is a structured object set per-scope in nonprod.tfvars / prod.tfvars.
# All inputs are NO-DEFAULT (D-307) — subnet CIDRs/names are connectivity-critical.
module "networking" {
  source = "./modules/networking"

  # Scope identity — from the pre-created RG data source (D-311).
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location

  # VNet
  vnet_name          = var.networking.vnet_name
  vnet_address_space = var.networking.vnet_address_space

  # Subnets, NSGs, Public IPs, Private DNS zones
  subnets           = var.networking.subnets
  nsgs              = var.networking.nsgs
  public_ips        = var.networking.public_ips
  private_dns_zones = var.networking.private_dns_zones

  # NAT gateway (prod only — "" on nonprod)
  nat_gateway_name       = var.networking.nat_gateway_name
  nat_gateway_pip_key    = var.networking.nat_gateway_pip_key
  nat_gateway_subnet_key = var.networking.nat_gateway_subnet_key

  # APIM StV2 private endpoint (prod only — "" on nonprod)
  apim_private_endpoint_name        = var.networking.apim_private_endpoint_name
  apim_private_endpoint_subnet_key  = var.networking.apim_private_endpoint_subnet_key
  apim_private_endpoint_resource_id = var.networking.apim_private_endpoint_resource_id
  apim_private_dns_zone_key         = var.networking.apim_private_dns_zone_key
}
# --- end networking module call ---

# --- keyvault module call (Plan 03-05) ---
# Scope-shared: ONE vault per scope, no for_each (D-302).
# D-306: kv_enable_rbac_authorization is the divergence anchor (prod=false, nonprod=true).
# D-307: all posture vars no-default, set explicitly in each tfvars.
module "keyvault" {
  source = "./modules/keyvault"

  # Scope placement (D-311)
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location

  # Vault identity (D-307 no-default — vault name is connectivity-critical)
  kv_name     = var.kv_name
  kv_sku_name = var.kv_sku_name

  # D-306: The RBAC-vs-access-policy divergence anchor (T-03-17)
  # prod.tfvars=false (legacy access-policy mode), nonprod.tfvars=true (RBAC mode)
  kv_enable_rbac_authorization = var.kv_enable_rbac_authorization

  # D-307 network posture (M1=Allow/Enabled; M3 flips to Deny/false)
  kv_network_default_action        = var.kv_network_default_action
  kv_public_network_access_enabled = var.kv_public_network_access_enabled

  # Access policies (used only when kv_enable_rbac_authorization=false — prod scope in M1)
  kv_access_policies = var.kv_access_policies

  # Networking wiring — KV subnet from networking module (module.networking.keyvault_subnet_id)
  keyvault_subnet_id = module.networking.keyvault_subnet_id
}
# --- end keyvault module call ---

# --- apim module call (Plan 03-07) ---
# module "apim" {
#   source              = "./modules/apim"
#   resource_group_name = data.azurerm_resource_group.this.name
#   location            = data.azurerm_resource_group.this.location
#   # APIM SKU/instance/child config variables wired by Plan 03-07
# }
# --- end apim module call ---

# --- app-gateway module call (Plan 03-07) ---
# Scope-shared: ONE gateway per scope, no for_each (D-302).
# D-307 / T-03-23: appgw_sku_name + appgw_sku_tier are no-default posture variables.
#   M1: Standard_v2 (no WAF — posture preserved per plan boundary).
#   M3: WAF_v2 flip via tfvars diff — no code change needed.
# T-03-25: SSL certs accessed via KV managed identity (Shared 3) — no literal cert data.
module "app_gateway" {
  source = "./modules/app-gateway"

  # Scope placement (D-311)
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location

  # Gateway identity (D-307 no-default)
  agw_name          = var.agw_name
  agw_identity_name = var.agw_identity_name

  # SKU / posture (D-307 / T-03-23 — NO default; M1=Standard_v2 no WAF, M3→WAF_v2)
  appgw_sku_name   = var.appgw_sku_name
  appgw_sku_tier   = var.appgw_sku_tier
  agw_min_capacity = var.agw_min_capacity
  agw_max_capacity = var.agw_max_capacity

  # Networking wiring — subnet + public IP from module.networking outputs
  # agw_public_ip_key selects which PIP key in var.networking.public_ips maps to the AGW PIP.
  # prod: "agw_prod" → pip-prod-eastus; nonprod: "agw_common" → pip-common-nonproduction-eastus.
  agw_subnet_id    = module.networking.agw_subnet_id
  agw_public_ip_id = module.networking.public_ip_ids[var.agw_public_ip_key]

  # Key Vault wiring — for AGW identity role assignment (T-03-25)
  key_vault_id = module.keyvault.key_vault_id

  # Backend / routing configuration (map-driven D-305)
  backend_address_pools = var.agw_backend_address_pools
  backend_http_settings = var.agw_backend_http_settings
  http_listeners        = var.agw_http_listeners
  probes                = var.agw_probes
  request_routing_rules = var.agw_request_routing_rules
  rewrite_rule_sets     = var.agw_rewrite_rule_sets
  ssl_certificates      = var.agw_ssl_certificates
}
# --- end app-gateway module call ---

# --- observability module call (Plan 03-07) ---
# Scope-shared: ONE call per scope, no for_each (D-302).
# D-305: LA tables noise dropped; alerts via for_each over map (not N blocks).
# T-03-24: alert scopes reference NEW estate via alert_scope_ids map (never old LD-*-EastUS-V2 paths).
# T-03-25: app_insights connection_string output only — no instrumentation key literals.
module "observability" {
  source = "./modules/observability"

  # Scope placement (D-311)
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location

  # LA workspace (prod only — "" to skip on nonprod)
  log_analytics_workspace_name = var.log_analytics_workspace_name
  saved_searches               = var.saved_searches

  # App Insights instances
  app_insights_instances = var.app_insights_instances

  # Action groups
  action_groups = var.action_groups

  # Alert scope IDs — new estate resource IDs (T-03-24)
  # Wired from module outputs + app_gateway output.
  # Per-env app service / SQL scope IDs assembled via merge of enabled_envs outputs.
  alert_scope_ids = merge(
    # App Gateway scope
    { "app_gateway" = module.app_gateway.gateway_id },
    # Per-env app service plan IDs (web + function) — one entry per enabled env
    { for env, svc in module.app_service : "web_plan_${env}" => svc.web_plan_id },
    { for env, svc in module.app_service : "function_plan_${env}" => svc.function_plan_id },
    # Per-env web app IDs (flattened: "app_<app_name>" → id)
    merge([for env, svc in module.app_service : { for name, id in svc.web_app_ids : "app_${name}" => id }]...),
    # Per-env function app IDs
    merge([for env, svc in module.app_service : { for name, id in svc.function_app_ids : "fapp_${name}" => id }]...),
    # Per-env SQL server IDs
    { for env, sql in module.sql : "sql_${env}" => sql.server_id },
    # Additional explicit scope IDs from tfvars (APIM, etc., not yet wired via module)
    var.additional_alert_scope_ids,
  )

  # Alert definitions
  alerts = var.alerts

  # Smart detector rules
  smart_detector_rules = var.smart_detector_rules
}
# --- end observability module call ---

# ---------------------------------------------------------------------------
# § Per-env module calls (for_each over enabled_envs — D-301/303)
# ---------------------------------------------------------------------------

# --- sql module call (Plan 03-04) ---
# Per-env: for_each over local.enabled_envs (D-301a: dev only in v1).
# D-303: one SQL stack per enabled env — add/remove env = a tfvars edit.
# D-315: sql_subnet_id fed from module.networking.sql_subnet_id (explicit VNet rule wiring).
# D-307: all posture vars fed from root-level variables (set per tfvars, no defaults).
module "sql" {
  source   = "./modules/sql"
  for_each = local.enabled_envs # one SQL stack per enabled env (D-301a: dev only in v1)

  # Environment identity
  env    = each.key
  config = each.value

  # Scope placement (D-311)
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location

  # SQL subnet for VNet rule (D-315 / AUTH-03)
  # module.networking.sql_subnet_id resolves to the scope-correct sql-*-eastus-subnet.
  sql_subnet_id = module.networking.sql_subnet_id

  # No-default posture variables (D-307) — set explicitly per scope in tfvars.
  # M1 preserves current posture; M3 flips values via reviewed tfvars diff.
  sql_public_network_access_enabled = var.sql_public_network_access_enabled
  sql_allow_all_azure_ips           = var.sql_allow_all_azure_ips
  sql_auditing_enabled              = var.sql_auditing_enabled
  sql_azuread_only_auth             = var.sql_azuread_only_auth
}
# --- end sql module call ---

# --- storage module call (Plan 03-05) ---
# Hybrid model (D-302): scope-shared accounts called once; per-env accounts via for_each.
# D-303: accounts map is the parameterization surface — add/remove an account = a tfvars edit.
# D-307: all posture values are per-account no-default vars set in tfvars.

# Scope-shared storage accounts (deploy once per scope regardless of enabled envs)
# nonprod: ldfstnonproductioneastus (B2C/func storage, scope-shared)
# prod:    lifelatapublic (public CDN storage, scope-shared)
module "storage_shared" {
  source = "./modules/storage"

  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
  storage_subnet_id   = module.networking.storage_subnet_id

  # Scope-shared accounts map (D-302) — set per scope in tfvars
  accounts = var.storage_shared_accounts
}

# Per-environment storage accounts (one call per enabled env — D-301/D-303)
# nonprod dev:     ldstdeveastus + stqanonproductioneastus (QA)
# nonprod qa:      ldstqaeastus
# prod staging:    ststagingeastus
# prod prod:       stldprodeastus + stldprodeastus2
module "storage_env" {
  source   = "./modules/storage"
  for_each = local.enabled_envs

  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
  storage_subnet_id   = module.networking.storage_subnet_id

  # Per-env accounts map — each env key maps to its accounts in tfvars
  accounts = lookup(var.storage_env_accounts, each.key, {})
}
# --- end storage module call ---

# --- app-service module call (Plan 03-06) ---
# Per-env: for_each over local.enabled_envs (D-301a: dev only in v1).
# D-303: one app-service stack per enabled env — add/remove env = a tfvars edit.
# D-307: all posture/plan vars fed from root-level variables (set per tfvars, no defaults).
# T-03-19: app_settings use KV references via system-assigned MI — no literal secrets.
# T-03-20: module issues azurerm_role_assignment (Key Vault Secrets User) for each app MI.
module "app_service" {
  source   = "./modules/app-service"
  for_each = local.enabled_envs # one app-service stack per enabled env (D-301a: dev only in v1)

  # Environment identity
  env = each.key

  # Scope placement (D-311)
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location

  # App Service Plan names + SKUs (D-307 no-default — diverge between envs and scopes)
  web_plan_name      = var.app_service_plans[each.key].web_plan_name
  web_plan_sku       = var.app_service_plans[each.key].web_plan_sku
  function_plan_name = var.app_service_plans[each.key].function_plan_name
  function_plan_sku  = var.app_service_plans[each.key].function_plan_sku

  # Per-env app maps (D-303 for_each inside the module)
  web_app_map      = lookup(var.web_app_maps, each.key, {})
  function_app_map = lookup(var.function_app_maps, each.key, {})

  # Networking wiring — subnet IDs from module.networking
  app_subnet_id          = module.networking.app_subnet_id
  function_app_subnet_id = module.networking.function_app_subnet_id

  # Key Vault wiring — KV id + uri from module.keyvault (T-03-19/T-03-20)
  key_vault_id  = module.keyvault.key_vault_id
  key_vault_uri = module.keyvault.key_vault_uri
}
# --- end app-service module call ---

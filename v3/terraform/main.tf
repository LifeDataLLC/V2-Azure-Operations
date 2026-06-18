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
# module "keyvault" {
#   source              = "./modules/keyvault"
#   resource_group_name = data.azurerm_resource_group.this.name
#   location            = data.azurerm_resource_group.this.location
#   # keyvault posture variables wired by Plan 03-05
# }
# --- end keyvault module call ---

# --- apim module call (Plan 03-07) ---
# module "apim" {
#   source              = "./modules/apim"
#   resource_group_name = data.azurerm_resource_group.this.name
#   location            = data.azurerm_resource_group.this.location
#   # APIM SKU/instance/child config variables wired by Plan 03-07
# }
# --- end apim module call ---

# --- app-gateway module call (Plan 03-08) ---
# module "app_gateway" {
#   source              = "./modules/app-gateway"
#   resource_group_name = data.azurerm_resource_group.this.name
#   location            = data.azurerm_resource_group.this.location
#   # Application Gateway SKU/WAF variables wired by Plan 03-08
# }
# --- end app-gateway module call ---

# --- observability module call (Plan 03-09) ---
# module "observability" {
#   source              = "./modules/observability"
#   resource_group_name = data.azurerm_resource_group.this.name
#   location            = data.azurerm_resource_group.this.location
#   # Log Analytics/App Insights/alert variables wired by Plan 03-09
# }
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

# --- storage module call (Plan 03-04) ---
# module "storage" {
#   source   = "./modules/storage"
#   for_each = local.enabled_envs
#
#   env                 = each.key
#   config              = each.value
#   resource_group_name = data.azurerm_resource_group.this.name
#   location            = data.azurerm_resource_group.this.location
#   # storage posture variables wired by Plan 03-04
# }
# --- end storage module call ---

# --- app-service module call (Plan 03-06) ---
# module "app_service" {
#   source   = "./modules/app-service"
#   for_each = local.enabled_envs
#
#   env                 = each.key
#   config              = each.value
#   resource_group_name = data.azurerm_resource_group.this.name
#   location            = data.azurerm_resource_group.this.location
#   # app map + plan SKU variables wired by Plan 03-06
# }
# --- end app-service module call ---

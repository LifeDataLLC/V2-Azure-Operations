# modules/app-service/variables.tf — App Service module variable declarations
#
# DESIGN PRINCIPLES:
#   D-303: app_map and function_app_map are the per-env parameterization surface.
#          Add/remove an app = a tfvars edit. One module body for all envs.
#   D-307: NO `default` on divergence-bearing or posture vars (SKU, per-app config).
#   D-308: https_only = true is a module constant (invariant everywhere).
#   Shared 3: identity { type="SystemAssigned" } is wired unconditionally.
#   T-03-19: No secret literals — app_settings use KV references only.
#   T-03-20: system-assigned MI on every app; key_vault_id supplied for role-assignment.
#   T-03-21: Prod shape from data/prod_webapps_config/ live read (STRUCT-03).
#   T-03-22: Per-app posture (ftps/minTls/alwaysOn) as no-default map fields.
#
# PLAN SECTIONS:
#   § Scope placement (RG, location)
#   § Service plan configuration (per env name/SKU — no-default)
#   § Web app map (for_each — D-303)
#   § Function app map (for_each — D-303 hybrid; different subnet)
#   § Networking wiring (subnet IDs from module.networking)
#   § Key Vault wiring (KV id/uri for reference construction — T-03-19)

# ---------------------------------------------------------------------------
# § Scope placement
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  description = <<-EOT
    Name of the pre-created resource group for this scope (D-311).
    Supplied by root main.tf from data.azurerm_resource_group.this.name.
  EOT
  type        = string
}

variable "location" {
  description = <<-EOT
    Azure region for all resources in this module instance.
    Supplied by root main.tf from data.azurerm_resource_group.this.location.
    Always "eastus" for the LifeData estate (CLAUDE.md §Critical context).
  EOT
  type        = string
}

variable "env" {
  description = <<-EOT
    Environment key for this module instance (e.g. "dev", "qa", "staging", "prod").
    Matches the key in local.enabled_envs and var.environments in the root.
  EOT
  type        = string
}

# ---------------------------------------------------------------------------
# § Service plan configuration (no-default — D-307)
# ---------------------------------------------------------------------------

variable "web_plan_name" {
  description = <<-EOT
    Name of the App Service Plan for web apps in this environment.
    dev:     plan-dev-eastus     (evidence: appservice_plans.json name="plan-dev-eastus")
    qa:      plan-common-nonproduction-eastus
    staging: plan-staging-eastus (evidence: appservice_plans.json name="plan-staging-eastus")
    prod:    plan-prod-eastus    (evidence: appservice_plans.json name="plan-prod-eastus")
    NO DEFAULT (D-307) — plan name is connectivity-critical.
  EOT
  type        = string
}

variable "web_plan_sku" {
  description = <<-EOT
    SKU name for the web App Service Plan.
    dev:     B2  (evidence: appservice_plans.json plan-dev-eastus sku.name="B2")
    qa:      B2  (evidence: appservice_plans.json plan-common-nonproduction-eastus sku.name="B2")
    staging: B2  (evidence: appservice_plans.json plan-staging-eastus sku.name="B2")
    prod:    P1mv3 (evidence: appservice_plans.json plan-prod-eastus sku.name="P1mv3")
    NO DEFAULT (D-307) — SKU diverges between scopes (cost decision).
  EOT
  type        = string
}

variable "function_plan_name" {
  description = <<-EOT
    Name of the App Service Plan for function apps in this environment.
    dev:     plan-common-nonproduction-eastus (shared with QA web apps)
             (evidence: terraform/LD-NonProd-EastUS-V2/main.tf:2803 service_plan_id=res-2123)
    qa:      plan-qa-eastus
             (evidence: terraform/LD-NonProd-EastUS-V2/main.tf:3055 service_plan_id=res-2125)
    staging: plan-staging-eastus (same as staging web plan — function is on shared plan)
             (evidence: appservice_plans.json plan-staging-eastus numberOfSites=8)
    prod:    plan-prod-eastus (same as prod web plan — function uses prod plan)
    NO DEFAULT (D-307).
  EOT
  type        = string
}

variable "function_plan_sku" {
  description = <<-EOT
    SKU for the function App Service Plan.
    dev:  B2  (evidence: appservice_plans.json plan-common-nonproduction-eastus sku.name="B2")
    qa:   B1  (evidence: appservice_plans.json plan-qa-eastus sku.name="B1")
    staging: B2
    prod: P1mv3
    NO DEFAULT (D-307).
  EOT
  type        = string
}

# ---------------------------------------------------------------------------
# § Web app map (D-303 for_each — per-env app map)
# ---------------------------------------------------------------------------

variable "web_app_map" {
  description = <<-EOT
    Map of web apps for this environment (D-303 for_each).
    Key   = Azure resource name (e.g. "app-db-dev-eastus").
    Value = per-app configuration object.

    Fields:
      always_on       — bool. Evidence: data/prod_webapps_config/*.json alwaysOn field.
                        Prod = true (all). Staging = mixed (per live read). Dev = false.
      app_command_line — string. Startup command (empty for dotnet apps; pm2 for node).
                        Evidence: prod live read appCommandLine field.
      dotnet_version   — string or null. .NET version if a dotnet app (e.g. "8.0").
                        Evidence: data/prod_webapps_config linuxFxVersion="DOTNETCORE|8.0".
                        Set null for node apps.
      node_version     — string or null. Node.js version if a node app (e.g. "22-lts", "22", "24-lts").
                        Evidence: data/prod_webapps_config linuxFxVersion="NODE|22-lts".
                        Set null for dotnet apps.
      Exactly one of dotnet_version / node_version must be non-null per app (provider constraint).

    Constants (D-308 — uniform across all envs):
      https_only            = true   (all apps per live read)
      ftps_state            = "FtpsOnly" (all prod apps per live read)
      vnet_route_all_enabled = true  (all apps per live read vnetRouteAllEnabled=true)
      identity.type         = "SystemAssigned" (Shared 3)

    NO DEFAULT (D-307) — per-app divergence in always_on, stack version.
  EOT
  type = map(object({
    always_on        = bool
    app_command_line = string
    dotnet_version   = string
    node_version     = string
  }))
  # NO default — set per-env in nonprod.tfvars / prod.tfvars (D-307)
}

# ---------------------------------------------------------------------------
# § Function app map (D-303 hybrid — function apps use a different subnet)
# ---------------------------------------------------------------------------

variable "function_app_map" {
  description = <<-EOT
    Map of function apps for this environment (D-303 for_each, hybrid).
    Key   = Azure resource name (e.g. "fapp-process-response-dev-eastus").
    Value = per-app configuration object.

    Function apps differ from web apps in:
      - Use azurerm_linux_function_app (not azurerm_linux_web_app)
      - Use function_app_subnet_id (module.networking.function_app_subnet_id)
      - Require storage_account_name + storage_access_key_kv_secret_name (KV ref)
      - node_version in application_stack (if Node runtime)
      - builtin_logging_enabled controls function host logging

    Fields:
      always_on                  — bool. Evidence: prod live read fapp-process-res-prod alwaysOn=true.
      node_version               — string. Node version for application_stack. e.g. "22".
                                   Evidence: prod live read linuxFxVersion="Node|22" / "NODE|22".
      NOTE: min_tls_version is NOT a valid azurerm_linux_function_app attribute (provider v4).
            TLS posture is enforced via https_only=true. Live-read min_tls_version values
            (1.2 / 1.3 for fapp-process-res-stag) are documented in tfvars comments only.
      storage_account_name       — string. Evidence: nonprod HCL fapp storage_account_name.
                                   NO secret literals — storage_account_access_key_secret_name
                                   is used for KV reference.
      storage_access_key_kv_name — string. KV secret name holding the storage access key.
                                   The module builds the @Microsoft.KeyVault() reference.
                                   T-03-19: never a literal key in HCL/tfvars.
      builtin_logging_enabled    — bool. false for all prod function apps (evidence: nonprod HCL).
      client_certificate_mode    — string. "Required" for nonprod (HCL evidence); "Optional" for prod.

    Constants (D-308): https_only=true, ftps_state="FtpsOnly", vnet_route_all_enabled=true,
    identity.type="SystemAssigned".
    NO DEFAULT (D-307) — per-app divergence.
  EOT
  type = map(object({
    always_on                  = bool
    node_version               = string
    storage_account_name       = string
    storage_access_key_kv_name = string
    builtin_logging_enabled    = bool
    client_certificate_mode    = string
  }))
  # NO default — set per-env in nonprod.tfvars / prod.tfvars (D-307)
}

# ---------------------------------------------------------------------------
# § Networking wiring
# ---------------------------------------------------------------------------

variable "app_subnet_id" {
  description = <<-EOT
    Subnet ID for web app VNet integration (Microsoft.Web/serverFarms delegation).
    Supplied by module.networking.app_subnet_id.
    nonprod: app-service-nonproduction-eastus-subnet (10.0.3.0/24)
    prod:    app-service-production-eastus-subnet    (10.0.3.0/24)
    Evidence: vnets.json subnets, networking module outputs.tf.
  EOT
  type        = string
}

variable "function_app_subnet_id" {
  description = <<-EOT
    Subnet ID for function app VNet integration (Microsoft.Web/serverFarms delegation).
    Supplied by module.networking.function_app_subnet_id.
    nonprod: function-app-nonproduction-eastus-subnet (10.0.4.0/24)
    prod:    function-app-production-eastus-subnet    (10.0.4.0/24)
    Evidence: vnets.json subnets, networking module outputs.tf.
  EOT
  type        = string
}

# ---------------------------------------------------------------------------
# § Key Vault wiring (T-03-19 — KV references for app_settings)
# ---------------------------------------------------------------------------

variable "key_vault_id" {
  description = <<-EOT
    Resource ID of the scope's Key Vault.
    Supplied by module.keyvault.key_vault_id.
    Used for azurerm_role_assignment (Key Vault Secrets User on the new KV)
    for the system-assigned identity of each app.
    T-03-20: every app's MI needs the Secrets User role to resolve @Microsoft.KeyVault() refs.
  EOT
  type        = string
}

variable "key_vault_uri" {
  description = <<-EOT
    Vault URI for the scope's Key Vault.
    Supplied by module.keyvault.key_vault_uri.
    Example: "https://kvnonproductioneastus.vault.azure.net/"
    Used to construct @Microsoft.KeyVault(VaultName=...,SecretName=...) reference strings.
    T-03-19: no literal secret values — all sensitive app_settings use KV references.
  EOT
  type        = string
}

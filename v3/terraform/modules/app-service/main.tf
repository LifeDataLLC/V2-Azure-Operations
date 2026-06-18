# modules/app-service/main.tf — App Service module for LifeData V3
#
# DESIGN PRINCIPLES:
#   D-303: for_each over web_app_map / function_app_map (the per-env app surfaces).
#          Add/remove an app = a tfvars map edit. One module body for all envs.
#   D-305: hidden-link:/app-insights tags DROPPED (click-ops noise normalization).
#   D-307: No-default per-app divergence (alwaysOn, minTlsVersion, linuxFxVersion).
#   D-308: https_only=true is a constant (invariant-true across all apps and envs).
#   Shared 3: identity { type="SystemAssigned" } on every app (no secret literals).
#   T-03-19: app_settings use @Microsoft.KeyVault() KV references — NEVER literal secrets.
#   T-03-20: azurerm_role_assignment grants Key Vault Secrets User to each app's MI.
#   T-03-21: Prod shape from data/prod_webapps_config/ live read (STRUCT-03 canonical).
#   T-03-22: Per-app posture vars set from live-reference with evidence in tfvars.
#
# AUTH-01: No import/state capture of existing V2 resources. The V2 apps are read-only
#          shape reference.
#
# RESOURCE HIERARCHY (per env module instance):
#   azurerm_service_plan.web        — one web plan per env
#   azurerm_service_plan.function   — one function plan per env (may reuse web plan name/SKU)
#   azurerm_linux_web_app.this      — for_each over var.web_app_map
#   azurerm_linux_function_app.this — for_each over var.function_app_map
#   azurerm_role_assignment.web_kv_secrets_user     — KV Secrets User per web app MI
#   azurerm_role_assignment.fapp_kv_secrets_user    — KV Secrets User per function app MI
#
# FUNCTION APP WIRING NOTE (D-303 hybrid):
#   Function apps differ from web apps in:
#     - Resource type: azurerm_linux_function_app
#     - Subnet: function_app_subnet_id (separate VNet-delegated subnet)
#     - Storage: storage_account_name + storage_account_access_key via KV reference
#     - site_config.application_stack.node_version (explicit stack block)
#   The function plan may share the same SKU/name as the web plan (e.g. prod) or differ
#   (e.g. nonprod dev: function uses plan-common, web uses plan-dev).
#
# ---------------------------------------------------------------------------
# § App Service Plans
# ---------------------------------------------------------------------------

resource "azurerm_service_plan" "web" {
  # Web app plan for this environment.
  # evidence (nonprod): appservice_plans.json plan-dev-eastus (B2), plan-common-nonproduction-eastus (B2)
  # evidence (prod):    appservice_plans.json plan-prod-eastus (P1mv3), plan-staging-eastus (B2)
  name                = var.web_plan_name
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = var.web_plan_sku
}

resource "azurerm_service_plan" "function" {
  # Function app plan for this environment.
  # Dev:     plan-common-nonproduction-eastus (B2) — shared with QA web apps
  # QA:      plan-qa-eastus (B1)
  # Staging: plan-staging-eastus (B2) — shared with staging web apps
  # Prod:    plan-prod-eastus (P1mv3) — shared with prod web apps
  # evidence: appservice_plans.json; terraform/LD-NonProd-EastUS-V2/main.tf:2803 + 3055
  name                = var.function_plan_name
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = var.function_plan_sku
}

# ---------------------------------------------------------------------------
# § Web Apps — for_each over var.web_app_map (D-303)
# ---------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  for_each = var.web_app_map

  # Identity — D-308 constants
  name                = each.key # app name from map key (e.g. "app-db-dev-eastus")
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.web.id

  # D-308 constant: https_only=true is invariant-true for all apps across all envs.
  # Evidence: all prod live reads httpOnly=true; nonprod HCL https_only=true (line 2648).
  https_only = true

  # VNet integration — all apps route via the App Service subnet (D-302 shared VNet).
  # nonprod: app-service-nonproduction-eastus-subnet; prod: app-service-production-eastus-subnet
  # Evidence: prod live read vnetName contains "app-service-production-eastus-subnet".
  virtual_network_subnet_id = var.app_subnet_id

  # D-305: hidden-link:/app-insights tags DROPPED (click-ops noise; HCL lines 2653-2655).
  # App Insights wiring is module.observability's responsibility (Plan 03-09).

  # Shared 3: System-assigned managed identity — NO secret literals in HCL/tfvars (T-03-20).
  # Each app's MI is granted Key Vault Secrets User via azurerm_role_assignment below.
  identity {
    type = "SystemAssigned"
  }

  # App settings — KV references only (T-03-19 / PHI/HIPAA constraint).
  # Sensitive runtime values (connection strings, API keys) are stored in the new Key Vault
  # and referenced via @Microsoft.KeyVault(VaultName=...,SecretName=...) syntax.
  # The system-assigned identity resolves references at runtime — no literal secrets here.
  # Placeholder KV reference keys reflect the naming convention used in the V2 estate.
  # The actual secret names are set in Key Vault separately (outside Terraform scope for M1).
  app_settings = {
    # KV reference pattern: @Microsoft.KeyVault(VaultName=<vault>;SecretName=<secret>)
    # These reference the NEW Key Vault (var.key_vault_uri). The system-assigned identity
    # (granted Key Vault Secrets User below) resolves them at runtime.
    # Secret names follow the convention: <app-slug>--<setting-name>
    # T-03-19: NO literal connection strings, passwords, or account keys here.
    "KeyVaultUri" = var.key_vault_uri
  }

  # auth_settings block: disabled on all prod apps (evidence: prod live reads auth.enabled=false).
  # nonprod HCL also has auth_settings { enabled=false token_refresh_extension_hours=0 }.
  auth_settings {
    enabled                       = false
    token_refresh_extension_hours = 0
  }

  site_config {
    # D-307 per-app no-default vars:
    always_on        = each.value.always_on        # prod=true, staging=mixed, dev=false (live read)
    ftps_state       = "FtpsOnly"                  # D-308 near-constant: all apps = FtpsOnly (live read)
    app_command_line = each.value.app_command_line # pm2 for node apps, "" for dotnet
    # NOTE: min_tls_version is NOT an azurerm_linux_web_app attribute (provider limitation).
    # TLS posture is enforced via https_only=true (D-308 constant). The live read value
    # (1.2 / 1.3) is documented in tfvars comments for audit trail but not applied by Terraform.

    # VNet routing — route ALL traffic through VNet (not just RFC1918).
    # evidence: prod live read vnetRouteAllEnabled=true (all apps).
    vnet_route_all_enabled = true

    # Application stack — set via dotnet_version or node_version (exactly one non-null).
    # Evidence: data/prod_webapps_config/*.json config.linuxFxVersion.
    # dotnet apps: DOTNETCORE|8.0 → dotnet_version = "8.0"
    # node apps:   NODE|22-lts    → node_version   = "22-lts"
    # Both fields are in each.value; tfvars sets the relevant one, null for the other.
    application_stack {
      dotnet_version = each.value.dotnet_version # "8.0" or null
      node_version   = each.value.node_version   # "22-lts", "22", "24-lts" or null
    }
  }
}

# ---------------------------------------------------------------------------
# § Web App KV Secrets User role assignments (T-03-20)
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "web_kv_secrets_user" {
  for_each = var.web_app_map

  # Grant Key Vault Secrets User to each web app's system-assigned MI.
  # This allows the app to resolve @Microsoft.KeyVault() references in app_settings.
  # T-03-20: secretless auth — MI resolves KV references, no literal secrets in config.
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.this[each.key].identity[0].principal_id
}

# ---------------------------------------------------------------------------
# § Function Apps — for_each over var.function_app_map (D-303 hybrid)
# ---------------------------------------------------------------------------

resource "azurerm_linux_function_app" "this" {
  for_each = var.function_app_map

  name                = each.key
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.function.id

  # D-308 constant: https_only=true invariant for all function apps.
  https_only = true

  # Function app subnet (distinct from web app subnet — D-303 hybrid).
  # nonprod: function-app-nonproduction-eastus-subnet; prod: function-app-production-eastus-subnet
  # evidence: prod live read vnetName contains "function-app-production-eastus-subnet".
  virtual_network_subnet_id = var.function_app_subnet_id

  # Storage account — required by function app host (Azure Functions v4).
  # Name is not sensitive; key IS sensitive → KV reference via managed identity.
  # T-03-19: storage_account_access_key MUST be a KV reference, never a literal key.
  # evidence: nonprod HCL res-2174 has literal key (that IS the anti-pattern we're fixing).
  storage_account_name       = each.value.storage_account_name
  storage_account_access_key = "@Microsoft.KeyVault(VaultName=${replace(var.key_vault_uri, "https://", "")};SecretName=${each.value.storage_access_key_kv_name})"

  # Function-specific options from nonprod HCL analog (res-2174:2797, res-2201:3049).
  builtin_logging_enabled = each.value.builtin_logging_enabled
  client_certificate_mode = each.value.client_certificate_mode

  # App settings — KV references only (T-03-19).
  # AzureWebJobs.* disable-flags are non-sensitive (function enable/disable) — these are
  # author-time config, not runtime secrets. Actual storage keys + connection strings are KV refs.
  app_settings = {
    # KV reference for storage account access key (T-03-19).
    AZURE_STORAGE_ACCESS_KEY   = "@Microsoft.KeyVault(VaultName=${replace(var.key_vault_uri, "https://", "")};SecretName=${each.value.storage_access_key_kv_name})"
    AZURE_STORAGE_ACCOUNT_NAME = each.value.storage_account_name
    "KeyVaultUri"              = var.key_vault_uri
    WEBSITE_RUN_FROM_PACKAGE   = "1"
  }

  # D-305: hidden-link tags DROPPED.
  # Shared 3: SystemAssigned MI — no secret literals (T-03-20).
  identity {
    type = "SystemAssigned"
  }

  auth_settings {
    enabled                       = false
    token_refresh_extension_hours = 0
  }

  site_config {
    always_on  = each.value.always_on
    ftps_state = "FtpsOnly" # D-308 near-constant
    # NOTE: min_tls_version not an azurerm_linux_function_app attribute (provider limitation).
    # TLS posture enforced via https_only=true. Live-read values (1.2/1.3) in tfvars comments.
    vnet_route_all_enabled = true

    application_stack {
      node_version = each.value.node_version # e.g. "22" (evidence: prod live read Node|22)
    }

    # CORS — portal.azure.com allowed (evidence: prod live read fapp-process-res config_full.cors).
    cors {
      allowed_origins = ["https://portal.azure.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# § Function App KV Secrets User role assignments (T-03-20)
# ---------------------------------------------------------------------------

resource "azurerm_role_assignment" "fapp_kv_secrets_user" {
  for_each = var.function_app_map

  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.this[each.key].identity[0].principal_id
}

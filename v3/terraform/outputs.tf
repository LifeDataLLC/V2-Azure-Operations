# outputs.tf — Root outputs for the LifeData V3 Terraform root
#
# PURPOSE:
#   Exposes key resource attributes for inter-module wiring and for downstream
#   consumers (Phase 4 apply scripts, Phase 5 CI checks, cross-scope references).
#
# DESIGN:
#   Module plans append their own outputs in their labelled placeholder regions.
#   The scaffold ships with scope-level basics only; no outputs are emitted until
#   the respective module plan populates its section.
#
# ---------------------------------------------------------------------------
# § Scope-level outputs
# ---------------------------------------------------------------------------

output "resource_group_name" {
  description = "Name of the scope's resource group (from the data source)."
  value       = data.azurerm_resource_group.this.name
}

output "resource_group_location" {
  description = "Azure region of the scope's resource group."
  value       = data.azurerm_resource_group.this.location
}

output "enabled_environments" {
  description = "Map of currently-enabled environments in this scope (D-301)."
  value       = local.enabled_envs
}

# ---------------------------------------------------------------------------
# § Module output placeholders — filled in by each module plan
# ---------------------------------------------------------------------------

# --- networking outputs (Plan 03-03) ---

output "vnet_id" {
  description = "Resource ID of the scope's VNet (from module.networking)."
  value       = module.networking.vnet_id
}

output "sql_subnet_id" {
  description = "Subnet ID for SQL service endpoints (from module.networking)."
  value       = module.networking.sql_subnet_id
}

output "storage_subnet_id" {
  description = "Subnet ID for Storage service endpoints (from module.networking)."
  value       = module.networking.storage_subnet_id
}

output "keyvault_subnet_id" {
  description = "Subnet ID for Key Vault service endpoints (from module.networking)."
  value       = module.networking.keyvault_subnet_id
}

output "app_subnet_id" {
  description = "Subnet ID for App Service VNet integration (from module.networking)."
  value       = module.networking.app_subnet_id
}

output "function_app_subnet_id" {
  description = "Subnet ID for Function App VNet integration (from module.networking)."
  value       = module.networking.function_app_subnet_id
}

output "apim_subnet_id" {
  description = "Subnet ID for APIM VNet integration (from module.networking)."
  value       = module.networking.apim_subnet_id
}

# --- end networking outputs ---

# --- keyvault outputs (Plan 03-05) ---
# output "key_vault_id"     { ... }
# output "key_vault_uri"    { ... }
# --- end keyvault outputs ---

# --- sql outputs (Plan 03-03) ---
# output "sql_server_ids"   { ... }   # map keyed by env name
# --- end sql outputs ---

# --- storage outputs (Plan 03-04) ---
# output "storage_account_ids" { ... }
# --- end storage outputs ---

# --- app-service outputs (Plan 03-06) ---
# output "app_service_plan_ids" { ... }
# --- end app-service outputs ---

# --- apim outputs (Plan 03-07) ---
# output "apim_service_id"  { ... }
# --- end apim outputs ---

# --- app-gateway outputs (Plan 03-08) ---
# output "app_gateway_id"   { ... }
# --- end app-gateway outputs ---

# --- observability outputs (Plan 03-09) ---
# output "log_analytics_workspace_id" { ... }
# output "app_insights_ids"           { ... }
# --- end observability outputs ---

# modules/app-service/outputs.tf — App Service module outputs
#
# PURPOSE:
#   Export IDs consumed by downstream modules:
#   - observability module: web app IDs / plan IDs for metric alert scopes
#   - root (WHATS-DIFFERENT.md): identity principal IDs for verification
#
# DOWNSTREAM CONSUMERS:
#   observability  → web_app_ids, function_app_ids, web_plan_id (metric alert scopes)
#   root           → web_app_ids (for any cross-module wiring)

# ---------------------------------------------------------------------------
# § App Service Plan IDs
# ---------------------------------------------------------------------------

output "web_plan_id" {
  description = "Resource ID of the environment's web App Service Plan. Used as metric alert scope in module.observability."
  value       = azurerm_service_plan.web.id
}

output "function_plan_id" {
  description = "Resource ID of the environment's function App Service Plan. Used as metric alert scope in module.observability."
  value       = azurerm_service_plan.function.id
}

# ---------------------------------------------------------------------------
# § Web App IDs and Principal IDs
# ---------------------------------------------------------------------------

output "web_app_ids" {
  description = "Map of web app name → resource ID. Consumed by module.observability for metric alert scopes."
  value       = { for k, app in azurerm_linux_web_app.this : k => app.id }
}

output "web_app_principal_ids" {
  description = "Map of web app name → system-assigned MI principal ID. Useful for verifying KV role assignments."
  value       = { for k, app in azurerm_linux_web_app.this : k => app.identity[0].principal_id }
}

# ---------------------------------------------------------------------------
# § Function App IDs and Principal IDs
# ---------------------------------------------------------------------------

output "function_app_ids" {
  description = "Map of function app name → resource ID. Consumed by module.observability for metric alert scopes."
  value       = { for k, app in azurerm_linux_function_app.this : k => app.id }
}

output "function_app_principal_ids" {
  description = "Map of function app name → system-assigned MI principal ID. Useful for verifying KV role assignments."
  value       = { for k, app in azurerm_linux_function_app.this : k => app.identity[0].principal_id }
}

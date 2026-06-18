# modules/apim/outputs.tf
# APIM module outputs — consumed by root main.tf for observability wiring,
# private endpoint wiring, and app-gateway backend config.

output "gateway_url" {
  description = "APIM gateway URL (e.g. https://apim-common-nonproduction-eastus.azure-api.net)."
  value       = azurerm_api_management.this.gateway_url
}

output "gateway_id" {
  description = "Resource ID of the APIM service. Used for alert scope wiring (T-03-24) and private endpoint resource ID."
  value       = azurerm_api_management.this.id
}

output "service_id" {
  description = "Alias for gateway_id — resource ID of the APIM service."
  value       = azurerm_api_management.this.id
}

output "service_name" {
  description = "Name of the APIM service (for use in child resource references if needed)."
  value       = azurerm_api_management.this.name
}

output "principal_id" {
  description = "Object ID of the system-assigned managed identity on the APIM service (for RBAC assignments)."
  value       = azurerm_api_management.this.identity[0].principal_id
}

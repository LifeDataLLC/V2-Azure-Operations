# modules/storage/outputs.tf — Storage module outputs
#
# PURPOSE:
#   Export storage account IDs and names for downstream wiring:
#   - App Service module (Key Vault references to storage account names/IDs)
#   - Observability module (alert scopes referencing storage account IDs)
#   - Event Grid (system topics reference storage account IDs)
#
# DOWNSTREAM CONSUMERS:
#   app-service  → storage_account_ids / storage_account_names (KV connection string references)
#   observability → storage_account_ids (Event Grid system topic scopes)

output "storage_account_ids" {
  description = "Map of logical account key → storage account resource ID. Used for downstream wiring (alert scopes, Event Grid system topics, etc.)."
  value       = { for k, v in azurerm_storage_account.this : k => v.id }
}

output "storage_account_names" {
  description = "Map of logical account key → storage account name. Used for app-service Key Vault reference wiring."
  value       = { for k, v in azurerm_storage_account.this : k => v.name }
}

output "storage_account_primary_endpoints" {
  description = "Map of logical account key → primary_blob_endpoint. Useful for app config wiring without exposing access keys."
  value       = { for k, v in azurerm_storage_account.this : k => v.primary_blob_endpoint }
}

# modules/keyvault/outputs.tf — Key Vault module outputs
#
# PURPOSE:
#   Export the vault ID and URI for downstream wiring:
#   - App Service module (Key Vault reference URIs for app settings)
#   - APIM module (certificate / named-value references)
#   - App Gateway module (SSL certificate references)
#   - Root (wiring into APIM private endpoint resource ID)
#
# DOWNSTREAM CONSUMERS:
#   app-service  → key_vault_id / key_vault_uri (KV references for connection strings)
#   apim         → key_vault_id / key_vault_uri (named values / certificates)
#   app-gateway  → key_vault_uri (SSL certificate references)

output "key_vault_id" {
  description = "Resource ID of the scope's Key Vault. Used for role assignment targets and downstream KV references."
  value       = azurerm_key_vault.this.id
}

output "key_vault_uri" {
  description = "Vault URI (e.g. https://kvnonproductioneastus.vault.azure.net/). Used for app settings Key Vault reference construction."
  value       = azurerm_key_vault.this.vault_uri
}

output "key_vault_name" {
  description = "Name of the Key Vault. Convenience output for use in azurerm_key_vault_certificate_issuer etc."
  value       = azurerm_key_vault.this.name
}

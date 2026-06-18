# modules/app-gateway/outputs.tf — Application Gateway module outputs
#
# PURPOSE:
#   Export gateway ID and public IP for downstream consumption:
#   - observability module: gateway_id is used as an alert scope key ("app_gateway")
#   - root outputs.tf: expose gateway public IP for DNS verification
#
# DOWNSTREAM CONSUMERS:
#   observability  → gateway_id (alert scope for AGW metric alerts)
#   root           → gateway_public_ip_address (DNS / connectivity verification)

output "gateway_id" {
  description = <<-EOT
    Resource ID of the Application Gateway.
    Consumed by module.observability as an alert scope (alert_scope_ids["app_gateway"]).
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:7354,7376,7392,7407 (scopes = [agw.id]).
  EOT
  value       = azurerm_application_gateway.this.id
}

output "gateway_name" {
  description = "Name of the Application Gateway. Convenience output."
  value       = azurerm_application_gateway.this.name
}

output "agw_identity_id" {
  description = <<-EOT
    Resource ID of the user-assigned managed identity for the Application Gateway.
    Used for Key Vault SSL cert access (T-03-25 / Shared 3).
    Consumed by root to wire KV role assignment verification.
  EOT
  value       = azurerm_user_assigned_identity.agw.id
}

output "agw_identity_principal_id" {
  description = "Principal ID of the AGW user-assigned managed identity. Used for KV role assignment verification."
  value       = azurerm_user_assigned_identity.agw.principal_id
}

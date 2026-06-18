# modules/observability/outputs.tf — Observability module outputs
#
# PURPOSE:
#   Export workspace ID and App Insights connection references for downstream wiring:
#   - App Service module: connection_string for APPINSIGHTS_CONNECTIONSTRING app setting
#   - Root: workspace_id for cross-module diagnostic wiring
#
# T-03-25: Output connection_string (not instrumentation_key) — connection_string does not
#          expose the classic ikey secret and is the recommended auth method in azurerm v4.
#
# DOWNSTREAM CONSUMERS:
#   app-service   → app_insights_connection_strings (per-instance map)
#   root          → log_analytics_workspace_id (for diagnostic settings if needed)

# ---------------------------------------------------------------------------
# § Log Analytics Workspace
# ---------------------------------------------------------------------------

output "log_analytics_workspace_id" {
  description = <<-EOT
    Resource ID of the Log Analytics workspace (prod scope only; null on nonprod).
    Used for diagnostic settings / linked storage wiring.
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:1519 (V2ProdLogAnalyticsWorkspace).
  EOT
  value       = length(azurerm_log_analytics_workspace.this) > 0 ? azurerm_log_analytics_workspace.this[0].id : null
}

output "log_analytics_workspace_resource_id" {
  description = "Azure resource ID of the LA workspace (alias for log_analytics_workspace_id)."
  value       = length(azurerm_log_analytics_workspace.this) > 0 ? azurerm_log_analytics_workspace.this[0].id : null
}

# ---------------------------------------------------------------------------
# § Application Insights — connection strings (T-03-25: no literal instrumentation key)
# ---------------------------------------------------------------------------

output "app_insights_connection_strings" {
  description = <<-EOT
    Map of App Insights key → connection_string.
    T-03-25: Uses connection_string (not instrumentation_key) — connection_string
    is the recommended auth reference; it does not expose the raw ikey as a literal value
    in Terraform state in the same way as the classic instrumentation_key output.
    Downstream: app-service module consumes this for APPINSIGHTS_CONNECTIONSTRING app setting.
  EOT
  value       = { for k, appi in azurerm_application_insights.this : k => appi.connection_string }
  sensitive   = true
}

output "app_insights_ids" {
  description = "Map of App Insights key → resource ID. Consumed by smart detector rules and alert scope wiring."
  value       = { for k, appi in azurerm_application_insights.this : k => appi.id }
}

# ---------------------------------------------------------------------------
# § Action Group IDs (convenience export for cross-module wiring)
# ---------------------------------------------------------------------------

output "action_group_ids" {
  description = <<-EOT
    Map of action group key → resource ID.
    T-03-24: These IDs are from the NEW estate; they replace the old LD-*-EastUS-V2 ARM paths
    that appeared in the aztfexport analog's action { action_group_id = "..." } blocks.
    Can be passed to other modules that need to reference action groups (e.g. smart detector rules).
  EOT
  value       = { for k, ag in azurerm_monitor_action_group.this : k => ag.id }
}

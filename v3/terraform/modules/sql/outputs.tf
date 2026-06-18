# modules/sql/outputs.tf — SQL module outputs
#
# PURPOSE:
#   Exposes per-env SQL resource IDs for downstream wiring:
#     - observability alerts (scoped to server/DB resource IDs)
#     - app-service connection wiring (DB endpoint / server FQDN)
#     - root outputs.tf § sql outputs section
#
# CONSUMERS:
#   module.observability → server_id (alert scope)
#   module.app_service   → server_fqdn (connection string base)
#   root outputs.tf      → sql_server_ids map (keyed by env)

output "server_id" {
  description = <<-EOT
    Resource ID of the azurerm_mssql_server for this environment.
    Used by: observability alerts (azurerm_monitor_metric_alert scope),
             app-service module (connection string wiring).
    Example: /subscriptions/.../resourceGroups/.../providers/Microsoft.Sql/servers/sql-server-dev-eastus
  EOT
  value       = azurerm_mssql_server.this.id
}

output "server_name" {
  description = <<-EOT
    Name of the azurerm_mssql_server for this environment.
    Pattern: sql-server-<env>-eastus
    Used by: app-service connection string wiring (server FQDN derivation).
  EOT
  value       = azurerm_mssql_server.this.name
}

output "server_fqdn" {
  description = <<-EOT
    Fully-qualified domain name of the SQL server.
    Pattern: sql-server-<env>-eastus.database.windows.net
    Used by: app-service module (connection string base — no password, MI auth).
  EOT
  value       = azurerm_mssql_server.this.fully_qualified_domain_name
}

output "database_id" {
  description = <<-EOT
    Resource ID of the azurerm_mssql_database for this environment.
    Used by: observability alerts (DB-level metric scope),
             app-service module (connection string wiring).
    Example: /subscriptions/.../resourceGroups/.../providers/Microsoft.Sql/servers/.../databases/sqldb-dev2
  EOT
  value       = azurerm_mssql_database.this.id
}

output "database_name" {
  description = <<-EOT
    Name of the azurerm_mssql_database for this environment.
    Values: "sqldb-dev2" (dev), "sqldb-qa", "sqldb-staging", "sqldb-prod".
  EOT
  value       = azurerm_mssql_database.this.name
}

# modules/networking/outputs.tf — Networking module outputs
#
# PURPOSE:
#   These outputs are the wiring contract that every downstream module consumes.
#   Downstream modules reference them as module.networking.<output_name>.
#
# DOWNSTREAM CONSUMERS:
#   sql         → sql_subnet_id
#   storage     → storage_subnet_id
#   keyvault    → keyvault_subnet_id
#   app-service → app_subnet_id, function_app_subnet_id
#   apim        → apim_subnet_id (legacy Developer SKU internal VNet)
#   app-gateway → agw_subnet_id
#   (all)       → vnet_id (for VNet peering, security rules referencing CIDR)
#
# KEY EVIDENCE:
#   vnets.json subnet names per scope; used by sql/storage/keyvault/app-service/apim
#   to reference their respective service-endpoint subnets.

# ---------------------------------------------------------------------------
# § VNet
# ---------------------------------------------------------------------------

output "vnet_id" {
  description = "Resource ID of the scope's VNet."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the scope's VNet."
  value       = azurerm_virtual_network.this.name
}

# ---------------------------------------------------------------------------
# § Subnet IDs — downstream wiring contract
# These outputs use the map key "sql", "storage", "keyvault", "app_service",
# "function_app", "apim", "agw" — the keys set in var.subnets via tfvars.
# Downstream modules look up by key; the key must match what tfvars sets.
# ---------------------------------------------------------------------------

output "sql_subnet_id" {
  description = <<-EOT
    Subnet ID for Azure SQL service endpoints.
    Key "sql" in var.subnets.
    nonprod: sql-nonproduction-eastus-subnet (10.0.9.0/24)
    prod:    sql-production-eastus-subnet (10.0.9.0/24)
  EOT
  value       = azurerm_subnet.this["sql"].id
}

output "storage_subnet_id" {
  description = <<-EOT
    Subnet ID for Azure Storage service endpoints.
    Key "storage" in var.subnets.
    nonprod: storage-nonproduction-eastus-subnet (10.0.8.0/24)
    prod:    storage-production-eastus-subnet (10.0.8.0/24)
  EOT
  value       = azurerm_subnet.this["storage"].id
}

output "keyvault_subnet_id" {
  description = <<-EOT
    Subnet ID for Key Vault service endpoints.
    Key "keyvault" in var.subnets.
    nonprod: kv-nonproduction-eastus-subnet (10.0.7.0/24)
    prod:    kv-production-eastus-subnet (10.0.7.0/24)
  EOT
  value       = azurerm_subnet.this["keyvault"].id
}

output "app_subnet_id" {
  description = <<-EOT
    Subnet ID for App Service VNet integration (Web.serverFarms delegation).
    Key "app_service" in var.subnets.
    nonprod: app-service-nonproduction-eastus-subnet (10.0.3.0/24)
    prod:    app-service-production-eastus-subnet (10.0.3.0/24)
  EOT
  value       = azurerm_subnet.this["app_service"].id
}

output "function_app_subnet_id" {
  description = <<-EOT
    Subnet ID for Function App VNet integration (Web.serverFarms delegation).
    Key "function_app" in var.subnets.
    nonprod: function-app-nonproduction-eastus-subnet (10.0.4.0/24)
    prod:    function-app-production-eastus-subnet (10.0.4.0/24)
  EOT
  value       = azurerm_subnet.this["function_app"].id
}

output "apim_subnet_id" {
  description = <<-EOT
    Subnet ID for the legacy APIM Developer-SKU internal VNet integration.
    Key "apim" in var.subnets.
    nonprod: apim2-nonproduction-eastus-subnet (10.0.10.0/24) — NSG-associated
    prod:    apim-production-eastus-subnet (10.0.5.0/24) — NSG-associated
  EOT
  value       = azurerm_subnet.this["apim"].id
}

output "agw_subnet_id" {
  description = <<-EOT
    Subnet ID for the Application Gateway.
    Key "agw" in var.subnets.
    nonprod: agw-nonproduction-eastus-subnet (10.0.6.0/24)
    prod:    agw-production-eastus-subnet (10.0.6.0/24)
  EOT
  value       = azurerm_subnet.this["agw"].id
}

# ---------------------------------------------------------------------------
# § Private DNS zone IDs
# ---------------------------------------------------------------------------

output "private_dns_zone_ids" {
  description = "Map of private DNS zone IDs, keyed by the same keys as var.private_dns_zones."
  value       = { for k, v in azurerm_private_dns_zone.this : k => v.id }
}

# ---------------------------------------------------------------------------
# § NAT gateway (prod-only — null when not provisioned)
# ---------------------------------------------------------------------------

output "nat_gateway_id" {
  description = "Resource ID of the NAT gateway (prod only; null on nonprod)."
  value       = length(azurerm_nat_gateway.this) > 0 ? azurerm_nat_gateway.this[0].id : null
}

# ---------------------------------------------------------------------------
# § All subnet IDs (convenience map — useful for debugging / downstream maps)
# ---------------------------------------------------------------------------

output "subnet_ids" {
  description = "Map of all subnet IDs, keyed by the same keys as var.subnets."
  value       = { for k, v in azurerm_subnet.this : k => v.id }
}

# ---------------------------------------------------------------------------
# § Public IP IDs (for app-gateway + APIM downstream wiring)
# ---------------------------------------------------------------------------

output "public_ip_ids" {
  description = <<-EOT
    Map of public IP resource IDs, keyed by the same keys as var.public_ips.
    Downstream consumers:
      app-gateway → public_ip_ids["agw_prod"] / public_ip_ids["agw_common"]
      apim        → public_ip_ids["apim_dev"] / public_ip_ids["apim_staging_stv2"]
    Evidence: public_ips.json per-scope PIP names; referenced by AGW frontend IP config.
  EOT
  value       = { for k, v in azurerm_public_ip.this : k => v.id }
}

# modules/networking/main.tf — Networking module for the LifeData V3 estate
#
# SCOPE: Scope-shared — deployed ONCE per scope (D-302). Produces VNet, subnets,
#        NSGs+rules+associations, public IPs, private DNS zones + VNet links,
#        and (prod-only) NAT gateway + private endpoint for APIM StV2.
#
# AUTH-01: No azurerm_resource_group block. resource_group_name + location are
#          injected from var.resource_group_name / var.location (fed from root's
#          data.azurerm_resource_group.this).
#
# D-305: App Insights link tags on public IPs are DROPPED (click-ops noise).
#        Empty tags blocks are NOT emitted.
#
# ANALOG SOURCES (read-only reference):
#   VNet/subnets/NSG:          terraform/LD-NonProd-EastUS-V2/main.tf:1267-1448
#   Prod NSG rules:            terraform/LD-Prod-EastUS-V2/main.tf:1161-1253
#   Prod NAT/PE:               terraform/LD-Prod-EastUS-V2/main.tf:1152-1282
#   Prod subnets:              terraform/LD-Prod-EastUS-V2/main.tf:1316-1515
#   Live data:                 data/vnets.json, data/nsgs.json, data/public_ips.json

# ---------------------------------------------------------------------------
# § Virtual Network
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  address_space       = var.vnet_address_space
  location            = var.location
  resource_group_name = var.resource_group_name
  # D-302: both scopes mirror the live 10.0.0.0/16. Per-env CIDR isolation → M3.
  # Evidence: vnets.json addressSpace.addressPrefixes = ["10.0.0.0/16"] (both RGs).
}

# ---------------------------------------------------------------------------
# § Subnets (map-driven — D-303)
# ---------------------------------------------------------------------------

resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                              = each.value.name
  address_prefixes                  = [each.value.address_prefix]
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  service_endpoints                 = length(each.value.service_endpoints) > 0 ? each.value.service_endpoints : null
  private_endpoint_network_policies = each.value.private_endpoint_network_policies

  # default_outbound_access_enabled: only set to false on StV2 APIM outbound/inbound subnets
  # to match the live estate (terraform/LD-Prod-EastUS-V2/main.tf:1349, 1360, 1442, 1453).
  default_outbound_access_enabled = each.value.default_outbound_access_enabled

  # App Service / Function App / APIM StV2 subnets carry a Web.serverFarms delegation.
  # delegation_name == "" means no delegation for this subnet.
  # Delegation service name examples (set in var.subnets[*].delegation_service):
  #   "Microsoft.Web/serverFarms"  — app-service, function-app, APIM StV2 subnets
  # Evidence: vnets.json subnets[*].delegations[*].serviceName
  dynamic "delegation" {
    for_each = each.value.delegation_name != "" ? [1] : []
    content {
      name = each.value.delegation_name
      service_delegation {
        name    = each.value.delegation_service # e.g. "Microsoft.Web/serverFarms"
        actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }
  }

  depends_on = [azurerm_virtual_network.this]
}

# ---------------------------------------------------------------------------
# § Network Security Groups (map-driven — D-303)
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "this" {
  for_each = var.nsgs

  name                = each.value.name
  location            = var.location
  resource_group_name = var.resource_group_name
}

# NSG security rules — one resource per rule per NSG.
# Flattened from the nested map: {nsg_key, rule_index} → rule object.
locals {
  nsg_rules_flat = merge([
    for nsg_key, nsg in var.nsgs : {
      for rule in nsg.security_rules :
      "${nsg_key}_${rule.name}" => merge(rule, { nsg_key = nsg_key })
    }
  ]...)
}

resource "azurerm_network_security_rule" "this" {
  for_each = local.nsg_rules_flat

  name                        = each.value.name
  priority                    = each.value.priority
  direction                   = each.value.direction
  access                      = each.value.access
  protocol                    = each.value.protocol
  source_port_range           = each.value.source_port_range
  destination_port_range      = length(each.value.destination_port_ranges) == 0 ? each.value.destination_port_range : null
  destination_port_ranges     = length(each.value.destination_port_ranges) > 0 ? each.value.destination_port_ranges : null
  source_address_prefix       = each.value.source_address_prefix
  destination_address_prefix  = each.value.destination_address_prefix
  description                 = each.value.description != "" ? each.value.description : null
  network_security_group_name = azurerm_network_security_group.this[each.value.nsg_key].name
  resource_group_name         = var.resource_group_name

  depends_on = [azurerm_network_security_group.this]
}

# NSG → subnet associations
resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = var.nsgs

  subnet_id                 = azurerm_subnet.this[each.value.subnet_key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id

  depends_on = [
    azurerm_subnet.this,
    azurerm_network_security_group.this,
  ]
}

# ---------------------------------------------------------------------------
# § Public IP addresses (map-driven — D-303)
# D-305: App Insights link tags on public IPs are dropped (click-ops noise).
#        The live estate has such tags on pip-common-nonproduction-eastus,
#        pip-dev-eastus, pip-prod-eastus, and pip-staging-eastus.
#        Evidence: public_ips.json tags field.
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "this" {
  for_each = var.public_ips

  name                    = each.value.name
  location                = var.location
  resource_group_name     = var.resource_group_name
  allocation_method       = each.value.allocation_method
  sku                     = each.value.sku
  idle_timeout_in_minutes = each.value.idle_timeout_in_minutes
  zones                   = length(each.value.zones) > 0 ? each.value.zones : null
  domain_name_label       = each.value.domain_name_label != "" ? each.value.domain_name_label : null
  # NO tags block — App Insights link tags stripped per D-305 (noise normalization).
}

# ---------------------------------------------------------------------------
# § Private DNS zones + VNet links (map-driven)
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "this" {
  for_each = var.private_dns_zones

  name                = each.value.zone_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = var.private_dns_zones

  name                  = each.value.link_name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.key].name
  resource_group_name   = var.resource_group_name
  virtual_network_id    = azurerm_virtual_network.this.id

  depends_on = [azurerm_private_dns_zone.this]
}

# ---------------------------------------------------------------------------
# § NAT Gateway (prod-only — conditional on var.nat_gateway_name != "")
# Evidence: terraform/LD-Prod-EastUS-V2/main.tf:1152-1160
#           public_ips.json: pip-nat-ldapim-prod-stv2-eastus → natgw-prod-stv2-eastus
# ---------------------------------------------------------------------------

resource "azurerm_nat_gateway" "this" {
  count = var.nat_gateway_name != "" ? 1 : 0

  name                = var.nat_gateway_name
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  count = var.nat_gateway_name != "" ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.this[0].id
  public_ip_address_id = azurerm_public_ip.this[var.nat_gateway_pip_key].id

  depends_on = [
    azurerm_nat_gateway.this,
    azurerm_public_ip.this,
  ]
}

resource "azurerm_subnet_nat_gateway_association" "this" {
  count = var.nat_gateway_name != "" ? 1 : 0

  nat_gateway_id = azurerm_nat_gateway.this[0].id
  subnet_id      = azurerm_subnet.this[var.nat_gateway_subnet_key].id

  depends_on = [
    azurerm_nat_gateway.this,
    azurerm_subnet.this,
    # The subnet also has an NSG association — declare it so Terraform serialises
    # the operations. Mirrors the aztfexport comment at res-2654.
    azurerm_subnet_network_security_group_association.this,
  ]
}

# ---------------------------------------------------------------------------
# § Private Endpoint for APIM StandardV2 (prod-only)
# Evidence: terraform/LD-Prod-EastUS-V2/main.tf:1267-1282
# ---------------------------------------------------------------------------

resource "azurerm_private_endpoint" "apim_stv2" {
  count = var.apim_private_endpoint_name != "" ? 1 : 0

  name                = var.apim_private_endpoint_name
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = azurerm_subnet.this[var.apim_private_endpoint_subnet_key].id

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.this[var.apim_private_dns_zone_key].id]
  }

  private_service_connection {
    name                           = var.apim_private_endpoint_name
    private_connection_resource_id = var.apim_private_endpoint_resource_id
    subresource_names              = ["Gateway"]
    is_manual_connection           = false
  }

  depends_on = [
    azurerm_subnet.this,
    azurerm_private_dns_zone.this,
  ]
}

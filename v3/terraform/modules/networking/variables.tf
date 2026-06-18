# modules/networking/variables.tf — Input variables for the networking module
#
# DESIGN PRINCIPLES (D-302/303/307/311):
#   D-311: resource_group_name + location are ALWAYS injected from the root's
#          data.azurerm_resource_group.this — no azurerm_resource_group block here.
#   D-307: address_space, per-subnet prefix/name/service-endpoints, NSG rules are
#          NO-DEFAULT (divergence-bearing). Each value MUST be set in prod.tfvars /
#          nonprod.tfvars with cited evidence.
#   D-302: This module is scope-shared — called ONCE per scope, no for_each.
#          Both scopes use 10.0.0.0/16 (M1 mirrors live overlapping CIDRs; per-env
#          CIDR isolation is M3).
#   D-305: No azurerm_resource_group, no hidden-link tags.
#
# EVIDENCE BASE:
#   data/vnets.json               — subnet names, prefixes, service endpoints, delegations
#   data/nsgs.json                — NSG names, security rules
#   data/public_ips.json          — public IP names, SKU, allocation method
#   terraform/LD-NonProd-EastUS-V2/main.tf:1267-1448 — nonprod shape
#   terraform/LD-Prod-EastUS-V2/main.tf:1152-1516    — prod NAT/PE/subnets shape

# ---------------------------------------------------------------------------
# § Core scope inputs (D-311 — always injected from root's data source)
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  description = <<-EOT
    Name of the pre-created V3 resource group for this scope (D-311).
    Fed from data.azurerm_resource_group.this.name in the root module.
    Values: "ld-nonprod-eastus-v3" | "ld-prod-eastus-v3".
  EOT
  type        = string
}

variable "location" {
  description = <<-EOT
    Azure region for all resources in this scope.
    Fed from data.azurerm_resource_group.this.location in the root module.
    Value: "eastus" (single-region estate — CLAUDE.md §Critical context).
  EOT
  type        = string
}

# ---------------------------------------------------------------------------
# § VNet — divergence-bearing, NO DEFAULT (D-307)
# ---------------------------------------------------------------------------

variable "vnet_name" {
  description = <<-EOT
    Name of the virtual network for this scope.
    Evidence: vnets.json name field.
    nonprod = "vnet-common-nonproduction-eastus"
    prod    = "vnet-production-eastus"
    NO DEFAULT (D-307).
  EOT
  type        = string
}

variable "vnet_address_space" {
  description = <<-EOT
    VNet address space CIDR(s).
    M1: both scopes mirror the live overlapping 10.0.0.0/16 (D-302).
    Per-env CIDR isolation is deferred to M3.
    Evidence: vnets.json addressSpace.addressPrefixes.
    NO DEFAULT (D-307 — address space is connectivity-critical).
  EOT
  type        = list(string)
}

# ---------------------------------------------------------------------------
# § Subnets — map-driven (D-303), NO DEFAULT on the map (D-307)
# ---------------------------------------------------------------------------

variable "subnets" {
  description = <<-EOT
    Map of subnets to create in this scope's VNet.
    Key   = logical subnet role (e.g. "sql", "storage", "app_service", ...).
    Value = object with:
      name                  — real Azure subnet name (from vnets.json).
      address_prefix        — CIDR prefix (from vnets.json).
      service_endpoints     — list of endpoint service tokens (may be empty).
      delegation_name       — delegation block name (null = no delegation).
      delegation_service    — delegation serviceName (null = no delegation).
      private_endpoint_network_policies — "Enabled" | "Disabled" | "RouteTableEnabled".
      default_outbound_access_enabled   — bool; only false for StV2 APIM subnets.

    NO DEFAULT (D-307 — subnet prefixes/names are divergence-bearing).
    Evidence: vnets.json subnets[*] per scope.
  EOT
  type = map(object({
    name                              = string
    address_prefix                    = string
    service_endpoints                 = list(string)
    delegation_name                   = string
    delegation_service                = string
    private_endpoint_network_policies = string
    default_outbound_access_enabled   = bool
  }))
}

# ---------------------------------------------------------------------------
# § NSGs — map-driven, NO DEFAULT (D-307)
# ---------------------------------------------------------------------------

variable "nsgs" {
  description = <<-EOT
    Map of Network Security Groups to create.
    Key   = logical NSG role (e.g. "apim", "prod_stv2").
    Value = object with:
      name             — real Azure NSG name (from nsgs.json).
      subnet_key       — key in var.subnets to associate this NSG with.
      security_rules   — list of security rule objects (may be empty).

    Each security_rule object:
      name                       string
      priority                   number
      direction                  "Inbound" | "Outbound"
      access                     "Allow" | "Deny"
      protocol                   "*" | "Tcp" | "Udp"
      source_port_range          string
      destination_port_range     string  (use "" if destination_port_ranges is set)
      destination_port_ranges    list(string) (use [] if destination_port_range is set)
      source_address_prefix      string
      destination_address_prefix string
      description                string

    NO DEFAULT (D-307 — NSG rules are connectivity-critical).
    Evidence: nsgs.json securityRules[*] per scope.
  EOT
  type = map(object({
    name       = string
    subnet_key = string
    security_rules = list(object({
      name                       = string
      priority                   = number
      direction                  = string
      access                     = string
      protocol                   = string
      source_port_range          = string
      destination_port_range     = string
      destination_port_ranges    = list(string)
      source_address_prefix      = string
      destination_address_prefix = string
      description                = string
    }))
  }))
}

# ---------------------------------------------------------------------------
# § Public IPs — map-driven, NO DEFAULT (D-307)
# ---------------------------------------------------------------------------

variable "public_ips" {
  description = <<-EOT
    Map of public IP addresses to create.
    Key   = logical role (e.g. "agw_nonprod", "nat_stv2", ...).
    Value = object with:
      name                    — real Azure PIP name (from public_ips.json).
      allocation_method       — "Static" | "Dynamic".
      sku                     — "Standard" | "Basic".
      idle_timeout_in_minutes — number (default 4 in live estate).
      zones                   — list(string) (empty = no zone pinning).
      domain_name_label       — string (empty string = none).

    NO DEFAULT (D-307 — PIP names drive downstream AppGW/APIM config).
    Evidence: public_ips.json per scope.
  EOT
  type = map(object({
    name                    = string
    allocation_method       = string
    sku                     = string
    idle_timeout_in_minutes = number
    zones                   = list(string)
    domain_name_label       = string
  }))
}

# ---------------------------------------------------------------------------
# § Private DNS zones — map-driven, NO DEFAULT (D-307)
# ---------------------------------------------------------------------------

variable "private_dns_zones" {
  description = <<-EOT
    Map of private DNS zones + VNet links to create.
    Key   = logical role (e.g. "redis", "apim_stv2").
    Value = object with:
      zone_name  — DNS zone name (e.g. "privatelink.redis.cache.windows.net").
      link_name  — VNet link resource name.

    NO DEFAULT (D-307 — zone names are connectivity-critical).
    Evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1288 (redis);
              terraform/LD-Prod-EastUS-V2/main.tf:1254 (apim privatelink.azure-api.net).
  EOT
  type = map(object({
    zone_name = string
    link_name = string
  }))
}

# ---------------------------------------------------------------------------
# § NAT Gateway (prod-only) — conditional on non-empty name (D-302/D-307)
# ---------------------------------------------------------------------------

variable "nat_gateway_name" {
  description = <<-EOT
    Name of the NAT gateway, or empty string if not required (nonprod = "").
    Prod: "natgw-prod-stv2-eastus" (associated with pip-nat-ldapim-prod-stv2-eastus
    and ldapim-prod-stv2-eastus-outbound-subnet).
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:1152; public_ips.json (pip-nat-*).
    NO DEFAULT (D-307).
  EOT
  type        = string
}

variable "nat_gateway_pip_key" {
  description = <<-EOT
    Key in var.public_ips that holds the NAT gateway's public IP.
    Ignored when nat_gateway_name is "".
    Prod: "nat_stv2"  (pip-nat-ldapim-prod-stv2-eastus).
    Evidence: public_ips.json + terraform/LD-Prod-EastUS-V2/main.tf:1157-1159.
    NO DEFAULT (D-307).
  EOT
  type        = string
}

variable "nat_gateway_subnet_key" {
  description = <<-EOT
    Key in var.subnets for the subnet to attach the NAT gateway to.
    Ignored when nat_gateway_name is "".
    Prod: "apim_stv2_outbound"  (ldapim-prod-stv2-eastus-outbound-subnet).
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:1470-1476.
    NO DEFAULT (D-307).
  EOT
  type        = string
}

# ---------------------------------------------------------------------------
# § Private Endpoint (prod APIM StV2) — conditional on non-empty name (D-302/D-307)
# ---------------------------------------------------------------------------

variable "apim_private_endpoint_name" {
  description = <<-EOT
    Name of the APIM StandardV2 private endpoint, or "" if not needed (nonprod = "").
    Prod: "pip-prod-stv2-eastus"
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:1267-1282.
    NO DEFAULT (D-307).
  EOT
  type        = string
}

variable "apim_private_endpoint_subnet_key" {
  description = <<-EOT
    Key in var.subnets for the subnet that hosts the APIM private endpoint.
    Ignored when apim_private_endpoint_name is "".
    Prod: "apim_stv2_inbound"  (ldapim-prod-stv2-eastus-inbound-subnet).
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:1271.
    NO DEFAULT (D-307).
  EOT
  type        = string
}

variable "apim_private_endpoint_resource_id" {
  description = <<-EOT
    ARM resource ID of the APIM StandardV2 service the private endpoint connects to.
    Ignored when apim_private_endpoint_name is "".
    Prod: obtained from module.apim output (wired by Plan 03-07).
    For initial authoring this is an empty string; Plan 03-07 wires the real reference.
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:1279.
    NO DEFAULT (D-307).
  EOT
  type        = string
}

variable "apim_private_dns_zone_key" {
  description = <<-EOT
    Key in var.private_dns_zones whose zone is associated with the APIM private endpoint.
    Ignored when apim_private_endpoint_name is "".
    Prod: "apim_stv2"  (privatelink.azure-api.net).
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:1254-1265, 1272-1275.
    NO DEFAULT (D-307).
  EOT
  type        = string
}

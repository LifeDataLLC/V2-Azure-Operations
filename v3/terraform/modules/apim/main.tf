# modules/apim/main.tf
# APIM service-level resource + identity_provider_aad (prod)
#
# DESIGN PRINCIPLES:
#   D-307: apim_sku_name, apim_vnet_type, apim_subnet_id — NO default.
#          Mid-migration posture (Developer_1 + StandardV2_1) preserved per D-310.
#   D-309: Full child clone is in children.tf — this file manages the service only.
#   D-311: resource_group_name is var.resource_group_name (never azurerm_resource_group).
#   AUTH-01: No existing V2 resource imported or managed in place.
#
# Evidence:
#   nonprod shape: terraform/LD-NonProd-EastUS-V2/main.tf:5-22
#   prod shape:    terraform/LD-Prod-EastUS-V2/main.tf:255-272 + identity_provider_aad:273
#   SKU/vnet:      data/apim_services.json, data/apim_security.json, data/FINDINGS-DATA.md §APIM

resource "azurerm_api_management" "this" {
  name                = var.apim_name
  location            = var.location
  resource_group_name = var.resource_group_name

  # Publisher info — from apim_services.json publisherEmail / publisherName
  publisher_name  = var.apim_publisher_name
  publisher_email = var.apim_publisher_email

  # D-307 NO DEFAULT: SKU mid-migration pair preserved as explicit per-instance vars.
  # nonprod: Developer_1; prod: Developer_1 (legacy) or StandardV2_1 (migration target).
  # M4 consolidates 5→3 (D-DEFER); M1 preserves current posture.
  # Evidence: apim_services.json sku.name per instance.
  sku_name = var.apim_sku_name

  # D-307 NO DEFAULT: VNet type — Internal (Developer+VNet) or External (StV2) or None.
  # Evidence: apim_services.json virtualNetworkType per instance.
  virtual_network_type = var.apim_vnet_type

  # VNet subnet — only wired when vnet_type != "None"
  # apim_subnet_id="" on None-type instances (standard; Terraform accepts empty string for optional)
  dynamic "virtual_network_configuration" {
    for_each = var.apim_vnet_type != "None" ? [1] : []
    content {
      subnet_id = var.apim_subnet_id
    }
  }

  # System-assigned managed identity (Shared 3 — D-311; consistent across all instances)
  # Evidence: LD-NonProd main.tf:13-15; LD-Prod main.tf:262-264
  identity {
    type = "SystemAssigned"
  }

  # Hostname configurations for custom domains (KV-backed certs, Shared 3)
  # Passed as a list — empty list = no custom hostnames (nonprod instances without custom domains)
  dynamic "hostname_configuration" {
    for_each = length(var.apim_hostname_configurations) > 0 ? [var.apim_hostname_configurations] : []
    content {
      dynamic "proxy" {
        for_each = lookup(hostname_configuration.value, "proxy", [])
        content {
          host_name                    = proxy.value.host_name
          key_vault_id                 = lookup(proxy.value, "key_vault_id", null)
          default_ssl_binding          = lookup(proxy.value, "default_ssl_binding", false)
          negotiate_client_certificate = lookup(proxy.value, "negotiate_client_certificate", false)
        }
      }
      dynamic "management" {
        for_each = lookup(hostname_configuration.value, "management", [])
        content {
          host_name    = management.value.host_name
          key_vault_id = lookup(management.value, "key_vault_id", null)
        }
      }
      dynamic "portal" {
        for_each = lookup(hostname_configuration.value, "portal", [])
        content {
          host_name    = portal.value.host_name
          key_vault_id = lookup(portal.value, "key_vault_id", null)
        }
      }
      dynamic "developer_portal" {
        for_each = lookup(hostname_configuration.value, "developer_portal", [])
        content {
          host_name    = developer_portal.value.host_name
          key_vault_id = lookup(developer_portal.value, "key_vault_id", null)
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# AAD B2C Identity Provider (prod instances only — D-309 / D-310)
# ---------------------------------------------------------------------------
# Evidence: terraform/LD-Prod-EastUS-V2/main.tf:273-282 (azurerm_api_management_identity_provider_aad)
# The B2C identity provider is the authentication mechanism for client registrations.
# nonprod instances do NOT have this resource — controlled by var.apim_aad_identity_provider_enabled.
resource "azurerm_api_management_identity_provider_aad" "this" {
  count = var.apim_aad_identity_provider_enabled ? 1 : 0

  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  client_id           = var.apim_aad_client_id
  client_secret       = var.apim_aad_client_secret
  allowed_tenants     = var.apim_aad_allowed_tenants

  depends_on = [azurerm_api_management.this]
}

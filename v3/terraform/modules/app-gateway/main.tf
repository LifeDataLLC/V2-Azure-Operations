# modules/app-gateway/main.tf — Application Gateway module for the LifeData V3 estate
#
# DESIGN PRINCIPLES:
#   D-302: Scope-shared — one gateway per scope (no for_each at root level).
#   D-307: appgw_sku_name, appgw_sku_tier have NO default. M1=Standard_v2 (no WAF).
#          M3 flips sku_tier to WAF_v2 via tfvars diff — no code change needed.
#   D-305: backend_address_pools, http_settings, listeners, routing_rules, probes,
#          ssl_certificates driven by map variables — NOT N hand-written blocks.
#   T-03-23: appgw_sku_tier is a no-default variable (posture-preservation boundary).
#   T-03-25: ssl_certificate blocks reference KV secrets via key_vault_secret_id (Shared 3);
#            no certificate/key literals in HCL or tfvars.
#   T-03-26: No WAF in M1 (Standard_v2). Accepted risk — documented in WHATS-DIFFERENT.
#
# ANALOG EVIDENCE:
#   Prod:    terraform/LD-Prod-EastUS-V2/main.tf:559-1050  (agw-prod-eastus, Standard_v2)
#   Nonprod: terraform/LD-NonProd-EastUS-V2/main.tf:533-   (agw-common-nonproduction-eastus, Standard_v2)
#   data/appgw.json: autoscale min=1 max=2 confirmed on both gateways.

# ---------------------------------------------------------------------------
# § User-Assigned Identity (for Key Vault SSL cert access — Shared 3)
# The Application Gateway uses a user-assigned managed identity to access
# SSL certificates stored in Key Vault as secrets.
# Evidence: terraform/LD-Prod-EastUS-V2/main.tf:755-758 (UserAssigned identity block).
# ---------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "agw" {
  name                = var.agw_identity_name
  location            = var.location
  resource_group_name = var.resource_group_name
}

# Grant the AGW identity "Key Vault Secrets User" on the scope's Key Vault.
# This allows the gateway to retrieve SSL certificates stored as KV secrets.
# T-03-25: Certificate access via RBAC + managed identity — no certificate literals.
resource "azurerm_role_assignment" "agw_kv_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.agw.principal_id
}

# ---------------------------------------------------------------------------
# § Application Gateway
# Evidence:
#   Prod sku: name="Standard_v2" tier="Standard_v2" (main.tf:965-968).
#   Nonprod:  name="Standard_v2" tier="Standard_v2" (nonprod main.tf:~533).
#   D-307: appgw_sku_tier NO DEFAULT — M1=Standard_v2, M3 flips to WAF_v2.
#   T-03-23: Posture-preservation boundary — never silently default to WAF or non-WAF.
# ---------------------------------------------------------------------------

resource "azurerm_application_gateway" "this" {
  name                = var.agw_name
  location            = var.location
  resource_group_name = var.resource_group_name
  http2_enabled       = true

  # Autoscale — capacity vars are no-default (D-307; diverge per scope/env).
  # Evidence: data/appgw.json autoscaleConfiguration.minCapacity=1, maxCapacity=2 (both gateways).
  autoscale_configuration {
    min_capacity = var.agw_min_capacity
    max_capacity = var.agw_max_capacity
  }

  # SKU — tier is the D-307 no-default posture variable.
  # M1: Standard_v2 (no WAF). M3: WAF_v2. Never silent default.
  # T-03-23 / D-307: Both appgw_sku_name and appgw_sku_tier have NO default in variables.tf.
  sku {
    name = var.appgw_sku_name
    tier = var.appgw_sku_tier
  }

  # User-assigned identity for Key Vault SSL cert access (T-03-25 / Shared 3).
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.agw.id]
  }

  # Gateway subnet — fed from module.networking.agw_subnet_id at root.
  # Evidence: main.tf:679-682 (appGatewayIpConfig → agw-*-eastus-subnet).
  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = var.agw_subnet_id
  }

  # Frontend IP — public IP fed from module.networking public_ip output.
  # Evidence: main.tf:671-674 (appGwPublicFrontendIpIPv4 → pip-prod-eastus).
  frontend_ip_configuration {
    name                 = "appGwPublicFrontendIpIPv4"
    public_ip_address_id = var.agw_public_ip_id
  }

  # Frontend port — 443 HTTPS only.
  # Evidence: main.tf:675-677 (port_443 = 443).
  frontend_port {
    name = "port_443"
    port = 443
  }

  # Backend Address Pools — driven by map variable (D-305).
  # Evidence: prod main.tf:568-599 (8 backend pools for prod+staging APIM and web-frontend).
  dynamic "backend_address_pool" {
    for_each = var.backend_address_pools
    content {
      name         = backend_address_pool.value.name
      fqdns        = lookup(backend_address_pool.value, "fqdns", [])
      ip_addresses = lookup(backend_address_pool.value, "ip_addresses", [])
    }
  }

  # Backend HTTP Settings — driven by map variable.
  # Evidence: prod main.tf:600-670 (8 backend settings entries).
  dynamic "backend_http_settings" {
    for_each = var.backend_http_settings
    content {
      name                  = backend_http_settings.value.name
      cookie_based_affinity = backend_http_settings.value.cookie_based_affinity
      affinity_cookie_name  = lookup(backend_http_settings.value, "affinity_cookie_name", null)
      port                  = backend_http_settings.value.port
      protocol              = backend_http_settings.value.protocol
      request_timeout       = backend_http_settings.value.request_timeout
      probe_name            = lookup(backend_http_settings.value, "probe_name", null)
      host_name             = lookup(backend_http_settings.value, "host_name", null)
    }
  }

  # HTTP Listeners — driven by map variable.
  # Evidence: prod main.tf:683-754 (8 listeners with SNI and ssl_certificate_name).
  dynamic "http_listener" {
    for_each = var.http_listeners
    content {
      name                           = http_listener.value.name
      frontend_ip_configuration_name = "appGwPublicFrontendIpIPv4"
      frontend_port_name             = "port_443"
      protocol                       = "Https"
      require_sni                    = true
      ssl_certificate_name           = http_listener.value.ssl_certificate_name
      # host_names for multi-site listeners; host_name for single-site
      host_names = lookup(http_listener.value, "host_names", [])
      host_name  = lookup(http_listener.value, "host_name", null)
    }
  }

  # Probes — driven by map variable.
  # Evidence: prod main.tf:759-854 (8 health probes).
  dynamic "probe" {
    for_each = var.probes
    content {
      name                = probe.value.name
      host                = probe.value.host
      path                = probe.value.path
      protocol            = "Https"
      interval            = probe.value.interval
      timeout             = probe.value.timeout
      unhealthy_threshold = probe.value.unhealthy_threshold
      match {
        status_code = ["200-399"]
      }
    }
  }

  # Request Routing Rules — driven by map variable.
  # Evidence: prod main.tf:855-926 (8 routing rules).
  dynamic "request_routing_rule" {
    for_each = var.request_routing_rules
    content {
      name                       = request_routing_rule.value.name
      rule_type                  = "Basic"
      http_listener_name         = request_routing_rule.value.http_listener_name
      backend_address_pool_name  = request_routing_rule.value.backend_address_pool_name
      backend_http_settings_name = request_routing_rule.value.backend_http_settings_name
      priority                   = request_routing_rule.value.priority
      rewrite_rule_set_name      = lookup(request_routing_rule.value, "rewrite_rule_set_name", null)
    }
  }

  # Rewrite Rule Sets — driven by map variable.
  # Evidence: prod main.tf:927-963 ("front-end-app-rewrite" security headers + "Cros-Origin-Response" CORS).
  dynamic "rewrite_rule_set" {
    for_each = var.rewrite_rule_sets
    content {
      name = rewrite_rule_set.value.name
      dynamic "rewrite_rule" {
        for_each = rewrite_rule_set.value.rewrite_rules
        content {
          name          = rewrite_rule.value.name
          rule_sequence = rewrite_rule.value.rule_sequence
          dynamic "response_header_configuration" {
            for_each = rewrite_rule.value.response_headers
            content {
              header_name  = response_header_configuration.value.header_name
              header_value = response_header_configuration.value.header_value
            }
          }
        }
      }
    }
  }

  # SSL Certificates — KV-referenced certs via key_vault_secret_id (T-03-25 / Shared 3).
  # Evidence: prod main.tf:969-1050 (mix of name-only historic certs + KV-secret active certs).
  # The active certs reference kvproductioneastus.vault.azure.net/secrets/* — no literals.
  # Historic date-tagged certs (api-prod-20260428, etc.) have no key_vault_secret_id — they are
  # upload-once certs managed outside Terraform; we author only the KV-referenced active ones.
  dynamic "ssl_certificate" {
    for_each = var.ssl_certificates
    content {
      name                = ssl_certificate.value.name
      key_vault_secret_id = lookup(ssl_certificate.value, "key_vault_secret_id", null)
    }
  }
}

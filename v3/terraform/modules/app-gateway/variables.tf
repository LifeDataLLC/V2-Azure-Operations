# modules/app-gateway/variables.tf — Application Gateway module variable surface
#
# D-307: NO `default` on risk-/divergence-bearing values:
#   - appgw_sku_name, appgw_sku_tier (the WAF posture decision — T-03-23)
#   - agw_min_capacity, agw_max_capacity (capacity is scope-specific)
#   - agw_name, agw_identity_name (resource names are connectivity-critical)
# D-308: Invariants (enable_http2=true, frontend_port=443) are constants in main.tf.
# T-03-23: appgw_sku_tier has NO default — M1=Standard_v2 (no WAF), M3→WAF_v2 via tfvars flip.

# ---------------------------------------------------------------------------
# § Scope placement
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the pre-created V3 resource group for this scope. Fed from data.azurerm_resource_group.this.name at root."
  type        = string
}

variable "location" {
  description = "Azure region. Fed from data.azurerm_resource_group.this.location at root."
  type        = string
}

# ---------------------------------------------------------------------------
# § Gateway identity
# ---------------------------------------------------------------------------

variable "agw_name" {
  description = <<-EOT
    Name of the Application Gateway resource.
    prod:    "agw-prod-eastus"    (evidence: terraform/LD-Prod-EastUS-V2/main.tf:562)
    nonprod: "agw-common-nonproduction-eastus" (evidence: nonprod main.tf:536)
    NO DEFAULT (D-307) — name is connectivity-critical and differs between scopes.
  EOT
  type        = string
}

variable "agw_identity_name" {
  description = <<-EOT
    Name of the user-assigned managed identity for AGW Key Vault cert access (T-03-25 / Shared 3).
    prod:    "id-agw-prod-eastus"    (v3 naming convention)
    nonprod: "id-agw-nonprod-eastus" (v3 naming convention)
    NO DEFAULT (D-307).
  EOT
  type        = string
}

# ---------------------------------------------------------------------------
# § SKU and capacity — THE posture variables (D-307 / T-03-23)
# ---------------------------------------------------------------------------

variable "appgw_sku_name" {
  description = <<-EOT
    SKU name for the Application Gateway.
    M1 value (both scopes): "Standard_v2".
    M3 value (prod): "WAF_v2" — flipped via tfvars diff, no code change.
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:965-968 (sku.name="Standard_v2").
              data/appgw.json sku.name="Standard_v2" (confirmed on both gateways).
    NO DEFAULT (D-307 / T-03-23) — posture-preservation boundary; unset = plan failure.
  EOT
  type        = string

  validation {
    condition     = contains(["Standard_v2", "WAF_v2"], var.appgw_sku_name)
    error_message = "appgw_sku_name must be 'Standard_v2' or 'WAF_v2'. M1=Standard_v2; M3 flips to WAF_v2."
  }
}

variable "appgw_sku_tier" {
  description = <<-EOT
    SKU tier for the Application Gateway.
    M1 value (both scopes): "Standard_v2" (NO WAF — preserved A-/F-finding per posture boundary).
    M3 value (prod): "WAF_v2" — flipped via tfvars diff, no code change.
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:966-967 (sku.tier="Standard_v2").
              FINDINGS-DATA.md §Networking (no WAF on prod App Gateway — HIGH security finding).
    NO DEFAULT (D-307 / T-03-23) — WAF posture is a deliberate per-scope security decision;
    unset = plan failure (fail fast). Never silently default to WAF or non-WAF.
  EOT
  type        = string

  validation {
    condition     = contains(["Standard_v2", "WAF_v2"], var.appgw_sku_tier)
    error_message = "appgw_sku_tier must be 'Standard_v2' or 'WAF_v2'. M1=Standard_v2 (no WAF); M3→WAF_v2."
  }
}

variable "agw_min_capacity" {
  description = <<-EOT
    Autoscale minimum instance capacity.
    Evidence: data/appgw.json autoscaleConfiguration.minCapacity=1 (both gateways).
    NO DEFAULT (D-307) — capacity is a cost/scaling decision.
  EOT
  type        = number
}

variable "agw_max_capacity" {
  description = <<-EOT
    Autoscale maximum instance capacity.
    Evidence: data/appgw.json autoscaleConfiguration.maxCapacity=2 (both gateways).
    NO DEFAULT (D-307) — capacity is a cost/scaling decision.
  EOT
  type        = number
}

# ---------------------------------------------------------------------------
# § Networking wiring (fed from module.networking outputs at root)
# ---------------------------------------------------------------------------

variable "agw_subnet_id" {
  description = <<-EOT
    Subnet ID for the Application Gateway's gateway_ip_configuration.
    Fed from module.networking.agw_subnet_id at root.
    prod:    agw-production-eastus-subnet (10.0.6.0/24)
    nonprod: agw-nonproduction-eastus-subnet (10.0.6.0/24)
    Evidence: vnets.json agw subnet; terraform/LD-Prod-EastUS-V2/main.tf:679-682.
    NO DEFAULT (D-307) — subnet ID is connectivity-critical.
  EOT
  type        = string
}

variable "agw_public_ip_id" {
  description = <<-EOT
    Resource ID of the Public IP for the AGW frontend.
    Fed from module.networking public_ip output (key "agw_prod" / "agw_common").
    prod:    pip-prod-eastus; nonprod: pip-common-nonproduction-eastus.
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:671-674.
    NO DEFAULT (D-307) — PIP ID is connectivity-critical.
  EOT
  type        = string
}

variable "key_vault_id" {
  description = <<-EOT
    Resource ID of the scope's Key Vault. Used for azurerm_role_assignment granting
    the AGW user-assigned identity 'Key Vault Secrets User' (T-03-25 / Shared 3).
    Fed from module.keyvault.key_vault_id at root.
    NO DEFAULT (D-307) — KV ID is connectivity-critical.
  EOT
  type        = string
}

# ---------------------------------------------------------------------------
# § Backend and routing configuration (map-driven, D-305)
# ---------------------------------------------------------------------------

variable "backend_address_pools" {
  description = <<-EOT
    Map of backend address pool definitions.
    Key = logical pool name; value = { name, fqdns, ip_addresses }.
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:568-599 (8 pools).
    D-305: map-driven, not N hand-written blocks.
    NO DEFAULT (D-307) — FQDN/IP targets differ between scopes.
  EOT
  type = map(object({
    name         = string
    fqdns        = list(string)
    ip_addresses = list(string)
  }))
}

variable "backend_http_settings" {
  description = <<-EOT
    Map of backend HTTP settings definitions.
    Key = logical settings name; value = per-settings config.
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:600-670 (8 entries).
    NO DEFAULT (D-307).
  EOT
  type = map(object({
    name                  = string
    cookie_based_affinity = string
    affinity_cookie_name  = string
    port                  = number
    protocol              = string
    request_timeout       = number
    probe_name            = string
    host_name             = string
  }))
}

variable "http_listeners" {
  description = <<-EOT
    Map of HTTP listener definitions.
    Key = logical listener name; value = { name, ssl_certificate_name, host_names, host_name }.
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:683-754 (8 listeners, all HTTPS + SNI).
    T-03-25: ssl_certificate_name references a cert entry in var.ssl_certificates (no literal keys).
    NO DEFAULT (D-307).
  EOT
  type = map(object({
    name                 = string
    ssl_certificate_name = string
    host_names           = list(string)
    host_name            = string
  }))
}

variable "probes" {
  description = <<-EOT
    Map of health probe definitions.
    Key = logical probe name; value = per-probe config.
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:759-854 (8 probes).
    NO DEFAULT (D-307).
  EOT
  type = map(object({
    name                = string
    host                = string
    path                = string
    interval            = number
    timeout             = number
    unhealthy_threshold = number
  }))
}

variable "request_routing_rules" {
  description = <<-EOT
    Map of request routing rule definitions.
    Key = logical rule name; value = per-rule config.
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:855-926 (8 rules, Basic type).
    NO DEFAULT (D-307).
  EOT
  type = map(object({
    name                       = string
    http_listener_name         = string
    backend_address_pool_name  = string
    backend_http_settings_name = string
    priority                   = number
    rewrite_rule_set_name      = string
  }))
}

variable "rewrite_rule_sets" {
  description = <<-EOT
    Map of rewrite rule sets (security headers + CORS response headers).
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:927-963
      "front-end-app-rewrite": X-Frame-Options, X-Content-Type-Options, HSTS, Referrer-Policy, Permission-Policy
      "Cros-Origin-Response": Access-Control-Allow-Origin: *
    NO DEFAULT (D-307) — rewrite rules differ between scopes (nonprod may omit some).
  EOT
  type = map(object({
    name = string
    rewrite_rules = list(object({
      name          = string
      rule_sequence = number
      response_headers = list(object({
        header_name  = string
        header_value = string
      }))
    }))
  }))
}

variable "ssl_certificates" {
  description = <<-EOT
    Map of SSL certificate entries for the Application Gateway.
    Key = logical cert name; value = { name, key_vault_secret_id }.
    T-03-25: Active certs use key_vault_secret_id (KV reference via managed identity — no literals).
             Historic date-tagged certs (uploaded via Portal) are omitted — they are not managed
             by Terraform and cause state drift if imported without the actual certificate data.
    Active KV-referenced certs evidence (prod main.tf:990-1050):
      api-ssl-prod-cert:      kvproductioneastus.vault.azure.net/secrets/api-ssl-prod-cert
      api-ssl-staging-cert:   kvproductioneastus.vault.azure.net/secrets/api-ssl-staging-cert
      apimgmt-ssl-prod-cert:  kvproductioneastus.vault.azure.net/secrets/apimgmt-ssl-prod-cert
      (+ additional KV refs from prod main.tf:1014-1050)
    NO DEFAULT (D-307) — cert names and KV refs differ between scopes.
    NO LITERAL CERTIFICATE DATA — key_vault_secret_id only (T-03-25 / HIPAA).
  EOT
  type = map(object({
    name                = string
    key_vault_secret_id = string
  }))
}

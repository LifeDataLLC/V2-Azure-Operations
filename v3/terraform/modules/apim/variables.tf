# modules/apim/variables.tf
# APIM module input variables
#
# DESIGN PRINCIPLES:
#   D-307: NO `default` on posture/divergence/connectivity-critical variables.
#          apim_sku_name, apim_vnet_type, apim_subnet_id: no default.
#   D-308: Invariant constants (identical across ALL instances) may carry defaults
#          in module internals — but NOT here at the variable declaration level.
#   T-03-27: Named values flagged as secret MUST NOT have literal values authored.
#            They are declared in the tfvars as secret=true with no value field.
#
# Evidence:
#   data/apim_services.json — SKU, vnet_type, hostname configs per instance
#   data/apim_security.json — named value values for ldapim-eastus-dev (only plain instance)
#   data/apim_full/INVENTORY.md — per-instance child counts
#   data/apim_full/<instance>/{apis,products,named_values,subscriptions,policy_fragments}.json

# ---------------------------------------------------------------------------
# § Service-level variables
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Pre-created resource group name (D-311). Passed from root data.azurerm_resource_group.this.name."
  type        = string
}

variable "location" {
  description = "Azure region. Passed from root data.azurerm_resource_group.this.location. Always eastus for this estate."
  type        = string
}

variable "apim_name" {
  description = <<-EOT
    Name of the APIM service instance (D-307 NO DEFAULT — connectivity-critical).
    Values per instance:
      nonprod scope: "apim-common-nonproduction-eastus", "ldapim-eastus-dev"
      prod scope:    "apim-staging-eastus", "ldapim-prod-eastus", "ldapim-prod-stv2-eastus"
    Evidence: apim_services.json name field.
  EOT
  type        = string
}

variable "apim_publisher_name" {
  description = <<-EOT
    APIM publisher display name.
    Evidence: apim_services.json publisherName = "LifeData LLC."
  EOT
  type        = string
}

variable "apim_publisher_email" {
  description = <<-EOT
    APIM publisher email.
    Evidence: apim_services.json publisherEmail = "amalesh.debnath@gmail.com"
  EOT
  type        = string
}

variable "apim_sku_name" {
  description = <<-EOT
    SKU name for the APIM service (D-307 NO DEFAULT — mid-migration posture preserved).
    Format: "<tier>_<capacity>" e.g. "Developer_1", "StandardV2_1".
    Per instance (evidence: apim_services.json sku.name + sku.capacity):
      apim-common-nonproduction-eastus: Developer_1
      ldapim-eastus-dev:                Developer_1
      apim-staging-eastus:              Developer_1
      ldapim-prod-eastus:               Developer_1
      ldapim-prod-stv2-eastus:          StandardV2_1
    M4: consolidate 5→3 instances (D-DEFER). M1 preserves current posture.
    T-03-30: No normalization of mid-migration pair — both Developer+StandardV2 preserved.
  EOT
  type        = string

  validation {
    condition     = can(regex("^(Developer|StandardV2|Premium|Basic|Consumption)_[0-9]+$", var.apim_sku_name))
    error_message = "apim_sku_name must be in format '<Tier>_<capacity>' (e.g. Developer_1, StandardV2_1)."
  }
}

variable "apim_vnet_type" {
  description = <<-EOT
    VNet integration type for the APIM instance (D-307 NO DEFAULT).
    Values: "Internal" | "External" | "None"
    Per instance (evidence: apim_services.json virtualNetworkType):
      apim-common-nonproduction-eastus: "Internal"  (Developer SKU, VNet-injected, apim2-nonproduction-eastus-subnet)
      ldapim-eastus-dev:                "Internal"  (Developer SKU, VNet-injected, apim2-nonproduction-eastus-subnet)
      apim-staging-eastus:              "Internal"  (Developer SKU, VNet-injected, apim-production-eastus-subnet)
      ldapim-prod-eastus:               "None"      (Developer SKU, no VNet integration)
      ldapim-prod-stv2-eastus:          "External"  (StandardV2, VNet-integrated, ldapim-prod-stv2-eastus-outbound-subnet)
  EOT
  type        = string

  validation {
    condition     = contains(["Internal", "External", "None"], var.apim_vnet_type)
    error_message = "apim_vnet_type must be one of: Internal, External, None."
  }
}

variable "apim_subnet_id" {
  description = <<-EOT
    Subnet ID for VNet integration (D-307 NO DEFAULT for VNet-type instances).
    Set to "" (empty string) for instances with vnet_type="None".
    Provided by module.networking.apim_subnet_id (legacy Developer SKU subnets).
    Evidence: vnets.json subnets per scope.
  EOT
  type        = string
}

variable "apim_hostname_configurations" {
  description = <<-EOT
    Hostname configuration object for custom domains. Object with optional keys:
      proxy         = list({ host_name, key_vault_id, default_ssl_binding })
      management    = list({ host_name, key_vault_id })
      portal        = list({ host_name, key_vault_id })
      developer_portal = list({ host_name, key_vault_id })
    Use {} (empty map) for instances without custom hostname configurations.
    Evidence: apim_services.json hostnameConfigurations per instance.
    T-03-25: SSL certs referenced via KV ID (key_vault_id) — no cert data literals.
  EOT
  type = object({
    proxy            = optional(list(object({ host_name = string, key_vault_id = optional(string), default_ssl_binding = optional(bool, false), negotiate_client_certificate = optional(bool, false) })), [])
    management       = optional(list(object({ host_name = string, key_vault_id = optional(string) })), [])
    portal           = optional(list(object({ host_name = string, key_vault_id = optional(string) })), [])
    developer_portal = optional(list(object({ host_name = string, key_vault_id = optional(string) })), [])
  })
  default = {
    proxy            = []
    management       = []
    portal           = []
    developer_portal = []
  }
}

# ---------------------------------------------------------------------------
# § AAD B2C Identity Provider (prod instances only)
# ---------------------------------------------------------------------------

variable "apim_aad_identity_provider_enabled" {
  description = <<-EOT
    Enable the AAD B2C identity provider on this APIM instance.
    Only prod-scope instances have this configured.
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:273-282 (azurerm_api_management_identity_provider_aad).
  EOT
  type        = bool
  default     = false
}

variable "apim_aad_client_id" {
  description = "B2C App Registration client ID for the APIM identity provider (prod only). Set to empty string when apim_aad_identity_provider_enabled=false."
  type        = string
  default     = ""
}

variable "apim_aad_client_secret" {
  description = "B2C App Registration client secret for the APIM identity provider (prod only). Sensitive. Set to empty string when apim_aad_identity_provider_enabled=false."
  type        = string
  sensitive   = true
  default     = ""
}

variable "apim_aad_allowed_tenants" {
  description = "List of AAD tenant IDs allowed for the identity provider. Evidence: LD-Prod main.tf:278."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# § Service policy (D-309: full child clone)
# ---------------------------------------------------------------------------

variable "apim_service_policy_xml_path" {
  description = <<-EOT
    Path (relative to modules/apim/) to the service-level policy XML file.
    Format: "policies/<instance>/service.policy.xml"
    Set per-instance call in root main.tf — references the copied asset.
    Evidence: data/apim_full/<instance>/service.policy.xml (acquired per D-310a).
  EOT
  type        = string
}

# ---------------------------------------------------------------------------
# § Child graph variables (D-309 — full child clone, D-305 exception)
# ---------------------------------------------------------------------------
# These are map-driven variables — the module iterates over them via for_each.
# All maps are NO-DEFAULT (D-307): per-instance data is set in tfvars.

variable "apim_apis" {
  description = <<-EOT
    Map of APIs to create on this APIM instance. Key = API name (stable for_each address).
    Each object carries:
      display_name         — friendly name
      path                 — URL path prefix
      service_url          — backend service URL
      subscription_required — bool
      openapi_path         — path relative to modules/apim/ for the import{} block
                             (format: "openapi/<instance>/<api>.openapi.yaml")
    Evidence: data/apim_full/<instance>/apis.json — one entry per API.
    D-309: Import {} block auto-creates operations from the exported OpenAPI spec.
    NO DEFAULT — set per instance in tfvars.
  EOT
  type = map(object({
    display_name          = string
    path                  = string
    service_url           = optional(string, "")
    subscription_required = optional(bool, false)
    openapi_path          = string
    policy_xml_path       = optional(string, "") # "" = no API-level policy (inherits service)
  }))
}

variable "apim_products" {
  description = <<-EOT
    Map of products for this APIM instance. Key = product name.
    Evidence: data/apim_full/<instance>/products.json.
    D-309: Full child clone — all products authored.
    NO DEFAULT — set per instance in tfvars.
  EOT
  type = map(object({
    display_name          = string
    description           = optional(string, "")
    state                 = optional(string, "published") # "published" | "notPublished"
    subscription_required = optional(bool, false)
    subscriptions_limit   = optional(number, null)
    approval_required     = optional(bool, null)
    api_names             = list(string) # list of API names (keys) to link to this product
  }))
}

variable "apim_named_values" {
  description = <<-EOT
    Map of named values for this APIM instance. Key = named value name.
    Evidence: data/apim_full/<instance>/named_values.json.
    T-03-27 (SECURITY): Named values with secret=true MUST NOT have a value field authored.
      They are declared with secret=true and no value.
      Post-apply, the actual values must be set manually or via KV-backed named values.
    Non-secret named values (secret=false) carry their value in the tfvars.
    D-309: Full clone — all named values authored (secret ones as secret=true, no literal value).
    NO DEFAULT — set per instance in tfvars.
  EOT
  type = map(object({
    display_name = string
    secret       = optional(bool, false)
    value        = optional(string, null) # null for secret=true entries (T-03-27)
  }))
}

variable "apim_subscriptions" {
  description = <<-EOT
    Map of subscriptions for this APIM instance. Key = subscription name/id.
    Evidence: data/apim_full/<instance>/subscriptions.json.
    Subscriptions scoped to products (product/* scope).
    The built-in "master" subscription is managed by Azure — NOT authored here.
    D-309: Full child clone — all non-master subscriptions authored.
    NO DEFAULT — set per instance in tfvars.
  EOT
  type = map(object({
    display_name  = optional(string, null)
    product_name  = optional(string, null) # product key (null = all-apis scope)
    allow_tracing = optional(bool, false)
    state         = optional(string, "active")
  }))
}

variable "apim_policy_fragments" {
  description = <<-EOT
    Map of policy fragments for this APIM instance. Key = fragment name.
    Evidence: data/apim_full/<instance>/policy_fragments.json.
    D-309: Full child clone — all fragments authored inline.
    T-03-29: B2C validate-jwt + CORS fragments cloned verbatim (positive auth posture preserved).
    NO DEFAULT — set per instance in tfvars.
  EOT
  type = map(object({
    description = optional(string, "")
    value       = string # the fragment XML content
  }))
}

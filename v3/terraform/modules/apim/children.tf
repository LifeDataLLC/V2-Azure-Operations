# modules/apim/children.tf
# Full APIM child graph — the D-309 full child clone (explicit D-305 exception).
#
# RESOURCE TYPES AUTHORED (AUTH-03 / D-309):
#   azurerm_api_management_policy          — service-level policy
#   azurerm_api_management_api             — APIs (with import{} for operations auto-gen)
#   azurerm_api_management_api_policy      — per-API policies (where exists)
#   azurerm_api_management_product         — products
#   azurerm_api_management_product_api     — product↔API links
#   azurerm_api_management_named_value     — named values (secret and non-secret)
#   azurerm_api_management_subscription    — subscriptions (non-master)
#   azurerm_api_management_policy_fragment — policy fragments (B2C JWT + CORS + others)
#
# DESIGN NOTES:
#   - All resources use for_each over the corresponding map variable (D-303).
#   - Operations are auto-generated via import{} from exported OpenAPI specs (Pattern 6).
#   - Explicit azurerm_api_management_api_operation is NOT used — import{} suffices.
#     (Open Question 2 resolved: per-operation policies exist only in operation.policies
#     within ops.json — the acquisition shows policies=null on all operations checked.)
#   - Named values with secret=true have no value authored (T-03-27).
#   - Policy fragments cloned verbatim (T-03-29 — positive auth posture preserved).
#   - The "master" subscription is Azure-managed and NOT authored here.
#
# Evidence:
#   data/apim_full/<instance>/apis.json, products.json, named_values.json,
#   subscriptions.json, policy_fragments.json, policies/*.xml, openapi/*.yaml

# ---------------------------------------------------------------------------
# § Service-level policy
# ---------------------------------------------------------------------------
# Evidence: data/apim_full/<instance>/service.policy.xml
# Cloned verbatim — includes CORSPolicy fragment reference + Authorization header passthrough.

resource "azurerm_api_management_policy" "service" {
  api_management_id = azurerm_api_management.this.id
  xml_content       = file("${path.module}/${var.apim_service_policy_xml_path}")
}

# ---------------------------------------------------------------------------
# § Policy Fragments (D-309 / T-03-29)
# ---------------------------------------------------------------------------
# B2C validate-jwt (MobileROPCAccessTokenValidatePolicy, WebAccessTokenValidatePolicy,
# TaskInboundPolicy), CORS (CORSPolicy), Blob/Queue storage access policies, etc.
# Cloned verbatim — the positive auth posture is preserved exactly.
# Evidence: data/apim_full/<instance>/policy_fragments.json

resource "azurerm_api_management_policy_fragment" "this" {
  for_each = var.apim_policy_fragments

  api_management_id = azurerm_api_management.this.id
  name              = each.key
  description       = each.value.description
  value             = each.value.value

  depends_on = [azurerm_api_management.this]
}

# ---------------------------------------------------------------------------
# § APIs (with import{} — auto-generates operations, D-309/Pattern 6)
# ---------------------------------------------------------------------------
# Each API imports its OpenAPI 3.0.1 spec from the copied asset directory.
# This auto-creates all operations — no explicit azurerm_api_management_api_operation needed.
# Evidence: data/apim_full/<instance>/apis.json + openapi/<api>.openapi.yaml

resource "azurerm_api_management_api" "this" {
  for_each = var.apim_apis

  name                  = each.key
  api_management_name   = azurerm_api_management.this.name
  resource_group_name   = var.resource_group_name
  revision              = "1"
  display_name          = each.value.display_name
  path                  = each.value.path
  protocols             = ["https"]
  service_url           = each.value.service_url != "" ? each.value.service_url : null
  subscription_required = each.value.subscription_required

  import {
    content_format = "openapi"
    content_value  = file("${path.module}/${each.value.openapi_path}")
  }

  depends_on = [azurerm_api_management.this]
}

# ---------------------------------------------------------------------------
# § API-level policies (where they exist — not all APIs have an API-level policy)
# ---------------------------------------------------------------------------
# Only APIs with a non-empty policy_xml_path get an explicit policy resource.
# Evidence: data/apim_full/<instance>/policies/<api>.policy.xml
# APIs without a policy file inherit from the service-level policy.

resource "azurerm_api_management_api_policy" "this" {
  for_each = {
    for name, api in var.apim_apis : name => api
    if api.policy_xml_path != ""
  }

  api_name            = each.key
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  xml_content         = file("${path.module}/${each.value.policy_xml_path}")

  depends_on = [azurerm_api_management_api.this]
}

# ---------------------------------------------------------------------------
# § Products (D-309)
# ---------------------------------------------------------------------------
# Evidence: data/apim_full/<instance>/products.json

resource "azurerm_api_management_product" "this" {
  for_each = var.apim_products

  product_id            = each.key
  api_management_name   = azurerm_api_management.this.name
  resource_group_name   = var.resource_group_name
  display_name          = each.value.display_name
  description           = each.value.description != "" ? each.value.description : null
  published             = each.value.state == "published"
  subscription_required = each.value.subscription_required
  subscriptions_limit   = each.value.subscriptions_limit
  approval_required     = each.value.approval_required

  depends_on = [azurerm_api_management.this]
}

# ---------------------------------------------------------------------------
# § Product↔API Links (D-309)
# ---------------------------------------------------------------------------
# Links are expressed as product.api_names in the products map.
# We flatten the list to a map keyed by "<product>-<api>" for stable for_each addresses.

locals {
  product_api_links = merge([
    for prod_name, prod in var.apim_products : {
      for api_name in prod.api_names : "${prod_name}--${api_name}" => {
        product_name = prod_name
        api_name     = api_name
      }
    }
  ]...)
}

resource "azurerm_api_management_product_api" "this" {
  for_each = local.product_api_links

  product_id          = each.value.product_name
  api_name            = each.value.api_name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name

  depends_on = [
    azurerm_api_management_product.this,
    azurerm_api_management_api.this,
  ]
}

# ---------------------------------------------------------------------------
# § Named Values (D-309 / T-03-27)
# ---------------------------------------------------------------------------
# Non-secret named values carry their value explicitly.
# Secret named values (B2C client IDs, issuer URLs, storage account names) are authored
# with secret=true and NO value — the actual value must be set post-apply via:
#   - KV-backed named value (preferred for M3): key_vault_secret_id
#   - Manual portal update (acceptable for M1 dev scope)
# T-03-27: No secret literal values authored. This satisfies the threat mitigation.
# Evidence: data/apim_full/<instance>/named_values.json

resource "azurerm_api_management_named_value" "this" {
  for_each = var.apim_named_values

  name                = each.key
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  display_name        = each.value.display_name
  secret              = each.value.secret

  # Only set value for non-secret named values (T-03-27)
  # Secret named values have value=null in the tfvars (no literal authored)
  value = each.value.secret ? null : each.value.value

  depends_on = [azurerm_api_management.this]
}

# ---------------------------------------------------------------------------
# § Subscriptions (D-309)
# ---------------------------------------------------------------------------
# Product-scoped subscriptions from the live acquisition.
# The "master" (all-access) subscription is Azure-managed — NOT authored.
# Subscription keys are auto-generated by Azure — never authored as literals.
# Evidence: data/apim_full/<instance>/subscriptions.json

resource "azurerm_api_management_subscription" "this" {
  for_each = var.apim_subscriptions

  subscription_id     = each.key
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  display_name        = each.value.display_name != null ? each.value.display_name : each.key
  product_id          = each.value.product_name != null ? azurerm_api_management_product.this[each.value.product_name].id : null
  allow_tracing       = each.value.allow_tracing
  state               = each.value.state

  depends_on = [azurerm_api_management_product.this]
}

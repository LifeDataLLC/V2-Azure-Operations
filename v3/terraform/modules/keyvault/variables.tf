# modules/keyvault/variables.tf — Key Vault module variable surface
#
# DESIGN PRINCIPLES:
#   D-306: kv_enable_rbac_authorization is THE no-default divergence variable anchoring
#          the prod-vs-nonprod auth model split. prod.tfvars=false (legacy access policies,
#          an F-finding). nonprod.tfvars=true (RBAC). M3 flips prod→true via a reviewed tfvars diff.
#   D-307: NO `default` on risk-bearing or posture variables.
#   D-302: Scope-shared — one vault per scope (kvproductioneastus for prod, kvnonproductioneastus for nonprod).
#   T-03-17: kv_enable_rbac_authorization no-default (D-306); prod=false/nonprod=true explicit.
#
# EVIDENCE:
#   data/keyvaults_detail.json    — enableRbacAuthorization, accessPolicies, networkAcls
#   data/FINDINGS-DATA.md §Key Vaults — KV divergence, the F-finding on prod legacy access-policies
#   terraform/LD-NonProd-EastUS-V2/main.tf:515-522  (nonprod KV analog — RBAC=true)
#   terraform/LD-Prod-EastUS-V2/main.tf:520-527     (prod KV analog — access-policy=true)

# ---------------------------------------------------------------------------
# § Scope identity (passed from root)
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the pre-created V3 resource group (D-311). Passed from data.azurerm_resource_group.this.name at root."
  type        = string
}

variable "location" {
  description = "Azure region for the Key Vault. Passed from data.azurerm_resource_group.this.location at root. Both KVs are in eastus (evidence: keyvaults_detail.json)."
  type        = string
}

# ---------------------------------------------------------------------------
# § Vault identity
# ---------------------------------------------------------------------------

variable "kv_name" {
  description = <<-EOT
    Name of the Key Vault resource.
    nonprod: "kvnonproductioneastus"  (evidence: keyvaults_detail.json name)
    prod:    "kvproductioneastus"     (evidence: keyvaults_detail.json name)
    Set per-scope in nonprod.tfvars / prod.tfvars (D-307 no-default — name is connectivity-critical).
  EOT
  type        = string
}

variable "kv_sku_name" {
  description = <<-EOT
    SKU of the Key Vault. Both vaults use "standard".
    Evidence: keyvaults_detail.json properties.sku.name="Standard" (both vaults).
    Set per-scope in tfvars (D-307 — explicit even for uniform values).
  EOT
  type        = string

  validation {
    condition     = contains(["standard", "premium"], var.kv_sku_name)
    error_message = "kv_sku_name must be 'standard' or 'premium'."
  }
}

# ---------------------------------------------------------------------------
# § D-306: The RBAC-vs-access-policy divergence anchor
# ---------------------------------------------------------------------------

variable "kv_enable_rbac_authorization" {
  description = <<-EOT
    KV authentication model — the D-306 divergence anchor (T-03-17).
    nonprod.tfvars = true  — kvnonproductioneastus uses Azure RBAC for data-plane access.
                             Evidence: keyvaults_detail.json kvnonproductioneastus enableRbacAuthorization=true.
    prod.tfvars    = false — kvproductioneastus uses legacy access policies (an F-finding).
                             Evidence: keyvaults_detail.json kvproductioneastus enableRbacAuthorization=false.
    M3 flips prod→true (after confirming role assignments exist).
    NO DEFAULT (D-307) — auth model is a deliberate per-scope security decision.
  EOT
  type        = bool
  # NO default — fails fast at plan time if not set (D-307)
}

# ---------------------------------------------------------------------------
# § Network posture (D-307 no-default, M1 preserve, M3 flip)
# ---------------------------------------------------------------------------

variable "kv_network_default_action" {
  description = <<-EOT
    Network ACL default action for the Key Vault.
    M1 value: "Allow" on both scopes (public network access enabled).
    Evidence: keyvaults_detail.json networkAcls.defaultAction="Allow" (both vaults).
    M3 flips to "Deny" + explicit subnet rules (T-03-17 / Shared 4).
    NO DEFAULT (D-307) — network exposure is an explicit per-scope risk decision.
  EOT
  type        = string

  validation {
    condition     = contains(["Allow", "Deny"], var.kv_network_default_action)
    error_message = "kv_network_default_action must be 'Allow' or 'Deny'."
  }
}

variable "kv_public_network_access_enabled" {
  description = <<-EOT
    Whether public network access is enabled for the Key Vault.
    M1 value: true on both scopes.
    Evidence: keyvaults_detail.json publicNetworkAccess="Enabled" (both vaults).
    M3 flips to false.
    NO DEFAULT (D-307) — public exposure is a deliberate risk decision.
  EOT
  type        = bool
}

# ---------------------------------------------------------------------------
# § Subnet wiring (networking module contract)
# ---------------------------------------------------------------------------

variable "keyvault_subnet_id" {
  description = <<-EOT
    Subnet ID of the Key Vault service-endpoint subnet in this scope's VNet.
    Wired from module.networking.keyvault_subnet_id at root.
    nonprod: kv-nonproduction-eastus-subnet (10.0.7.0/24)
    prod:    kv-production-eastus-subnet (10.0.7.0/24)
    Used in network_acls.virtual_network_subnet_ids when kv_network_default_action="Deny".
  EOT
  type        = string
}

# ---------------------------------------------------------------------------
# § Access policy inputs (prod only — used when kv_enable_rbac_authorization=false)
# ---------------------------------------------------------------------------

variable "kv_access_policies" {
  description = <<-EOT
    List of access policy objects for the Key Vault.
    Used only when kv_enable_rbac_authorization=false (prod scope, legacy access-policy mode).
    When kv_enable_rbac_authorization=true, this must be empty list (RBAC mode uses role assignments instead).

    Each policy carries:
      object_id    — AAD object ID of the principal (user, group, or service principal)
      tenant_id    — AAD tenant ID (always b504d3d4-ffb7-40f4-b25a-97ccb228fde3)
      secret_permissions      — list of secret permissions (e.g. ["Get", "List"])
      key_permissions         — list of key permissions
      certificate_permissions — list of certificate permissions

    Evidence: keyvaults_detail.json kvproductioneastus.properties.accessPolicies (8 policies)
              keyvaults_detail.json kvnonproductioneastus.properties.accessPolicies (8 policies, ignored in RBAC mode)
    NO DEFAULT (D-307) — access policy surface is a deliberate per-scope auth decision.
  EOT
  type = list(object({
    object_id               = string
    tenant_id               = string
    secret_permissions      = list(string)
    key_permissions         = list(string)
    certificate_permissions = list(string)
  }))
  # NO default — caller supplies the full list per scope (D-307)
}

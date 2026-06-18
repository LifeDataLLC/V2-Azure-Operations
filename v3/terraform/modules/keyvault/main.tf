# modules/keyvault/main.tf — Key Vault (scope-shared, one per scope — D-302)
#
# DESIGN PRINCIPLES:
#   D-306: The RBAC-vs-access-policy divergence is parameterized via kv_enable_rbac_authorization
#          (no-default bool). prod=false (access-policy mode); nonprod=true (RBAC mode).
#          M3 flips prod→true via a reviewed tfvars diff — no code change needed.
#   D-302: Scope-shared — exactly ONE vault per scope. Root calls this module ONCE (no for_each).
#   D-305: Architectural fidelity — purge_protection, soft_delete, network_acls, tenant_id preserved.
#   D-311: resource_group_name = var.resource_group_name (pre-created RG reference, not managed).
#   T-03-17: kv_enable_rbac_authorization no-default; access_policy blocks gated on !RBAC.
#
# ANALOG:
#   terraform/LD-NonProd-EastUS-V2/main.tf:515-522  (nonprod KV — minimal export, RBAC=true)
#   terraform/LD-Prod-EastUS-V2/main.tf:520-527      (prod KV — minimal export, access-policy=true)
#   data/keyvaults_detail.json                        (full network_acls, access_policy, RBAC flags)

# ---------------------------------------------------------------------------
# § Key Vault (the common vault for this scope)
# ---------------------------------------------------------------------------

resource "azurerm_key_vault" "this" {
  name                = var.kv_name
  resource_group_name = var.resource_group_name
  location            = var.location

  # D-306: THE divergence anchor — bool, no default.
  # nonprod=true (RBAC), prod=false (legacy access policies).
  # When true, access_policy blocks below are skipped (RBAC manages data-plane access via role assignments).
  # Evidence: keyvaults_detail.json enableRbacAuthorization per vault.
  enable_rbac_authorization = var.kv_enable_rbac_authorization

  sku_name = var.kv_sku_name

  # Tenant ID for the LifeData AAD tenant (D-308 constant — same for both scopes)
  # Evidence: keyvaults_detail.json properties.tenantId = "b504d3d4-ffb7-40f4-b25a-97ccb238fde3"
  tenant_id = "b504d3d4-ffb7-40f4-b25a-97ccb238fde3"

  # D-305: Purge protection and soft-delete enabled on both vaults
  # Evidence: keyvaults_detail.json enablePurgeProtection=true, enableSoftDelete=true (both vaults)
  purge_protection_enabled   = true
  soft_delete_retention_days = 90 # evidence: softDeleteRetentionInDays=90 (both vaults)

  # D-307: Public network access — no-default var; M1=true; M3=false
  public_network_access_enabled = var.kv_public_network_access_enabled

  # D-307: Network ACL — default action is no-default; M1=Allow; M3=Deny
  # VNet subnet rules are present in the live estate (keyvaults_detail.json networkAcls.virtualNetworkRules)
  # When default_action=Allow, VNet rules provide additional-allow (belt-and-suspenders);
  # when default_action=Deny (M3), the subnet rule becomes the sole authorized path.
  network_acls {
    default_action             = var.kv_network_default_action
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [var.keyvault_subnet_id]
  }

  # D-306: Access policy blocks — authored only when kv_enable_rbac_authorization=false (prod, M1)
  # When RBAC=true (nonprod), access policies are ignored by Azure even if present;
  # the dynamic block produces zero blocks in RBAC mode, keeping HCL clean.
  # Evidence: keyvaults_detail.json kvproductioneastus.properties.accessPolicies (8 entries)
  dynamic "access_policy" {
    for_each = var.kv_enable_rbac_authorization ? [] : var.kv_access_policies
    content {
      tenant_id               = access_policy.value.tenant_id
      object_id               = access_policy.value.object_id
      secret_permissions      = access_policy.value.secret_permissions
      key_permissions         = access_policy.value.key_permissions
      certificate_permissions = access_policy.value.certificate_permissions
    }
  }
}

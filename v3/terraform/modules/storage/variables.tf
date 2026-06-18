# modules/storage/variables.tf — Storage module variable surface
#
# DESIGN PRINCIPLES:
#   D-307: NO `default` on risk-bearing or posture variables.
#          Every posture value must be set explicitly by the caller (root tfvars).
#   D-303: accounts map drives for_each — one module body, many accounts.
#   D-305: Architectural fidelity; reproduce all 8 accounts (4 nonprod + 4 prod).
#   T-03-15: No storage key / SAS literals anywhere in this module.
#   T-03-16: Posture (blob public, shared-key, network defaults) as no-default vars;
#            M1 preserves current state; M3 flips.
#
# EVIDENCE:
#   data/storage_accounts.json  — nonprod posture (allowBlobPublicAccess, allowSharedKeyAccess, minimumTlsVersion, networkRuleSet)
#   data/prod_storage_accounts.json — prod posture (absent from aztfexport; live read from Plan 03-02)
#   data/FINDINGS-DATA.md §Storage — canonical posture table
#   terraform/LD-NonProd-EastUS-V2/main.tf:1694-2400 — nonprod account HCL shape + containers/queues/tables

# ---------------------------------------------------------------------------
# § Scope identity (passed from root)
# ---------------------------------------------------------------------------

variable "resource_group_name" {
  description = "Name of the pre-created V3 resource group (D-311). Passed from data.azurerm_resource_group.this.name at root."
  type        = string
}

variable "location" {
  description = "Azure region for storage accounts. Passed from data.azurerm_resource_group.this.location at root. Note: stldprodeastus2 is in eastus2 and lifelatapublic is in westus — those accounts override this via per-account location in the accounts map."
  type        = string
}

# ---------------------------------------------------------------------------
# § Subnet wiring (networking module contract)
# ---------------------------------------------------------------------------

variable "storage_subnet_id" {
  description = <<-EOT
    Subnet ID of the storage service-endpoint subnet in this scope's VNet.
    Wired from module.networking.storage_subnet_id at root.
    nonprod: storage-nonproduction-eastus-subnet (10.0.8.0/24)
    prod:    storage-production-eastus-subnet (10.0.8.0/24)
    Used in network_acls.virtual_network_subnet_ids on accounts that have VNet rules.
  EOT
  type        = string
}

# ---------------------------------------------------------------------------
# § Storage account map (D-303: one module body drives all accounts via for_each)
# ---------------------------------------------------------------------------

variable "accounts" {
  description = <<-EOT
    Map of storage accounts to create in this module call.
    Key = logical account key (used as Terraform resource address).
    Value = per-account configuration object.

    Each account object carries:
      name                      — Azure storage account name (globally unique, lowercase, 3-24 chars)
      location                  — Azure region (most are eastus; stldprodeastus2=eastus2, lifelatapublic=westus)
      account_replication_type  — D-307 no-default: prod=RA-GRS / RAGRS, others=LRS.
                                  Evidence: storage_accounts.json sku.name per account.
      allow_nested_items_to_be_public — D-307 no-default blob public access.
                                  Evidence: storage_accounts.json allowBlobPublicAccess per account.
                                  M1: true on 7/8 (false only on ldfstnonproductioneastus).
                                  M3 flips all to false (T-03-16).
      shared_access_key_enabled — D-307 no-default shared-key auth.
                                  Evidence: storage_accounts.json allowSharedKeyAccess per account.
                                  M1: false on ldfstnonproductioneastus; true on others.
                                  M3 flips all to false.
      min_tls_version           — D-307 no-default per-account TLS minimum.
                                  Evidence: storage_accounts.json minimumTlsVersion per account.
                                  M1: TLS1_2 on all except ldstqaeastus=TLS1_0 (T-03-18 exception).
                                  WHATS-DIFFERENT records the TLS1_0 exception.
      network_default_action    — D-307 no-default network ACL default action.
                                  Evidence: storage_accounts.json networkRuleSet.defaultAction.
                                  M1: Allow on all. M3 flips to Deny.
      large_file_shares_enabled — Whether large file share support is enabled.
                                  Evidence: storage_accounts.json largeFileSharesState.
                                  stldprodeastus2=true; others=false.
      sas_expiry_period         — Optional SAS expiration period (e.g. "1.00:00:00"). "" = no sas_policy block.
                                  Evidence: storage_accounts.json sasPolicy.sasExpirationPeriod.
      containers                — List of blob container names to create under this account.
      container_access_types    — Map of container_name -> access_type for containers that need non-private access.
                                  Most containers are private (""); only "study-content" (ldstdeveastus) is "blob".
                                  Evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1792.
      queues                    — List of storage queue names.
      tables                    — List of storage table names.
      file_shares               — Map of share_name -> quota_gb for file shares.
      queue_logging_enabled     — Whether queue_properties logging block is authored (D-305: present on ldstdeveastus/ldstqaeastus).
  EOT
  type = map(object({
    name                            = string
    location                        = string
    account_replication_type        = string
    allow_nested_items_to_be_public = bool
    shared_access_key_enabled       = bool
    min_tls_version                 = string
    network_default_action          = string
    large_file_shares_enabled       = bool
    sas_expiry_period               = string
    containers                      = list(string)
    container_access_types          = map(string)
    queues                          = list(string)
    tables                          = list(string)
    file_shares                     = map(number)
    queue_logging_enabled           = bool
  }))
  # NO default — caller (root) supplies the full accounts map per scope (D-307)
}

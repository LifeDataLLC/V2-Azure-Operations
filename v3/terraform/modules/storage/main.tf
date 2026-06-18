# modules/storage/main.tf — Storage accounts + child resources
#
# DESIGN PRINCIPLES:
#   D-303: One module body; for_each over var.accounts drives all accounts.
#   D-302: Called twice at root — once for scope-shared accounts, once per-env via for_each.
#   D-305: Architectural fidelity — all 8 accounts reproduced (4 nonprod + 4 prod absent from export).
#   D-311: resource_group_name = var.resource_group_name (pre-created RG reference, not managed).
#   T-03-15: No storage account keys or SAS tokens authored anywhere.
#   T-03-16: Posture (blob public, shared-key, network defaults) as no-default vars.
#   T-03-18: min_tls_version is per-account (ldstqaeastus = TLS1_0 exception).
#
# ANALOG:
#   terraform/LD-NonProd-EastUS-V2/main.tf:1694-2400 (account + child shapes)
#   data/storage_accounts.json, data/prod_storage_accounts.json (posture evidence)

# ---------------------------------------------------------------------------
# § Storage Accounts (for_each over var.accounts map — D-303)
# ---------------------------------------------------------------------------

resource "azurerm_storage_account" "this" {
  for_each = var.accounts

  name                = each.value.name
  resource_group_name = var.resource_group_name
  location            = each.value.location

  account_tier             = "Standard"
  account_replication_type = each.value.account_replication_type

  # D-307 no-default posture vars — evidence: storage_accounts.json per account
  allow_nested_items_to_be_public = each.value.allow_nested_items_to_be_public
  shared_access_key_enabled       = each.value.shared_access_key_enabled
  min_tls_version                 = each.value.min_tls_version
  https_traffic_only_enabled      = true # D-308 constant — uniform true across all 8 accounts

  # D-307: Network ACL — default action is no-default per account; M1=Allow; M3=Deny
  network_rules {
    default_action             = each.value.network_default_action
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = each.value.network_default_action == "Allow" ? [] : [var.storage_subnet_id]
  }

  # Large file shares — only stldprodeastus2 has this enabled
  # evidence: storage_accounts.json stldprodeastus2 largeFileSharesState="Enabled"
  large_file_share_enabled = each.value.large_file_shares_enabled

  # SAS policy — present on ldstdeveastus (1.00:00:00) and lifelatapublic (3650.00:00:00)
  # evidence: storage_accounts.json sasPolicy.sasExpirationPeriod
  dynamic "sas_policy" {
    for_each = each.value.sas_expiry_period != "" ? [each.value.sas_expiry_period] : []
    content {
      expiration_period = sas_policy.value
      expiration_action = "Log"
    }
  }
}

# ---------------------------------------------------------------------------
# § Queue Properties (azurerm_storage_account_queue_properties)
# Present on ldstdeveastus and ldstqaeastus (D-305: all analog accounts with queues)
# Analog: terraform/LD-NonProd-EastUS-V2/main.tf:1827-1843 (ldstdeveastus)
#         terraform/LD-NonProd-EastUS-V2/main.tf:2073-2089 (ldstqaeastus)
# ---------------------------------------------------------------------------

resource "azurerm_storage_account_queue_properties" "this" {
  for_each = { for k, v in var.accounts : k => v if v.queue_logging_enabled }

  storage_account_id = azurerm_storage_account.this[each.key].id

  hour_metrics {
    include_apis          = true
    retention_policy_days = 7
    version               = "1.0"
  }

  logging {
    delete  = false
    read    = false
    version = "1.0"
    write   = false
  }

  minute_metrics {
    version = "1.0"
  }
}

# ---------------------------------------------------------------------------
# § Blob Containers (azurerm_storage_container)
# for_each over a flattened set of (account_key, container_name) pairs
# Analog: terraform/LD-NonProd-EastUS-V2/main.tf:1707-1826 (ldstdeveastus containers)
# ---------------------------------------------------------------------------

locals {
  # Flatten accounts -> containers into a map keyed by "account_key/container_name"
  containers = {
    for pair in flatten([
      for account_key, account_cfg in var.accounts : [
        for container_name in account_cfg.containers : {
          key         = "${account_key}/${container_name}"
          account_key = account_key
          name        = container_name
          access_type = lookup(account_cfg.container_access_types, container_name, "")
        }
      ]
    ]) : pair.key => pair
  }

  # Flatten accounts -> queues into a map keyed by "account_key/queue_name"
  queues = {
    for pair in flatten([
      for account_key, account_cfg in var.accounts : [
        for queue_name in account_cfg.queues : {
          key         = "${account_key}/${queue_name}"
          account_key = account_key
          name        = queue_name
        }
      ]
    ]) : pair.key => pair
  }

  # Flatten accounts -> tables into a map keyed by "account_key/table_name"
  tables = {
    for pair in flatten([
      for account_key, account_cfg in var.accounts : [
        for table_name in account_cfg.tables : {
          key         = "${account_key}/${table_name}"
          account_key = account_key
          name        = table_name
        }
      ]
    ]) : pair.key => pair
  }

  # Flatten accounts -> file_shares into a map keyed by "account_key/share_name"
  file_shares = {
    for pair in flatten([
      for account_key, account_cfg in var.accounts : [
        for share_name, quota in account_cfg.file_shares : {
          key         = "${account_key}/${share_name}"
          account_key = account_key
          name        = share_name
          quota       = quota
        }
      ]
    ]) : pair.key => pair
  }
}

resource "azurerm_storage_container" "this" {
  for_each = local.containers

  name               = each.value.name
  storage_account_id = azurerm_storage_account.this[each.value.account_key].id

  # "" = private (default); "blob" or "container" where the live estate uses non-private
  # evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1792 study-content (ldstdeveastus) = "blob"
  #           terraform/LD-NonProd-EastUS-V2/main.tf:1690 b2c-signup-www (ldfstnonproductioneastus) = "container"
  container_access_type = each.value.access_type != "" ? each.value.access_type : null

  depends_on = [azurerm_storage_account_queue_properties.this]
}

# ---------------------------------------------------------------------------
# § Storage Queues (azurerm_storage_queue)
# Analog: terraform/LD-NonProd-EastUS-V2/main.tf:1844-2025 (ldstdeveastus queues)
#         terraform/LD-NonProd-EastUS-V2/main.tf:2090-2165 (ldstqaeastus queues)
# ---------------------------------------------------------------------------

resource "azurerm_storage_queue" "this" {
  for_each = local.queues

  name                 = each.value.name
  storage_account_name = azurerm_storage_account.this[each.value.account_key].name

  depends_on = [azurerm_storage_account_queue_properties.this]
}

# ---------------------------------------------------------------------------
# § Storage Tables (azurerm_storage_table)
# Analog: terraform/LD-NonProd-EastUS-V2/main.tf:2026-2041 (ldstdeveastus tables — AzureFunctionsDiagnosticEvents)
#         D-305: diagnostic event tables are ephemeral/rotating — model the pattern but don't clone all timestamps.
# ---------------------------------------------------------------------------

resource "azurerm_storage_table" "this" {
  for_each = local.tables

  name                 = each.value.name
  storage_account_name = azurerm_storage_account.this[each.value.account_key].name
}

# ---------------------------------------------------------------------------
# § File Shares (azurerm_storage_share)
# Analog: terraform/LD-NonProd-EastUS-V2/main.tf:2065-2071 (ldstqaeastus fapp-process-response, 100 GiB)
# ---------------------------------------------------------------------------

resource "azurerm_storage_share" "this" {
  for_each = local.file_shares

  name               = each.value.name
  quota              = each.value.quota
  storage_account_id = azurerm_storage_account.this[each.value.account_key].id
}

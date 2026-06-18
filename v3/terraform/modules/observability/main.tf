# modules/observability/main.tf — Observability module for the LifeData V3 estate
#
# DESIGN PRINCIPLES:
#   D-302: Scope-shared — one call per scope, no for_each at root.
#   D-305: Architectural fidelity:
#     - 1 Log Analytics workspace (prod only; nonprod scope has no dedicated workspace)
#     - App Insights instances (up to 3 in prod scope, 1 in nonprod) authored via for_each
#     - Action groups authored via for_each over var.action_groups map
#     - Metric alerts authored via for_each over var.alerts map (NOT N hand-written blocks)
#     - 672 built-in LA workspace tables and mid-migration linked-storage DROPPED as noise
#     - Genuine saved-search queries retained (business-value custom KQL)
#   D-307 / AUTH-01: alert scopes reference NEW estate module outputs — never old ARM paths.
#   M1 posture: default LA retention (≥365-day OBS milestone deferred to M2).
#   T-03-24: All scopes/action-group IDs re-pointed to new-estate resources via vars.
#   T-03-25: No instrumentation key literals — connection_string output only.
#
# ---------------------------------------------------------------------------
# § Log Analytics Workspace (prod scope only)
# ---------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "this" {
  count = var.log_analytics_workspace_name != "" ? 1 : 0

  name                = var.log_analytics_workspace_name
  location            = var.location
  resource_group_name = var.resource_group_name
  # M1: default retention (30 days). M2 (OBS milestone) flips to 365 for HIPAA.
  # retention_in_days is intentionally omitted (provider default = 30); M2 sets it explicitly.
  # Evidence: terraform/LD-Prod-EastUS-V2/main.tf:1519-1523 (no retention override in analog).
}

# ---------------------------------------------------------------------------
# § Saved Searches (prod scope — business-value custom KQL queries, NOT built-in tables)
# D-305: Drop 672 azurerm_log_analytics_workspace_table_custom_log (built-in noise).
# Retain the custom saved queries from the analog (res-2662 through res-2672 set).
# ---------------------------------------------------------------------------

resource "azurerm_log_analytics_saved_search" "this" {
  for_each = var.log_analytics_workspace_name != "" ? var.saved_searches : {}

  log_analytics_workspace_id = azurerm_log_analytics_workspace.this[0].id
  name                       = each.key
  category                   = each.value.category
  display_name               = each.value.display_name
  query                      = each.value.query
}

# ---------------------------------------------------------------------------
# § Application Insights instances
# Evidence:
#   nonprod: terraform/LD-NonProd-EastUS-V2/main.tf:3629-3635 (appi-common-nonproduction-eastus)
#   prod:    terraform/LD-Prod-EastUS-V2/main.tf:7343-7349    (appi-production-eastus)
#            terraform/LD-Prod-EastUS-V2/main.tf:8324-8333    (app-db-data-access-prod-eastus appi)
# D-305: sampling_percentage=0 (preserved from analog — no sampling in clinical workload).
# ---------------------------------------------------------------------------

resource "azurerm_application_insights" "this" {
  for_each = var.app_insights_instances

  name                = each.value.name
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = each.value.application_type
  sampling_percentage = each.value.sampling_percentage

  # workspace_id: wired to the LA workspace when present (prod scope).
  # Enables workspace-based mode (recommended over classic).
  # nonprod: no workspace → omit; prod: wire to azurerm_log_analytics_workspace.this[0].id
  workspace_id = var.log_analytics_workspace_name != "" ? azurerm_log_analytics_workspace.this[0].id : null
}

# ---------------------------------------------------------------------------
# § Monitor Action Groups
# Evidence: terraform/LD-Prod-EastUS-V2/main.tf:7174-7342 (7 action groups)
#           terraform/LD-NonProd-EastUS-V2/main.tf:3594-3628 (1 action group)
# D-305: Authored via for_each over var.action_groups map — not N hand-written blocks.
# T-03-24: New estate — action group IDs are OUTPUT from THIS resource, never old ARM paths.
# ---------------------------------------------------------------------------

resource "azurerm_monitor_action_group" "this" {
  for_each = var.action_groups

  name                = each.value.name
  resource_group_name = var.resource_group_name
  short_name          = each.value.short_name

  # ARM role receivers (e.g., Contributor role for automated remediation)
  dynamic "arm_role_receiver" {
    for_each = each.value.arm_role_receivers
    content {
      name                    = arm_role_receiver.value.name
      role_id                 = arm_role_receiver.value.role_id
      use_common_alert_schema = arm_role_receiver.value.use_common_alert_schema
    }
  }

  # Email receivers
  dynamic "email_receiver" {
    for_each = each.value.email_receivers
    content {
      name                    = email_receiver.value.name
      email_address           = email_receiver.value.email_address
      use_common_alert_schema = lookup(email_receiver.value, "use_common_alert_schema", false)
    }
  }

  # Azure mobile app push receivers
  dynamic "azure_app_push_receiver" {
    for_each = each.value.azure_app_push_receivers
    content {
      name          = azure_app_push_receiver.value.name
      email_address = azure_app_push_receiver.value.email_address
    }
  }
}

# ---------------------------------------------------------------------------
# § Metric Alerts — for_each over var.alerts map (D-305 / T-03-24)
#
# Evidence: 54 prod alerts (res-3906 through res-3959) + 9 nonprod alerts (res-2329..2337)
# D-305: expressed as a for_each over a map variable, NOT 63 hand-written blocks.
# T-03-24: scopes reference NEW estate resources passed via var.alert_scope_ids,
#           keyed by a logical scope name (e.g. "agw", "web_plan", "sql_dev", "app_data_access").
#           Action group IDs reference azurerm_monitor_action_group.this[<key>].id.
#
# SCOPE WIRING PATTERN:
#   Each alert entry carries a "scope_key" that resolves to a resource ID from
#   var.alert_scope_ids (a map passed by the root from module outputs).
#   "action_group_key" resolves to azurerm_monitor_action_group.this[key].id.
#   This keeps the alert map value-only (no raw ARM IDs) and re-points all scopes
#   off the old LD-*-EastUS-V2 ARM paths.
# ---------------------------------------------------------------------------

resource "azurerm_monitor_metric_alert" "this" {
  for_each = var.alerts

  name                = each.value.name
  resource_group_name = var.resource_group_name

  # Resolve scope: look up scope_key in var.alert_scope_ids.
  # var.alert_scope_ids is a map of logical key → resource ID (new estate).
  # T-03-24: All scopes reference new estate — no old RG ARM paths.
  scopes = [var.alert_scope_ids[each.value.scope_key]]

  description = lookup(each.value, "description", null)
  enabled     = lookup(each.value, "enabled", true)
  severity    = lookup(each.value, "severity", 3)
  frequency   = lookup(each.value, "frequency", "PT1M")
  window_size = lookup(each.value, "window_size", "PT5M")

  # Action group (optional — some alerts in the analog have no action block)
  dynamic "action" {
    for_each = lookup(each.value, "action_group_key", "") != "" ? [1] : []
    content {
      action_group_id = azurerm_monitor_action_group.this[each.value.action_group_key].id
    }
  }

  # Primary criteria block
  criteria {
    aggregation      = each.value.aggregation
    metric_name      = each.value.metric_name
    metric_namespace = each.value.metric_namespace
    operator         = each.value.operator
    threshold        = each.value.threshold

    # Optional dimension filter (e.g. HttpStatusGroup=5xx)
    dynamic "dimension" {
      for_each = lookup(each.value, "dimension_name", "") != "" ? [1] : []
      content {
        name     = each.value.dimension_name
        operator = "Include"
        values   = each.value.dimension_values
      }
    }
  }
}

# ---------------------------------------------------------------------------
# § Smart Detector Alert Rules
# Evidence: terraform/LD-Prod-EastUS-V2/main.tf:8309-8323 (FailureAnomaliesDetector)
# D-305: authored via for_each over var.smart_detector_rules map.
# Action group IDs resolved from azurerm_monitor_action_group.this[key].id.
# ---------------------------------------------------------------------------

resource "azurerm_monitor_smart_detector_alert_rule" "this" {
  for_each = var.smart_detector_rules

  name                = each.value.name
  resource_group_name = var.resource_group_name
  detector_type       = each.value.detector_type
  frequency           = each.value.frequency
  severity            = each.value.severity
  description         = lookup(each.value, "description", null)

  # scope_resource_ids: app insights component IDs (new estate)
  scope_resource_ids = [
    for k in each.value.app_insights_keys : azurerm_application_insights.this[k].id
  ]

  action_group {
    ids = [azurerm_monitor_action_group.this[each.value.action_group_key].id]
  }
}

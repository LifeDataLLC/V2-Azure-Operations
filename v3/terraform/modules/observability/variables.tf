# modules/observability/variables.tf — Observability module variable surface
#
# D-307: NO `default` on scope/resource names or divergence-bearing values.
# D-308: Invariant module behaviours (application_type=web) may be defaulted inside the map schema.
# T-03-24: All scope IDs / action-group IDs come in as explicit map inputs — no raw old-estate ARM paths.
# T-03-25: No instrumentation key literals; connection_string output only.

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
# § Log Analytics Workspace (prod scope only)
# ---------------------------------------------------------------------------

variable "log_analytics_workspace_name" {
  description = <<-EOT
    Name of the Log Analytics workspace to create.
    prod scope: "V2ProdLogAnalyticsWorkspace" (evidence: terraform/LD-Prod-EastUS-V2/main.tf:1521).
    nonprod scope: "" (no dedicated LA workspace — set to empty string to skip creation).
    NO DEFAULT (D-307) — workspace presence differs between scopes.
  EOT
  type        = string
}

variable "saved_searches" {
  description = <<-EOT
    Map of custom saved KQL searches to author in the LA workspace (prod only).
    Key = unique name/GUID for the saved search. Value = object with category, display_name, query.
    D-305: Only genuine business-value queries retained — built-in LA tables dropped as noise.
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:1536-1620 (res-2662 through custom KQL set).
    Set to {} when log_analytics_workspace_name = "" (nonprod scope).
    NO DEFAULT (D-307) — query set differs between scopes.
  EOT
  type = map(object({
    category     = string
    display_name = string
    query        = string
  }))
}

# ---------------------------------------------------------------------------
# § Application Insights
# ---------------------------------------------------------------------------

variable "app_insights_instances" {
  description = <<-EOT
    Map of Application Insights instances to author.
    Key = logical name (e.g. "common", "prod_appi", "data_access_appi").
    Value = per-instance config.
    Evidence:
      nonprod: appi-common-nonproduction-eastus (nonprod main.tf:3629).
      prod:    appi-production-eastus (prod main.tf:7343); app-db-data-access-prod-eastus (prod main.tf:8324).
    D-307: name and application_type are connectivity-critical.
    NO DEFAULT — instances differ between scopes.
  EOT
  type = map(object({
    name                = string
    application_type    = string
    sampling_percentage = number
  }))
}

# ---------------------------------------------------------------------------
# § Action Groups
# ---------------------------------------------------------------------------

variable "action_groups" {
  description = <<-EOT
    Map of Monitor Action Groups.
    Key = logical key (used by alert map entries via action_group_key field).
    Value = per-group config with email_receivers, arm_role_receivers, azure_app_push_receivers.
    Evidence:
      prod: res-3898..res-3904 (7 groups): "APIM Capacity", "Action Group for Production Server Error",
            "Dev-Email", "DevAdmin", "Http Server Error", "Overall Gateway Duration", "Server Health".
      nonprod: res-2326 (1 group): "LifeData Azure Contributor".
    D-307: NO DEFAULT — group names and recipients differ between scopes.
    T-03-24: IDs of these groups are OUTPUT from this module; alert action_group_id references
             azurerm_monitor_action_group.this[key].id — never the old LD-*-EastUS-V2 ARM path.
  EOT
  type = map(object({
    name       = string
    short_name = string
    arm_role_receivers = list(object({
      name                    = string
      role_id                 = string
      use_common_alert_schema = bool
    }))
    email_receivers = list(object({
      name                    = string
      email_address           = string
      use_common_alert_schema = bool
    }))
    azure_app_push_receivers = list(object({
      name          = string
      email_address = string
    }))
  }))
  # NO default — set per scope in tfvars (D-307)
}

# ---------------------------------------------------------------------------
# § Alert Scope IDs (new estate — T-03-24)
# ---------------------------------------------------------------------------

variable "alert_scope_ids" {
  description = <<-EOT
    Map of logical scope key → Azure resource ID for metric alert scopes.
    All IDs reference the NEW V3 estate (fed from module outputs at root).
    T-03-24: NEVER the old LD-*-EastUS-V2 ARM paths — re-pointed to new estate.

    Logical keys used by var.alerts[*].scope_key:
      "web_plan"        → module.app_service[env].web_plan_id
      "function_plan"   → module.app_service[env].function_plan_id
      "app_gateway"     → module.app_gateway.gateway_id
      "sql_<env>"       → module.sql[env].server_id  (added by root for each enabled env)
      "app_<name>"      → module.app_service[env].web_app_ids[<app_name>]
      "apim_<name>"     → module.apim.service_id (when apim module is wired)
      "appi_<key>"      → azurerm_application_insights.this[key].id  (self-referential, for smart detectors)

    For scopes not yet available (e.g. APIM service ID before 03-07 is wired), the root
    passes an empty-string sentinel value; the alert is authoratively valued once all
    modules are wired. This allows terraform validate to succeed without all modules wired.
    NO DEFAULT (D-307) — scope IDs are environment/scope-specific.
  EOT
  type        = map(string)
}

# ---------------------------------------------------------------------------
# § Metric Alerts map (D-305 for_each pattern)
# ---------------------------------------------------------------------------

variable "alerts" {
  description = <<-EOT
    Map of metric alert definitions. Key = unique alert key (logical name).
    D-305: The ~63 alerts (54 prod + 9 nonprod) are expressed via this map — NOT 63 hand-written blocks.
    T-03-24: Each entry's scope_key resolves to a new-estate resource ID from var.alert_scope_ids.
             action_group_key resolves to azurerm_monitor_action_group.this[key].id.

    Each value carries:
      name             — alert display name (e.g. "V2 Prod AGW 5XX")
      scope_key        — key into var.alert_scope_ids
      metric_name      — Azure Monitor metric (e.g. "BackendResponseStatus")
      metric_namespace — Azure resource type namespace (e.g. "Microsoft.Network/applicationGateways")
      aggregation      — "Total", "Average", "Maximum", "Minimum", "Count"
      operator         — "GreaterThan", "LessThan", "GreaterThanOrEqual", "LessThanOrEqual"
      threshold        — numeric threshold
      description      — optional alert description string
      enabled          — bool (default: true); some alerts are authored as disabled in analog
      severity         — 0-4 (default: 3)
      frequency        — ISO 8601 evaluation frequency (default: "PT1M")
      window_size      — ISO 8601 window (default: "PT5M")
      action_group_key — key into azurerm_monitor_action_group.this (empty = no action)
      dimension_name   — optional dimension filter name (e.g. "HttpStatusGroup")
      dimension_values — list of dimension values (e.g. ["5xx"])

    NO DEFAULT (D-307) — alert definitions differ between scopes.
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:7350-8228 (54 prod alerts)
              terraform/LD-NonProd-EastUS-V2/main.tf:3636-3781 (9 nonprod alerts)
  EOT
  type = map(object({
    name             = string
    scope_key        = string
    metric_name      = string
    metric_namespace = string
    aggregation      = string
    operator         = string
    threshold        = number
    description      = string
    enabled          = bool
    severity         = number
    frequency        = string
    window_size      = string
    action_group_key = string
    dimension_name   = string
    dimension_values = list(string)
  }))
  # NO default — set per scope in tfvars (D-307)
}

# ---------------------------------------------------------------------------
# § Smart Detector Alert Rules
# ---------------------------------------------------------------------------

variable "smart_detector_rules" {
  description = <<-EOT
    Map of Azure Monitor Smart Detector Alert Rules.
    Key = logical rule key.
    Evidence: terraform/LD-Prod-EastUS-V2/main.tf:8309-8323
              "Failure Anomalies - app-db-data-access-prod-eastus" (FailureAnomaliesDetector).
    app_insights_keys: list of keys into azurerm_application_insights.this (new estate self-reference).
    action_group_key: key into azurerm_monitor_action_group.this.
    Set to {} for nonprod scope (nonprod analog has no smart detector rules).
    NO DEFAULT (D-307).
  EOT
  type = map(object({
    name              = string
    detector_type     = string
    frequency         = string
    severity          = string
    description       = string
    app_insights_keys = list(string)
    action_group_key  = string
  }))
  # NO default — set per scope in tfvars (D-307)
}

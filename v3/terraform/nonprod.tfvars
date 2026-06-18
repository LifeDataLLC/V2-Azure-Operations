# nonprod.tfvars — Nonprod scope variable values for LifeData V3
#
# SCOPE:  ld-nonprod-eastus-v3  (D-08 / D-12)
# STATE:  tfstate-nonprod / nonprod/terraform.tfstate  (D-205)
# USAGE:
#   terraform init   -backend-config=nonprod.backend.hcl
#   terraform plan   -var-file=nonprod.tfvars
#   terraform apply  -var-file=nonprod.tfvars
#
# SECURITY (T-03-02 / HIPAA):
#   NO secrets, passwords, connection strings, or SAS tokens here.
#   Sensitive values are stored in Azure Key Vault and referenced at runtime
#   via system-assigned managed identity (Shared 3 / CLAUDE.md §Constraints).
#
# EVIDENCE CITATIONS:
#   All posture values are derived from live reference data:
#     data/FINDINGS-DATA.md    — canonical config briefing
#     data/sql_detail.json     — SQL firewall/audit/auth posture
#     data/storage_accounts.json — storage replication/TLS/public-access
#     data/keyvaults_detail.json — KV auth model (RBAC vs access policies)
#     01-Infrastructure-Overview.md §3 — app service plan inventory
#
# ---------------------------------------------------------------------------
# § Scope-level
# ---------------------------------------------------------------------------

resource_group_name = "ld-nonprod-eastus-v3"
subscription_id     = "e3e4d658-d924-4c2b-ad05-a4457e197527"

# Environments (D-301a): DEV enabled; QA disabled in v1.
# Each downstream module plan adds per-env fields to the environments map objects
# in its own § section below — the types must extend what variables.tf declares.
environments = {
  dev = {
    enabled             = true  # D-301a: DEV is the only active env in M1
    sql_sku             = "S1"  # Standard S1 (10 DTU). Evidence: sql_detail.json dev server currentServiceObjectiveName="S1"
    app_plan_sku        = "B2"  # Basic B2. Evidence: appservice_plans.json nonprod plan sku.name="B2"
    storage_replication = "LRS" # Locally-redundant. Evidence: storage_accounts.json ldstdeveastus accountType="Standard_LRS"
  }
  qa = {
    enabled             = false # D-301a: QA off in v1
    sql_sku             = "S1"  # Standard S1. Evidence: sql_detail.json qa server currentServiceObjectiveName="S1"
    app_plan_sku        = "B2"  # Basic B2. Evidence: appservice_plans.json (same nonprod plan)
    storage_replication = "LRS" # Locally-redundant. Evidence: storage_accounts.json ldstqaeastus accountType="Standard_LRS"
  }
}

# ---------------------------------------------------------------------------
# § networking values (Plan 03-02)
# ---------------------------------------------------------------------------

# --- networking values (Plan 03-03) ---
# Evidence: data/vnets.json (nonprod VNet), data/nsgs.json (nonprod NSG),
#           data/public_ips.json (nonprod PIPs)
#           terraform/LD-NonProd-EastUS-V2/main.tf:1267-1448 (HCL shape)
#
# D-302: Mirrors live overlapping 10.0.0.0/16. Per-env CIDR isolation → M3.
# D-305: hidden-link/App Insights tags on PIPs DROPPED (noise normalization).

networking = {
  # evidence: vnets.json name="vnet-common-nonproduction-eastus"
  vnet_name = "vnet-common-nonproduction-eastus"
  # evidence: vnets.json addressSpace.addressPrefixes=["10.0.0.0/16"]
  vnet_address_space = ["10.0.0.0/16"]

  subnets = {
    # Logical key → real subnet. Keys match module.networking output variable expectations.

    "default" = {
      name                              = "default"
      address_prefix                    = "10.0.1.0/24" # evidence: vnets.json subnets[0]
      service_endpoints                 = []
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "Disabled" # evidence: vnets.json privateEndpointNetworkPolicies="Disabled"
      default_outbound_access_enabled   = true
    }

    "common" = {
      name                              = "common-nonproduction-eastus-subnet"
      address_prefix                    = "10.0.2.0/24" # evidence: vnets.json subnets[1]
      service_endpoints                 = []
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }

    "app_service" = {
      name              = "app-service-nonproduction-eastus-subnet"
      address_prefix    = "10.0.3.0/24" # evidence: vnets.json subnets[2]
      service_endpoints = ["Microsoft.Web"]
      # evidence: vnets.json delegations[0].serviceName="Microsoft.Web/serverFarms"
      delegation_name                   = "Microsoft.Web.serverFarms"
      delegation_service                = "Microsoft.Web/serverFarms"
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }

    "function_app" = {
      name              = "function-app-nonproduction-eastus-subnet"
      address_prefix    = "10.0.4.0/24" # evidence: vnets.json subnets[3]
      service_endpoints = ["Microsoft.Web"]
      # evidence: vnets.json delegations[0].serviceName="Microsoft.Web/serverFarms"
      delegation_name                   = "Microsoft.Web.serverFarms"
      delegation_service                = "Microsoft.Web/serverFarms"
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }

    "apim_legacy" = {
      name                              = "apim-nonproduction-eastus-subnet"
      address_prefix                    = "10.0.5.0/24" # evidence: vnets.json subnets[4]
      service_endpoints                 = ["Microsoft.KeyVault", "Microsoft.Web"]
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }

    "agw" = {
      name                              = "agw-nonproduction-eastus-subnet"
      address_prefix                    = "10.0.6.0/24" # evidence: vnets.json subnets[5]
      service_endpoints                 = []
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }

    "keyvault" = {
      name                              = "kv-nonproduction-eastus-subnet"
      address_prefix                    = "10.0.7.0/24" # evidence: vnets.json subnets[6]
      service_endpoints                 = ["Microsoft.KeyVault"]
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }

    "storage" = {
      name                              = "storage-nonproduction-eastus-subnet"
      address_prefix                    = "10.0.8.0/24" # evidence: vnets.json subnets[7]
      service_endpoints                 = ["Microsoft.Storage"]
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }

    "sql" = {
      name                              = "sql-nonproduction-eastus-subnet"
      address_prefix                    = "10.0.9.0/24" # evidence: vnets.json subnets[8]
      service_endpoints                 = ["Microsoft.Sql"]
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }

    "apim" = {
      # NSG-associated subnet (apim2 = the actual APIM Developer-SKU internal subnet)
      # evidence: vnets.json subnets[9] name="apim2-nonproduction-eastus-subnet"
      #           nsgs.json subnets[0].id contains apim2-nonproduction-eastus-subnet
      name                              = "apim2-nonproduction-eastus-subnet"
      address_prefix                    = "10.0.10.0/24"
      service_endpoints                 = ["Microsoft.KeyVault", "Microsoft.Web"]
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }
  }

  nsgs = {
    "apim" = {
      # evidence: nsgs.json name="nsg-nonproduction-eastus", associated with apim2 subnet
      name       = "nsg-nonproduction-eastus"
      subnet_key = "apim"
      security_rules = [
        {
          name                       = "AllowAnyHTTPSInbound"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "*" # evidence: nsgs.json protocol="*"
          source_port_range          = "*"
          destination_port_range     = "3443"
          destination_port_ranges    = []
          source_address_prefix      = "ApiManagement"
          destination_address_prefix = "VirtualNetwork"
          description                = "" # no description in live NSG rule
        }
      ]
    }
  }

  public_ips = {
    "agw_common" = {
      # evidence: public_ips.json name="pip-common-nonproduction-eastus"
      # Associated with agw-common-nonproduction-eastus frontend
      # D-305: hidden-link tag DROPPED
      name                    = "pip-common-nonproduction-eastus"
      allocation_method       = "Static"
      sku                     = "Standard"
      idle_timeout_in_minutes = 4
      zones                   = []
      domain_name_label       = ""
    }
    "apim_dev" = {
      # evidence: public_ips.json name="pip-dev-eastus"
      # D-305: hidden-link tag DROPPED
      name                    = "pip-dev-eastus"
      allocation_method       = "Static"
      sku                     = "Standard"
      idle_timeout_in_minutes = 4
      zones                   = []
      domain_name_label       = ""
    }
  }

  private_dns_zones = {
    "redis" = {
      # evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1288-1300
      zone_name = "privatelink.redis.cache.windows.net"
      link_name = "4ir5orskrm2je" # link name from export (kept for fidelity)
    }
  }

  # NAT gateway — nonprod has no NAT gateway
  # evidence: public_ips.json no pip-nat-* in nonprod scope
  nat_gateway_name       = ""
  nat_gateway_pip_key    = ""
  nat_gateway_subnet_key = ""

  # APIM StV2 private endpoint — nonprod has no StV2 APIM private endpoint
  apim_private_endpoint_name        = ""
  apim_private_endpoint_subnet_key  = ""
  apim_private_endpoint_resource_id = ""
  apim_private_dns_zone_key         = ""
}

# --- end networking values ---

# ---------------------------------------------------------------------------
# § sql values (Plan 03-03)
# ---------------------------------------------------------------------------

# --- sql values (Plan 03-04) ---
# D-307: Every posture value explicit + evidence-cited. M1 preserves current
# (insecure) posture; M3 flips to secure values via reviewed tfvars diff.
# D-305: developer-home / transient firewall rules DROPPED in the module itself;
# only the AllowAllWindowsAzureIps structural rule is governed by a var here.

sql_public_network_access_enabled = true  # M1: preserve. Evidence: sql_detail.json nonprod servers publicNetworkAccess="Enabled"; FINDINGS-DATA.md §SQL F1
sql_allow_all_azure_ips           = true  # M1: preserve. Evidence: sql_detail.json firewallRules[0].name="AllowAllWindowsAzureIps" (dev+qa servers); FINDINGS-DATA.md §SQL F2
sql_auditing_enabled              = false # M1: preserve. Evidence: sql_detail.json auditPolicy.state="Disabled" (dev+qa servers); FINDINGS-DATA.md §SQL F3
sql_azuread_only_auth             = false # M1: preserve. Evidence: sql_detail.json aadAdmins.azureAdOnlyAuthentication=false (dev+qa servers); FINDINGS-DATA.md §SQL F4

# --- end sql values ---

# ---------------------------------------------------------------------------
# § storage values (Plan 03-04)
# ---------------------------------------------------------------------------

# --- storage values (Plan 03-05) ---
# Evidence: data/storage_accounts.json (nonprod accounts — ldfstnonproductioneastus, ldstdeveastus, ldstqaeastus, stqanonproductioneastus)
# D-307: Every posture value explicit + evidence-cited. M1 preserves current (insecure) posture.
# M3 flips blob_public→false, shared_key→false, network_default→Deny.
# T-03-18: ldstqaeastus has TLS1_0 exception (per storage_accounts.json minimumTlsVersion).

# Scope-shared accounts (deploy once regardless of enabled envs — D-302)
# nonprod scope: ldfstnonproductioneastus (B2C/func static assets, scope-shared)
# Evidence: storage_accounts.json ldfstnonproductioneastus
storage_shared_accounts = {
  "ldfstnonproduction" = {
    name                            = "ldfstnonproductioneastus"
    location                        = "eastus" # evidence: storage_accounts.json location
    account_replication_type        = "LRS"    # evidence: storage_accounts.json sku.name="Standard_LRS"
    allow_nested_items_to_be_public = false    # evidence: storage_accounts.json allowBlobPublicAccess=false (only account with false in nonprod)
    shared_access_key_enabled       = false    # evidence: storage_accounts.json allowSharedKeyAccess=false
    min_tls_version                 = "TLS1_2" # evidence: storage_accounts.json minimumTlsVersion="TLS1_2"
    network_default_action          = "Allow"  # evidence: storage_accounts.json networkRuleSet.defaultAction="Allow"
    large_file_shares_enabled       = false    # evidence: storage_accounts.json largeFileSharesState=null
    sas_expiry_period               = ""       # evidence: storage_accounts.json sasPolicy=null
    containers = [
      "$web",           # evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1685-1686
      "b2c-signup-www", # evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1689-1692
    ]
    container_access_types = {
      "b2c-signup-www" = "container" # evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1690 container_access_type="container"
    }
    queues                = []
    tables                = []
    file_shares           = {}
    queue_logging_enabled = false
  }
}

# Per-environment storage accounts (for_each over enabled_envs — D-301)
# dev env:  ldstdeveastus (primary dev storage, per-env)
# qa env:   ldstqaeastus + stqanonproductioneastus (qa-specific)
# Evidence: storage_accounts.json per account
storage_env_accounts = {
  dev = {
    "ldstdev" = {
      name                            = "ldstdeveastus"
      location                        = "eastus"     # evidence: storage_accounts.json location
      account_replication_type        = "LRS"        # evidence: storage_accounts.json sku.name="Standard_LRS"
      allow_nested_items_to_be_public = true         # evidence: storage_accounts.json allowBlobPublicAccess=true
      shared_access_key_enabled       = true         # evidence: storage_accounts.json allowSharedKeyAccess=true
      network_default_action          = "Allow"      # evidence: storage_accounts.json networkRuleSet.defaultAction="Allow"
      large_file_shares_enabled       = false        # evidence: storage_accounts.json largeFileSharesState=null
      sas_expiry_period               = "1.00:00:00" # evidence: storage_accounts.json sasPolicy.sasExpirationPeriod="1.00:00:00"
      containers = [
        "$web",
        "azure-webjobs-hosts",
        "azure-webjobs-secrets",
        "data-files",
        "db-backups",
        "insights-logs-auditevent",
        "insights-logs-connectedclientlist",
        "organization-root",
        "participant-info",
        "participant-info-error",
        "qr-code",
        "sql-server-dev",
        "study-content",
        "study-dictionary-data",
        "study-report",
        "study-response",
        "user-content",
      ]
      container_access_types = {
        "study-content" = "blob" # evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1792 container_access_type="blob"
      }
      queues = [
        "block-response",
        "block-response-error",
        "file-upload-response",
        "file-upload-response-error",
        "media-response",
        "media-response-error",
        "participant-info",
        "participant-info-error",
        "participant-response",
        "participant-response-error",
        "push-response",
        "push-response-error",
        "question-response",
        "question-response-error",
        "question-response-multi-select",
        "question-response-multi-select-error",
        "score-response",
        "score-response-error",
        "session-instance-response",
        "session-instance-response-error",
        "session-reminder-response",
        "session-reminder-response-error",
        "session-response",
        "session-response-error",
        "trigger-response",
        "trigger-response-error",
      ]
      # D-305: AzureFunctionsDiagnosticEvents tables are ephemeral/rotating (timestamp-suffixed).
      # Author a representative set; the function runtime creates new ones automatically.
      tables = [
        "AzureFunctionsDiagnosticEvents202507",
        "AzureFunctionsDiagnosticEvents202509",
        "AzureFunctionsDiagnosticEvents202511",
        "AzureFunctionsDiagnosticEvents202602",
      ]
      file_shares           = {}
      queue_logging_enabled = true # evidence: terraform/LD-NonProd-EastUS-V2/main.tf:1827-1843 queue_properties block present
    }
  }

  qa = {
    "ldstqa" = {
      name                            = "ldstqaeastus"
      location                        = "eastus"
      account_replication_type        = "LRS"   # evidence: storage_accounts.json sku.name="Standard_LRS"
      allow_nested_items_to_be_public = false   # evidence: storage_accounts.json allowBlobPublicAccess=false
      shared_access_key_enabled       = true    # evidence: storage_accounts.json allowSharedKeyAccess=null (provider default=true)
      network_default_action          = "Allow" # evidence: storage_accounts.json networkRuleSet.defaultAction="Allow"
      large_file_shares_enabled       = false   # evidence: storage_accounts.json largeFileSharesState=null
      sas_expiry_period               = ""      # evidence: storage_accounts.json sasPolicy=null
      containers = [
        "azure-webjobs-hosts",
        "azure-webjobs-secrets",
      ]
      container_access_types = {}
      queues = [
        "block-response",
        "block-response-error",
        "file-upload-response",
        "file-upload-response-error",
        "media-response",
        "media-response-error",
        "notif-response",
        "notif-response-error",
        "notif-trigger-response",
        "notif-trigger-response-error",
        "notification-master-response",
        "notification-master-response-error",
        "push-response",
        "push-response-error",
        "question-response",
        "question-response-error",
        "score-response",
        "score-response-error",
        "session-reminder-response",
        "session-reminder-response-error",
        "session-response",
        "session-response-error",
      ]
      tables = [
        "AzureFunctionsDiagnosticEvents202507",
        "AzureFunctionsDiagnosticEvents202508",
        "AzureFunctionsDiagnosticEvents202509",
        "AzureFunctionsDiagnosticEvents202511",
        "AzureFunctionsDiagnosticEvents202512",
        "AzureFunctionsDiagnosticEvents202601",
      ]
      file_shares = {
        "fapp-process-response" = 102400 # evidence: terraform/LD-NonProd-EastUS-V2/main.tf:2065-2071 quota=102400
      }
      queue_logging_enabled = true # evidence: terraform/LD-NonProd-EastUS-V2/main.tf:2073-2089
    }
    "stqanonproduction" = {
      name                            = "stqanonproductioneastus"
      location                        = "eastus"
      account_replication_type        = "LRS"   # evidence: storage_accounts.json sku.name="Standard_LRS"
      allow_nested_items_to_be_public = true    # evidence: storage_accounts.json allowBlobPublicAccess=true
      shared_access_key_enabled       = true    # evidence: storage_accounts.json allowSharedKeyAccess=true
      network_default_action          = "Allow" # evidence: storage_accounts.json networkRuleSet.defaultAction="Allow"
      large_file_shares_enabled       = false   # evidence: storage_accounts.json largeFileSharesState=null
      sas_expiry_period               = ""      # evidence: storage_accounts.json sasPolicy=null
      containers = [
        "$web",
        "azure-webjobs-hosts",
        "azure-webjobs-secrets",
        "data-files",
        "db-backups",
        "organization-root",
        "participant-info",
        "participant-info-error",
        "qr-code",
        "study-content",
        "study-dictionary-data",
        "study-report",
        "study-response",
        "user-content",
      ]
      container_access_types = {}
      queues = [
        "block-response",
        "block-response-error",
        "file-upload-response",
        "file-upload-response-error",
        "media-response",
        "media-response-error",
        "participant-info",
        "participant-info-error",
        "push-response",
        "push-response-error",
        "question-response",
        "question-response-error",
        "score-response",
        "score-response-error",
        "session-reminder-response",
        "session-reminder-response-error",
        "session-response",
        "session-response-error",
      ]
      tables                = []
      file_shares           = {}
      queue_logging_enabled = false
    }
  }
}

# --- end storage values ---

# ---------------------------------------------------------------------------
# § keyvault values (Plan 03-05)
# ---------------------------------------------------------------------------

# --- keyvault values (Plan 03-05) ---
# D-306: kv_enable_rbac_authorization=true for nonprod (RBAC mode).
# Evidence: keyvaults_detail.json kvnonproductioneastus.properties.enableRbacAuthorization=true
# D-307: All posture values explicit + evidence-cited. M1 preserves current posture.

kv_name     = "kvnonproductioneastus" # evidence: keyvaults_detail.json name
kv_sku_name = "standard"              # evidence: keyvaults_detail.json properties.sku.name="Standard"

# D-306 DIVERGENCE ANCHOR: nonprod=true (RBAC mode). M3 is a no-op here (already true).
# Evidence: keyvaults_detail.json kvnonproductioneastus.properties.enableRbacAuthorization=true
kv_enable_rbac_authorization = true

# D-307 network posture — M1 preserves Allow (public). M3 flips to Deny.
# Evidence: keyvaults_detail.json kvnonproductioneastus.properties.networkAcls.defaultAction="Allow"
kv_network_default_action = "Allow"

# M1: public network access enabled. M3 flips to false.
# Evidence: keyvaults_detail.json kvnonproductioneastus.properties.publicNetworkAccess="Enabled"
kv_public_network_access_enabled = true

# RBAC mode (kv_enable_rbac_authorization=true): access_policy blocks are not authored.
# The module's dynamic "access_policy" block produces zero blocks when RBAC=true.
# Evidence: keyvaults_detail.json accessPolicies present but RBAC takes precedence.
kv_access_policies = []

# --- end keyvault values ---

# ---------------------------------------------------------------------------
# § app-service values (Plan 03-06)
# ---------------------------------------------------------------------------

# --- app-service values (Plan 03-06) ---
# Evidence: terraform/LD-NonProd-EastUS-V2/main.tf:2620-4040 (nonprod app HCL shapes)
#           data/appservice_plans.json (plan names and SKUs)
# D-303: web_app_maps + function_app_maps are the per-env app surfaces.
# D-305: hidden-link:/app-insights tags DROPPED; app_command_line reproduced from HCL.
# D-307: All posture values (always_on, min_tls_version, plan SKU) explicit + evidence-cited.
# T-03-19: NO literal secrets/connection strings — storage keys via KV secret name only.
# T-03-22: Per-app posture from nonprod HCL reference.

# Per-environment App Service Plan names and SKUs.
# Evidence: appservice_plans.json (all nonprod plans)
app_service_plans = {
  dev = {
    # Web apps use plan-dev-eastus (B2, 6 sites). evidence: appservice_plans.json
    web_plan_name = "plan-dev-eastus"
    web_plan_sku  = "B2"
    # Function app uses plan-common-nonproduction-eastus (B2). evidence: main.tf:2803 res-2123
    function_plan_name = "plan-common-nonproduction-eastus"
    function_plan_sku  = "B2"
  }
  qa = {
    # QA web apps share plan-common-nonproduction-eastus (B2, 7 sites). evidence: appservice_plans.json
    web_plan_name = "plan-common-nonproduction-eastus"
    web_plan_sku  = "B2"
    # QA function app uses plan-qa-eastus (B1). evidence: appservice_plans.json + main.tf:3055 res-2125
    function_plan_name = "plan-qa-eastus"
    function_plan_sku  = "B1"
  }
}

# Per-environment web app maps (D-303 for_each).
# Dev: 6 web apps on plan-dev-eastus. QA: 6 web apps on plan-common-nonproduction-eastus.
# Evidence: terraform/LD-NonProd-EastUS-V2/main.tf (azurerm_linux_web_app blocks).
# app_command_line from HCL site_config.app_command_line; dotnet_version/node_version from
# linuxFxVersion (nonprod export does not have linuxFxVersion; default to matching prod canonical).
web_app_maps = {
  dev = {
    # app-db-dev-eastus: .NET 8.0 API. evidence: nonprod HCL res-2126; prod canonical DOTNETCORE|8.0
    "app-db-dev-eastus" = {
      always_on        = false # evidence: nonprod HCL res-2126 site_config.always_on=false
      app_command_line = ""    # evidence: nonprod HCL res-2126 (no app_command_line)
      dotnet_version   = "8.0" # evidence: prod canonical DOTNETCORE|8.0
      node_version     = null
    }
    # data-access-dev-eastus: Node.js API. evidence: nonprod HCL res-2144
    "data-access-dev-eastus" = {
      always_on        = false                                   # evidence: nonprod HCL res-2144 always_on=false
      app_command_line = "pm2-runtime start ecosystem.config.js" # evidence: nonprod HCL res-2144:2731
      dotnet_version   = null
      node_version     = "22-lts" # evidence: prod canonical NODE|22-lts
    }
    # mobile-backend-dev-eastus: Node.js API. evidence: nonprod HCL res-2227
    "mobile-backend-dev-eastus" = {
      always_on        = false                                   # evidence: nonprod HCL res-2227 site_config.always_on=false
      app_command_line = "pm2-runtime start ecosystem.config.js" # evidence: nonprod HCL res-2227:3287
      dotnet_version   = null
      node_version     = "22-lts" # evidence: prod canonical NODE|22-lts
    }
    # study-module-dev-eastus: Node.js API. evidence: nonprod HCL res-2248
    "study-module-dev-eastus" = {
      always_on        = false                                                                            # evidence: nonprod HCL (study-module-dev always_on not set → false)
      app_command_line = "npm install pm2@latest -g && pm2 start /home/site/wwwroot/index.js --no-daemon" # evidence: nonprod HCL res-2248 area
      dotnet_version   = null
      node_version     = "22-lts" # evidence: prod canonical NODE|22-lts
    }
    # user-module-dev-eastus: Node.js API. evidence: nonprod HCL res-~3440
    "user-module-dev-eastus" = {
      always_on        = false                                                                            # evidence: nonprod HCL (no always_on set)
      app_command_line = "npm install pm2@latest -g && pm2 start /home/site/wwwroot/index.js --no-daemon" # evidence: prod canonical
      dotnet_version   = null
      node_version     = "22-lts" # evidence: prod canonical NODE|22-lts
    }
    # web-frontend-dev-eastus: Node.js SPA frontend. evidence: nonprod HCL res-2365
    "web-frontend-dev-eastus" = {
      always_on        = false                                                                          # evidence: nonprod HCL res-2365:4010 always_on=false
      app_command_line = "npm install pm2@latest -g && pm2 serve /home/site/wwwroot/ --no-daemon --spa" # evidence: nonprod HCL res-2365:4011
      dotnet_version   = null
      node_version     = "22-lts" # evidence: prod canonical NODE|22-lts
    }
  }

  qa = {
    # app-db-qa-nonproduction-eastus: .NET 8.0 API. evidence: nonprod HCL res-2135
    "app-db-qa-nonproduction-eastus" = {
      always_on        = false # evidence: nonprod HCL res-2135 (no always_on)
      app_command_line = ""
      dotnet_version   = "8.0"
      node_version     = null
    }
    # data-access-qa-nonproduction-eastus: Node.js API. evidence: nonprod HCL res-2159
    "data-access-qa-nonproduction-eastus" = {
      always_on        = false
      app_command_line = "npm install pm2@latest -g && pm2 start /home/site/wwwroot/index.js --no-daemon" # evidence: nonprod HCL res-2159:2764
      dotnet_version   = null
      node_version     = "22-lts"
    }
    # mobile-backend-qa-nonproduction-eastus: Node.js API. evidence: nonprod HCL res-~3949
    "mobile-backend-qa-nonproduction-eastus" = {
      always_on        = false
      app_command_line = "pm2-runtime start ecosystem.config.js"
      dotnet_version   = null
      node_version     = "22-lts"
    }
    # storage-service-qa-nonproduction-eastus: Node.js API. evidence: nonprod HCL res-2242
    "storage-service-qa-nonproduction-eastus" = {
      always_on        = false
      app_command_line = "npm install pm2@latest -g && pm2 start /home/site/wwwroot/index.js --no-daemon" # evidence: nonprod HCL res-2242:3320
      dotnet_version   = null
      node_version     = "22-lts"
    }
    # study-module-qa-nonproduction-eastus: Node.js API. evidence: nonprod HCL res-~3385
    "study-module-qa-nonproduction-eastus" = {
      always_on        = false
      app_command_line = "npm install pm2@latest -g && pm2 start /home/site/wwwroot/index.js --no-daemon"
      dotnet_version   = null
      node_version     = "22-lts"
    }
    # user-module-qa-eastus: Node.js API. evidence: nonprod HCL res-~3496
    "user-module-qa-eastus" = {
      always_on        = false
      app_command_line = "npm install pm2@latest -g && pm2 start /home/site/wwwroot/index.js --no-daemon"
      dotnet_version   = null
      node_version     = "22-lts"
    }
    # web-frontend-qa-nonproduction-eastus: Node.js SPA frontend. evidence: nonprod HCL res-~3543
    "web-frontend-qa-nonproduction-eastus" = {
      always_on        = false
      app_command_line = "npm install pm2@latest -g && pm2 serve /home/site/wwwroot/ --no-daemon --spa"
      dotnet_version   = null
      node_version     = "22-lts"
    }
  }
}

# Per-environment function app maps (D-303 hybrid).
# Dev: 1 function app (fapp-process-response-dev-eastus). QA: 1 function app.
# Evidence: terraform/LD-NonProd-EastUS-V2/main.tf:2779-3260 (dev fapp res-2174),
#           terraform/LD-NonProd-EastUS-V2/main.tf:3035-3263 (qa fapp res-2201).
# T-03-19: storage_access_key_kv_name is the KV SECRET NAME, not the key value.
#           The literal key in the nonprod HCL (res-2174:2804) is the anti-pattern being fixed.
function_app_maps = {
  dev = {
    # fapp-process-response-dev-eastus: Node.js 22, timer-triggered queue processor.
    # evidence: nonprod HCL res-2174; storage=ldstdeveastus (line 2805).
    "fapp-process-response-dev-eastus" = {
      always_on                  = false                               # evidence: nonprod HCL (no always_on in site_config)
      node_version               = "22"                                # evidence: nonprod HCL res-2174 site_config node_version="22"
      storage_account_name       = "ldstdeveastus"                     # evidence: nonprod HCL res-2174:2805
      storage_access_key_kv_name = "ldstdeveastus--storage-access-key" # KV secret name (T-03-19)
      builtin_logging_enabled    = false                               # evidence: nonprod HCL res-2174:2797 builtin_logging_enabled=false
      client_certificate_mode    = "Required"                          # evidence: nonprod HCL res-2174:2798
    }
  }

  qa = {
    # fapp-process-response-qa-eastus: Node.js 22, timer-triggered queue processor.
    # evidence: nonprod HCL res-2201; storage=ldstqaeastus (line 3057).
    "fapp-process-response-qa-eastus" = {
      always_on                  = false
      node_version               = "22"                               # evidence: nonprod HCL res-2201 site_config node_version="22"
      storage_account_name       = "ldstqaeastus"                     # evidence: nonprod HCL res-2201:3057
      storage_access_key_kv_name = "ldstqaeastus--storage-access-key" # KV secret name (T-03-19)
      builtin_logging_enabled    = false                              # evidence: nonprod HCL res-2201:3049
      client_certificate_mode    = "Required"                         # evidence: nonprod HCL res-2201:3050
    }
  }
}

# --- end app-service values ---

# ---------------------------------------------------------------------------
# § apim values (Plan 03-07)
# ---------------------------------------------------------------------------

# --- apim values (Plan 03-07) ---
# (Plan 03-07 adds APIM instance name/SKU and child config values here)
# --- end apim values ---

# ---------------------------------------------------------------------------
# § app-gateway values (Plan 03-08)
# ---------------------------------------------------------------------------

# --- app-gateway values (Plan 03-08) ---
# (Plan 03-08 adds Application Gateway name/SKU/capacity values here)
# --- end app-gateway values ---

# ---------------------------------------------------------------------------
# § observability values (Plan 03-09)
# ---------------------------------------------------------------------------

# --- observability values (Plan 03-09) ---
# (Plan 03-09 adds Log Analytics/App Insights/alert map values here)
# --- end observability values ---

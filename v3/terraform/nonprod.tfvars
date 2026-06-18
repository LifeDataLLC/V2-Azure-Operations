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

# --- apim values (Plan 03-08) ---
# D-310: Nonprod scope has 2 instances: apim-common-nonproduction-eastus + ldapim-eastus-dev.
# D-307: apim_sku_name and apim_vnet_type are NO DEFAULT — set here with evidence.
# D-309: Full child clone — APIs (with import{} openapi paths), products, named values,
#        subscriptions, policy fragments all authored 1:1 from live acquisition.
# T-03-27: Named values with secret=true have value=null (no literal authored).
#          Non-secret named values (ldapim-eastus-dev: all plain; apim-common-nonproduction-eastus:
#          minimum-android-app-version, minimum-ios-app-version) authored with values.
# T-03-29: Policy fragments (B2C JWT + CORS) cloned verbatim from live acquisition.
# Evidence: data/apim_full/INVENTORY.md, data/apim_services.json, data/apim_security.json

apim_stv2_subnet_key = "" # nonprod scope has no StV2 instance

apim_instances = {
  # ---------------------------------------------------------------------------
  # Instance 1: apim-common-nonproduction-eastus
  # Evidence: apim_services.json name=apim-common-nonproduction-eastus
  #           SKU=Developer_1, VNet=Internal, apim2-nonproduction-eastus-subnet
  #           data/apim_full/apim-common-nonproduction-eastus/
  # ---------------------------------------------------------------------------
  "apim-common-nonproduction-eastus" = {
    apim_name            = "apim-common-nonproduction-eastus" # evidence: apim_services.json
    apim_publisher_name  = "LifeData LLC."                    # evidence: apim_services.json publisherName
    apim_publisher_email = "amalesh.debnath@gmail.com"        # evidence: apim_services.json publisherEmail
    apim_sku_name        = "Developer_1"                      # evidence: apim_services.json sku.name=Developer, sku.capacity=1
    apim_vnet_type       = "Internal"                         # evidence: apim_services.json virtualNetworkType=Internal
    apim_subnet_key      = "apim"                             # maps to apim2-nonproduction-eastus-subnet (10.0.10.0/24)

    apim_service_policy_xml_path = "policies/apim-common-nonproduction-eastus/service.policy.xml"

    # No custom hostname configurations for this instance (built-in azure-api.net only)
    # evidence: apim_services.json hostnameConfigurations = [] (no KV-backed certs)
    apim_hostname_configurations = {
      proxy            = []
      management       = []
      portal           = []
      developer_portal = []
    }

    apim_aad_identity_provider_enabled = false # nonprod instance — no AAD B2C identity provider
    apim_aad_client_id                 = ""
    apim_aad_allowed_tenants           = []

    # --- APIs (9 total — evidence: data/apim_full/apim-common-nonproduction-eastus/apis.json) ---
    apim_apis = {
      "blob-storage-rest-api" = {
        display_name          = "Blob Storage REST API"
        path                  = "blob-service"
        service_url           = "https://stqanonproductioneastus.blob.core.windows.net"
        subscription_required = false
        openapi_path          = "openapi/apim-common-nonproduction-eastus/blob-storage-rest-api.openapi.yaml"
        policy_xml_path       = "policies/apim-common-nonproduction-eastus/blob-storage-rest-api.policy.xml"
      }
      "data-access-rest-api" = {
        display_name          = "Data Access REST API"
        path                  = "data-access"
        service_url           = "https://data-access-qa-nonproduction-eastus.azurewebsites.net"
        subscription_required = false
        openapi_path          = "openapi/apim-common-nonproduction-eastus/data-access-rest-api.openapi.yaml"
        policy_xml_path       = "policies/apim-common-nonproduction-eastus/data-access-rest-api.policy.xml"
      }
      "mobile-notifications-rest-api" = {
        display_name          = "Mobile Notifications REST API"
        path                  = "mobile-notification-service"
        service_url           = "https://mobile-backend-qa-nonproduction-eastus.azurewebsites.net/"
        subscription_required = false
        openapi_path          = "openapi/apim-common-nonproduction-eastus/mobile-notifications-rest-api.openapi.yaml"
        policy_xml_path       = "" # no API-level policy — inherits service policy
      }
      "mobile-participant-rest-api" = {
        display_name          = "Mobile Participant REST API"
        path                  = "mobile-participant-service"
        service_url           = "https://mobile-backend-qa-nonproduction-eastus.azurewebsites.net"
        subscription_required = false
        openapi_path          = "openapi/apim-common-nonproduction-eastus/mobile-participant-rest-api.openapi.yaml"
        policy_xml_path       = "" # no API-level policy — inherits service policy
      }
      "mobile-response-rest-api" = {
        display_name          = "Mobile Response REST API"
        path                  = "mobile-response"
        service_url           = "https://ldstqaeastus.queue.core.windows.net"
        subscription_required = false
        openapi_path          = "openapi/apim-common-nonproduction-eastus/mobile-response-rest-api.openapi.yaml"
        policy_xml_path       = "policies/apim-common-nonproduction-eastus/mobile-response-rest-api.policy.xml"
      }
      "mobile-study-rest-api" = {
        display_name          = "Mobile Study REST API"
        path                  = "mobile-study-service"
        service_url           = "https://mobile-backend-qa-nonproduction-eastus.azurewebsites.net"
        subscription_required = false
        openapi_path          = "openapi/apim-common-nonproduction-eastus/mobile-study-rest-api.openapi.yaml"
        policy_xml_path       = "policies/apim-common-nonproduction-eastus/mobile-study-rest-api.policy.xml"
      }
      "queue-storage-rest-api" = {
        display_name          = "Queue Storage REST API"
        path                  = "queue-service"
        service_url           = "https://stqanonproductioneastus.queue.core.windows.net"
        subscription_required = false
        openapi_path          = "openapi/apim-common-nonproduction-eastus/queue-storage-rest-api.openapi.yaml"
        policy_xml_path       = "policies/apim-common-nonproduction-eastus/queue-storage-rest-api.policy.xml"
      }
      "user-management-rest-api" = {
        display_name          = "User Management REST API"
        path                  = "user"
        service_url           = "https://user-module-qa-eastus.azurewebsites.net"
        subscription_required = false
        openapi_path          = "openapi/apim-common-nonproduction-eastus/user-management-rest-api.openapi.yaml"
        policy_xml_path       = "policies/apim-common-nonproduction-eastus/user-management-rest-api.policy.xml"
      }
      "web-study-rest-api" = {
        display_name          = "Web Study REST API"
        path                  = "web"
        service_url           = "https://study-module-qa-nonproduction-eastus.azurewebsites.net"
        subscription_required = false
        openapi_path          = "openapi/apim-common-nonproduction-eastus/web-study-rest-api.openapi.yaml"
        policy_xml_path       = "policies/apim-common-nonproduction-eastus/web-study-rest-api.policy.xml"
      }
    }

    # --- Products (7 total — evidence: data/apim_full/apim-common-nonproduction-eastus/products.json) ---
    apim_products = {
      "data-api" = {
        display_name          = "Data API"
        description           = "This collection will contain all the APIs related to Data access and management"
        state                 = "published"
        subscription_required = false
        api_names             = ["data-access-rest-api"]
      }
      "mobile-api" = {
        display_name          = "Mobile API"
        description           = "This collection contains all the APIs required by our mobile applications"
        state                 = "published"
        subscription_required = false
        api_names             = ["mobile-notifications-rest-api", "mobile-participant-rest-api", "mobile-response-rest-api", "mobile-study-rest-api"]
      }
      "starter" = {
        display_name          = "Starter"
        description           = "Subscribers will be able to run 5 calls/minute up to a maximum of 100 calls/week."
        state                 = "published"
        subscription_required = true
        subscriptions_limit   = 1
        approval_required     = false
        api_names             = []
      }
      "storage-api" = {
        display_name          = "Storage API"
        description           = "This collection contains all the APIs required for Storage related functionalities"
        state                 = "published"
        subscription_required = false
        api_names             = ["blob-storage-rest-api", "queue-storage-rest-api"]
      }
      "unlimited" = {
        display_name          = "Unlimited"
        description           = "Subscribers have completely unlimited access to the API. Administrator approval is required."
        state                 = "published"
        subscription_required = true
        subscriptions_limit   = 1
        approval_required     = true
        api_names             = []
      }
      "user-management-api" = {
        display_name          = "User Management API"
        description           = "This API will allow the administrator of the system to add new web users and mobile participants."
        state                 = "published"
        subscription_required = false
        api_names             = ["user-management-rest-api"]
      }
      "web-api" = {
        display_name          = "Web API"
        description           = "This collection is consiste of "
        state                 = "published"
        subscription_required = false
        api_names             = ["web-study-rest-api"]
      }
    }

    # --- Named Values (16 total — evidence: data/apim_full/apim-common-nonproduction-eastus/named_values.json) ---
    # T-03-27: secret=true entries have value=null (no literal value authored).
    # Non-secret entries: minimum-android-app-version, minimum-ios-app-version only.
    # storage-account-name-dev is secret=true — no value.
    apim_named_values = {
      "app-reg-client-id-for-apim-to-mobile-app" = {
        display_name = "app-reg-client-id-for-apim-to-mobile-app"
        secret       = true
        value        = null # T-03-27: secret — no literal authored; must be set post-apply
      }
      "app-reg-client-id-for-apim-to-web-app" = {
        display_name = "app-reg-client-id-for-apim-to-web-app"
        secret       = true
        value        = null
      }
      "app-reg-client-id-for-mobile-android-app" = {
        display_name = "app-reg-client-id-for-mobile-android-app"
        secret       = true
        value        = null
      }
      "app-reg-client-id-for-mobile-ios-app" = {
        display_name = "app-reg-client-id-for-mobile-ios-app"
        secret       = true
        value        = null
      }
      "app-reg-client-id-for-mobile-ropc-app" = {
        display_name = "app-reg-client-id-for-mobile-ropc-app"
        secret       = true
        value        = null
      }
      "app-reg-client-id-for-web-apim" = {
        display_name = "app-reg-client-id-for-web-apim"
        secret       = true
        value        = null
      }
      "app-reg-client-id-for-web-app" = {
        display_name = "app-reg-client-id-for-web-app"
        secret       = true
        value        = null
      }
      "b2c-login-issuer-for-mobile-ropc-user" = {
        display_name = "b2c-login-issuer-for-mobile-ropc-user"
        secret       = true
        value        = null
      }
      "b2c-login-issuer-for-mobile-user" = {
        display_name = "b2c-login-issuer-for-mobile-user"
        secret       = true
        value        = null
      }
      "b2c-login-issuer-for-web-user" = {
        display_name = "b2c-login-issuer-for-web-user"
        secret       = true
        value        = null
      }
      "b2c-well-known-config-url-for-mobile-ropc-user" = {
        display_name = "b2c-well-known-config-url-for-mobile-ropc-user"
        secret       = true
        value        = null
      }
      "b2c-well-known-config-url-for-mobile-user" = {
        display_name = "b2c-well-known-config-url-for-mobile-user"
        secret       = true
        value        = null
      }
      "b2c-well-known-config-url-for-web-user" = {
        display_name = "b2c-well-known-config-url-for-web-user"
        secret       = true
        value        = null
      }
      "minimum-android-app-version" = {
        display_name = "minimum-android-app-version"
        secret       = false
        value        = "0.0.0" # evidence: named_values.json value="0.0.0"
      }
      "minimum-ios-app-version" = {
        display_name = "minimum-ios-app-version"
        secret       = false
        value        = "0.0.0"
      }
      "storage-account-name-dev" = {
        display_name = "storage-account-name-dev"
        secret       = true
        value        = null # T-03-27: secret=true in live instance — no literal authored
      }
    }

    # --- Subscriptions (8 total, excluding master — evidence: data/apim_full/apim-common-nonproduction-eastus/subscriptions.json) ---
    # "master" is Azure-managed (Built-in all-access subscription) — NOT authored.
    apim_subscriptions = {
      "64d31196f9471c0050070001" = { product_name = "starter", state = "active" }
      "64d31196f9471c0050070002" = { product_name = "unlimited", state = "active" }
      "64ef4c246694ec0788b1f77f" = { product_name = "web-api", state = "active" }
      "64ef4c876694ec0788b1f784" = { product_name = "mobile-api", state = "active" }
      "64ef4e726694ec0788b1f79a" = { product_name = "data-api", state = "active" }
      "64ef574d6694ec0788b1f7b5" = { product_name = "storage-api", state = "active" }
      "6728af815ddd1711381bf445" = { product_name = "user-management-api", state = "active" }
    }

    # --- Policy Fragments (9 total — evidence: data/apim_full/apim-common-nonproduction-eastus/policy_fragments.json) ---
    # T-03-29: Cloned verbatim from live acquisition — positive auth posture preserved.
    apim_policy_fragments = {
      "BlobStorageCacheLookupPolicy" = {
        description = "This will be used in inbound policy of Blob Storage Put Action"
        value       = "<!--\r\n    IMPORTANT:\r\n    - Policy fragment are included as-is whenever they are referenced.\r\n    - If using variables. Ensure they are setup before use.\r\n    - Copy and paste your code here or simply start coding\r\n-->\r\n<fragment>\r\n\t<cache-lookup vary-by-developer=\"false\" vary-by-developer-groups=\"false\" must-revalidate=\"true\" downstream-caching-type=\"public\">\r\n\t\t<vary-by-header>Accept</vary-by-header>\r\n\t\t<vary-by-header>Accept-Charset</vary-by-header>\r\n\t\t<vary-by-header>Authorization</vary-by-header>\r\n\t\t<vary-by-header>Container</vary-by-header>\r\n\t\t<vary-by-header>Blob</vary-by-header>\r\n\t</cache-lookup>\r\n</fragment>"
      }
      "BlobStorageCacheStorePolicy" = {
        description = "This need to be added to the outbound policy of Blob Storage Put Action"
        value       = "<!--\r\n    IMPORTANT:\r\n    - Policy fragment are included as-is whenever they are referenced.\r\n    - If using variables. Ensure they are setup before use.\r\n    - Copy and paste your code here or simply start coding\r\n-->\r\n<fragment>\r\n\t<cache-store duration=\"@{&#xA;        var header = context.Response.Headers.GetValueOrDefault(&quot;Cache-Control&quot;,&quot;&quot;);&#xA;        var maxAge = Regex.Match(header, @&quot;max-age=(?&lt;maxAge&gt;\\d+)&quot;).Groups[&quot;maxAge&quot;]?.Value;&#xA;        return (!string.IsNullOrEmpty(maxAge))?int.Parse(maxAge):300;&#xA;    }\" />\r\n</fragment>"
      }
      "BlobStorageGetPolicy" = {
        description = "This will be used as inbound policy when trying to Get files from Blob Storage"
        value       = "<fragment>\r\n\t<set-variable name=\"ContainerName\" value=\"@(context.Request.Headers.GetValueOrDefault(&quot;Container&quot;))\" />\r\n\t<set-variable name=\"BlobName\" value=\"@(context.Request.Headers.GetValueOrDefault(&quot;Blob&quot;))\" />\r\n\t<set-variable name=\"StorageAccountName\" value=\"{{storage-account-name-dev}}\" />\r\n\t<set-header name=\"Ocp-Apim-Subscription-Key\" exists-action=\"delete\" />\r\n\t<authentication-managed-identity resource=\"https://storage.azure.com/\" />\r\n</fragment>"
      }
      "BlobStoragePutPolicy" = {
        description = "Will be used as inbound policy in Blob Storage creation/edit calls"
        value       = "<fragment>\r\n\t<set-variable name=\"ContainerName\" value=\"@(context.Request.Headers.GetValueOrDefault(&quot;Container&quot;))\" />\r\n\t<set-variable name=\"BlobName\" value=\"@(context.Request.Headers.GetValueOrDefault(&quot;Blob&quot;))\" />\r\n\t<set-variable name=\"StorageAccountName\" value=\"{{storage-account-name-dev}}\" />\r\n\t<set-header name=\"Ocp-Apim-Subscription-Key\" exists-action=\"delete\" />\r\n\t<authentication-managed-identity resource=\"https://storage.azure.com/\" />\r\n</fragment>"
      }
      "CORSPolicy" = {
        description = "Cors policy for our APIS. should be applied on the global scope of the APIM"
        value       = "<fragment>\r\n\t<cors allow-credentials=\"true\">\r\n\t\t<allowed-origins>\r\n\t\t\t<origin>https://app.dev.lifedatadev.com</origin>\r\n\t\t\t<origin>https://apiportal.dev.lifedatadev.com</origin>\r\n\t\t\t<origin>https://apimgmt.dev.lifedatadev.com</origin>\r\n\t\t\t<origin>https://app.qa.lifedatadev.com</origin>\r\n\t\t\t<origin>https://apiportal.qa.lifedatadev.com</origin>\r\n\t\t\t<origin>https://apimgmt.qa.lifedatadev.com</origin>\r\n\t\t\t<origin>http://localhost:5173/</origin>\r\n\t\t\t<origin>http://localhost:4173/</origin>\r\n\t\t</allowed-origins>\r\n\t\t<allowed-methods preflight-result-max-age=\"300\">\r\n\t\t\t<method>*</method>\r\n\t\t</allowed-methods>\r\n\t\t<allowed-headers>\r\n\t\t\t<header>*</header>\r\n\t\t</allowed-headers>\r\n\t\t<expose-headers>\r\n\t\t\t<header>*</header>\r\n\t\t</expose-headers>\r\n\t</cors>\r\n</fragment>"
      }
      "MobileROPCAccessTokenValidatePolicy" = {
        description = "Anonymous from mobile application will make request with this type of access token"
        value       = "<fragment>\r\n\t<validate-jwt header-name=\"Authorization\" failed-validation-httpcode=\"401\" failed-validation-error-message=\"Unauthorized. ROPC Access token is missing or invalid.\">\r\n\t\t<openid-config url=\"{{b2c-well-known-config-url-for-mobile-ropc-user}}\" />\r\n\t\t<audiences>\r\n\t\t\t<audience>{{app-reg-client-id-for-mobile-ropc-app}}</audience>\r\n\t\t\t<audience>{{app-reg-client-id-for-apim-to-mobile-app}}</audience>\r\n\t\t</audiences>\r\n\t\t<issuers>\r\n\t\t\t<issuer>{{b2c-login-issuer-for-mobile-ropc-user}}</issuer>\r\n\t\t</issuers>\r\n\t</validate-jwt>\r\n</fragment>"
      }
      "QueueServicePolicy" = {
        description = "This will be needed when APIM will make call to the Queue Service"
        value       = "<fragment>\r\n\t<set-header name=\"Ocp-Apim-Subscription-Key\" exists-action=\"delete\" />\r\n\t<set-header name=\"x-ms-version\" exists-action=\"override\">\r\n\t\t<value>@{string version = \"2021-02-12\"; return version;}</value>\r\n\t</set-header>\r\n\t<set-variable name=\"StorageAccountName\" value=\"{{storage-account-name-dev}}\" />\r\n\t<authentication-managed-identity resource=\"https://storage.azure.com/\" />\r\n</fragment>"
      }
      "TaskInboundPolicy" = {
        description = "The conditional Authentication for the shared API between mobile and web app"
        value       = "<fragment>\r\n\t<set-variable name=\"userDeviceType\" value=\"@(context.Request.Headers.GetValueOrDefault(&quot;x-user-device-type&quot;))\" />\r\n\t<choose>\r\n\t\t<when condition=\"@(context.Variables.GetValueOrDefault&lt;string&gt;(&quot;userDeviceType&quot;) == &quot;Mobile&quot;)\">\r\n\t\t\t<validate-jwt header-name=\"Authorization\" failed-validation-httpcode=\"401\" failed-validation-error-message=\"Unauthorized. Mobile Access token is missing or invalid.\">\r\n\t\t\t\t<openid-config url=\"{{b2c-well-known-config-url-for-mobile-user}}\" />\r\n\t\t\t\t<audiences>\r\n\t\t\t\t\t<audience>{{app-reg-client-id-for-mobile-ios-app}}</audience>\r\n\t\t\t\t\t<audience>{{app-reg-client-id-for-mobile-android-app}}</audience>\r\n\t\t\t\t\t<audience>{{app-reg-client-id-for-mobile-ropc-app}}</audience>\r\n\t\t\t\t\t<audience>{{app-reg-client-id-for-apim-to-mobile-app}}</audience>\r\n\t\t\t\t</audiences>\r\n\t\t\t\t<issuers>\r\n\t\t\t\t\t<issuer>{{b2c-login-issuer-for-mobile-user}}</issuer>\r\n\t\t\t\t</issuers>\r\n\t\t\t</validate-jwt>\r\n\t\t</when>\r\n\t\t<otherwise>\r\n\t\t\t<validate-jwt header-name=\"Authorization\" failed-validation-httpcode=\"401\" failed-validation-error-message=\"Unauthorized. Web Access token is missing or invalid.\">\r\n\t\t\t\t<openid-config url=\"{{b2c-well-known-config-url-for-web-user}}\" />\r\n\t\t\t\t<audiences>\r\n\t\t\t\t\t<audience>{{app-reg-client-id-for-web-app}}</audience>\r\n\t\t\t\t\t<audience>{{app-reg-client-id-for-web-apim}}</audience>\r\n\t\t\t\t\t<audience>{{app-reg-client-id-for-apim-to-web-app}}</audience>\r\n\t\t\t\t</audiences>\r\n\t\t\t\t<issuers>\r\n\t\t\t\t\t<issuer>{{b2c-login-issuer-for-web-user}}</issuer>\r\n\t\t\t\t</issuers>\r\n\t\t\t</validate-jwt>\r\n\t\t</otherwise>\r\n\t</choose>\r\n</fragment>"
      }
      "WebAccessTokenValidatePolicy" = {
        description = "Web Applications will make request with web users access token. This code will handle the AD B2C jwt token validation."
        value       = "<fragment>\r\n\t<validate-jwt header-name=\"Authorization\" failed-validation-httpcode=\"401\" failed-validation-error-message=\"Unauthorized. Web Access token is missing or invalid.\">\r\n\t\t<openid-config url=\"{{b2c-well-known-config-url-for-web-user}}\" />\r\n\t\t<audiences>\r\n\t\t\t<audience>{{app-reg-client-id-for-web-app}}</audience>\r\n\t\t\t<audience>{{app-reg-client-id-for-apim-to-web-app}}</audience>\r\n\t\t\t<audience>{{app-reg-client-id-for-web-apim}}</audience>\r\n\t\t</audiences>\r\n\t\t<issuers>\r\n\t\t\t<issuer>{{b2c-login-issuer-for-web-user}}</issuer>\r\n\t\t</issuers>\r\n\t</validate-jwt>\r\n</fragment>"
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Instance 2: ldapim-eastus-dev
  # Evidence: apim_services.json name=ldapim-eastus-dev
  #           SKU=Developer_1, VNet=Internal, apim2-nonproduction-eastus-subnet
  #           data/apim_full/ldapim-eastus-dev/
  #           NOTABLE: This is the ONLY instance where ALL named values are non-secret
  #           (dev instance with test B2C tenants — values from data/apim_security.json)
  # ---------------------------------------------------------------------------
  "ldapim-eastus-dev" = {
    apim_name            = "ldapim-eastus-dev"
    apim_publisher_name  = "LifeData LLC."
    apim_publisher_email = "amalesh.debnath@gmail.com"
    apim_sku_name        = "Developer_1" # evidence: apim_services.json
    apim_vnet_type       = "Internal"    # evidence: apim_services.json virtualNetworkType=Internal
    apim_subnet_key      = "apim"        # apim2-nonproduction-eastus-subnet (shared with apim-common)

    apim_service_policy_xml_path = "policies/ldapim-eastus-dev/service.policy.xml"

    apim_hostname_configurations = {
      proxy = [
        {
          host_name           = "api.dev.lifedatadev.com"
          key_vault_id        = "https://kvnonproductioneastus.vault.azure.net/secrets/api-ssl-dev-cert"
          default_ssl_binding = true
        }
      ]
      management = [
        {
          host_name    = "apimgmt.dev.lifedatadev.com"
          key_vault_id = "https://kvnonproductioneastus.vault.azure.net/secrets/apimgmt-ssl-dev-cert"
        }
      ]
      portal = []
      developer_portal = [
        {
          host_name    = "apiportal.dev.lifedatadev.com"
          key_vault_id = "https://kvnonproductioneastus.vault.azure.net/secrets/apiportal-ssl-dev-cert"
        }
      ]
    }

    apim_aad_identity_provider_enabled = false
    apim_aad_client_id                 = ""
    apim_aad_allowed_tenants           = []

    # --- APIs (8 total — same as apim-common minus mobile-notifications) ---
    # evidence: data/apim_full/ldapim-eastus-dev/apis.json
    apim_apis = {
      "blob-storage-rest-api" = {
        display_name    = "Blob Storage REST API"
        path            = "blob-service"
        service_url     = "https://ldstdeveastus.blob.core.windows.net"
        openapi_path    = "openapi/ldapim-eastus-dev/blob-storage-rest-api.openapi.yaml"
        policy_xml_path = "policies/ldapim-eastus-dev/blob-storage-rest-api.policy.xml"
      }
      "data-access-rest-api" = {
        display_name    = "Data Access REST API"
        path            = "data-access"
        service_url     = "https://data-access-dev-eastus.azurewebsites.net"
        openapi_path    = "openapi/ldapim-eastus-dev/data-access-rest-api.openapi.yaml"
        policy_xml_path = "policies/ldapim-eastus-dev/data-access-rest-api.policy.xml"
      }
      "mobile-participant-rest-api" = {
        display_name    = "Mobile Participant REST API"
        path            = "mobile-participant-service"
        service_url     = "https://mobile-backend-dev-eastus.azurewebsites.net"
        openapi_path    = "openapi/ldapim-eastus-dev/mobile-participant-rest-api.openapi.yaml"
        policy_xml_path = ""
      }
      "mobile-response-rest-api" = {
        display_name    = "Mobile Response REST API"
        path            = "mobile-response"
        service_url     = "https://ldstdeveastus.queue.core.windows.net"
        openapi_path    = "openapi/ldapim-eastus-dev/mobile-response-rest-api.openapi.yaml"
        policy_xml_path = "policies/ldapim-eastus-dev/mobile-response-rest-api.policy.xml"
      }
      "mobile-study-rest-api" = {
        display_name    = "Mobile Study REST API"
        path            = "mobile-study-service"
        service_url     = "https://mobile-backend-dev-eastus.azurewebsites.net"
        openapi_path    = "openapi/ldapim-eastus-dev/mobile-study-rest-api.openapi.yaml"
        policy_xml_path = "policies/ldapim-eastus-dev/mobile-study-rest-api.policy.xml"
      }
      "queue-storage-rest-api" = {
        display_name    = "Queue Storage REST API"
        path            = "queue-service"
        service_url     = "https://ldstdeveastus.queue.core.windows.net"
        openapi_path    = "openapi/ldapim-eastus-dev/queue-storage-rest-api.openapi.yaml"
        policy_xml_path = "policies/ldapim-eastus-dev/queue-storage-rest-api.policy.xml"
      }
      "user-management-rest-api" = {
        display_name    = "User Management REST API"
        path            = "user"
        service_url     = "https://user-module-dev-eastus.azurewebsites.net"
        openapi_path    = "openapi/ldapim-eastus-dev/user-management-rest-api.openapi.yaml"
        policy_xml_path = "policies/ldapim-eastus-dev/user-management-rest-api.policy.xml"
      }
      "web-study-rest-api" = {
        display_name    = "Web Study REST API"
        path            = "web"
        service_url     = "https://study-module-dev-eastus.azurewebsites.net"
        openapi_path    = "openapi/ldapim-eastus-dev/web-study-rest-api.openapi.yaml"
        policy_xml_path = "policies/ldapim-eastus-dev/web-study-rest-api.policy.xml"
      }
    }

    # --- Products (8 total — evidence: data/apim_full/ldapim-eastus-dev/products.json) ---
    apim_products = {
      "data-access-rest-api" = {
        display_name          = "Data Access Rest API"
        description           = "Rest API for data request and dawnload"
        state                 = "published"
        subscription_required = false
        api_names             = ["data-access-rest-api"]
      }
      "mobile-rest-api" = {
        display_name          = "Mobile REST API"
        description           = "A collection of API for mobile Application"
        state                 = "published"
        subscription_required = false
        api_names             = ["mobile-participant-rest-api", "mobile-response-rest-api", "mobile-study-rest-api"]
      }
      "starter" = {
        display_name          = "Starter"
        description           = "Subscribers will be able to run 5 calls/minute up to a maximum of 100 calls/week."
        state                 = "published"
        subscription_required = true
        subscriptions_limit   = 1
        approval_required     = false
        api_names             = []
      }
      "storage-api" = {
        display_name          = "Storage API"
        description           = "API related to Azure Storage And Queues"
        state                 = "published"
        subscription_required = false
        api_names             = ["blob-storage-rest-api", "queue-storage-rest-api"]
      }
      "unlimited" = {
        display_name          = "Unlimited"
        description           = "Subscribers have completely unlimited access to the API. Administrator approval is required."
        state                 = "published"
        subscription_required = true
        subscriptions_limit   = 1
        approval_required     = true
        api_names             = []
      }
      "user-management-api" = {
        display_name          = "User Management API"
        description           = "This API will allow the administrator of the system to add new web users and mobile participants."
        state                 = "published"
        subscription_required = false
        api_names             = ["user-management-rest-api"]
      }
      "web-api" = {
        display_name          = "Web API"
        description           = "The API Collections for Web Application and clients"
        state                 = "notPublished"
        subscription_required = true
        api_names             = ["web-study-rest-api"]
      }
      "web-rest-api" = {
        display_name          = "Web Rest API"
        description           = "A collection of APIs to be used by the Web Application and Clients"
        state                 = "published"
        subscription_required = false
        api_names             = ["web-study-rest-api"]
      }
    }

    # --- Named Values (16 total — evidence: data/apim_full/ldapim-eastus-dev/named_values.json) ---
    # NOTABLE: ldapim-eastus-dev is the ONLY instance where all named values are non-secret.
    # Values from data/apim_security.json (dev B2C tenant values).
    apim_named_values = {
      "app-reg-client-id-for-apim-to-mobile-app" = {
        display_name = "app-reg-client-id-for-apim-to-mobile-app"
        secret       = false
        value        = "d0584a2e-dd25-4d52-b564-5703b7726b21" # evidence: apim_security.json
      }
      "app-reg-client-id-for-apim-to-web-app" = {
        display_name = "app-reg-client-id-for-apim-to-web-app"
        secret       = false
        value        = "42b9fc07-3711-4d34-9324-046fd19f3b29"
      }
      "app-reg-client-id-for-mobile-android-app" = {
        display_name = "app-reg-client-id-for-mobile-android-app"
        secret       = false
        value        = "bdded0a0-8e65-4d70-89fc-d75407b66e34"
      }
      "app-reg-client-id-for-mobile-ios-app" = {
        display_name = "app-reg-client-id-for-mobile-ios-app"
        secret       = false
        value        = "3397af85-e13f-493d-ab72-1a09ea75cf82"
      }
      "app-reg-client-id-for-mobile-ropc-app" = {
        display_name = "app-reg-client-id-for-mobile-ropc-app"
        secret       = false
        value        = "419cdb34-dcb4-455a-8130-f346f71b0f3c"
      }
      "app-reg-client-id-for-web-apim" = {
        display_name = "app-reg-client-id-for-web-apim"
        secret       = false
        value        = "42858b43-c783-4209-a342-ae2240ba3790"
      }
      "app-reg-client-id-for-web-app" = {
        display_name = "app-reg-client-id-for-web-app"
        secret       = false
        value        = "e6eab19c-859d-4d52-ab0b-f7fcdf23fdf5"
      }
      "b2c-login-issuer-for-mobile-ropc-user" = {
        display_name = "b2c-login-issuer-for-mobile-ropc-user"
        secret       = false
        value        = "https://workshopmobileusers.b2clogin.com/d67eb34d-7f5f-4a70-ae82-6b2130a80f05/v2.0/"
      }
      "b2c-login-issuer-for-mobile-user" = {
        display_name = "b2c-login-issuer-for-mobile-user"
        secret       = false
        value        = "https://workshopmobileusers.b2clogin.com/d67eb34d-7f5f-4a70-ae82-6b2130a80f05/v2.0/"
      }
      "b2c-login-issuer-for-web-user" = {
        display_name = "b2c-login-issuer-for-web-user"
        secret       = false
        value        = "https://workshopwebusers.b2clogin.com/e5393880-af26-4cc1-a0ce-3319e69b84b6/v2.0/"
      }
      "b2c-well-known-config-url-for-mobile-ropc-user" = {
        display_name = "b2c-well-known-config-url-for-mobile-ropc-user"
        secret       = false
        value        = "https://workshopmobileusers.b2clogin.com/workshopmobileusers.onmicrosoft.com/B2C_1_ropc_signin_flow/v2.0/.well-known/openid-configuration"
      }
      "b2c-well-known-config-url-for-mobile-user" = {
        display_name = "b2c-well-known-config-url-for-mobile-user"
        secret       = false
        value        = "https://workshopmobileusers.b2clogin.com/workshopmobileusers.onmicrosoft.com/v2.0/.well-known/openid-configuration?p=B2C_1_mobile_signup_signin"
      }
      "b2c-well-known-config-url-for-web-user" = {
        display_name = "b2c-well-known-config-url-for-web-user"
        secret       = false
        value        = "https://workshopwebusers.b2clogin.com/workshopwebusers.onmicrosoft.com/v2.0/.well-known/openid-configuration?p=B2C_1_web-user-signin"
      }
      "minimum-android-app-version" = {
        display_name = "minimum-android-app-version"
        secret       = false
        value        = "1.0.2"
      }
      "minimum-ios-app-version" = {
        display_name = "minimum-ios-app-version"
        secret       = false
        value        = "1.0.5"
      }
      "storage-account-name-dev" = {
        display_name = "storage-account-name-dev"
        secret       = false
        value        = "ldstdeveastus" # evidence: apim_security.json value="ldstdeveastus"
      }
    }

    # --- Subscriptions (9 total, excluding master — evidence: data/apim_full/ldapim-eastus-dev/subscriptions.json) ---
    apim_subscriptions = {
      "650dba3b4c8d3f0067070001" = { product_name = "starter", state = "active" }
      "650dba3b4c8d3f0067070002" = { product_name = "unlimited", state = "active" }
      "650dba3b6b12c2007e070006" = { product_name = "storage-api", state = "active" }
      "650dba3b6b12c2007e070007" = { product_name = "mobile-rest-api", state = "active" }
      "650dba3b6b12c2007e070008" = { product_name = "data-access-rest-api", state = "active" }
      "650dba3b6b12c2007e07000a" = { product_name = "user-management-api", state = "active" }
      "66fd84a2f5aafd00f2040001" = { product_name = "web-rest-api", state = "active" }
      "66fd84a2f5aafd00f2040002" = { product_name = "web-api", state = "active" }
    }

    # --- Policy Fragments (10 total — evidence: data/apim_full/ldapim-eastus-dev/policy_fragments.json) ---
    # Same 9 as apim-common + 1 additional (MobileAccessTokenValidatePolicy)
    apim_policy_fragments = {
      "BlobStorageCacheLookupPolicy" = {
        description = "This will be used in inbound policy of Blob Storage Put Action"
        value       = "<!--\r\n    IMPORTANT:\r\n    - Policy fragment are included as-is whenever they are referenced.\r\n    - If using variables. Ensure they are setup before use.\r\n    - Copy and paste your code here or simply start coding\r\n-->\r\n<fragment>\r\n\t<cache-lookup vary-by-developer=\"false\" vary-by-developer-groups=\"false\" must-revalidate=\"true\" downstream-caching-type=\"public\">\r\n\t\t<vary-by-header>Accept</vary-by-header>\r\n\t\t<vary-by-header>Accept-Charset</vary-by-header>\r\n\t\t<vary-by-header>Authorization</vary-by-header>\r\n\t\t<vary-by-header>Container</vary-by-header>\r\n\t\t<vary-by-header>Blob</vary-by-header>\r\n\t</cache-lookup>\r\n</fragment>"
      }
      "BlobStorageCacheStorePolicy" = {
        description = "This need to be added to the outbound policy of Blob Storage Put Action"
        value       = "<!--\r\n    IMPORTANT:\r\n    - Policy fragment are included as-is whenever they are referenced.\r\n    - If using variables. Ensure they are setup before use.\r\n    - Copy and paste your code here or simply start coding\r\n-->\r\n<fragment>\r\n\t<cache-store duration=\"@{&#xA;        var header = context.Response.Headers.GetValueOrDefault(&quot;Cache-Control&quot;,&quot;&quot;);&#xA;        var maxAge = Regex.Match(header, @&quot;max-age=(?&lt;maxAge&gt;\\d+)&quot;).Groups[&quot;maxAge&quot;]?.Value;&#xA;        return (!string.IsNullOrEmpty(maxAge))?int.Parse(maxAge):300;&#xA;    }\" />\r\n</fragment>"
      }
      "BlobStorageGetPolicy" = {
        description = "This will be used as inbound policy when trying to Get files from Blob Storage"
        value       = "<fragment>\r\n\t<set-variable name=\"StorageAccountName\" value=\"{{storage-account-name-dev}}\" />\r\n\t<authentication-managed-identity resource=\"https://storage.azure.com/\" />\r\n</fragment>"
      }
      "BlobStoragePutPolicy" = {
        description = "Will be used as inbound policy in Blob Storage creation/edit calls"
        value       = "<fragment>\r\n\t<set-variable name=\"StorageAccountName\" value=\"{{storage-account-name-dev}}\" />\r\n\t<authentication-managed-identity resource=\"https://storage.azure.com/\" />\r\n</fragment>"
      }
      "CORSPolicy" = {
        description = "Cors policy for our APIS. should be applied on the global scope of the APIM"
        value       = "<fragment>\r\n\t<cors allow-credentials=\"true\">\r\n\t\t<allowed-origins>\r\n\t\t\t<origin>https://app.dev.lifedatadev.com</origin>\r\n\t\t\t<origin>https://apiportal.dev.lifedatadev.com</origin>\r\n\t\t\t<origin>https://apimgmt.dev.lifedatadev.com</origin>\r\n\t\t\t<origin>https://app.qa.lifedatadev.com</origin>\r\n\t\t\t<origin>http://localhost:5173/</origin>\r\n\t\t\t<origin>http://localhost:4173/</origin>\r\n\t\t</allowed-origins>\r\n\t\t<allowed-methods preflight-result-max-age=\"300\">\r\n\t\t\t<method>*</method>\r\n\t\t</allowed-methods>\r\n\t\t<allowed-headers>\r\n\t\t\t<header>*</header>\r\n\t\t</allowed-headers>\r\n\t\t<expose-headers>\r\n\t\t\t<header>*</header>\r\n\t\t</expose-headers>\r\n\t</cors>\r\n</fragment>"
      }
      "MobileAccessTokenValidatePolicy" = {
        description = "Mobile Applications will make request with mobile users access token."
        value       = "<fragment>\r\n\t<validate-jwt header-name=\"Authorization\" failed-validation-httpcode=\"401\" failed-validation-error-message=\"Unauthorized. Mobile Access token is missing or invalid.\">\r\n\t\t<openid-config url=\"{{b2c-well-known-config-url-for-mobile-user}}\" />\r\n\t\t<audiences>\r\n\t\t\t<audience>{{app-reg-client-id-for-mobile-ios-app}}</audience>\r\n\t\t\t<audience>{{app-reg-client-id-for-mobile-android-app}}</audience>\r\n\t\t\t<audience>{{app-reg-client-id-for-mobile-ropc-app}}</audience>\r\n\t\t\t<audience>{{app-reg-client-id-for-apim-to-mobile-app}}</audience>\r\n\t\t</audiences>\r\n\t\t<issuers>\r\n\t\t\t<issuer>{{b2c-login-issuer-for-mobile-user}}</issuer>\r\n\t\t</issuers>\r\n\t</validate-jwt>\r\n</fragment>"
      }
      "MobileROPCAccessTokenValidatePolicy" = {
        description = "Anonymous from mobile application will make request with this type of access token"
        value       = "<fragment>\r\n\t<validate-jwt header-name=\"Authorization\" failed-validation-httpcode=\"401\" failed-validation-error-message=\"Unauthorized. ROPC Access token is missing or invalid.\">\r\n\t\t<openid-config url=\"{{b2c-well-known-config-url-for-mobile-ropc-user}}\" />\r\n\t\t<audiences>\r\n\t\t\t<audience>{{app-reg-client-id-for-mobile-ropc-app}}</audience>\r\n\t\t\t<audience>{{app-reg-client-id-for-apim-to-mobile-app}}</audience>\r\n\t\t</audiences>\r\n\t\t<issuers>\r\n\t\t\t<issuer>{{b2c-login-issuer-for-mobile-ropc-user}}</issuer>\r\n\t\t</issuers>\r\n\t</validate-jwt>\r\n</fragment>"
      }
      "QueueServicePolicy" = {
        description = "This will be needed when APIM will make call to the Queue Service"
        value       = "<fragment>\r\n\t<set-header name=\"Ocp-Apim-Subscription-Key\" exists-action=\"delete\" />\r\n\t<set-header name=\"x-ms-version\" exists-action=\"override\">\r\n\t\t<value>@{string version = \"2021-02-12\"; return version;}</value>\r\n\t</set-header>\r\n\t<set-variable name=\"StorageAccountName\" value=\"{{storage-account-name-dev}}\" />\r\n\t<authentication-managed-identity resource=\"https://storage.azure.com/\" />\r\n</fragment>"
      }
      "TaskInboundPolicy" = {
        description = "The conditional Authentication for the shared API between mobile and web app"
        value       = "<fragment>\r\n\t<set-variable name=\"userDeviceType\" value=\"@(context.Request.Headers.GetValueOrDefault(&quot;x-user-device-type&quot;))\" />\r\n\t<choose>\r\n\t\t<when condition=\"@(context.Variables.GetValueOrDefault&lt;string&gt;(&quot;userDeviceType&quot;) == &quot;Mobile&quot;)\">\r\n\t\t\t<validate-jwt header-name=\"Authorization\" failed-validation-httpcode=\"401\" failed-validation-error-message=\"Unauthorized. Mobile Access token is missing or invalid.\">\r\n\t\t\t\t<openid-config url=\"{{b2c-well-known-config-url-for-mobile-user}}\" />\r\n\t\t\t\t<audiences>\r\n\t\t\t\t\t<audience>{{app-reg-client-id-for-mobile-ios-app}}</audience>\r\n\t\t\t\t\t<audience>{{app-reg-client-id-for-mobile-android-app}}</audience>\r\n\t\t\t\t</audiences>\r\n\t\t\t\t<issuers>\r\n\t\t\t\t\t<issuer>{{b2c-login-issuer-for-mobile-user}}</issuer>\r\n\t\t\t\t</issuers>\r\n\t\t\t</validate-jwt>\r\n\t\t</when>\r\n\t\t<otherwise>\r\n\t\t\t<validate-jwt header-name=\"Authorization\" failed-validation-httpcode=\"401\" failed-validation-error-message=\"Unauthorized. Web Access token is missing or invalid.\">\r\n\t\t\t\t<openid-config url=\"{{b2c-well-known-config-url-for-web-user}}\" />\r\n\t\t\t\t<audiences>\r\n\t\t\t\t\t<audience>{{app-reg-client-id-for-web-app}}</audience>\r\n\t\t\t\t</audiences>\r\n\t\t\t\t<issuers>\r\n\t\t\t\t\t<issuer>{{b2c-login-issuer-for-web-user}}</issuer>\r\n\t\t\t\t</issuers>\r\n\t\t\t</validate-jwt>\r\n\t\t</otherwise>\r\n\t</choose>\r\n</fragment>"
      }
      "WebAccessTokenValidatePolicy" = {
        description = "Web Applications will make request with web users access token."
        value       = "<fragment>\r\n\t<validate-jwt header-name=\"Authorization\" failed-validation-httpcode=\"401\" failed-validation-error-message=\"Unauthorized. Web Access token is missing or invalid.\">\r\n\t\t<openid-config url=\"{{b2c-well-known-config-url-for-web-user}}\" />\r\n\t\t<audiences>\r\n\t\t\t<audience>{{app-reg-client-id-for-web-app}}</audience>\r\n\t\t\t<audience>{{app-reg-client-id-for-apim-to-web-app}}</audience>\r\n\t\t</audiences>\r\n\t\t<issuers>\r\n\t\t\t<issuer>{{b2c-login-issuer-for-web-user}}</issuer>\r\n\t\t</issuers>\r\n\t</validate-jwt>\r\n</fragment>"
      }
    }
  }
}

# --- end apim values ---

# ---------------------------------------------------------------------------
# § app-gateway values (Plan 03-07)
# ---------------------------------------------------------------------------

# --- app-gateway values (Plan 03-07) ---
# Evidence: terraform/LD-NonProd-EastUS-V2/main.tf:533-1040 (agw-common-nonproduction-eastus)
#           data/appgw.json (autoscale min=1 max=2 confirmed on both gateways)
# D-307: appgw_sku_name + appgw_sku_tier are no-default posture variables.
#   M1: Standard_v2 (no WAF — preserved A-/F-finding). M3: WAF_v2 flip via tfvars diff.
# T-03-23: WAF posture-preservation boundary — never silent default.
# T-03-25: Only KV-referenced active certs authored. Historic date-tagged certs DROPPED.

agw_name          = "agw-common-nonproduction-eastus" # evidence: nonprod main.tf:536
agw_identity_name = "id-agw-nonprod-eastus"           # v3 naming convention

# D-307 / T-03-23: WAF posture — M1=Standard_v2 (no WAF). M3 flips to WAF_v2.
# Evidence: nonprod main.tf:904-907 sku.name="Standard_v2" sku.tier="Standard_v2".
appgw_sku_name = "Standard_v2" # M1: no WAF (preserved nonprod posture; M3→WAF_v2)
appgw_sku_tier = "Standard_v2" # M1: no WAF. Evidence: nonprod main.tf:905-906; data/appgw.json no WAF configured

# Autoscale capacity. Evidence: data/appgw.json autoscaleConfiguration.minCapacity=1 maxCapacity=2
agw_min_capacity = 1
agw_max_capacity = 2

# PIP key — selects pip-common-nonproduction-eastus from module.networking.public_ip_ids.
# Evidence: public_ips.json "pip-common-nonproduction-eastus"; nonprod main.tf:652-655.
agw_public_ip_key = "agw_common"

# Backend address pools — 8 pools (dev + qa APIM API/MGMT/Portal + dev/qa web frontend).
# Evidence: nonprod main.tf:542-573.
agw_backend_address_pools = {
  "bp-web-frontend-dev" = {
    name         = "bp-web-frontend-dev"
    fqdns        = ["web-frontend-dev-eastus.azurewebsites.net"]
    ip_addresses = []
  }
  "bp-web-frontend-qa" = {
    name         = "bp-web-frontend-qa"
    fqdns        = ["web-frontend-qa-nonproduction-eastus.azurewebsites.net"]
    ip_addresses = []
  }
  "bp-apim-api-dev" = {
    name         = "bp-apim-api-dev"
    fqdns        = []
    ip_addresses = ["10.0.10.4"] # evidence: appgw.json backendAddressPools bp-apim-api-dev
  }
  "bp-apim-api-qa" = {
    name         = "bp-apim-api-qa"
    fqdns        = []
    ip_addresses = ["10.0.10.7"] # evidence: appgw.json backendAddressPools bp-apim-api-qa
  }
  "bp-apim-mgmt-dev" = {
    name         = "bp-apim-mgmt-dev"
    fqdns        = []
    ip_addresses = ["10.0.10.4"] # evidence: nonprod main.tf:558-561
  }
  "bp-apim-mgmt-qa" = {
    name         = "bp-apim-mgmt-qa"
    fqdns        = []
    ip_addresses = ["10.0.10.7"] # evidence: nonprod main.tf:562-565
  }
  "bp-apim-portal-dev" = {
    name         = "bp-apim-portal-dev"
    fqdns        = []
    ip_addresses = ["10.0.10.4"] # evidence: nonprod main.tf:566-569
  }
  "bp-apim-portal-qa" = {
    name         = "bp-apim-portal-qa"
    fqdns        = []
    ip_addresses = ["10.0.10.7"] # evidence: nonprod main.tf:570-573
  }
}

# Backend HTTP settings — 8 entries (dev + qa APIM API/MGMT/Portal + dev/qa web frontend).
# Evidence: nonprod main.tf:574-651.
agw_backend_http_settings = {
  "bs-web-frontend-dev" = {
    name                  = "bs-web-frontend-dev"
    cookie_based_affinity = "Enabled"
    affinity_cookie_name  = "ApplicationGatewayAffinityDev"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 150
    probe_name            = "hp-web-frontend-dev"
    host_name             = ""
  }
  "bs-web-frontend-qa" = {
    name                  = "bs-web-frontend-qa"
    cookie_based_affinity = "Enabled"
    affinity_cookie_name  = "ApplicationGatewayAffinity"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 150
    probe_name            = "hp-web-frontend-qa"
    host_name             = ""
  }
  "bs-apim-api-dev" = {
    name                  = "bs-apim-api-dev"
    cookie_based_affinity = "Enabled"
    affinity_cookie_name  = "ApplicationGatewayAffinityDev"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 150
    probe_name            = "hp-api-dev"
    host_name             = "api.dev.lifedatadev.com" # evidence: nonprod main.tf:625-626
  }
  "bs-apim-api-qa" = {
    name                  = "bs-apim-api-qa"
    cookie_based_affinity = "Enabled"
    affinity_cookie_name  = "ApplicationGatewayAffinity"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 150
    probe_name            = "hp-api-qa"
    host_name             = "api.qa.lifedatadev.com" # evidence: nonprod main.tf:586-587
  }
  "bs-apim-mgmt-dev" = {
    name                  = "bs-apim-mgmt-dev"
    cookie_based_affinity = "Enabled"
    affinity_cookie_name  = "ApplicationGatewayAffinityDev"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 150
    probe_name            = "hp-apimgmt-dev"
    host_name             = "apimgmt.dev.lifedatadev.com" # evidence: nonprod main.tf:635-636
  }
  "bs-apim-mgmt-qa" = {
    name                  = "bs-apim-mgmt-qa"
    cookie_based_affinity = "Enabled"
    affinity_cookie_name  = "ApplicationGatewayAffinity"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 150
    probe_name            = "hp-apimgmt-qa"
    host_name             = "apimgmt.qa.lifedatadev.com" # evidence: nonprod main.tf:596-597
  }
  "bs-apim-portal-dev" = {
    name                  = "bs-apim-portal-dev"
    cookie_based_affinity = "Enabled"
    affinity_cookie_name  = "ApplicationGatewayAffinityDev"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 150
    probe_name            = "hp-apiportal-dev"
    host_name             = "apiportal.dev.lifedatadev.com" # evidence: nonprod main.tf:645-646
  }
  "bs-apim-portal-qa" = {
    name                  = "bs-apim-portal-qa"
    cookie_based_affinity = "Enabled"
    affinity_cookie_name  = "ApplicationGatewayAffinity"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 150
    probe_name            = "hp-apiportal-qa"
    host_name             = "apiportal.qa.lifedatadev.com" # evidence: nonprod main.tf:606-607
  }
}

# HTTP listeners — 8 listeners, all HTTPS + SNI, KV-referenced certs.
# Evidence: nonprod main.tf:668-739.
agw_http_listeners = {
  "listener-apim-api-dev" = {
    name                 = "listener-apim-api-dev"
    ssl_certificate_name = "ssl-kv-apim-api-06-05-2026" # KV cert evidence: nonprod main.tf:675
    host_names           = []
    host_name            = "api.dev.lifedatadev.com" # evidence: nonprod main.tf:671
  }
  "listener-apim-api-qa" = {
    name                 = "listener-apim-api-qa"
    ssl_certificate_name = "ssl-kv-apim-api-qa-06-05-2026" # KV cert evidence: nonprod main.tf:684
    host_names           = []
    host_name            = "api.qa.lifedatadev.com" # evidence: nonprod main.tf:680
  }
  "listener-apim-mgmt-dev" = {
    name                 = "listener-apim-mgmt-dev"
    ssl_certificate_name = "ssl-kv-apim-mgmt-dev-06-05-2026" # KV cert evidence: nonprod main.tf:693
    host_names           = []
    host_name            = "apimgmt.dev.lifedatadev.com" # evidence: nonprod main.tf:689
  }
  "listener-apim-mgmt-qa" = {
    name                 = "listener-apim-mgmt-qa"
    ssl_certificate_name = "ssl-kv-apim-mgmt-qa-06-05-2026" # KV cert evidence: nonprod main.tf:702
    host_names           = []
    host_name            = "apimgmt.qa.lifedatadev.com" # evidence: nonprod main.tf:698
  }
  "listener-apim-portal-dev" = {
    name                 = "listener-apim-portal-dev"
    ssl_certificate_name = "ssl-kv-apim-portal-dev" # KV cert evidence: nonprod main.tf:711
    host_names           = []
    host_name            = "apiportal.dev.lifedatadev.com" # evidence: nonprod main.tf:708
  }
  "listener-apim-portal-qa" = {
    name                 = "listener-apim-portal-qa"
    ssl_certificate_name = "ssl-kv-apim-portal-qa-06-05-2026" # KV cert evidence: nonprod main.tf:720
    host_names           = []
    host_name            = "apiportal.qa.lifedatadev.com" # evidence: nonprod main.tf:716
  }
  "listener-web-frontend-dev" = {
    name                 = "listener-web-frontend-dev"
    ssl_certificate_name = "ssl-kv-app-dev-06-05-2026" # KV cert evidence: nonprod main.tf:729
    host_names           = []
    host_name            = "app.dev.lifedatadev.com" # evidence: nonprod main.tf:725
  }
  "listener-web-frontend-qa" = {
    name                 = "listener-web-frontend-qa"
    ssl_certificate_name = "ssl-kv-app-qa-06-05-2026" # KV cert evidence: nonprod main.tf:738
    host_names           = []
    host_name            = "app.qa.lifedatadev.com" # evidence: nonprod main.tf:734
  }
}

# Health probes — 8 probes. Evidence: nonprod main.tf:744-839.
agw_probes = {
  "hp-api-dev" = {
    name                = "hp-api-dev"
    host                = "api.dev.lifedatadev.com"
    path                = "/status-0123456789abcdef"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }
  "hp-api-qa" = {
    name                = "hp-api-qa"
    host                = "api.qa.lifedatadev.com"
    path                = "/status-0123456789abcdef"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }
  "hp-apimgmt-dev" = {
    name                = "hp-apimgmt-dev"
    host                = "apimgmt.dev.lifedatadev.com"
    path                = "/ServiceStatus"
    interval            = 30
    timeout             = 60
    unhealthy_threshold = 3
  }
  "hp-apimgmt-qa" = {
    name                = "hp-apimgmt-qa"
    host                = "apimgmt.qa.lifedatadev.com"
    path                = "/ServiceStatus"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }
  "hp-apiportal-dev" = {
    name                = "hp-apiportal-dev"
    host                = "apiportal.dev.lifedatadev.com"
    path                = "/signin"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }
  "hp-apiportal-qa" = {
    name                = "hp-apiportal-qa"
    host                = "apiportal.qa.lifedatadev.com"
    path                = "/signin"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }
  "hp-web-frontend-dev" = {
    name                = "hp-web-frontend-dev"
    host                = "app.dev.lifedatadev.com"
    path                = "/"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }
  "hp-web-frontend-qa" = {
    name                = "hp-web-frontend-qa"
    host                = "app.qa.lifedatadev.com"
    path                = "/"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }
}

# Request routing rules — 8 rules. Evidence: nonprod main.tf:840-903.
agw_request_routing_rules = {
  "rule-apim-api-dev" = {
    name                       = "rule-apim-api-dev"
    http_listener_name         = "listener-apim-api-dev"
    backend_address_pool_name  = "bp-apim-api-dev"
    backend_http_settings_name = "bs-apim-api-dev"
    priority                   = 6
    rewrite_rule_set_name      = "" # nonprod has no rewrite rule sets
  }
  "rule-apim-api-qa" = {
    name                       = "rule-apim-api-qa"
    http_listener_name         = "listener-apim-api-qa"
    backend_address_pool_name  = "bp-apim-api-qa"
    backend_http_settings_name = "bs-apim-api-qa"
    priority                   = 2
    rewrite_rule_set_name      = ""
  }
  "rule-apim-mgmt-dev" = {
    name                       = "rule-apim-mgmt-dev"
    http_listener_name         = "listener-apim-mgmt-dev"
    backend_address_pool_name  = "bp-apim-mgmt-dev"
    backend_http_settings_name = "bs-apim-mgmt-dev"
    priority                   = 8
    rewrite_rule_set_name      = ""
  }
  "rule-apim-mgmt-qa" = {
    name                       = "rule-apim-mgmt-qa"
    http_listener_name         = "listener-apim-mgmt-qa"
    backend_address_pool_name  = "bp-apim-mgmt-qa"
    backend_http_settings_name = "bs-apim-mgmt-qa"
    priority                   = 4
    rewrite_rule_set_name      = ""
  }
  "rule-apim-portal-dev" = {
    name                       = "rule-apim-portal-dev"
    http_listener_name         = "listener-apim-portal-dev"
    backend_address_pool_name  = "bp-apim-portal-dev"
    backend_http_settings_name = "bs-apim-portal-dev"
    priority                   = 7
    rewrite_rule_set_name      = ""
  }
  "rule-apim-portalqa" = {
    name                       = "rule-apim-portalqa" # evidence: nonprod main.tf:884 (exact name used)
    http_listener_name         = "listener-apim-portal-qa"
    backend_address_pool_name  = "bp-apim-portal-qa"
    backend_http_settings_name = "bs-apim-portal-qa"
    priority                   = 3
    rewrite_rule_set_name      = ""
  }
  "rule-web-frontend-dev" = {
    name                       = "rule-web-frontend-dev"
    http_listener_name         = "listener-web-frontend-dev"
    backend_address_pool_name  = "bp-web-frontend-dev"
    backend_http_settings_name = "bs-web-frontend-dev"
    priority                   = 5
    rewrite_rule_set_name      = ""
  }
  "rule-web-frontend-qa" = {
    name                       = "rule-web-frontend-qa"
    http_listener_name         = "listener-web-frontend-qa"
    backend_address_pool_name  = "bp-web-frontend-qa"
    backend_http_settings_name = "bs-web-frontend-qa"
    priority                   = 1
    rewrite_rule_set_name      = ""
  }
}

# Rewrite rule sets — nonprod has no rewrite rule sets.
# Evidence: nonprod main.tf (no rewrite_rule_set blocks in nonprod AGW resource).
agw_rewrite_rule_sets = {}

# SSL certificates — only the 8 KV-referenced active certs.
# T-03-25: Historic date-tagged certs (no key_vault_secret_id) DROPPED — upload-once Portal certs.
# Evidence: nonprod main.tf:1004-1035 (KV-referenced certs with kvnonproductioneastus vault).
agw_ssl_certificates = {
  "ssl-kv-apim-api-06-05-2026" = {
    name                = "ssl-kv-apim-api-06-05-2026"
    key_vault_secret_id = "https://kvnonproductioneastus.vault.azure.net/secrets/api-ssl-dev-cert"
  }
  "ssl-kv-apim-api-qa-06-05-2026" = {
    name                = "ssl-kv-apim-api-qa-06-05-2026"
    key_vault_secret_id = "https://kvnonproductioneastus.vault.azure.net/secrets/api-ssl-cert-qa"
  }
  "ssl-kv-apim-mgmt-dev-06-05-2026" = {
    name                = "ssl-kv-apim-mgmt-dev-06-05-2026"
    key_vault_secret_id = "https://kvnonproductioneastus.vault.azure.net/secrets/apimgmt-ssl-dev-cert"
  }
  "ssl-kv-apim-mgmt-qa-06-05-2026" = {
    name                = "ssl-kv-apim-mgmt-qa-06-05-2026"
    key_vault_secret_id = "https://kvnonproductioneastus.vault.azure.net/secrets/apimgmt-ssl-qa-cert"
  }
  "ssl-kv-apim-portal-dev" = {
    name                = "ssl-kv-apim-portal-dev"
    key_vault_secret_id = "https://kvnonproductioneastus.vault.azure.net/secrets/apiportal-ssl-dev-cert"
  }
  "ssl-kv-apim-portal-qa-06-05-2026" = {
    name                = "ssl-kv-apim-portal-qa-06-05-2026"
    key_vault_secret_id = "https://kvnonproductioneastus.vault.azure.net/secrets/apiportal-ssl-qa-cert"
  }
  "ssl-kv-app-dev-06-05-2026" = {
    name                = "ssl-kv-app-dev-06-05-2026"
    key_vault_secret_id = "https://kvnonproductioneastus.vault.azure.net/secrets/app-ssl-dev-cert"
  }
  "ssl-kv-app-qa-06-05-2026" = {
    name                = "ssl-kv-app-qa-06-05-2026"
    key_vault_secret_id = "https://kvnonproductioneastus.vault.azure.net/secrets/app-ssl-qa-cert"
  }
}

# --- end app-gateway values ---

# ---------------------------------------------------------------------------
# § observability values (Plan 03-07)
# ---------------------------------------------------------------------------

# --- observability values (Plan 03-07) ---
# Evidence: terraform/LD-NonProd-EastUS-V2/main.tf:3594-3781
#           (1 action group + 9 nonprod metric alerts + 1 app insights instance)
# D-305: Alerts expressed via for_each map — NOT 9 hand-written blocks.
# T-03-24: Action group IDs from new estate outputs — never old LD-*-EastUS-V2 ARM paths.
# T-03-25: App Insights connection_string output only — no instrumentation key literal.

# nonprod scope has no Log Analytics workspace.
# Evidence: nonprod HCL has no azurerm_log_analytics_workspace resource.
log_analytics_workspace_name = ""

# No saved searches on nonprod (workspace absent).
saved_searches = {}

# 1 App Insights instance for nonprod.
# Evidence: nonprod main.tf:3629-3635 (appi-common-nonproduction-eastus, sampling_percentage=0).
app_insights_instances = {
  "common" = {
    name                = "appi-common-nonproduction-eastus"
    application_type    = "web"
    sampling_percentage = 0
  }
}

# 1 action group for nonprod.
# Evidence: nonprod main.tf:3594-3628 (res-2326 "LifeData Azure Contributor", short="LDAzCon").
action_groups = {
  "lifedata_contributor" = {
    name       = "LifeData Azure Contributor"
    short_name = "LDAzCon"
    arm_role_receivers = [
      {
        name                    = "LifeData Azure Contributor"
        role_id                 = "b24988ac-6180-42a0-ab88-20f7382dd24c" # Contributor role ID (builtin)
        use_common_alert_schema = false
      }
    ]
    email_receivers          = []
    azure_app_push_receivers = []
  }
}

# 9 nonprod metric alerts expressed via for_each map (D-305).
# Evidence: nonprod main.tf:3636-3781 (res-2329 through res-2337).
# Scopes use logical keys resolved to new-estate IDs via alert_scope_ids merge in main.tf.
# T-03-24: scope_key resolves against new-estate module outputs — no old ARM paths.
alerts = {
  "nonprod-agw-5xx-backend" = {
    name             = "V2 NonProd AGW 5XX Backend"
    scope_key        = "app_gateway"
    metric_name      = "BackendResponseStatus"
    metric_namespace = "Microsoft.Network/applicationGateways"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
    description      = "NonProd Application Gateway backend 5XX response count exceeded threshold"
    enabled          = true
    severity         = 2
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "lifedata_contributor"
    dimension_name   = "HttpStatusGroup"
    dimension_values = ["5xx"]
  }
  "nonprod-agw-5xx-total" = {
    name             = "V2 NonProd AGW 5XX Total"
    scope_key        = "app_gateway"
    metric_name      = "TotalRequests"
    metric_namespace = "Microsoft.Network/applicationGateways"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
    description      = "NonProd Application Gateway total 5XX count exceeded threshold"
    enabled          = true
    severity         = 2
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "lifedata_contributor"
    dimension_name   = "HttpStatusGroup"
    dimension_values = ["5xx"]
  }
  "nonprod-agw-unhealthy-backend" = {
    name             = "V2 NonProd AGW UnhealthyBackend"
    scope_key        = "app_gateway"
    metric_name      = "UnhealthyHostCount"
    metric_namespace = "Microsoft.Network/applicationGateways"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 0
    description      = "NonProd Application Gateway has unhealthy backend hosts"
    enabled          = true
    severity         = 2
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "lifedata_contributor"
    dimension_name   = ""
    dimension_values = []
  }
  "nonprod-sql-dev-dtu" = {
    name             = "V2 NonProd SQL Dev DTU"
    scope_key        = "sql_dev"
    metric_name      = "dtu_consumption_percent"
    metric_namespace = "Microsoft.Sql/servers/databases"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90
    description      = "NonProd Dev SQL DTU consumption exceeded 90%"
    enabled          = true
    severity         = 2
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "lifedata_contributor"
    dimension_name   = ""
    dimension_values = []
  }
  "nonprod-web-plan-dev-cpu" = {
    name             = "V2 NonProd Web Plan Dev CPU"
    scope_key        = "web_plan_dev"
    metric_name      = "CpuPercentage"
    metric_namespace = "Microsoft.Web/serverfarms"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90
    description      = "NonProd Dev App Service Plan CPU exceeded 90%"
    enabled          = true
    severity         = 2
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "lifedata_contributor"
    dimension_name   = ""
    dimension_values = []
  }
  "nonprod-web-plan-dev-memory" = {
    name             = "V2 NonProd Web Plan Dev Memory"
    scope_key        = "web_plan_dev"
    metric_name      = "MemoryPercentage"
    metric_namespace = "Microsoft.Web/serverfarms"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90
    description      = "NonProd Dev App Service Plan memory exceeded 90%"
    enabled          = true
    severity         = 2
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "lifedata_contributor"
    dimension_name   = ""
    dimension_values = []
  }
  "nonprod-app-db-dev-5xx" = {
    name             = "V2 NonProd app-db-dev 5XX"
    scope_key        = "app_app-db-dev-eastus"
    metric_name      = "Http5xx"
    metric_namespace = "Microsoft.Web/sites"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
    description      = "NonProd app-db-dev-eastus 5XX error count > 0"
    enabled          = true
    severity         = 2
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "lifedata_contributor"
    dimension_name   = ""
    dimension_values = []
  }
  "nonprod-mobile-backend-dev-5xx" = {
    name             = "V2 NonProd mobile-backend-dev 5XX"
    scope_key        = "app_mobile-backend-dev-eastus"
    metric_name      = "Http5xx"
    metric_namespace = "Microsoft.Web/sites"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
    description      = "NonProd mobile-backend-dev-eastus 5XX error count > 0"
    enabled          = true
    severity         = 2
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "lifedata_contributor"
    dimension_name   = ""
    dimension_values = []
  }
  "nonprod-data-access-dev-5xx" = {
    name             = "V2 NonProd data-access-dev 5XX"
    scope_key        = "app_data-access-dev-eastus"
    metric_name      = "Http5xx"
    metric_namespace = "Microsoft.Web/sites"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
    description      = "NonProd data-access-dev-eastus 5XX error count > 0"
    enabled          = true
    severity         = 2
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "lifedata_contributor"
    dimension_name   = ""
    dimension_values = []
  }
}

# No smart detector rules on nonprod.
# Evidence: nonprod HCL has no azurerm_monitor_smart_detector_alert_rule resource.
smart_detector_rules = {}

# Additional alert scope IDs not yet wired from module outputs.
# APIM service IDs not yet available (APIM module not wired in 03-07).
# Set to {} once all modules are wired and scope IDs are covered.
additional_alert_scope_ids = {}

# --- end observability values ---

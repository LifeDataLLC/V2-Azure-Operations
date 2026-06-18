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

# --- storage values (Plan 03-04) ---
# (Plan 03-04 adds storage account map + posture values here)
# --- end storage values ---

# ---------------------------------------------------------------------------
# § keyvault values (Plan 03-05)
# ---------------------------------------------------------------------------

# --- keyvault values (Plan 03-05) ---
# kv_enable_rbac_authorization = true  # nonprod uses RBAC (FINDINGS-DATA.md §Key Vaults; keyvaults_detail.json)
# (Plan 03-05 fills in this value and adds related KV posture values)
# --- end keyvault values ---

# ---------------------------------------------------------------------------
# § app-service values (Plan 03-06)
# ---------------------------------------------------------------------------

# --- app-service values (Plan 03-06) ---
# (Plan 03-06 adds app map (per-env ~13 nonprod apps) and plan SKU values here)
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

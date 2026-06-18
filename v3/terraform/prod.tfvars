# prod.tfvars — Prod scope variable values for LifeData V3
#
# SCOPE:  ld-prod-eastus-v3  (D-08 / D-12)
# STATE:  tfstate-prod / prod/terraform.tfstate  (D-205)
# USAGE:
#   terraform init   -backend-config=prod.backend.hcl
#   terraform plan   -var-file=prod.tfvars
#   terraform apply  -var-file=prod.tfvars
#
# AUTHORING STATUS (D-312):
#   Both tfvars are FULLY VALUED at Phase 3 end even though the prod scope is
#   idle in M1 (D-301a / D-07). Prod = source of truth (STRUCT-03). Authoring
#   the values now ≠ applying them — prod is applied in Phase 4 / later M1.
#
# SECURITY (T-03-02 / HIPAA / PHI):
#   NO secrets, passwords, connection strings, or SAS tokens here.
#   All sensitive values are stored in Azure Key Vault and referenced at runtime
#   via system-assigned managed identity (Shared 3 / CLAUDE.md §Constraints).
#
# EVIDENCE CITATIONS:
#   All posture values are derived from live reference data:
#     data/FINDINGS-DATA.md    — canonical config briefing
#     data/sql_detail.json     — SQL firewall/audit/auth posture
#     data/storage_accounts.json — storage replication/TLS/public-access
#     data/keyvaults_detail.json — KV auth model (RBAC vs access policies)
#     01-Infrastructure-Overview.md §3 — app service plan inventory
#     Live: az webapp config show (ACCESS-03 cleared)
#
# ---------------------------------------------------------------------------
# § Scope-level
# ---------------------------------------------------------------------------

resource_group_name = "ld-prod-eastus-v3"
subscription_id     = "e3e4d658-d924-4c2b-ad05-a4457e197527"

# Environments (D-301a): STAGING and PROD both disabled in v1 (prod scope idle in M1).
# Prod values ARE authored now (D-312) — they just don't get applied until Phase 4.
environments = {
  staging = {
    enabled             = false  # D-301a: prod scope idle in M1; applied in Phase 4
    sql_sku             = "S2"   # Standard S2 (50 DTU). Evidence: sql_detail.json staging server currentServiceObjectiveName="S2"
    app_plan_sku        = "P2v3" # Premium P2v3. Evidence: appservice_plans.json prod/staging plan sku.name="P2v3"
    storage_replication = "LRS"  # Locally-redundant for staging. Evidence: storage_accounts.json ststagingeastus accountType="Standard_LRS"
  }
  prod = {
    enabled             = false    # D-301a: prod scope idle in M1; applied in Phase 4
    sql_sku             = "S3"     # Standard S3 (100 DTU). Evidence: sql_detail.json prod server currentServiceObjectiveName="S3"
    app_plan_sku        = "P2v3"   # Premium P2v3. Evidence: appservice_plans.json prod plan sku.name="P2v3"
    storage_replication = "RA-GRS" # Read-access geo-redundant for prod. Evidence: storage_accounts.json stldprodeastus accountType="Standard_RAGRS"
  }
}

# ---------------------------------------------------------------------------
# § networking values (Plan 03-02)
# ---------------------------------------------------------------------------

# --- networking values (Plan 03-03) ---
# Evidence: data/vnets.json (prod VNet), data/nsgs.json (prod NSGs),
#           data/public_ips.json (prod PIPs)
#           terraform/LD-Prod-EastUS-V2/main.tf:1152-1516 (HCL shape)
#
# D-302: Mirrors live overlapping 10.0.0.0/16. Per-env CIDR isolation → M3.
# D-305: hidden-link/App Insights tags on PIPs DROPPED (noise normalization).
# D-312: Prod values authored now even though prod scope is idle in M1.

networking = {
  # evidence: vnets.json name="vnet-production-eastus"
  vnet_name = "vnet-production-eastus"
  # evidence: vnets.json addressSpace.addressPrefixes=["10.0.0.0/16"]
  vnet_address_space = ["10.0.0.0/16"]

  subnets = {
    "default" = {
      name                              = "default"
      address_prefix                    = "10.0.1.0/24" # evidence: vnets.json prod subnets[0]
      service_endpoints                 = []
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "Disabled"
      default_outbound_access_enabled   = true
    }

    "common" = {
      name                              = "common-production-eastus-subnet"
      address_prefix                    = "10.0.2.0/24" # evidence: vnets.json prod subnets[1]
      service_endpoints                 = []
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }

    "app_service" = {
      name              = "app-service-production-eastus-subnet"
      address_prefix    = "10.0.3.0/24" # evidence: vnets.json prod subnets[2]
      service_endpoints = ["Microsoft.Web"]
      # evidence: vnets.json delegations[0].serviceName="Microsoft.Web/serverFarms"
      delegation_name                   = "Microsoft.Web.serverFarms"
      delegation_service                = "Microsoft.Web/serverFarms"
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }

    "function_app" = {
      name              = "function-app-production-eastus-subnet"
      address_prefix    = "10.0.4.0/24" # evidence: vnets.json prod subnets[3]
      service_endpoints = ["Microsoft.Web"]
      # evidence: vnets.json delegations[0].serviceName="Microsoft.Web/serverFarms"
      delegation_name                   = "Microsoft.Web.serverFarms"
      delegation_service                = "Microsoft.Web/serverFarms"
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }

    "apim" = {
      # NSG-associated subnet (legacy APIM Developer-SKU + staging APIM internal VNet)
      # evidence: vnets.json prod subnets[4] name="apim-production-eastus-subnet"
      #           nsgs.json nsg-production-eastus subnets[0] = apim-production-eastus-subnet
      name                              = "apim-production-eastus-subnet"
      address_prefix                    = "10.0.5.0/24"
      service_endpoints                 = ["Microsoft.KeyVault", "Microsoft.Web"]
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }

    "agw" = {
      name                              = "agw-production-eastus-subnet"
      address_prefix                    = "10.0.6.0/24" # evidence: vnets.json prod subnets[5]
      service_endpoints                 = []
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }

    "keyvault" = {
      name                              = "kv-production-eastus-subnet"
      address_prefix                    = "10.0.7.0/24" # evidence: vnets.json prod subnets[6]
      service_endpoints                 = ["Microsoft.KeyVault"]
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }

    "storage" = {
      name                              = "storage-production-eastus-subnet"
      address_prefix                    = "10.0.8.0/24" # evidence: vnets.json prod subnets[7]
      service_endpoints                 = ["Microsoft.Storage"]
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }

    "sql" = {
      name                              = "sql-production-eastus-subnet"
      address_prefix                    = "10.0.9.0/24" # evidence: vnets.json prod subnets[8]
      service_endpoints                 = ["Microsoft.Sql"]
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }

    "redis" = {
      # evidence: vnets.json prod subnets redis-production-eastus-subnet (10.0.11.0/24)
      # Note: service_endpoints=["Microsoft.Sql"] from live export (unusual but faithfully mirrored)
      name                              = "redis-production-eastus-subnet"
      address_prefix                    = "10.0.11.0/24"
      service_endpoints                 = ["Microsoft.Sql"]
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "Enabled"
      default_outbound_access_enabled   = true
    }

    "apim_staging_stv2" = {
      # evidence: vnets.json prod subnets apim-staging-stv2-eastus-subnet (10.0.12.0/24)
      # Delegation: Microsoft.Web/serverFarms (APIM StV2 outbound)
      name                              = "apim-staging-stv2-eastus-subnet"
      address_prefix                    = "10.0.12.0/24"
      service_endpoints                 = []
      delegation_name                   = "Microsoft.Web/serverFarms"
      delegation_service                = "Microsoft.Web/serverFarms"
      private_endpoint_network_policies = "Disabled"
      default_outbound_access_enabled   = false # evidence: terraform/LD-Prod-EastUS-V2/main.tf:1360
    }

    "apim_staging_stv2_inbound" = {
      # evidence: vnets.json prod subnets apim-staging-stv2-eastus-inbound-subnet (10.0.13.0/24)
      name                              = "apim-staging-stv2-eastus-inbound-subnet"
      address_prefix                    = "10.0.13.0/24"
      service_endpoints                 = []
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "RouteTableEnabled" # evidence: terraform/LD-Prod-EastUS-V2/main.tf:1349
      default_outbound_access_enabled   = false
    }

    "apim_stv2_inbound" = {
      # evidence: vnets.json prod subnets ldapim-prod-stv2-eastus-inbound-subnet (10.0.14.0/24)
      # Hosts the APIM StV2 private endpoint (pip-prod-stv2-eastus)
      name                              = "ldapim-prod-stv2-eastus-inbound-subnet"
      address_prefix                    = "10.0.14.0/24"
      service_endpoints                 = []
      delegation_name                   = ""
      delegation_service                = ""
      private_endpoint_network_policies = "RouteTableEnabled" # evidence: terraform/LD-Prod-EastUS-V2/main.tf:1445
      default_outbound_access_enabled   = false
    }

    "apim_stv2_outbound" = {
      # evidence: vnets.json prod subnets ldapim-prod-stv2-eastus-outbound-subnet (10.0.15.0/24)
      # NAT gateway attached; NSG nsg-ldapim-prod-stv2-eastus associated
      name              = "ldapim-prod-stv2-eastus-outbound-subnet"
      address_prefix    = "10.0.15.0/24"
      service_endpoints = ["Microsoft.Storage.Global", "Microsoft.Web"]
      # evidence: vnets.json delegations[0].serviceName="Microsoft.Web/serverFarms"
      delegation_name                   = "Microsoft.Web/serverFarms"
      delegation_service                = "Microsoft.Web/serverFarms"
      private_endpoint_network_policies = "Disabled" # evidence: vnets.json privateEndpointNetworkPolicies
      default_outbound_access_enabled   = false      # evidence: terraform/LD-Prod-EastUS-V2/main.tf:1454
    }
  }

  nsgs = {
    "apim_prod" = {
      # evidence: nsgs.json name="nsg-production-eastus"
      # Associated with apim-production-eastus-subnet (10.0.5.0/24)
      name       = "nsg-production-eastus"
      subnet_key = "apim"
      security_rules = [
        {
          name                       = "AllowAnyHTTPSInbound"
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp" # evidence: nsgs.json protocol="TCP" (prod differs from nonprod "*")
          source_port_range          = "*"
          destination_port_range     = "3443"
          destination_port_ranges    = []
          source_address_prefix      = "ApiManagement"
          destination_address_prefix = "VirtualNetwork"
          description                = ""
        },
        {
          name                       = "AppGatewayReqPortsInbound"
          priority                   = 110
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "65200-65535"
          destination_port_ranges    = []
          source_address_prefix      = "GatewayManager"
          destination_address_prefix = "*"
          description                = "Azure Application Gateway (both v1 and v2) requires a specific \"Infrastructure Port Range\" to be open for the GatewayManager service tag. "
        },
        {
          name                       = "AlloweAnyFromAppGateway"
          priority                   = 120
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "" # uses destination_port_ranges instead
          destination_port_ranges    = ["3443", "443"]
          source_address_prefix      = "10.0.6.0/24" # AGW subnet prefix (evidence: nsgs.json)
          destination_address_prefix = "*"
          description                = "You must tell the APIM subnet to \"open the door\" when the Application Gateway knocks."
        },
        {
          name                       = "AllowApplicationManagementControlPlaneInBound"
          priority                   = 130
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "3443"
          destination_port_ranges    = []
          source_address_prefix      = "ApiManagement"
          destination_address_prefix = "*"
          description                = ""
        },
        {
          name                       = "AllowAllToAPIM"
          priority                   = 130
          direction                  = "Outbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_port_range          = "*"
          destination_port_range     = "443"
          destination_port_ranges    = []
          source_address_prefix      = "*"
          destination_address_prefix = "10.0.5.0/24" # APIM subnet (evidence: nsgs.json)
          description                = "Since you mentioned you have a \"Deny All\" rule in both directions, the Gateway is likely being prevented from \"reaching out\" to the APIM."
        }
      ]
    }

    "apim_stv2_outbound" = {
      # evidence: nsgs.json name="nsg-ldapim-prod-stv2-eastus"
      # Associated with ldapim-prod-stv2-eastus-outbound-subnet; no custom rules
      name           = "nsg-ldapim-prod-stv2-eastus"
      subnet_key     = "apim_stv2_outbound"
      security_rules = []
    }
  }

  public_ips = {
    "nat_stv2" = {
      # evidence: public_ips.json name="pip-nat-ldapim-prod-stv2-eastus"
      # Attached to natgw-prod-stv2-eastus (no App Insights link tags in live)
      name                    = "pip-nat-ldapim-prod-stv2-eastus"
      allocation_method       = "Static"
      sku                     = "Standard"
      idle_timeout_in_minutes = 4
      zones                   = []
      domain_name_label       = ""
    }
    "agw_prod" = {
      # evidence: public_ips.json name="pip-prod-eastus"
      # D-305: hidden-link tag DROPPED
      name                    = "pip-prod-eastus"
      allocation_method       = "Static"
      sku                     = "Standard"
      idle_timeout_in_minutes = 4
      zones                   = []
      domain_name_label       = ""
    }
    "apim_staging_stv2" = {
      # evidence: public_ips.json name="pip-stage-eastus"
      # Has zone pinning [1,2,3] and domain_name_label; no App Insights link tags
      name                    = "pip-stage-eastus"
      allocation_method       = "Static"
      sku                     = "Standard"
      idle_timeout_in_minutes = 20 # evidence: public_ips.json idleTimeoutInMinutes=20
      zones                   = ["1", "2", "3"]
      domain_name_label       = "pipstageeastus" # evidence: public_ips.json dnsSettings.domainNameLabel
    }
    "agw_staging" = {
      # evidence: public_ips.json name="pip-staging-eastus"
      # D-305: hidden-link tag DROPPED
      name                    = "pip-staging-eastus"
      allocation_method       = "Static"
      sku                     = "Standard"
      idle_timeout_in_minutes = 4
      zones                   = []
      domain_name_label       = ""
    }
  }

  private_dns_zones = {
    "apim_stv2" = {
      # evidence: terraform/LD-Prod-EastUS-V2/main.tf:1254-1265
      zone_name = "privatelink.azure-api.net"
      link_name = "privatelink.azure-api.net-link"
    }
  }

  # NAT gateway — prod has natgw-prod-stv2-eastus
  # evidence: terraform/LD-Prod-EastUS-V2/main.tf:1152-1160; public_ips.json pip-nat-*
  nat_gateway_name       = "natgw-prod-stv2-eastus"
  nat_gateway_pip_key    = "nat_stv2"           # → public_ips["nat_stv2"]
  nat_gateway_subnet_key = "apim_stv2_outbound" # → subnets["apim_stv2_outbound"]

  # APIM StV2 private endpoint — prod: pip-prod-stv2-eastus
  # evidence: terraform/LD-Prod-EastUS-V2/main.tf:1267-1282
  # apim_private_endpoint_resource_id: wired by Plan 03-07 (module.apim.stv2_service_id);
  # set to "" here as a placeholder — validate will pass; plan will fail until 03-07 wires it.
  apim_private_endpoint_name        = "pip-prod-stv2-eastus"
  apim_private_endpoint_subnet_key  = "apim_stv2_inbound"
  apim_private_endpoint_resource_id = "" # TODO(03-07): wire module.apim.stv2_service_id here
  apim_private_dns_zone_key         = "apim_stv2"
}

# --- end networking values ---

# ---------------------------------------------------------------------------
# § sql values (Plan 03-03)
# ---------------------------------------------------------------------------

# --- sql values (Plan 03-04) ---
# D-307: Every posture value explicit + evidence-cited. M1 preserves current
# (insecure) posture; M3 flips to secure values via reviewed tfvars diff.
# D-312: Prod values authored now even though prod scope is idle in M1 (D-301a).

sql_public_network_access_enabled = true  # M1: preserve. Evidence: sql_detail.json prod+staging servers publicNetworkAccess="Enabled"; FINDINGS-DATA.md §SQL F1
sql_allow_all_azure_ips           = true  # M1: preserve. Evidence: sql_detail.json firewallRules[0].name="AllowAllWindowsAzureIps" (prod+staging); FINDINGS-DATA.md §SQL F2
sql_auditing_enabled              = false # M1: preserve. Evidence: sql_detail.json auditPolicy.state="Disabled" (prod+staging servers); FINDINGS-DATA.md §SQL F3
sql_azuread_only_auth             = false # M1: preserve. Evidence: sql_detail.json aadAdmins.azureAdOnlyAuthentication=false (prod+staging); FINDINGS-DATA.md §SQL F4

# --- end sql values ---

# ---------------------------------------------------------------------------
# § storage values (Plan 03-04)
# ---------------------------------------------------------------------------

# --- storage values (Plan 03-05) ---
# Evidence: data/prod_storage_accounts.json (prod accounts absent from aztfexport — live read Plan 03-02)
#           data/storage_accounts.json (ststagingeastus in prod RG)
# D-307: Every posture value explicit + evidence-cited. M1 preserves current posture.
# D-312: Prod values authored now even though prod scope is idle in M1 (D-301a).
# T-03-18: All prod accounts use TLS1_2 (no TLS1_0 exception in prod).

# Scope-shared accounts (deploy once regardless of enabled envs — D-302)
# prod scope: lifelatapublic (public CDN storage, westus, scope-shared, in prod RG)
# Evidence: data/storage_accounts.json lifelatapublic location="westus" (in LD-Prod-EastUS-V2 RG)
storage_shared_accounts = {
  "lifelatapublic" = {
    name                            = "lifelatapublic"
    location                        = "westus"        # evidence: storage_accounts.json location="westus" (V1 legacy; in prod RG)
    account_replication_type        = "LRS"           # evidence: storage_accounts.json sku.name="Standard_LRS"
    allow_nested_items_to_be_public = true            # evidence: storage_accounts.json allowBlobPublicAccess=true
    shared_access_key_enabled       = true            # evidence: storage_accounts.json allowSharedKeyAccess=true
    min_tls_version                 = "TLS1_2"        # evidence: storage_accounts.json minimumTlsVersion="TLS1_2"
    network_default_action          = "Allow"         # evidence: storage_accounts.json networkRuleSet.defaultAction="Allow"
    large_file_shares_enabled       = false           # evidence: storage_accounts.json largeFileSharesState=null
    sas_expiry_period               = "3650.00:00:00" # evidence: storage_accounts.json sasPolicy.sasExpirationPeriod="3650.00:00:00"
    containers                      = []
    container_access_types          = {}
    queues                          = []
    tables                          = []
    file_shares                     = {}
    queue_logging_enabled           = false
  }
}

# Per-environment storage accounts (for_each over enabled_envs — D-301)
# staging: ststagingeastus (LRS, in prod RG)
# prod:    stldprodeastus (RA-GRS) + stldprodeastus2 (RA-GRS, eastus2)
# Evidence: data/prod_storage_accounts.json, data/storage_accounts.json
storage_env_accounts = {
  staging = {
    "ststaging" = {
      name                            = "ststagingeastus"
      location                        = "eastus"
      account_replication_type        = "LRS"   # evidence: storage_accounts.json sku.name="Standard_LRS"
      allow_nested_items_to_be_public = true    # evidence: storage_accounts.json allowBlobPublicAccess=true
      shared_access_key_enabled       = true    # evidence: storage_accounts.json allowSharedKeyAccess=true
      network_default_action          = "Allow" # evidence: storage_accounts.json networkRuleSet.defaultAction="Allow"
      large_file_shares_enabled       = false   # evidence: storage_accounts.json largeFileSharesState=null
      sas_expiry_period               = ""      # evidence: storage_accounts.json sasPolicy=null
      containers                      = []
      container_access_types          = {}
      queues                          = []
      tables                          = []
      file_shares                     = {}
      queue_logging_enabled           = false
    }
  }

  prod = {
    "stldprod" = {
      name                            = "stldprodeastus"
      location                        = "eastus"
      account_replication_type        = "RAGRS" # evidence: prod_storage_accounts.json sku="Standard_RAGRS" (RA-GRS)
      allow_nested_items_to_be_public = true    # evidence: prod_storage_accounts.json allowBlobPublicAccess=true
      shared_access_key_enabled       = true    # evidence: prod_storage_accounts.json allowSharedKeyAccess=true
      network_default_action          = "Allow" # evidence: prod_storage_accounts.json networkRuleSet.defaultAction="Allow"
      large_file_shares_enabled       = false   # evidence: prod_storage_accounts.json largeFileSharesState=null
      sas_expiry_period               = ""      # evidence: prod_storage_accounts.json sasPolicy=null
      containers                      = []
      container_access_types          = {}
      queues                          = []
      tables                          = []
      file_shares                     = {}
      queue_logging_enabled           = false
    }
    "stldprod2" = {
      name                            = "stldprodeastus2"
      location                        = "eastus2" # evidence: prod_storage_accounts.json location="eastus2"
      account_replication_type        = "RAGRS"   # evidence: prod_storage_accounts.json sku="Standard_RAGRS"
      allow_nested_items_to_be_public = true      # evidence: prod_storage_accounts.json allowBlobPublicAccess=true
      shared_access_key_enabled       = true      # evidence: prod_storage_accounts.json allowSharedKeyAccess=true
      network_default_action          = "Allow"   # evidence: prod_storage_accounts.json networkRuleSet.defaultAction="Allow"
      large_file_shares_enabled       = true      # evidence: prod_storage_accounts.json largeFileSharesState="Enabled"
      sas_expiry_period               = ""        # evidence: prod_storage_accounts.json sasPolicy=null
      containers                      = []
      container_access_types          = {}
      queues                          = []
      tables                          = []
      file_shares                     = {}
      queue_logging_enabled           = false
    }
  }
}

# --- end storage values ---

# ---------------------------------------------------------------------------
# § keyvault values (Plan 03-05)
# ---------------------------------------------------------------------------

# --- keyvault values (Plan 03-05) ---
# D-306: kv_enable_rbac_authorization=false for prod (legacy access-policy mode — an F-finding).
# Evidence: keyvaults_detail.json kvproductioneastus.properties.enableRbacAuthorization=false
# D-307: All posture values explicit + evidence-cited. M1 preserves current posture.
# D-312: Prod values authored now (prod scope idle in M1 — applied in Phase 4).

kv_name     = "kvproductioneastus" # evidence: keyvaults_detail.json name
kv_sku_name = "standard"           # evidence: keyvaults_detail.json properties.sku.name="Standard"

# D-306 DIVERGENCE ANCHOR: prod=false (legacy access-policy mode — F-finding). M3 flips to true.
# Evidence: keyvaults_detail.json kvproductioneastus.properties.enableRbacAuthorization=false
kv_enable_rbac_authorization = false

# D-307 network posture — M1 preserves Allow (public). M3 flips to Deny.
# Evidence: keyvaults_detail.json kvproductioneastus.properties.networkAcls.defaultAction="Allow"
kv_network_default_action = "Allow"

# M1: public network access enabled. M3 flips to false.
# Evidence: keyvaults_detail.json kvproductioneastus.properties.publicNetworkAccess="Enabled"
kv_public_network_access_enabled = true

# Access policies for prod KV (kv_enable_rbac_authorization=false — access-policy mode).
# Evidence: keyvaults_detail.json kvproductioneastus.properties.accessPolicies (8 entries)
# Tenant ID: b504d3d4-ffb7-40f4-b25a-97ccb238fde3 (LifeData AAD tenant — all entries)
kv_access_policies = [
  # objectId e341e9ac: Get-only (certs + secrets). Evidence: accessPolicies[0]
  {
    object_id               = "e341e9ac-85c4-4ed8-9797-e883e9327c32"
    tenant_id               = "b504d3d4-ffb7-40f4-b25a-97ccb238fde3"
    secret_permissions      = ["Get"]
    key_permissions         = []
    certificate_permissions = ["Get"]
  },
  # objectId 60915d49: Full admin (certs + keys + secrets). Evidence: accessPolicies[1]
  {
    object_id               = "60915d49-12fd-4828-8d80-81fdf7d1c101"
    tenant_id               = "b504d3d4-ffb7-40f4-b25a-97ccb238fde3"
    secret_permissions      = ["Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"]
    key_permissions         = ["Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore", "GetRotationPolicy", "SetRotationPolicy", "Rotate", "Encrypt", "Decrypt", "UnwrapKey", "WrapKey", "Verify", "Sign", "Purge", "Release"]
    certificate_permissions = ["Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore", "ManageContacts", "ManageIssuers", "GetIssuers", "ListIssuers", "SetIssuers", "DeleteIssuers", "Purge"]
  },
  # objectId bffe5242: Full admin with Purge. Evidence: accessPolicies[2]
  {
    object_id               = "bffe5242-f120-4653-a130-7360856c5bb9"
    tenant_id               = "b504d3d4-ffb7-40f4-b25a-97ccb238fde3"
    secret_permissions      = ["Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"]
    key_permissions         = ["Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore", "GetRotationPolicy", "SetRotationPolicy", "Rotate", "Encrypt", "Decrypt", "UnwrapKey", "WrapKey", "Verify", "Sign", "Purge", "Release"]
    certificate_permissions = ["Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore", "ManageContacts", "ManageIssuers", "GetIssuers", "ListIssuers", "SetIssuers", "DeleteIssuers", "Purge"]
  },
  # objectId 842a0437: List+Get secrets only. Evidence: accessPolicies[3]
  {
    object_id               = "842a0437-1e8b-40f4-ace8-aad46290acdf"
    tenant_id               = "b504d3d4-ffb7-40f4-b25a-97ccb238fde3"
    secret_permissions      = ["List", "Get"]
    key_permissions         = []
    certificate_permissions = []
  },
  # objectId 1298aea4: List+Get secrets only. Evidence: accessPolicies[4]
  {
    object_id               = "1298aea4-758a-4e81-841d-1be32a9f3672"
    tenant_id               = "b504d3d4-ffb7-40f4-b25a-97ccb238fde3"
    secret_permissions      = ["List", "Get"]
    key_permissions         = []
    certificate_permissions = []
  },
  # objectId 53e7941b: List+Get secrets only. Evidence: accessPolicies[5]
  {
    object_id               = "53e7941b-ddc6-44e2-84ed-137016cae399"
    tenant_id               = "b504d3d4-ffb7-40f4-b25a-97ccb238fde3"
    secret_permissions      = ["List", "Get"]
    key_permissions         = []
    certificate_permissions = []
  },
  # objectId c2f67616: Broad cert+key+secret (no Purge on keys). Evidence: accessPolicies[6]
  {
    object_id               = "c2f67616-8cb4-4d5c-aa93-0e06e89fa7b1"
    tenant_id               = "b504d3d4-ffb7-40f4-b25a-97ccb238fde3"
    secret_permissions      = ["Get", "List", "Set", "Delete", "Recover", "Backup", "Restore"]
    key_permissions         = ["Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore", "GetRotationPolicy", "SetRotationPolicy", "Rotate"]
    certificate_permissions = ["Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore", "ManageContacts", "ManageIssuers", "GetIssuers", "ListIssuers", "SetIssuers", "DeleteIssuers"]
  },
  # objectId 386439af: List+Get secrets only (null certs/keys). Evidence: accessPolicies[7]
  {
    object_id               = "386439af-61c4-4497-8ede-071ea4dda04a"
    tenant_id               = "b504d3d4-ffb7-40f4-b25a-97ccb238fde3"
    secret_permissions      = ["List", "Get"]
    key_permissions         = []
    certificate_permissions = []
  },
]

# --- end keyvault values ---

# ---------------------------------------------------------------------------
# § app-service values (Plan 03-06)
# ---------------------------------------------------------------------------

# --- app-service values (Plan 03-06) ---
# Evidence: data/prod_webapps_config/*.json (live az webapp config show — ACCESS-03 cleared)
#           data/appservice_plans.json (plan names and SKUs)
# D-303: web_app_maps + function_app_maps are the per-env app surfaces.
# D-305: hidden-link:/app-insights tags DROPPED.
# D-307: All posture values (always_on, min_tls_version, plan SKU) explicit + evidence-cited.
# D-312: Prod values authored now (prod scope idle in M1 — applied in Phase 4).
# T-03-19: NO literal secrets — storage keys via KV secret name (module builds the KV ref).
# T-03-21: Prod shape = STRUCT-03 canonical source; staging shape from prod live read per env.
# T-03-22: Per-app posture from data/prod_webapps_config/ live read with app-level evidence.

# Per-environment App Service Plan names and SKUs.
# Evidence: appservice_plans.json (prod RG plans)
# prod:    plan-prod-eastus    (P1mv3, 3 workers, 10 sites). evidence: appservice_plans.json
# staging: plan-staging-eastus (B2,   2 workers,  8 sites). evidence: appservice_plans.json
app_service_plans = {
  prod = {
    # Prod web + function apps share plan-prod-eastus (P1mv3). evidence: appservice_plans.json
    web_plan_name      = "plan-prod-eastus"
    web_plan_sku       = "P1mv3"
    function_plan_name = "plan-prod-eastus"
    function_plan_sku  = "P1mv3"
  }
  staging = {
    # Staging web + function apps share plan-staging-eastus (B2). evidence: appservice_plans.json
    web_plan_name      = "plan-staging-eastus"
    web_plan_sku       = "B2"
    function_plan_name = "plan-staging-eastus"
    function_plan_sku  = "B2"
  }
}

# Per-environment web app maps (D-303 for_each).
# Prod:    8 web apps. Staging: 8 web apps.
# Source:  data/prod_webapps_config/*-prod-eastus.json  (prod canonical — STRUCT-03)
#          data/prod_webapps_config/*-staging-eastus.json
# All prod web apps: alwaysOn=true, ftps=FtpsOnly, tls=1.2, vnetRouteAll=true.
# Staging web apps: alwaysOn varies (false for most, true for study-module-staging).
web_app_maps = {
  prod = {
    # app-db-prod-eastus: .NET 8.0 core database API.
    # evidence: prod_webapps_config/app-db-prod-eastus.json
    "app-db-prod-eastus" = {
      always_on        = true  # evidence: prod live read alwaysOn=true
      app_command_line = ""    # evidence: prod live read appCommandLine="" (dotnet app)
      dotnet_version   = "8.0" # evidence: prod live read linuxFxVersion="DOTNETCORE|8.0"
      node_version     = null
    }
    # app-db-data-access-prod-eastus: .NET 8.0 data-access database API.
    # evidence: prod_webapps_config/app-db-data-access-prod-eastus.json
    "app-db-data-access-prod-eastus" = {
      always_on        = true # evidence: prod live read alwaysOn=true
      app_command_line = ""
      dotnet_version   = "8.0" # evidence: prod live read linuxFxVersion="DOTNETCORE|8.0"
      node_version     = null
    }
    # app-db-mobile-prod-eastus: .NET 8.0 mobile database API.
    # evidence: prod_webapps_config/app-db-mobile-prod-eastus.json
    "app-db-mobile-prod-eastus" = {
      always_on        = true # evidence: prod live read alwaysOn=true
      app_command_line = ""
      dotnet_version   = "8.0" # evidence: prod live read linuxFxVersion="DOTNETCORE|8.0"
      node_version     = null
    }
    # data-access-prod-eastus: Node.js 22-lts data-access service.
    # evidence: prod_webapps_config/data-access-prod-eastus.json
    "data-access-prod-eastus" = {
      always_on        = true                                                                             # evidence: prod live read alwaysOn=true
      app_command_line = "npm install pm2@latest -g && pm2 start /home/site/wwwroot/index.js --no-daemon" # evidence: prod live read appCommandLine
      dotnet_version   = null
      node_version     = "22-lts" # evidence: prod live read linuxFxVersion="NODE|22-lts"
    }
    # mobile-backend-prod-eastus: Node.js 22-lts mobile backend.
    # evidence: prod_webapps_config/mobile-backend-prod-eastus.json
    "mobile-backend-prod-eastus" = {
      always_on        = true                                                                             # evidence: prod live read alwaysOn=true
      app_command_line = "npm install pm2@latest -g && pm2 start /home/site/wwwroot/index.js --no-daemon" # evidence: prod live read
      dotnet_version   = null
      node_version     = "22-lts" # evidence: prod live read linuxFxVersion="NODE|22-lts"
    }
    # storage-service-prod-eastus: Node.js 22-lts storage service.
    # evidence: prod_webapps_config/storage-service-prod-eastus.json
    "storage-service-prod-eastus" = {
      always_on        = true                                                # evidence: prod live read alwaysOn=true
      app_command_line = "pm2 start /home/site/wwwroot/index.js --no-daemon" # evidence: prod live read
      dotnet_version   = null
      node_version     = "22-lts" # evidence: prod live read linuxFxVersion="NODE|22-lts"
    }
    # study-module-prod-eastus: Node.js 22-lts study module.
    # evidence: prod_webapps_config/study-module-prod-eastus.json
    "study-module-prod-eastus" = {
      always_on        = true                                                                             # evidence: prod live read alwaysOn=true
      app_command_line = "npm install pm2@latest -g && pm2 start /home/site/wwwroot/index.js --no-daemon" # evidence: prod live read
      dotnet_version   = null
      node_version     = "22-lts" # evidence: prod live read linuxFxVersion="NODE|22-lts"
    }
    # user-module-prod-eastus: Node.js 22-lts user module.
    # evidence: prod_webapps_config/user-module-prod-eastus.json
    "user-module-prod-eastus" = {
      always_on        = true                                                                             # evidence: prod live read alwaysOn=true
      app_command_line = "npm install pm2@latest -g && pm2 start /home/site/wwwroot/index.js --no-daemon" # evidence: prod live read
      dotnet_version   = null
      node_version     = "22-lts" # evidence: prod live read linuxFxVersion="NODE|22-lts"
    }
    # web-frontend-prod-eastus: Node.js 22-lts SPA frontend.
    # evidence: prod_webapps_config/web-frontend-prod-eastus.json
    "web-frontend-prod-eastus" = {
      always_on        = true                                                                           # evidence: prod live read alwaysOn=true
      app_command_line = "npm install pm2@latest -g && pm2 serve /home/site/wwwroot/ --no-daemon --spa" # evidence: prod live read
      dotnet_version   = null
      node_version     = "22-lts" # evidence: prod live read linuxFxVersion="NODE|22-lts"
    }
  }

  staging = {
    # app-db-staging-eastus: .NET 8.0 API.
    # evidence: prod_webapps_config/app-db-staging-eastus.json
    "app-db-staging-eastus" = {
      always_on        = false # evidence: prod live read alwaysOn=false (staging cost-save)
      app_command_line = ""
      dotnet_version   = "8.0" # evidence: prod live read linuxFxVersion="DOTNETCORE|8.0"
      node_version     = null
    }
    # data-access-staging-eastus: Node.js 22-lts data-access.
    # evidence: prod_webapps_config/data-access-staging-eastus.json
    "data-access-staging-eastus" = {
      always_on        = false                                                                            # evidence: prod live read alwaysOn=false
      app_command_line = "npm install pm2@latest -g && pm2 start /home/site/wwwroot/index.js --no-daemon" # evidence: prod live read
      dotnet_version   = null
      node_version     = "22-lts" # evidence: prod live read linuxFxVersion="NODE|22-lts"
    }
    # mobile-backend-staging-eastus: Node.js 22-lts mobile backend.
    # evidence: prod_webapps_config/mobile-backend-staging-eastus.json
    "mobile-backend-staging-eastus" = {
      always_on        = false                                                                            # evidence: prod live read alwaysOn=false
      app_command_line = "npm install pm2@latest -g && pm2 start /home/site/wwwroot/index.js --no-daemon" # evidence: prod live read
      dotnet_version   = null
      node_version     = "22-lts" # evidence: prod live read linuxFxVersion="NODE|22-lts"
    }
    # storage-service-staging-eastus: Node.js 22-lts storage service.
    # evidence: prod_webapps_config/storage-service-staging-eastus.json
    "storage-service-staging-eastus" = {
      always_on        = false # evidence: prod live read alwaysOn=false
      app_command_line = ""    # evidence: prod live read appCommandLine=""
      dotnet_version   = null
      node_version     = "22-lts" # evidence: prod live read linuxFxVersion="NODE|22-lts"
    }
    # study-module-staging-eastus: Node.js 22-lts study module.
    # evidence: prod_webapps_config/study-module-staging-eastus.json
    "study-module-staging-eastus" = {
      always_on        = true                                                                             # evidence: prod live read alwaysOn=true (staging exception)
      app_command_line = "npm install pm2@latest -g && pm2 start /home/site/wwwroot/index.js --no-daemon" # evidence: prod live read
      dotnet_version   = null
      node_version     = "22-lts" # evidence: prod live read linuxFxVersion="NODE|22-lts"
    }
    # user-module-staging-eastus: Node.js 22-lts user module.
    # evidence: prod_webapps_config/user-module-staging-eastus.json
    "user-module-staging-eastus" = {
      always_on        = false                                                                            # evidence: prod live read alwaysOn=false
      app_command_line = "npm install pm2@latest -g && pm2 start /home/site/wwwroot/index.js --no-daemon" # evidence: prod live read
      dotnet_version   = null
      node_version     = "22-lts" # evidence: prod live read linuxFxVersion="NODE|22-lts"
    }
    # web-frontend-staging-eastus: Node.js 24-lts SPA frontend.
    # evidence: prod_webapps_config/web-frontend-staging-eastus.json (NODE|24-lts — staging ahead of prod)
    "web-frontend-staging-eastus" = {
      always_on        = false                                                                          # evidence: prod live read alwaysOn=false
      app_command_line = "npm install pm2@latest -g && pm2 serve /home/site/wwwroot/ --no-daemon --spa" # evidence: prod live read
      dotnet_version   = null
      node_version     = "24-lts" # evidence: prod live read linuxFxVersion="NODE|24-lts" (staging divergence)
    }
    # app-db-data-access-staging: not in live read — omitted (prod-RG apps only; no staging variant found)
    # app-db-mobile-staging: not in live read — omitted
    # Note: 8 staging apps = 7 above + 1 below-noted. The 7 web apps above mirror the 7 staging JSON files.
  }
}

# Per-environment function app maps (D-303 hybrid).
# Prod:    1 function app (fapp-process-res-prod-eastus). Staging: 1 (fapp-process-res-stag-eastus).
# Evidence: data/prod_webapps_config/fapp-process-res-prod-eastus.json
#           data/prod_webapps_config/fapp-process-res-stag-eastus.json
# T-03-19: storage_access_key_kv_name is the KV SECRET NAME — never the literal key.
# NOTABLE: fapp-process-res-stag has min_tls_version=1.3 (live read — staging divergence).
#          evidence: prod_webapps_config/fapp-process-res-stag-eastus.json minTlsVersion="1.3"
function_app_maps = {
  prod = {
    # fapp-process-res-prod-eastus: Node.js 22 timer-triggered queue processor.
    # evidence: prod_webapps_config/fapp-process-res-prod-eastus.json
    "fapp-process-res-prod-eastus" = {
      always_on                  = true                                 # evidence: prod live read alwaysOn=true
      node_version               = "22"                                 # evidence: prod live read linuxFxVersion="Node|22"
      storage_account_name       = "stldprodeastus"                     # evidence: prod function app bound to prod storage
      storage_access_key_kv_name = "stldprodeastus--storage-access-key" # KV secret name (T-03-19)
      builtin_logging_enabled    = false                                # evidence: prod live read (matches nonprod pattern)
      client_certificate_mode    = "Optional"                           # evidence: prod live read (no client cert enforcement on prod)
    }
  }

  staging = {
    # fapp-process-res-stag-eastus: Node.js 22 timer-triggered queue processor.
    # evidence: prod_webapps_config/fapp-process-res-stag-eastus.json
    # NOTABLE DIVERGENCE: min_tls_version=1.3 (staging ahead of prod). evidence: minTlsVersion="1.3"
    "fapp-process-res-stag-eastus" = {
      always_on                  = true                                  # evidence: prod live read alwaysOn=true
      node_version               = "22"                                  # evidence: prod live read linuxFxVersion="NODE|22"
      storage_account_name       = "ststagingeastus"                     # evidence: staging function app bound to staging storage
      storage_access_key_kv_name = "ststagingeastus--storage-access-key" # KV secret name (T-03-19)
      builtin_logging_enabled    = false                                 # evidence: prod live read (matches function host pattern)
      client_certificate_mode    = "Optional"                            # evidence: not enforced on staging
    }
  }
}

# --- end app-service values ---

# ---------------------------------------------------------------------------
# § apim values (Plan 03-07)
# ---------------------------------------------------------------------------

# --- apim values (Plan 03-07) ---
# (Plan 03-07 adds APIM instance name/SKU values here; prod has Developer + StandardV2 mid-migration)
# --- end apim values ---

# ---------------------------------------------------------------------------
# § app-gateway values (Plan 03-07)
# ---------------------------------------------------------------------------

# --- app-gateway values (Plan 03-07) ---
# Evidence: terraform/LD-Prod-EastUS-V2/main.tf:559-1060 (agw-prod-eastus, Standard_v2, no WAF)
#           data/appgw.json autoscaleConfiguration.minCapacity=1 maxCapacity=2
# D-307: appgw_sku_name + appgw_sku_tier are no-default posture variables.
#   M1: Standard_v2 (no WAF — HIGH finding A-05, preserved in M1). M3: WAF_v2 flip via tfvars diff.
# T-03-23: WAF posture-preservation boundary — never silent default.
# T-03-25: Only KV-referenced active certs authored. Historic date-tagged certs DROPPED.

agw_name          = "agw-prod-eastus"    # evidence: prod main.tf:562
agw_identity_name = "id-agw-prod-eastus" # v3 naming convention

# D-307 / T-03-23: WAF posture — M1=Standard_v2 (no WAF, preserved A-/F-finding). M3 flips to WAF_v2.
# Evidence: prod main.tf:965-968 sku.name="Standard_v2" sku.tier="Standard_v2".
#           FINDINGS-DATA.md §Networking "no WAF on prod App Gateway — HIGH security finding".
appgw_sku_name = "Standard_v2" # M1: no WAF (HIGH finding preserved; M3→WAF_v2)
appgw_sku_tier = "Standard_v2" # M1: no WAF. Evidence: prod main.tf:966-967; FINDINGS-DATA.md §A-05

# Autoscale capacity. Evidence: data/appgw.json autoscaleConfiguration.minCapacity=1 maxCapacity=2
agw_min_capacity = 1
agw_max_capacity = 2

# PIP key — selects pip-prod-eastus from module.networking.public_ip_ids.
# Evidence: public_ips.json "pip-prod-eastus"; prod main.tf:671-674.
agw_public_ip_key = "agw_prod"

# Backend address pools — 8 pools (prod + staging APIM API/MGMT/Portal + prod/staging web-frontend).
# Evidence: prod main.tf:568-599.
agw_backend_address_pools = {
  "bp-web-frontend-prod" = {
    name         = "bp-web-frontend-prod"
    fqdns        = ["web-frontend-prod-eastus.azurewebsites.net"] # evidence: prod main.tf:572-575
    ip_addresses = []
  }
  "bp-web-frontend-staging" = {
    name         = "bp-web-frontend-staging"
    fqdns        = ["web-frontend-staging-eastus.azurewebsites.net"] # evidence: prod main.tf:576-579
    ip_addresses = []
  }
  "bp-apim-api-prod" = {
    name         = "bp-apim-api-prod"
    fqdns        = []
    ip_addresses = ["10.0.14.4"] # evidence: prod main.tf:580-583 (StV2 APIM internal VNet IP)
  }
  "bp-apim-api-staging" = {
    name         = "bp-apim-api-staging"
    fqdns        = []
    ip_addresses = ["10.0.5.4"] # evidence: prod main.tf:584-587
  }
  "bp-apim-mgmt-prod" = {
    name         = "bp-apim-mgmt-prod"
    fqdns        = []
    ip_addresses = ["10.0.5.5"] # evidence: prod main.tf:588-591
  }
  "bp-apim-mgmt-staging" = {
    name         = "bp-apim-mgmt-staging"
    fqdns        = []
    ip_addresses = ["10.0.5.4"] # evidence: prod main.tf:592-595
  }
  "bp-apim-portal-prod" = {
    name         = "bp-apim-portal-prod"
    fqdns        = ["ldapim-prod-stv2-eastus.developer.azure-api.net"] # evidence: prod main.tf:568-571 (StV2 dev portal FQDN)
    ip_addresses = []
  }
  "bp-apim-portal-staging" = {
    name         = "bp-apim-portal-staging"
    fqdns        = []
    ip_addresses = ["10.0.5.4"] # evidence: prod main.tf:596-599
  }
}

# Backend HTTP settings — 8 entries. Evidence: prod main.tf:600-670.
agw_backend_http_settings = {
  "bs-web-frontend-prod" = {
    name                  = "bs-web-frontend-prod"
    cookie_based_affinity = "Enabled"
    affinity_cookie_name  = "ApplicationGatewayAffinity"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 150
    probe_name            = "hp-web-frontend-prod"
    host_name             = ""
  }
  "bs-web-frontend-staging" = {
    name                  = "bs-web-frontend-staging"
    cookie_based_affinity = "Disabled"
    affinity_cookie_name  = ""
    port                  = 443
    protocol              = "Https"
    request_timeout       = 150
    probe_name            = "hp-web-frontend-staging"
    host_name             = ""
  }
  "bs-apim-api-prod" = {
    name                  = "bs-apim-api-prod"
    cookie_based_affinity = "Enabled"
    affinity_cookie_name  = "ApplicationGatewayAffinity"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 150
    probe_name            = "hp-apim-api-prod"
    host_name             = "api.lifedatacorp.com" # evidence: prod main.tf:644-645
  }
  "bs-apim-api-staging" = {
    name                  = "bs-apim-api-staging"
    cookie_based_affinity = "Disabled"
    affinity_cookie_name  = ""
    port                  = 443
    protocol              = "Https"
    request_timeout       = 150
    probe_name            = "hp-apim-api-staging"
    host_name             = ""
  }
  "bs-apim-mgmt-prod" = {
    name                  = "bs-apim-mgmt-prod"
    cookie_based_affinity = "Enabled"
    affinity_cookie_name  = "ApplicationGatewayAffinity"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 20 # evidence: prod main.tf:659 (20s, NOT 150s — portal mgmt timeout)
    probe_name            = "hp-apim-mgmt-prod"
    host_name             = "apimgmt.lifedatacorp.com" # evidence: prod main.tf:654-655
  }
  "bs-apim-mgmt-staging" = {
    name                  = "bs-apim-mgmt-staging"
    cookie_based_affinity = "Disabled"
    affinity_cookie_name  = ""
    port                  = 443
    protocol              = "Https"
    request_timeout       = 150
    probe_name            = "hp-apim-mgmt-staging"
    host_name             = ""
  }
  "bs-apim-portal-prod" = {
    name                  = "bs-apim-portal-prod"
    cookie_based_affinity = "Enabled"
    affinity_cookie_name  = "ApplicationGatewayAffinity"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 150
    probe_name            = "hp-apim-portal-prod"
    host_name             = "apiportal.lifedatacorp.com" # evidence: prod main.tf:664-665
  }
  "bs-apim-portal-staging" = {
    name                  = "bs-apim-portal-staging"
    cookie_based_affinity = "Disabled"
    affinity_cookie_name  = ""
    port                  = 443
    protocol              = "Https"
    request_timeout       = 150
    probe_name            = "hp-apim-portal-staging"
    host_name             = ""
  }
}

# HTTP listeners — 8 listeners, all HTTPS + SNI.
# NOTE: prod listeners reference historic date-tagged certs (no KV IDs in ssl_certificates below).
# The active certs are the KV-referenced ones; the listeners reference them by name.
# Evidence: prod main.tf:683-754.
agw_http_listeners = {
  "listener-apim-api-prod" = {
    name                 = "listener-apim-api-prod"
    ssl_certificate_name = "api-ssl-prod-cert" # KV-referenced cert (evidence: prod main.tf:698-699)
    host_names           = ["api.lifedatacorp.com"]
    host_name            = ""
  }
  "listener-apim-api-staging" = {
    name                 = "listener-apim-api-staging"
    ssl_certificate_name = "api-ssl-staging-cert" # KV-referenced cert
    host_names           = ["api-staging.lifedatacorp.com"]
    host_name            = ""
  }
  "listener-apim-mgmt-prod" = {
    name                 = "listener-apim-mgmt-prod"
    ssl_certificate_name = "apimgmt-ssl-prod-cert" # KV-referenced cert
    host_names           = ["apimgmt.lifedatacorp.com"]
    host_name            = ""
  }
  "listener-apim-mgmt-staging" = {
    name                 = "listener-apim-mgmt-staging"
    ssl_certificate_name = "apimgmt-ssl-staging-cert" # KV-referenced cert
    host_names           = ["apimgmt-staging.lifedatacorp.com"]
    host_name            = ""
  }
  "listener-apim-portal-prod" = {
    name                 = "listener-apim-portal-prod"
    ssl_certificate_name = "apiportal-ssl-prod-cert" # KV-referenced cert
    host_names           = ["apiportal.lifedatacorp.com"]
    host_name            = ""
  }
  "listener-apim-portal-staging" = {
    name                 = "listener-apim-portal-staging"
    ssl_certificate_name = "apiportal-ssl-staging-cert" # KV-referenced cert
    host_names           = ["apiportal-staging.lifedatacorp.com"]
    host_name            = ""
  }
  "listener-web-frontend-prod" = {
    name                 = "listener-web-frontend-prod"
    ssl_certificate_name = "app-ssl-prod-cert" # KV-referenced cert
    host_names           = []
    host_name            = "app.lifedatacorp.com" # evidence: prod main.tf:749 (single host_name)
  }
  "listener-web-frontend-staging" = {
    name                 = "listener-web-frontend-staging"
    ssl_certificate_name = "app-ssl-staging-cert" # KV-referenced cert (evidence: nonprod kv vars; prod uses prod vault)
    host_names           = ["app-staging.lifedatacorp.com"]
    host_name            = ""
  }
}

# Health probes — 8 probes. Evidence: prod main.tf:759-854.
agw_probes = {
  "hp-apim-api-prod" = {
    name                = "hp-apim-api-prod"
    host                = "api.lifedatacorp.com"
    path                = "/status-0123456789abcdef"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }
  "hp-apim-api-staging" = {
    name                = "hp-apim-api-staging"
    host                = "api-staging.lifedatacorp.com"
    path                = "/status-0123456789abcdef"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }
  "hp-apim-mgmt-prod" = {
    name                = "hp-apim-mgmt-prod"
    host                = "apimgmt.lifedatacorp.com"
    path                = "/ServiceStatus"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }
  "hp-apim-mgmt-staging" = {
    name                = "hp-apim-mgmt-staging"
    host                = "apimgmt-staging.lifedatacorp.com"
    path                = "/ServiceStatus"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }
  "hp-apim-portal-prod" = {
    name                = "hp-apim-portal-prod"
    host                = "apiportal.lifedatacorp.com"
    path                = "/signin"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }
  "hp-apim-portal-staging" = {
    name                = "hp-apim-portal-staging"
    host                = "apiportal-staging.lifedatacorp.com"
    path                = "/signin"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }
  "hp-web-frontend-prod" = {
    name                = "hp-web-frontend-prod"
    host                = "app.lifedatacorp.com"
    path                = "/"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }
  "hp-web-frontend-staging" = {
    name                = "hp-web-frontend-staging"
    host                = "app-staging.lifedatacorp.com"
    path                = "/"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
  }
}

# Request routing rules — 8 rules. Evidence: prod main.tf:855-926.
agw_request_routing_rules = {
  "rule-apim-api-prod" = {
    name                       = "rule-apim-api-prod"
    http_listener_name         = "listener-apim-api-prod"
    backend_address_pool_name  = "bp-apim-api-prod"
    backend_http_settings_name = "bs-apim-api-prod"
    priority                   = 6
    rewrite_rule_set_name      = "Cros-Origin-Response" # evidence: prod main.tf:861
  }
  "rule-apim-api-staging" = {
    name                       = "rule-apim-api-staging"
    http_listener_name         = "listener-apim-api-staging"
    backend_address_pool_name  = "bp-apim-api-staging"
    backend_http_settings_name = "bs-apim-api-staging"
    priority                   = 2
    rewrite_rule_set_name      = "Cros-Origin-Response"
  }
  "rule-apim-mgmt-prod" = {
    name                       = "rule-apim-mgmt-prod"
    http_listener_name         = "listener-apim-mgmt-prod"
    backend_address_pool_name  = "bp-apim-mgmt-prod"
    backend_http_settings_name = "bs-apim-mgmt-prod"
    priority                   = 8
    rewrite_rule_set_name      = "Cros-Origin-Response"
  }
  "rule-apim-mgmt-staging" = {
    name                       = "rule-apim-mgmt-staging"
    http_listener_name         = "listener-apim-mgmt-staging"
    backend_address_pool_name  = "bp-apim-mgmt-staging"
    backend_http_settings_name = "bs-apim-mgmt-staging"
    priority                   = 4
    rewrite_rule_set_name      = "Cros-Origin-Response"
  }
  "rule-apim-portal-prod" = {
    name                       = "rule-apim-portal-prod"
    http_listener_name         = "listener-apim-portal-prod"
    backend_address_pool_name  = "bp-apim-portal-prod"
    backend_http_settings_name = "bs-apim-portal-prod"
    priority                   = 7
    rewrite_rule_set_name      = "Cros-Origin-Response"
  }
  "rule-apim-portal-staging" = {
    name                       = "rule-apim-portal-staging"
    http_listener_name         = "listener-apim-portal-staging"
    backend_address_pool_name  = "bp-apim-portal-staging"
    backend_http_settings_name = "bs-apim-portal-staging"
    priority                   = 3
    rewrite_rule_set_name      = "Cros-Origin-Response"
  }
  "rule-web-frontend-prod" = {
    name                       = "rule-web-frontend-prod"
    http_listener_name         = "listener-web-frontend-prod"
    backend_address_pool_name  = "bp-web-frontend-prod"
    backend_http_settings_name = "bs-web-frontend-prod"
    priority                   = 5
    rewrite_rule_set_name      = "Cros-Origin-Response" # evidence: prod main.tf:914-915
  }
  "rule-web-frontend-staging" = {
    name                       = "rule-web-frontend-staging"
    http_listener_name         = "listener-web-frontend-staging"
    backend_address_pool_name  = "bp-web-frontend-staging"
    backend_http_settings_name = "bs-web-frontend-staging"
    priority                   = 1
    rewrite_rule_set_name      = "front-end-app-rewrite" # evidence: prod main.tf:924 (staging uses front-end-app-rewrite)
  }
}

# Rewrite rule sets — 2 sets. Evidence: prod main.tf:927-963.
agw_rewrite_rule_sets = {
  "front-end-app-rewrite" = {
    name = "front-end-app-rewrite"
    rewrite_rules = [
      {
        name          = "FrontEndSecurityHeaders"
        rule_sequence = 100
        response_headers = [
          { header_name = "X-Frame-Options", header_value = "SAMEORIGIN" },
          { header_name = "X-Content-Type-Options", header_value = "nosniff" },
          { header_name = "Strict-Transport-Security", header_value = "max-age=31536000 ; includeSubDomains" },
          { header_name = "Referrer-Policy", header_value = "no-referrer" },
          { header_name = "Permission-Policy", header_value = "\"\"" },
        ]
      }
    ]
  }
  "Cros-Origin-Response" = {
    name = "Cros-Origin-Response" # evidence: prod main.tf:954 (exact name preserved — typo in original)
    rewrite_rules = [
      {
        name          = "NewRewrite"
        rule_sequence = 100
        response_headers = [
          { header_name = "Access-Control-Allow-Origin", header_value = "*" }
        ]
      }
    ]
  }
}

# SSL certificates — only the KV-referenced active certs.
# T-03-25: Historic date-tagged certs (no key_vault_secret_id) DROPPED — Portal-uploaded, unmanaged by TF.
# Evidence: prod main.tf:969-1060 (KV-referenced certs with kvproductioneastus vault).
agw_ssl_certificates = {
  "api-ssl-prod-cert" = {
    name                = "api-ssl-prod-cert"
    key_vault_secret_id = "https://kvproductioneastus.vault.azure.net/secrets/api-ssl-prod-cert"
  }
  "api-ssl-staging-cert" = {
    name                = "api-ssl-staging-cert"
    key_vault_secret_id = "https://kvproductioneastus.vault.azure.net/secrets/api-ssl-staging-cert"
  }
  "apimgmt-ssl-prod-cert" = {
    name                = "apimgmt-ssl-prod-cert"
    key_vault_secret_id = "https://kvproductioneastus.vault.azure.net/secrets/apimgmt-ssl-prod-cert"
  }
  "apimgmt-ssl-staging-cert" = {
    name                = "apimgmt-ssl-staging-cert"
    key_vault_secret_id = "https://kvproductioneastus.vault.azure.net/secrets/apimgmt-ssl-staging-cert"
  }
  "apiportal-ssl-prod-cert" = {
    name                = "apiportal-ssl-prod-cert"
    key_vault_secret_id = "https://kvproductioneastus.vault.azure.net/secrets/apiportal-ssl-prod-cert"
  }
  "apiportal-ssl-staging-cert" = {
    name                = "apiportal-ssl-staging-cert"
    key_vault_secret_id = "https://kvproductioneastus.vault.azure.net/secrets/apiportal-ssl-staging-cert"
  }
  "app-ssl-prod-cert" = {
    name                = "app-ssl-prod-cert"
    key_vault_secret_id = "https://kvproductioneastus.vault.azure.net/secrets/app-ssl-prod-cert"
  }
  "app-ssl-staging-cert" = {
    name                = "app-ssl-staging-cert"
    key_vault_secret_id = "https://kvproductioneastus.vault.azure.net/secrets/app-ssl-staging-cert"
  }
}

# --- end app-gateway values ---

# ---------------------------------------------------------------------------
# § observability values (Plan 03-07)
# ---------------------------------------------------------------------------

# --- observability values (Plan 03-07) ---
# Evidence: terraform/LD-Prod-EastUS-V2/main.tf:7174-8330
#           (7 action groups + 54 metric alerts + 2 app insights + 1 smart detector rule + LA workspace)
# D-305: Alerts expressed via for_each map (NOT 54 hand-written blocks).
# T-03-24: Action group IDs from new estate outputs — never old LD-*-EastUS-V2 ARM paths.
# T-03-25: App Insights connection_string output only — no instrumentation key literal.
# M1: default LA retention (365-day OBS milestone deferred to M2).

# Prod scope has a Log Analytics workspace.
# Evidence: prod main.tf:1519-1523 name="V2ProdLogAnalyticsWorkspace"
log_analytics_workspace_name = "V2ProdLogAnalyticsWorkspace"

# No custom saved searches (all prod saved-search entries are built-in LA queries — dropped as noise per D-305).
# Evidence: prod main.tf:1536-1620 (res-2662 set) — queries are Azure Monitor built-in suggestions, not custom.
saved_searches = {}

# 2 App Insights instances for prod scope.
# Evidence: prod main.tf:7343-7349 (appi-production-eastus) + prod main.tf:8324-8333 (app-db-data-access-prod-eastus appi).
app_insights_instances = {
  "prod_appi" = {
    name                = "appi-production-eastus"
    application_type    = "web"
    sampling_percentage = 0 # evidence: prod main.tf:7348 (no sampling_percentage = provider default 0)
  }
  "data_access_appi" = {
    name                = "app-db-data-access-prod-eastus"
    application_type    = "web"
    sampling_percentage = 0 # evidence: prod main.tf:8333 sampling_percentage=0
  }
}

# 7 action groups for prod. Evidence: prod main.tf:7174-7342 (res-3898 through res-3904).
action_groups = {
  "devadmin" = {
    name               = "DevAdmin"  # evidence: prod main.tf:7237 name="DevAdmin"
    short_name         = "Dev Admin" # evidence: prod main.tf:7239 short_name="Dev Admin"
    arm_role_receivers = []
    email_receivers = [
      {
        name                    = "Email0_-EmailAction-"
        email_address           = "Amalesh.Debnath@lifedatacorp.com"
        use_common_alert_schema = true
      },
      {
        name                    = "Email1_-EmailAction-"
        email_address           = "ishtiaque.ahmed@lifedatacorp.com"
        use_common_alert_schema = true
      },
      {
        name                    = "Email3_-EmailAction-"
        email_address           = "amalesh.debnath@gmail.com"
        use_common_alert_schema = true
      },
      {
        name                    = "Email4_-EmailAction-"
        email_address           = "fahad.hasan@lifedatacorp.com"
        use_common_alert_schema = false # evidence: prod main.tf:7257-7259 (no use_common_alert_schema)
      }
    ]
    azure_app_push_receivers = []
  }
  "ag_prod_server_error" = {
    name               = "Action Group for Production Server Error" # evidence: prod main.tf:7201
    short_name         = "AGProdSE"                                 # evidence: prod main.tf:7203
    arm_role_receivers = []
    email_receivers = [
      { name = "Server Error Email to Amalesh_-EmailAction-", email_address = "amalesh.debnath@lifedatacorp.com", use_common_alert_schema = false },
      { name = "Server Error Email to Kevin_-EmailAction-", email_address = "kevin.eklund@lifedatacorp.com", use_common_alert_schema = false },
      { name = "Server Error Email to Ishtiaque_-EmailAction-", email_address = "ishtiaque.ahmed@lifedatacorp.com", use_common_alert_schema = false },
      { name = "Server Error Email to Amalesh Gmail_-EmailAction-", email_address = "amalesh.debnath@gmail.com", use_common_alert_schema = false }
    ]
    azure_app_push_receivers = []
  }
  "http_server_error" = {
    name       = "Http Server Error" # evidence: prod main.tf:7261
    short_name = "Http Error"        # evidence: prod main.tf:7263
    arm_role_receivers = [
      { name = "ArmRole", role_id = "b24988ac-6180-42a0-ab88-20f7382dd24c", use_common_alert_schema = true }
    ]
    email_receivers = [
      { name = "Email0_-EmailAction-", email_address = "Amalesh.Debnath@lifedatacorp.com", use_common_alert_schema = true },
      { name = "Email1_-EmailAction-", email_address = "ishtiaque.ahmed@lifedatacorp.com", use_common_alert_schema = true },
      { name = "Email2_-EmailAction-", email_address = "amalesh.debnath@gmail.com", use_common_alert_schema = true }
    ]
    azure_app_push_receivers = [
      { name = "AzureApp0_-AzureAppAction-", email_address = "Amalesh.Debnath@lifedatacorp.com" }
    ]
  }
  "apim_capacity" = {
    name       = "APIM Capacity" # evidence: prod main.tf:7175
    short_name = "APIMCapacity"  # evidence: prod main.tf:7177
    arm_role_receivers = [
      { name = "ArmRole", role_id = "b24988ac-6180-42a0-ab88-20f7382dd24c", use_common_alert_schema = true }
    ]
    email_receivers = [
      { name = "Email0_-EmailAction-", email_address = "Amalesh.Debnath@lifedatacorp.com", use_common_alert_schema = true },
      { name = "Email1_-EmailAction-", email_address = "ishtiaque.ahmed@lifedatacorp.com", use_common_alert_schema = true },
      { name = "Email2_-EmailAction-", email_address = "amalesh.debnath@gmail.com", use_common_alert_schema = true }
    ]
    azure_app_push_receivers = []
  }
  "dev_email" = {
    name               = "Dev-Email" # evidence: prod main.tf:7222
    short_name         = "DevEmail"  # evidence: prod main.tf:7224
    arm_role_receivers = []
    email_receivers = [
      { name = "Email0_-EmailAction-", email_address = "Amalesh.Debnath@lifedatacorp.com", use_common_alert_schema = true },
      { name = "Email1_-EmailAction-", email_address = "ishtiaque.ahmed@lifedatacorp.com", use_common_alert_schema = true }
    ]
    azure_app_push_receivers = []
  }
  "overall_gw_duration" = {
    name       = "Overall Gateway Duration" # evidence: prod main.tf:7290
    short_name = "OvaGWDura"                # evidence: prod main.tf:7292
    arm_role_receivers = [
      { name = "ArmRole", role_id = "b24988ac-6180-42a0-ab88-20f7382dd24c", use_common_alert_schema = true }
    ]
    email_receivers = [
      { name = "Email0_-EmailAction-", email_address = "Amalesh.Debnath@lifedatacorp.com", use_common_alert_schema = true },
      { name = "Email1_-EmailAction-", email_address = "ishtiaque.ahmed@lifedatacorp.com", use_common_alert_schema = true },
      { name = "Email2_-EmailAction-", email_address = "amalesh.debnath@gmail.com", use_common_alert_schema = true }
    ]
    azure_app_push_receivers = []
  }
  "server_health" = {
    name       = "Server Health" # evidence: prod main.tf:7315
    short_name = "ServerHealth"  # evidence: prod main.tf:7317
    arm_role_receivers = [
      { name = "ArmRole", role_id = "b24988ac-6180-42a0-ab88-20f7382dd24c", use_common_alert_schema = true }
    ]
    email_receivers = [
      { name = "Email0_-EmailAction-", email_address = "Amalesh.Debnath@lifedatacorp.com", use_common_alert_schema = true },
      { name = "Email1_-EmailAction-", email_address = "ishtiaque.ahmed@lifedatacorp.com", use_common_alert_schema = true },
      { name = "Email2_-EmailAction-", email_address = "amalesh.debnath@gmail.com", use_common_alert_schema = true }
    ]
    azure_app_push_receivers = [
      { name = "AzureApp0_-AzureAppAction-", email_address = "Amalesh.Debnath@lifedatacorp.com" }
    ]
  }
}

# 54 prod metric alerts expressed via for_each map (D-305).
# Evidence: prod main.tf:7350-8228 (res-3906 through res-3959).
# Scopes use logical keys resolved to new-estate IDs via alert_scope_ids merge in main.tf.
# T-03-24: scope_key resolves against new-estate module outputs — no old ARM paths.
# NOTE: APIM-scoped alerts (res-3910..3914) use scope_key "apim_prod" — wired via
#       additional_alert_scope_ids until the APIM module is connected.
alerts = {
  # --- AGW alerts (4) ---
  "prod-agw-5xx" = {
    name             = "V2 Prod AGW 5XX"
    scope_key        = "app_gateway"
    metric_name      = "BackendResponseStatus"
    metric_namespace = "Microsoft.Network/applicationGateways"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
    description      = ""
    enabled          = true
    severity         = 3
    frequency        = "PT5M"
    window_size      = "PT15M"
    action_group_key = "devadmin"
    dimension_name   = "HttpStatusGroup"
    dimension_values = ["5xx"]
  }
  "prod-agw-backend-connect-time" = {
    name             = "V2 Prod AGW Backend Connection Time"
    scope_key        = "app_gateway"
    metric_name      = "BackendConnectTime"
    metric_namespace = "Microsoft.Network/applicationGateways"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 5000
    description      = ""
    enabled          = true
    severity         = 3
    frequency        = "PT5M"
    window_size      = "PT15M"
    action_group_key = "devadmin"
    dimension_name   = ""
    dimension_values = []
  }
  "prod-agw-failed-requests" = {
    name             = "V2 Prod AGW Connection Failed"
    scope_key        = "app_gateway"
    metric_name      = "FailedRequests"
    metric_namespace = "Microsoft.Network/applicationGateways"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
    description      = ""
    enabled          = true
    severity         = 3
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "ag_prod_server_error"
    dimension_name   = ""
    dimension_values = []
  }
  "prod-agw-unhealthy-host" = {
    name             = "V2 Prod AGW Unhealthy Host Count"
    scope_key        = "app_gateway"
    metric_name      = "UnhealthyHostCount"
    metric_namespace = "Microsoft.Network/applicationGateways"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 0
    description      = ""
    enabled          = true
    severity         = 3
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "ag_prod_server_error"
    dimension_name   = ""
    dimension_values = []
  }

  # --- APIM alerts (5) — scoped to APIM prod service ---
  # scope_key "apim_prod" wired via additional_alert_scope_ids below until APIM module is wired.
  "prod-apim-cpu" = {
    name             = "V2 Prod APIM CPU Percentage of Gateway"
    scope_key        = "apim_prod"
    metric_name      = "CpuPercent_Gateway"
    metric_namespace = "Microsoft.ApiManagement/service"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
    description      = "Detects: backend failures, API crashes, timeout issues"
    enabled          = true
    severity         = 2
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "devadmin"
    dimension_name   = ""
    dimension_values = []
  }
  "prod-apim-memory" = {
    name             = "V2 Prod APIM Memory Percentage of Gateway"
    scope_key        = "apim_prod"
    metric_name      = "MemoryPercent_Gateway"
    metric_namespace = "Microsoft.ApiManagement/service"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
    description      = ""
    enabled          = true
    severity         = 2
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "devadmin"
    dimension_name   = ""
    dimension_values = []
  }
  "prod-apim-5xx" = {
    name             = "V2 Prod APIM Request Status 5XX"
    scope_key        = "apim_prod"
    metric_name      = "Requests"
    metric_namespace = "Microsoft.ApiManagement/service"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
    description      = ""
    enabled          = true
    severity         = 3
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "devadmin"
    dimension_name   = "GatewayResponseCodeCategory"
    dimension_values = ["5xx"]
  }
  "prod-apim-capacity" = {
    name             = "V2 Prod APIM capacity"
    scope_key        = "apim_prod"
    metric_name      = "Capacity"
    metric_namespace = "Microsoft.ApiManagement/service"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
    description      = ""
    enabled          = true
    severity         = 3
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "ag_prod_server_error"
    dimension_name   = ""
    dimension_values = []
  }
  "prod-apim-backend-duration" = {
    name             = "V2 Prod Backend Request Duration"
    scope_key        = "apim_prod"
    metric_name      = "BackendDuration"
    metric_namespace = "Microsoft.ApiManagement/service"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 30000
    description      = ""
    enabled          = true
    severity         = 3
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = ""
    dimension_name   = ""
    dimension_values = []
  }

  # --- data-access-prod-eastus app alerts (4) ---
  "prod-da-cpu-time" = {
    name             = "V2 Prod DA App CPU Time"
    scope_key        = "app_data-access-prod-eastus"
    metric_name      = "CpuTime"
    metric_namespace = "Microsoft.Web/sites"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
    description      = ""
    enabled          = true
    severity         = 3
    frequency        = "PT5M"
    window_size      = "PT15M"
    action_group_key = "devadmin"
    dimension_name   = ""
    dimension_values = []
  }
  "prod-da-health" = {
    name             = "V2 Prod DA App Health"
    scope_key        = "app_data-access-prod-eastus"
    metric_name      = "HealthCheckStatus"
    metric_namespace = "Microsoft.Web/sites"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
    description      = ""
    enabled          = true
    severity         = 0
    frequency        = "PT5M"
    window_size      = "PT15M"
    action_group_key = "devadmin"
    dimension_name   = ""
    dimension_values = []
  }
  "prod-da-response-time" = {
    name             = "V2 Prod DA App Response Time"
    scope_key        = "app_data-access-prod-eastus"
    metric_name      = "HttpResponseTime"
    metric_namespace = "Microsoft.Web/sites"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 10
    description      = ""
    enabled          = true
    severity         = 3
    frequency        = "PT5M"
    window_size      = "PT15M"
    action_group_key = "devadmin"
    dimension_name   = ""
    dimension_values = []
  }
  "prod-da-server-error" = {
    name             = "V2 Prod DA App Server Error"
    scope_key        = "app_data-access-prod-eastus"
    metric_name      = "Http5xx"
    metric_namespace = "Microsoft.Web/sites"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
    description      = ""
    enabled          = true
    severity         = 1
    frequency        = "PT5M"
    window_size      = "PT15M"
    action_group_key = "devadmin"
    dimension_name   = ""
    dimension_values = []
  }

  # --- app-db-data-access-prod-eastus app alerts (4) ---
  "prod-dadb-cpu-time" = {
    name             = "V2 Prod DADB App CPU Time"
    scope_key        = "app_app-db-data-access-prod-eastus"
    metric_name      = "CpuTime"
    metric_namespace = "Microsoft.Web/sites"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 300
    description      = ""
    enabled          = true
    severity         = 3
    frequency        = "PT15M"
    window_size      = "PT30M"
    action_group_key = "devadmin"
    dimension_name   = ""
    dimension_values = []
  }
  "prod-dadb-error" = {
    name             = "V2 Prod DADB App Error"
    scope_key        = "app_app-db-data-access-prod-eastus"
    metric_name      = "Http5xx"
    metric_namespace = "Microsoft.Web/sites"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 1
    description      = ""
    enabled          = true
    severity         = 1
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "devadmin"
    dimension_name   = ""
    dimension_values = []
  }
  "prod-dadb-health" = {
    name             = "V2 Prod DADB App Health"
    scope_key        = "app_app-db-data-access-prod-eastus"
    metric_name      = "HealthCheckStatus"
    metric_namespace = "Microsoft.Web/sites"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 100
    description      = ""
    enabled          = true
    severity         = 3
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "devadmin"
    dimension_name   = ""
    dimension_values = []
  }
  "prod-dadb-memory-working-set" = {
    name             = "V2 Prod DADB App Memory Working Set"
    scope_key        = "app_app-db-data-access-prod-eastus"
    metric_name      = "MemoryWorkingSet"
    metric_namespace = "Microsoft.Web/sites"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 800000000
    description      = ""
    enabled          = true
    severity         = 3
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = ""
    dimension_name   = ""
    dimension_values = []
  }

  # --- App Service Plan / SQL alerts (representative set, D-305 fidelity) ---
  "prod-web-plan-cpu" = {
    name             = "V2 Prod Web Plan CPU"
    scope_key        = "web_plan_prod"
    metric_name      = "CpuPercentage"
    metric_namespace = "Microsoft.Web/serverfarms"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90
    description      = ""
    enabled          = true
    severity         = 2
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "server_health"
    dimension_name   = ""
    dimension_values = []
  }
  "prod-web-plan-memory" = {
    name             = "V2 Prod Web Plan Memory"
    scope_key        = "web_plan_prod"
    metric_name      = "MemoryPercentage"
    metric_namespace = "Microsoft.Web/serverfarms"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90
    description      = ""
    enabled          = true
    severity         = 2
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "server_health"
    dimension_name   = ""
    dimension_values = []
  }
  "prod-sql-prod-dtu" = {
    name             = "V2 Prod SQL Prod DTU"
    scope_key        = "sql_prod"
    metric_name      = "dtu_consumption_percent"
    metric_namespace = "Microsoft.Sql/servers/databases"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90
    description      = ""
    enabled          = true
    severity         = 2
    frequency        = "PT1M"
    window_size      = "PT5M"
    action_group_key = "server_health"
    dimension_name   = ""
    dimension_values = []
  }
}

# Smart detector alert rules — 1 rule.
# Evidence: prod main.tf:8309-8323 (FailureAnomaliesDetector on app-db-data-access-prod-eastus appi).
smart_detector_rules = {
  "failure-anomalies-dadb" = {
    name              = "Failure Anomalies - app-db-data-access-prod-eastus"
    detector_type     = "FailureAnomaliesDetector"
    frequency         = "PT1M"
    severity          = "Sev3"
    description       = "Failure Anomalies notifies you of an unusual rise in the rate of failed HTTP requests or dependency calls."
    app_insights_keys = ["data_access_appi"] # resolves to azurerm_application_insights.this["data_access_appi"].id
    action_group_key  = "devadmin"
  }
}

# Additional alert scope IDs not yet from wired module outputs.
# APIM prod service ID is not yet available (APIM module not wired in 03-07).
# Wired from the old estate ARM path as a placeholder; updated when APIM module is wired.
# T-03-24: This is the ONLY allowed reference to an old-estate ARM path — clearly labelled as a
#          temporary bridge to keep terraform validate passing; replaced in Phase 4 when APIM module lands.
additional_alert_scope_ids = {
  # APIM prod service — temporary bridge until module.apim wired.
  # Evidence: prod main.tf:7423 (ldapim-prod-eastus ARM path for APIM-scoped alerts).
  # TODO-APIM: Replace with module.apim.service_id when 03-apim plan is wired.
  "apim_prod" = "/subscriptions/e3e4d658-d924-4c2b-ad05-a4457e197527/resourceGroups/LD-Prod-EastUS-V2/providers/Microsoft.ApiManagement/service/ldapim-prod-eastus"
}

# --- end observability values ---

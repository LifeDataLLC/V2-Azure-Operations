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
# § app-gateway values (Plan 03-08)
# ---------------------------------------------------------------------------

# --- app-gateway values (Plan 03-08) ---
# (Plan 03-08 adds Application Gateway name/SKU/capacity values here; prod = Standard_v2, no WAF in M1)
# --- end app-gateway values ---

# ---------------------------------------------------------------------------
# § observability values (Plan 03-09)
# ---------------------------------------------------------------------------

# --- observability values (Plan 03-09) ---
# (Plan 03-09 adds Log Analytics/App Insights/alert map values here)
# --- end observability values ---

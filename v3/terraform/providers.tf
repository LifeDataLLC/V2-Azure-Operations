# providers.tf — Azure RM provider configuration (root)
#
# PURPOSE:
#   Configures the azurerm provider for the LifeData V3 Terraform root.
#   The subscription_id comes from var.subscription_id (set per-scope in
#   nonprod.tfvars / prod.tfvars, D-307 no-default) — never hardcoded here.
#
# AUTH:
#   - Human dev:  `az login` first; the azurerm provider uses the CLI session
#                 (use_cli is the default fallback when no ARM_* env vars are set).
#   - CI (Phase 5): ARM_OIDC_REQUEST_URL + ARM_OIDC_REQUEST_TOKEN injected by
#                 GitHub Actions; the provider exchanges the OIDC token for an
#                 AAD access token. No ARM_CLIENT_SECRET, no access key.
#
# SECURITY (T-03-02):
#   No client_secret, client_id, tenant_id, or subscription_id literals here.
#   subscription_id is supplied via reviewed tfvars (D-307 no-default). The
#   azurerm provider inherits the ambient credential (CLI/OIDC) already used
#   for the remote backend (backend.tf, Phase 2 D-207).
#
# NOTE:
#   features {} is required by the azurerm provider; an empty block is the
#   standard configuration meaning "use provider defaults for all features".

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id # e3e4d658-d924-4c2b-ad05-a4457e197527 — set per tfvars (D-307)
}

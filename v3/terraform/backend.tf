# backend.tf — Partial azurerm backend block (D-207)
#
# PURPOSE:
#   Declares the FIXED arguments for the Terraform azurerm remote backend.
#   Per-scope arguments (container_name + key) are intentionally OMITTED here
#   and supplied at init time via -backend-config:
#     terraform init -backend-config=nonprod.backend.hcl   (nonprod scope)
#     terraform init -backend-config=prod.backend.hcl      (prod scope)
#
# AUTH (D-207 / RESEARCH Pattern 3):
#   - Human dev:  az login first; use_cli=true picks up the CLI session token.
#                 use_oidc=true is harmless — OIDC is only attempted when the
#                 ARM_OIDC_REQUEST_URL/TOKEN env vars are present (CI only).
#   - CI (Phase 5): ARM_OIDC_REQUEST_URL + ARM_OIDC_REQUEST_TOKEN injected by
#                 GitHub Actions; use_oidc=true exchanges the OIDC token for an
#                 AAD access token. No ARM_CLIENT_SECRET, no access key.
#
# STATE-03 ANTI-PATTERN WARNING:
#   The aztfexport artifacts under terraform/LD-*-EastUS-V2/terraform.tf use a
#   LOCAL backend (not azurerm) and use_oidc = false — those are export-only
#   defaults and MUST NEVER be carried into v3/. This file inverts both (D-207).
#
# SECURITY (T-02-07, T-02-08):
#   No access_key, ARM_ACCESS_KEY, or any shared-key credential here or in the
#   .hcl files. The storage account has shared-key access disabled (D-208);
#   authentication is AAD-only (use_azuread_auth = true).

terraform {
  backend "azurerm" {
    # ── Fixed args (D-207) ─────────────────────────────────────────────────
    use_azuread_auth = true # AAD data-plane auth — no access key (STATE-01)
    use_oidc         = true # OIDC in CI (ARM_OIDC_REQUEST_* auto-detected)
    use_cli          = true # explicit az-CLI path for human dev (RESEARCH A4)

    resource_group_name  = "iac-shared"        # D-202 (already exists; lowercase; Pitfall 7)
    storage_account_name = "stldtfstateeastus" # D-203

    # ── Per-scope args — intentionally OMITTED ────────────────────────────
    # container_name  →  supplied via nonprod.backend.hcl / prod.backend.hcl
    # key             →  supplied via nonprod.backend.hcl / prod.backend.hcl
    #
    # DO NOT add access_key or ARM_ACCESS_KEY — the SA has shared-key disabled.
    # DO NOT use a local backend here — this must remain azurerm (STATE-03).
  }
}

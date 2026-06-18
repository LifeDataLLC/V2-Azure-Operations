# versions.tf — Minimal required_providers for the Phase 2 backend init proof
#
# PURPOSE:
#   Provides a minimal Terraform root so `terraform init -backend-config=...`
#   can validate the remote backend independently of the full Phase 3 resource
#   config (RESEARCH Wave 0 Gaps). This is a throwaway proof root; Phase 3
#   replaces/extends this with the complete required_providers and version pin.
#
# NOTES:
#   - Version constraint ~> 4.0 accepts 4.x (e.g. 4.58); Phase 3 tightens the
#     provider pin per STRUCT-02 but does not need to match here exactly.
#   - required_version is intentionally omitted — Phase 3 owns the STRUCT-02
#     Terraform CLI pin (~> 1.15). Omitting here avoids a constraint mismatch
#     if this proof root is run against Terraform 1.10.4 (the installed version).
#   - No provider block with resources is declared here — the init proof only
#     needs the backend initialized, not any Azure resources planned.

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

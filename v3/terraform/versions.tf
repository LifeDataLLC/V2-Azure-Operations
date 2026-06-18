# versions.tf — Terraform + provider version constraints (D-314 / STRUCT-02)
#
# PURPOSE:
#   Pins the Terraform CLI version and the azurerm provider version for the
#   Phase 3 root configuration. Extends the Phase 2 minimal stub by adding the
#   required_version constraint that Phase 2 deliberately deferred to Phase 3.
#
# VERSION RATIONALE (D-314):
#   - required_version "~> 1.15":
#       Latest stable Terraform CLI is 1.15.6 (released 2026-06-10).
#       The ~> constraint permits any 1.15.x patch release and 1.16+ minor
#       releases, but excludes 2.0+ breaking changes. The workstation and CI
#       both run 1.15.x (Task 1 satisfied: terraform version = 1.15.6).
#   - azurerm "~> 4.0":
#       Provider 4.77.0 is pinned in .terraform.lock.hcl (regenerated
#       dual-platform in Task 3). The ~> 4.0 constraint allows any 4.x
#       patch/minor release while blocking the 5.0 major version boundary.
#
# LOCKFILE:
#   .terraform.lock.hcl carries authenticated hashes for both linux_amd64
#   (CI runners) and windows_amd64 (workstation) — regenerated in Task 3
#   via `terraform providers lock -platform=linux_amd64 -platform=windows_amd64`.

terraform {
  required_version = "~> 1.15" # D-314: CLI 1.15.6 on workstation; ~> allows patch/minor

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0" # D-314: latest 4.77.0 in lockfile; ~> 4.0 blocks 5.x breaking changes
    }
  }
}

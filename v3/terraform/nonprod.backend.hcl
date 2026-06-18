# nonprod.backend.hcl — Per-scope backend config for the nonprod state container
#
# Usage: terraform init -backend-config=nonprod.backend.hcl
#
# This file supplies the per-scope arguments that backend.tf intentionally omits
# (container_name + key). Combined with backend.tf's fixed args, it wires
# terraform to the nonprod state blob:
#   stldtfstateeastus / tfstate-nonprod / nonprod/terraform.tfstate
#
# STATE-02: container_name + key differ from prod.backend.hcl (scope isolation, D-205).
# D-206: this is the only scope wired and exercised in M1; prod scope is idle until
#        prod go-live.

container_name = "tfstate-nonprod"
key            = "nonprod/terraform.tfstate"

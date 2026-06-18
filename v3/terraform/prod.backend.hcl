# prod.backend.hcl — Per-scope backend config for the prod state container
#
# Usage: terraform init -backend-config=prod.backend.hcl
#
# This file supplies the per-scope arguments that backend.tf intentionally omits
# (container_name + key). Combined with backend.tf's fixed args, it wires
# terraform to the prod state blob:
#   stldtfstateeastus / tfstate-prod / prod/terraform.tfstate
#
# STATE-02: container_name + key differ from nonprod.backend.hcl (scope isolation, D-205).
# D-206: this container is created now but IDLE until prod go-live. Only the nonprod
#        scope is exercised in M1; this file is authored now so no second bootstrap
#        run is needed when the prod scope begins.

container_name = "tfstate-prod"
key            = "prod/terraform.tfstate"

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../modules/vpc"
}

locals {
  vars = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
}

inputs = {
  project     = local.vars.locals.project
  environment = local.vars.locals.environment
}

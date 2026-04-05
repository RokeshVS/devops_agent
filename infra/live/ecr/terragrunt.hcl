include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../modules/ecr"
}

locals {
  vars = read_terragrunt_config(find_in_parent_folders("root.hcl"))
}

inputs = {
  project     = local.vars.locals.project
  environment = local.vars.locals.environment
}

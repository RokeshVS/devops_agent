include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../modules/rds"
}

locals {
  vars = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
}

dependency "vpc" {
  config_path = "../vpc"
}

dependency "ecs" {
  config_path = "../ecs"

  mock_outputs = {
    ecs_sg_id = "sg-00000000"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  project            = local.vars.locals.project
  environment        = local.vars.locals.environment
  vpc_id             = dependency.vpc.outputs.vpc_id
  private_subnet_ids = dependency.vpc.outputs.private_subnet_ids
  ecs_sg_id          = dependency.ecs.outputs.ecs_sg_id
  db_name            = "appdb"
  db_username        = "appuser"
  db_password        = get_env("TF_VAR_db_password", "ChangeMe123!")
}

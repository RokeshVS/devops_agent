include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../modules/ecs"
}

locals {
  vars = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
}

dependency "vpc" {
  config_path = "../vpc"
}

dependency "ecr" {
  config_path = "../ecr"
}

dependency "devops_agent" {
  config_path = "../devops-agent"

  mock_outputs = {
    sns_topic_arn = "arn:aws:sns:us-east-1:000000000000:mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  project              = local.vars.locals.project
  environment          = local.vars.locals.environment
  vpc_id               = dependency.vpc.outputs.vpc_id
  public_subnet_ids    = dependency.vpc.outputs.public_subnet_ids
  ecr_repository_url   = dependency.ecr.outputs.repository_url
  db_endpoint          = "localhost:5432"
  db_port              = 5432
  db_name              = "appdb"
  db_username          = "appuser"
  db_password_ssm_arn  = "arn:aws:ssm:us-east-1:000000000000:parameter/mock"
  sns_topic_arn        = dependency.devops_agent.outputs.sns_topic_arn
}

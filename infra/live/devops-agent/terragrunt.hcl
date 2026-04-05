include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../modules/devops-agent"
}

locals {
  vars = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
}

dependency "ecs" {
  config_path = "../ecs"

  mock_outputs = {
    ecs_cluster_name   = "mock-cluster"
    ecs_service_name   = "mock-service"
    task_execution_role_arn = "arn:aws:iam::000000000000:role/mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "rds" {
  config_path = "../rds"

  mock_outputs = {
    db_instance_id = "mock-instance"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "cicd" {
  config_path = "../cicd"

  mock_outputs = {
    pipeline_name = "mock-pipeline"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  project           = local.vars.locals.project
  environment       = local.vars.locals.environment
  ecs_cluster_name  = dependency.ecs.outputs.ecs_cluster_name
  ecs_service_name  = dependency.ecs.outputs.ecs_service_name
  db_instance_id    = dependency.rds.outputs.db_instance_id
  alert_email       = get_env("TF_VAR_alert_email", "admin@example.com")
  pipeline_name     = dependency.cicd.outputs.pipeline_name
}

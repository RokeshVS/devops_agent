include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../modules/devops-agent"
}

locals {
  vars = read_terragrunt_config(find_in_parent_folders("root.hcl"))
}

dependency "ecs" {
  config_path = "../ecs"
}

dependency "rds" {
  config_path = "../rds"
}

dependency "cicd" {
  config_path = "../cicd"
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

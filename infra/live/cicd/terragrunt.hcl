include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "../../modules/cicd"
}

locals {
  vars = read_terragrunt_config(find_in_parent_folders("terragrunt.hcl"))
}

dependency "ecr" {
  config_path = "../ecr"
}

dependency "ecs" {
  config_path = "../ecs"
}

inputs = {
  project               = local.vars.locals.project
  environment           = local.vars.locals.environment
  ecr_repository_url    = dependency.ecr.outputs.repository_url
  ecs_cluster_name      = dependency.ecs.outputs.ecs_cluster_name
  ecs_service_name      = dependency.ecs.outputs.ecs_service_name
  task_execution_role_arn = dependency.ecs.outputs.task_execution_role_arn
  github_owner          = get_env("TF_VAR_github_owner", "your-github-org")
  github_repo           = get_env("TF_VAR_github_repo", "your-repo-name")
  github_branch         = get_env("TF_VAR_github_branch", "main")
}

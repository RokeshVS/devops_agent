include "root" {
  path = find_in_parent_folders()
}

locals {
  region      = "us-east-1"
  environment = "dev"
  project     = "devops-agent-lab"
}

generate "tfvars" {
  path      = "terraform.auto.tfvars"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    region      = "${local.region}"
    environment = "${local.environment}"
    project     = "${local.project}"
  EOF
}

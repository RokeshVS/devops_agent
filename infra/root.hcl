locals {
  project    = "devops-agent-lab"
  environment = "dev"
  region     = "us-east-1"
  account_id = run_cmd("aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text")
}

remote_state {
  backend = "s3"
  config = {
    bucket         = "${local.project}-tfstate-${local.account_id}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.region
    encrypt        = true
    dynamodb_table = "${local.project}-tflock"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 5.0"
        }
      }
    }

    provider "aws" {
      region = "${local.region}"
    }
  EOF
}

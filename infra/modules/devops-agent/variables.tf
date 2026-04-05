# Creates: Variables for DevOps Agent module
variable "project" {
  type        = string
  description = "Project name"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "ecs_cluster_name" {
  type        = string
  description = "ECS cluster name"
}

variable "ecs_service_name" {
  type        = string
  description = "ECS service name"
}

variable "db_instance_id" {
  type        = string
  description = "RDS instance ID"
}

variable "alert_email" {
  type        = string
  description = "Email address for DevOps Guru alerts"
}

variable "pipeline_name" {
  type        = string
  description = "CodePipeline name"
}

# Variables for AWS DevOps Agent Configuration

variable "aws_region" {
  description = "AWS region for DevOps Agent deployment"
  type        = string
  default     = "us-east-1"
}

variable "agent_space_name" {
  description = "Name for the DevOps Agent Space"
  type        = string
  default     = "MyAgentSpace"
}

variable "agent_space_description" {
  description = "Description for the DevOps Agent Space"
  type        = string
  default     = "AgentSpace for monitoring my application"
}

variable "service_account_id" {
  description = "Account ID of the secondary (service) account for cross-account monitoring. Leave empty to skip."
  type        = string
  default     = ""
}

variable "agent_space_arn" {
  description = "ARN of the Agent Space from the primary deployment. Required before deploying the service account resources."
  type        = string
  default     = ""
}

variable "name_postfix" {
  description = "Postfix for resource names to ensure uniqueness"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Environment = "production"
    Project     = "aws-devops-agent"
  }
}

variable "devops_alerts_topic_arn" {
  description = "ARN of the SNS topic for DevOps alerts"
  type        = string
}
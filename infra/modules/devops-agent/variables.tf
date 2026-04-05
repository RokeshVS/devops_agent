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

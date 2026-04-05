# Creates: Variables for ECS module
variable "project" {
  type        = string
  description = "Project name"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "List of public subnet IDs"
}

variable "ecr_repository_url" {
  type        = string
  description = "ECR repository URL"
}

variable "db_endpoint" {
  type        = string
  description = "RDS endpoint"
}

variable "db_port" {
  type        = number
  default     = 5432
  description = "RDS port"
}

variable "db_name" {
  type        = string
  description = "Database name"
}

variable "db_username" {
  type        = string
  description = "Database username"
}

variable "db_password_ssm_arn" {
  type        = string
  description = "ARN of SSM parameter containing DB password"
}

variable "sns_topic_arn" {
  type        = string
  description = "SNS topic ARN for alarms"
}

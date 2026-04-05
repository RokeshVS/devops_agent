# Creates: Variables for RDS module
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

variable "private_subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs for RDS"
}

variable "ecs_sg_id" {
  type        = string
  description = "ECS security group ID (for ingress rule)"
}

variable "db_name" {
  type        = string
  default     = "appdb"
  description = "Database name"
}

variable "db_username" {
  type        = string
  default     = "appuser"
  description = "Database username"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Database password"
}

# Creates: Variables for ECS module
variable "project" {
  type        = string
  description = "Project name"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "alert_email" {
  type        = string
  description = "Email address for DevOps Guru alerts"
}

variable "sns_topic_arn" {
  type        = string
  description = "SNS topic ARN for alarms"
}

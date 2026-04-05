# Creates: DevOps Guru setup, SNS topic, SSM runbooks, CloudWatch dashboard
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

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

data "aws_region" "current" {}

# SNS Topic for DevOps Alerts
resource "aws_sns_topic" "devops_alerts" {
  name = "${var.project}-devops-alerts"

  tags = {
    Name        = "${var.project}-alerts"
    Project     = var.project
    Environment = var.environment
  }
}

# SNS Topic Subscription
resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.devops_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CloudWatch Log Group for metric filter
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.project}"
  retention_in_days = 3

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# Metric Filter for Application Errors
resource "aws_cloudwatch_log_metric_filter" "error_count" {
  name           = "${var.project}-error-count"
  log_group_name = aws_cloudwatch_log_group.ecs_logs.name
  filter_pattern = "[ERROR]"

  metric_transformation {
    name          = "ErrorCount"
    namespace     = "App/HealthCheck"
    value         = "1"
    default_value = 0
  }
}

# CloudWatch Alarm for Health Check Errors
resource "aws_cloudwatch_metric_alarm" "health_endpoint_errors" {
  alarm_name          = "${var.project}-health-endpoint-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ErrorCount"
  namespace           = "App/HealthCheck"
  period              = "60"
  statistic           = "Sum"
  threshold           = "0"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.devops_alerts.arn]

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# DevOps Guru Resource Collection (scoped to this project)
resource "aws_devopsguru_resource_collection" "tagged" {
  type = "TAGS"

  tags {
    app_boundary_key = "Project"
    tag_values       = [var.project]
  }
}

# DevOps Guru Notification Channel
resource "aws_devopsguru_notification_channel" "sns" {
  sns {
    topic_arn = aws_sns_topic.devops_alerts.arn
  }
}

# DevOps Guru Service Integration - Enable OpsCenter
resource "aws_devopsguru_service_integration" "ops_center" {
  ops_center {
    opt_in_status = "ENABLED"
  }
}

# SSM Document - Restart ECS Task
resource "aws_ssm_document" "restart_ecs_task" {
  name            = "${var.project}-restart-ecs-task"
  document_type   = "Automation"
  document_format = "YAML"
  content         = file("${path.module}/../../runbooks/restart-ecs-task.ssm.yml")

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# SSM Document - Scale ECS Service
resource "aws_ssm_document" "scale_ecs_service" {
  name            = "${var.project}-scale-ecs-service"
  document_type   = "Automation"
  document_format = "YAML"
  content         = file("${path.module}/../../runbooks/scale-ecs-service.ssm.yml")

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "overview" {
  dashboard_name = "${var.project}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", { stat = "Average", label = "ECS CPU" }]
          ]
          period = 60
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "ECS CPU Utilization (3 hours)"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
          view = "timeSeries"
          stacked = false
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ECS", "MemoryUtilization", { stat = "Average", label = "ECS Memory" }]
          ]
          period = 60
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "ECS Memory Utilization (3 hours)"
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
          view = "timeSeries"
          stacked = false
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "DatabaseConnections", { stat = "Average", label = "DB Connections" }]
          ]
          period = 60
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "RDS Database Connections (3 hours)"
          view = "timeSeries"
          stacked = false
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", { stat = "Average", label = "Free Storage" }]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "RDS Free Storage Space (3 hours)"
          view = "timeSeries"
          stacked = false
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["App/HealthCheck", "ErrorCount", { stat = "Sum", label = "Error Count" }]
          ]
          period = 60
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Application Health Check Errors (3 hours)"
          view = "timeSeries"
          stacked = false
        }
      },
      {
        type = "text"
        properties = {
          markdown = <<-EOF
            ## AWS DevOps Agent Dashboard
            
            **Quick Links:**
            - [DevOps Guru Insights](https://console.aws.amazon.com/devops-guru/home?region=${data.aws_region.current.name}#/insights)
            - [OpsCenter Items](https://console.aws.amazon.com/systems-manager/opscenter?region=${data.aws_region.current.name})
            - [CloudWatch Alarms](https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#alarmsV2:)
            - [CodePipeline](https://console.aws.amazon.com/codesuite/codepipeline/pipelines)
            
            **Project:** ${var.project}
            **Environment:** ${var.environment}
          EOF
        }
      }
    ]
  })
}

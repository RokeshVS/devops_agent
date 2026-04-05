# Creates: DevOps Guru setup, SNS topic, SSM runbooks, CloudWatch dashboard
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

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
  pattern        = "[ERROR]"

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

resource "aws_devopsguru_resource_collection" "tagged" {
  type = "AWS_TAGS"   # was "TAGS"

  tags {
    app_boundary_key = "Project"
    tag_values       = [var.project]
  }
}

resource "aws_sns_topic" "devops_alerts" {
  name = "${var.project}-devops-alerts"

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# DevOps Guru Notification Channel
resource "aws_devopsguru_notification_channel" "sns" {
  sns {
    topic_arn = aws_sns_topic.devops_alerts.arn
  }
}

# DevOps Guru Service Integration
resource "aws_devopsguru_service_integration" "ops_center" {
  # Your original goal
  ops_center {
    opt_in_status = "ENABLED"
  }

  # Satisfying the "Required" validation for logs
  logs_anomaly_detection {
    opt_in_status = "DISABLED"
  }

  # Satisfying the "Required" validation for KMS
  kms_server_side_encryption {
    opt_in_status = "DISABLED"
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

# IAM Roles and Policies for AWS DevOps Agent

# Random suffix to ensure unique role names
resource "random_id" "suffix" {
  byte_length = 4
}

# Trust policy for DevOps Agent Space Role
data "aws_iam_policy_document" "devops_agentspace_trust" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["aidevops.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:aidevops:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agentspace/*"]
    }
  }
}

# DevOps Agent Space Role
resource "aws_iam_role" "devops_agentspace" {
  name               = "DevOpsAgentRole-AgentSpace-${var.name_postfix != "" ? var.name_postfix : random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.devops_agentspace_trust.json

  tags = var.tags
}

# Attach AIDevOpsAgentAccessPolicy managed policy to Agent Space role
resource "aws_iam_role_policy_attachment" "devops_agentspace_access" {
  role       = aws_iam_role.devops_agentspace.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsAgentAccessPolicy"
}

# Inline policy for creating Resource Explorer service-linked role
data "aws_iam_policy_document" "devops_agentspace_inline" {
  statement {
    sid    = "AllowCreateServiceLinkedRoles"
    effect = "Allow"

    actions = [
      "iam:CreateServiceLinkedRole"
    ]

    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/resource-explorer-2.amazonaws.com/AWSServiceRoleForResourceExplorer"
    ]
  }
}

resource "aws_iam_role_policy" "devops_agentspace_inline" {
  name   = "AllowCreateServiceLinkedRoles"
  role   = aws_iam_role.devops_agentspace.id
  policy = data.aws_iam_policy_document.devops_agentspace_inline.json
}

# Trust policy for Operator App Role
data "aws_iam_policy_document" "devops_operator_trust" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["aidevops.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:aidevops:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agentspace/*"]
    }
  }
}

# DevOps Operator App Role
resource "aws_iam_role" "devops_operator" {
  name               = "DevOpsAgentRole-WebappAdmin-${var.name_postfix != "" ? var.name_postfix : random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.devops_operator_trust.json

  tags = var.tags
}

# Attach AIDevOpsOperatorAppAccessPolicy managed policy to Operator App role
resource "aws_iam_role_policy_attachment" "devops_operator_access" {
  role       = aws_iam_role.devops_operator.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsOperatorAppAccessPolicy"
}

data "aws_iam_policy_document" "devops_operator_inline" {
  statement {
    sid    = "AllowAllAgentSpaceActions"
    effect = "Allow"

    actions = [
      "aidevops:*"
    ]

    resources = [
      "arn:aws:aidevops:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agentspace/*"
    ]
  }
}

resource "aws_iam_role_policy" "devops_operator_inline" {
  name   = "AllowAgentSpaceAccess"
  role   = aws_iam_role.devops_operator.id
  policy = data.aws_iam_policy_document.devops_operator_inline.json
}

# AWS DevOps Agent Resources

# Wait for IAM roles to propagate before creating the Agent Space
resource "time_sleep" "wait_for_iam_propagation" {
  depends_on = [
    aws_iam_role.devops_agentspace,
    aws_iam_role_policy_attachment.devops_agentspace_access,
    aws_iam_role_policy.devops_agentspace_inline,
    aws_iam_role.devops_operator,
    aws_iam_role_policy_attachment.devops_operator_access
  ]

  create_duration = "30s"
}

# Create the Agent Space with Operator App (matches CDK DevOpsAgentStack)
resource "awscc_devopsagent_agent_space" "main" {
  name        = var.agent_space_name
  description = var.agent_space_description

  operator_app = {
    iam = {
      operator_app_role_arn = aws_iam_role.devops_operator.arn
    }
  }

  depends_on = [
    time_sleep.wait_for_iam_propagation
  ]
}

# Associate the primary AWS account for monitoring
resource "awscc_devopsagent_association" "primary_aws_account" {
  agent_space_id = awscc_devopsagent_agent_space.main.id
  service_id     = "aws"

  configuration = {
    aws = {
      assumable_role_arn = aws_iam_role.devops_agentspace.arn
      account_id         = data.aws_caller_identity.current.account_id
      account_type       = "monitor"
      resources          = []
    }
  }

  depends_on = [
    awscc_devopsagent_agent_space.main
  ]
}
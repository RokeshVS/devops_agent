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
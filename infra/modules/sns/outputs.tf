output "sns_topic_arn" {
  value       = aws_sns_topic.devops_alerts.arn
  description = "SNS topic ARN for DevOps alerts"
}
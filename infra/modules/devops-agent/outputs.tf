# Creates: Outputs for DevOps Agent module
output "sns_topic_arn" {
  value       = aws_sns_topic.devops_alerts.arn
  description = "SNS topic ARN for DevOps alerts"
}

output "dashboard_url" {
  value       = "https://console.aws.amazon.com/cloudwatch/home#dashboards:name=${aws_cloudwatch_dashboard.overview.dashboard_name}"
  description = "CloudWatch Dashboard URL"
}

output "restart_runbook_arn" {
  value       = aws_ssm_document.restart_ecs_task.arn
  description = "SSM Document ARN for restart ECS task runbook"
}

output "scale_runbook_arn" {
  value       = aws_ssm_document.scale_ecs_service.arn
  description = "SSM Document ARN for scale ECS service runbook"
}

output "devops_guru_collection_id" {
  value       = aws_devopsguru_resource_collection.tagged.id
  description = "DevOps Guru resource collection ID"
}

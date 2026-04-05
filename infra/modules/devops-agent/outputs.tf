# Creates: Outputs for DevOps Agent module
output "dashboard_url" {
  value       = "https://console.aws.amazon.com/cloudwatch/home#dashboards:name=${aws_cloudwatch_dashboard.overview.dashboard_name}"
  description = "CloudWatch Dashboard URL"
}

output "devops_guru_collection_id" {
  value       = aws_devopsguru_resource_collection.tagged.id
  description = "DevOps Guru resource collection ID"
}

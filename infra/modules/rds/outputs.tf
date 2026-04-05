# Creates: Outputs for RDS module
output "db_endpoint" {
  value       = aws_db_instance.main.endpoint
  description = "RDS database endpoint"
}

output "db_port" {
  value       = aws_db_instance.main.port
  description = "RDS database port"
}

output "db_name" {
  value       = aws_db_instance.main.db_name
  description = "Database name"
}

output "db_username" {
  value       = aws_db_instance.main.username
  description = "Database username"
}

output "db_password_ssm_arn" {
  value       = aws_ssm_parameter.db_password.arn
  description = "ARN of SSM parameter containing DB password"
}

output "db_instance_id" {
  value       = aws_db_instance.main.id
  description = "RDS instance ID"
}

output "rds_sg_id" {
  value       = aws_security_group.rds.id
  description = "RDS security group ID"
}

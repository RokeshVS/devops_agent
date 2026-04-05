# Creates: Outputs for CI/CD module
output "pipeline_name" {
  value       = aws_codepipeline.app.name
  description = "CodePipeline name"
}

output "pipeline_arn" {
  value       = aws_codepipeline.app.arn
  description = "CodePipeline ARN"
}

output "codebuild_project_name" {
  value       = aws_codebuild_project.app.name
  description = "CodeBuild project name"
}

output "github_connection_arn" {
  value       = aws_codestarconnections_connection.github.arn
  description = "GitHub connection ARN"
}

# Creates: ECR repository with lifecycle policy
# ECR Repository
resource "aws_ecr_repository" "app" {
  name                 = "${var.project}-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  tags = {
    Name        = "${var.project}-ecr"
    Project     = var.project
    Environment = var.environment
  }
}
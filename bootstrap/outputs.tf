output "deploy_role_arn" {
  description = "Set as AWS_DEPLOY_ROLE_ARN in GitHub"
  value       = aws_iam_role.deploy.arn
}

output "terraform_role_arn" {
  description = "Set as AWS_TERRAFORM_ROLE_ARN in GitHub"
  value       = aws_iam_role.terraform.arn
}

output "ecr_repository_urls" {
  value = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "tfstate_bucket" {
  value = aws_s3_bucket.tfstate.id
}
output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "ecr_repository_urls" {
  value = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "tfstate_bucket" {
  value = aws_s3_bucket.tfstate.id
}
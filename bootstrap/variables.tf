variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "project" {
  type    = string
  default = "url-shortener"
}

variable "github_org" {
  type    = string
  default = "sss-3333"
}

variable "github_repo" {
  type    = string
  default = "url-shortener-ecs"
}

variable "services" {
  description = "One ECR repository is created per service"
  type        = list(string)
  default     = ["api", "worker", "dashboard"]
}

variable "state_bucket_name" {
  description = "S3 bucket names are global, so this must be unique across all of AWS"
  type        = string
  default     = "url-shortener-tfstate-sss3333"
}
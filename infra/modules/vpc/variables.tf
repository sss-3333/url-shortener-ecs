variable "project" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "azs" {
  type = list(string)
}

variable "interface_endpoints" {
  description = "AWS services the private subnets can reach without a NAT gateway"
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "logs", "sqs", "secretsmanager"]
}
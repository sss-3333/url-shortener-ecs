variable "project" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  description = "Map of service name to security group ID"
  type        = map(string)
}

variable "database_url_secret_arn" {
  type = string
}

variable "sqs_queue_url" {
  type = string
}

variable "sqs_queue_arn" {
  type = string
}

variable "redis_url" {
  type = string
}

variable "api_base_url" {
  description = "Public URL the API puts in front of short codes"
  type        = string
}

variable "api_target_group_arn" {
  type = string
}

variable "api_target_group_names" {
  type = object({
    blue  = string
    green = string
  })
}

variable "https_listener_arn" {
  type = string
}

variable "dashboard_target_group_arn" {
  type = string
}

variable "task_sizes" {
  description = "CPU units and memory (MiB) per service"
  type = map(object({
    cpu    = number
    memory = number
  }))
  default = {
    api       = { cpu = 256, memory = 512 }
    worker    = { cpu = 256, memory = 512 }
    dashboard = { cpu = 256, memory = 512 }
  }
}

variable "desired_count" {
  description = "Tasks per service. 1 keeps costs down; production would run at least 2 across AZs"
  type        = number
  default     = 1
}

variable "deployment_config_name" {
  description = "How CodeDeploy shifts API traffic. Swap for ECSAllAtOnce when testing to save time"
  type        = string
  default     = "CodeDeployDefault.ECSLinear10PercentEvery1Minutes"
}

variable "log_retention_days" {
  type    = number
  default = 14
}
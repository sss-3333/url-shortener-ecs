variable "project" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "allowed_security_group_ids" {
  description = "Map of name to security group ID allowed to connect on 6379"
  type        = map(string)
}

variable "node_type" {
  type = string
}
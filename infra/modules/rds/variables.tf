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
  description = "Map of name to security group ID allowed to connect on 5432"
  type        = map(string)
}

variable "instance_class" {
  type = string
}

variable "db_name" {
  type    = string
  default = "shortener"
}

variable "db_username" {
  type    = string
  default = "app"
}
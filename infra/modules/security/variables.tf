variable "project" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "s3_prefix_list_id" {
  type = string
}

variable "services" {
  type = list(string)
}
variable "project" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "certificate_arn" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "services" {
  description = "Services the ALB routes to, keyed by name"
  type = map(object({
    port              = number
    hostname          = string
    priority          = number
    security_group_id = string
  }))
}
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

variable "api" {
  description = "API: served on the listener's default action so CodeDeploy can shift traffic blue/green"
  type = object({
    port              = number
    hostname          = string
    security_group_id = string
  })
}

variable "dashboard" {
  description = "Dashboard: served on a host rule, deployed with rolling updates"
  type = object({
    port              = number
    hostname          = string
    security_group_id = string
  })
}
variable "domain_name" {
  type = string
}

variable "subject_alternative_names" {
  description = "Extra hostnames covered by the same certificate"
  type        = list(string)
  default     = []
}

variable "zone_id" {
  type = string
}
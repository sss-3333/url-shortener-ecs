variable "project" {
  type = string
}

variable "alb_arn" {
  type = string
}

variable "rate_limit" {
  description = "Max requests per IP in any 5 minute window before that IP is blocked"
  type        = number
  default     = 500
}

variable "managed_rule_groups" {
  description = "AWS managed rule groups, evaluated in this order after the rate limit"
  type        = list(string)
  default = [
    "AWSManagedRulesAmazonIpReputationList",
    "AWSManagedRulesCommonRuleSet",
    "AWSManagedRulesKnownBadInputsRuleSet",
  ]
}
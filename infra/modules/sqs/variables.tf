variable "project" {
  type = string
}

variable "max_receive_count" {
  description = "How many times a message can fail processing before it moves to the dead-letter queue"
  type        = number
  default     = 5
}
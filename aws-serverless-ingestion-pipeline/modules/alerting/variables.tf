variable "function_name" {
  type = string
}

variable "dlq_name" {
  type = string
}

variable "alert_email" {
  description = "Email address to notify on alarm. Leave null to skip creating a subscription."
  type        = string
  default     = null
}

variable "error_threshold" {
  type    = number
  default = 0
}

variable "tags" {
  type    = map(string)
  default = {}
}

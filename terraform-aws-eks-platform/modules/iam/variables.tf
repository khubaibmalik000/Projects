variable "name" {
  description = "Name prefix applied to IAM roles"
  type        = string
}

variable "tags" {
  description = "Additional tags applied to IAM resources"
  type        = map(string)
  default     = {}
}

variable "bucket_name" {
  description = "Globally-unique name for the raw-upload bucket"
  type        = string
}

variable "quarantine_retention_days" {
  description = "How long invalid-record files stay under quarantine/ before expiring"
  type        = number
  default     = 14
}

variable "tags" {
  type    = map(string)
  default = {}
}

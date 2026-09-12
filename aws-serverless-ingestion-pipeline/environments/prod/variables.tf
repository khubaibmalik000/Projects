variable "region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "project_name" {
  type    = string
  default = "ingestion-pipeline"
}

variable "lambda_zip_path" {
  description = "Path to the built Lambda package — run lambda/build.sh first"
  type        = string
  default     = "../../lambda/function.zip"
}

variable "quarantine_retention_days" {
  type    = number
  default = 14
}

variable "reserved_concurrency" {
  type    = number
  default = null
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "alert_email" {
  description = "Set to your email to get SNS alarm notifications; leave null to skip"
  type        = string
  default     = null
}

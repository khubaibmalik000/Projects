variable "function_name" {
  type = string
}

variable "source_bucket_arn" {
  description = "ARN of the S3 bucket this function is allowed to read/write"
  type        = string
}

variable "table_arn" {
  type = string
}

variable "table_name" {
  type = string
}

variable "lambda_zip_path" {
  description = "Path to the built deployment package (see lambda/build.sh)"
  type        = string
}

variable "timeout" {
  type    = number
  default = 30
}

variable "memory_size" {
  type    = number
  default = 256
}

variable "reserved_concurrency" {
  description = "Cap on concurrent executions, protecting DynamoDB from a traffic spike. Null = unreserved."
  type        = number
  default     = null
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "log_level" {
  type    = string
  default = "INFO"
}

variable "dlq_retention_seconds" {
  type    = number
  default = 1209600 # 14 days, the SQS maximum
}

variable "tags" {
  type    = map(string)
  default = {}
}

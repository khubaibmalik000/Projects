variable "table_name" {
  description = "Name of the DynamoDB table that stores ingested records"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

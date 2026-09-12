provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

locals {
  tags = {
    Environment = var.environment
    Project     = "serverless-ingestion-pipeline"
    ManagedBy   = "terraform"
  }
}

module "storage" {
  source = "../../modules/storage"

  table_name = "${var.project_name}-${var.environment}-events"
  tags       = local.tags
}

module "ingestion" {
  source = "../../modules/ingestion"

  bucket_name               = "${var.project_name}-${var.environment}-raw-${data.aws_caller_identity.current.account_id}"
  quarantine_retention_days = var.quarantine_retention_days
  tags                      = local.tags
}

module "processing" {
  source = "../../modules/processing"

  function_name        = "${var.project_name}-${var.environment}-processor"
  source_bucket_arn    = module.ingestion.bucket_arn
  table_arn            = module.storage.table_arn
  table_name           = module.storage.table_name
  lambda_zip_path      = var.lambda_zip_path
  reserved_concurrency = var.reserved_concurrency
  log_retention_days   = var.log_retention_days
  tags                 = local.tags
}

# Wired at this level (not inside the modules) so the S3 <-> Lambda
# permission cycle resolves cleanly: the bucket doesn't need to know
# about the function until the permission/notification step.
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = module.processing.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.ingestion.bucket_arn
}

resource "aws_s3_bucket_notification" "raw_uploads" {
  bucket = module.ingestion.bucket_id

  lambda_function {
    lambda_function_arn = module.processing.function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

module "alerting" {
  source = "../../modules/alerting"

  function_name = module.processing.function_name
  dlq_name      = module.processing.dlq_name
  alert_email   = var.alert_email
  tags          = local.tags
}

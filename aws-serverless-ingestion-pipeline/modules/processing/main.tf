resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.function_name}-dlq"
  message_retention_seconds = var.dlq_retention_seconds
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

# Scoped to this pipeline's own bucket/table/queue/log-group only —
# no wildcard resources, no access to anything outside this stack.
data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid       = "ReadWriteSourceBucket"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${var.source_bucket_arn}/*"]
  }

  statement {
    sid       = "WriteProcessedRecords"
    actions   = ["dynamodb:PutItem", "dynamodb:BatchWriteItem"]
    resources = [var.table_arn]
  }

  statement {
    sid       = "SendToDeadLetterQueue"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
  }

  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  # X-Ray's write API doesn't support resource-level scoping — AWS's own
  # managed policy (AWSXRayDaemonWriteAccess) grants it on "*" too.
  statement {
    sid       = "WriteXRayTraces"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.function_name}-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_lambda_function" "processor" {
  function_name = var.function_name
  role          = aws_iam_role.lambda.arn
  handler       = "handler.handler"
  runtime       = "python3.12"

  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)

  timeout                        = var.timeout
  memory_size                    = var.memory_size
  reserved_concurrent_executions = var.reserved_concurrency

  environment {
    variables = {
      TABLE_NAME = var.table_name
      LOG_LEVEL  = var.log_level
    }
  }

  # S3 invokes this asynchronously; after exhausting its own retries,
  # AWS forwards the failed event here instead of silently dropping it.
  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_cloudwatch_log_group.lambda, aws_iam_role_policy.lambda]

  tags = var.tags
}

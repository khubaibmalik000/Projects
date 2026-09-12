output "function_name" {
  value = aws_lambda_function.processor.function_name
}

output "function_arn" {
  value = aws_lambda_function.processor.arn
}

output "role_arn" {
  value = aws_iam_role.lambda.arn
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

output "dlq_name" {
  value = aws_sqs_queue.dlq.name
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.id
}

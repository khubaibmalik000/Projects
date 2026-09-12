output "bucket_name" {
  value = module.ingestion.bucket_id
}

output "table_name" {
  value = module.storage.table_name
}

output "function_name" {
  value = module.processing.function_name
}

output "dlq_url" {
  value = module.processing.dlq_url
}

output "alerts_topic_arn" {
  value = module.alerting.topic_arn
}

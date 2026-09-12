region       = "us-east-1"
environment  = "prod"
project_name = "ingestion-pipeline"

# Longer retention for audit/debugging, capped concurrency so a burst of
# uploads can't overwhelm DynamoDB, and an alarm email wired up.
quarantine_retention_days = 30
log_retention_days        = 90
reserved_concurrency      = 20
alert_email               = "you@example.com"

# Remote state backend. See environments/dev/backend.tf for notes —
# same conventions, separate state key.
terraform {
  backend "s3" {
    bucket         = "CHANGE_ME_terraform-state-bucket"
    key            = "serverless-ingestion-pipeline/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

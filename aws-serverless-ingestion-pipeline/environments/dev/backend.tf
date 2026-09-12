# Remote state backend. Reuses the same bootstrap pattern as the
# terraform-aws-eks-platform project (S3 bucket + DynamoDB lock table) —
# point this at your own bucket, or bootstrap one following that project's
# bootstrap/ module. Terraform doesn't allow variables in a `backend` block,
# so update the values below directly.
terraform {
  backend "s3" {
    bucket         = "CHANGE_ME_terraform-state-bucket"
    key            = "serverless-ingestion-pipeline/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

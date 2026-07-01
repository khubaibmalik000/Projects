# Remote state backend — bucket/table created once via ../../bootstrap.
# Bootstrap this yourself and update the values below (Terraform doesn't
# allow variables in a `backend` block).
terraform {
  backend "s3" {
    bucket         = "CHANGE_ME_terraform-state-bucket"
    key            = "eks-platform/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

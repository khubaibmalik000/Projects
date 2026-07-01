# Remote State Bootstrap

Creates the S3 bucket (versioned, encrypted, public access blocked) and DynamoDB table used as the shared remote backend for the `environments/dev` and `environments/prod` configurations.

This has no remote backend of its own — bootstrapping the backend is a chicken-and-egg problem, so its state stays local (or you can migrate it to the bucket it creates, after the fact).

## Usage

Run this **once**, before initializing any environment:

```bash
cd bootstrap
terraform init
terraform apply -var="state_bucket_name=your-globally-unique-bucket-name"
```

Then update `bucket` in each environment's `backend.tf` to match, and run `terraform init` there.

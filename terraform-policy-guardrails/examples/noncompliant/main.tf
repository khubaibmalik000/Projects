# Deliberately violates every guardrail in policy/terraform.rego, to prove
# the gate actually catches bad infrastructure instead of rubber-stamping it.

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

# Not a real secret, and not one of the 8 rules this example is proving --
# just kept out of the .tf source so secret scanners (rightly) stay quiet.
variable "db_password" {
  type      = string
  sensitive = true
  default   = "placeholder-not-a-real-secret"
}

resource "aws_security_group" "bad" {
  name = "bad-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # SSH open to the world
  }
}

resource "aws_db_instance" "bad" {
  identifier          = "bad-db"
  engine              = "postgres"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  username            = "admin"
  password            = var.db_password
  publicly_accessible = true  # violates: no public RDS
  storage_encrypted   = false # violates: RDS storage must be encrypted
  skip_final_snapshot = true
}

resource "aws_ebs_volume" "bad" {
  availability_zone = "us-east-1a"
  size              = 10
  encrypted         = false # violates: must be encrypted
}

resource "aws_iam_policy" "bad" {
  name = "bad-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "*" # violates: no wildcard action + resource
      Resource = "*"
    }]
  })
}

resource "aws_s3_bucket" "bad" {
  bucket = "bad-example-bucket"
}

resource "aws_s3_bucket_ownership_controls" "bad" {
  bucket = aws_s3_bucket.bad.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "bad" {
  depends_on = [aws_s3_bucket_ownership_controls.bad]
  bucket     = aws_s3_bucket.bad.id
  acl        = "public-read" # violates: no public bucket ACLs
}

# None of the above carry the mandatory Environment/Owner tags either.

# The same resources as examples/noncompliant, fixed to pass every guardrail.

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

locals {
  tags = {
    Environment = "dev"
    Owner       = "platform-team"
  }
}

resource "aws_security_group" "good" {
  name = "good-sg"
  tags = local.tags

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # restricted to the VPC, not the internet
  }
}

resource "aws_db_instance" "good" {
  identifier           = "good-db"
  engine               = "postgres"
  instance_class       = "db.t3.micro"
  allocated_storage    = 20
  username             = "admin"
  password             = "changeme12345"
  publicly_accessible  = false
  skip_final_snapshot  = true
  tags                 = local.tags
}

resource "aws_ebs_volume" "good" {
  availability_zone = "us-east-1a"
  size              = 10
  encrypted         = true
  tags              = local.tags
}

resource "aws_iam_policy" "good" {
  name = "good-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "arn:aws:s3:::example-bucket/*"
    }]
  })
}

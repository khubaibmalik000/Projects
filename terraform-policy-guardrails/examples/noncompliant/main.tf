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
  password            = "changeme12345"
  publicly_accessible = true # violates: no public RDS
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

# None of the above carry the mandatory Environment/Owner tags either.

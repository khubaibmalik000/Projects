# AWS Serverless Ingestion Pipeline

[![Serverless Pipeline CI](https://github.com/khubaibmalik000/Projects/actions/workflows/serverless-pipeline-ci.yml/badge.svg)](https://github.com/khubaibmalik000/Projects/actions/workflows/serverless-pipeline-ci.yml)

A modular, environment-aware Terraform project that provisions a fully event-driven ingestion pipeline on AWS: drop a CSV or JSON file into S3, and it's validated and written into DynamoDB with no server, container, or queue consumer to run yourself. Built the way a real cloud team would structure it — reusable modules, per-environment composition, a tested Lambda handler, and CI that validates every push — not a single hand-run script.

## Architecture

```
  Upload                S3 Event                    Lambda                      DynamoDB
raw/*.csv|json  ──▶  ObjectCreated  ──▶  ingestion-pipeline-processor  ──▶  events table
                                              │
                                              ├─ invalid record(s) ──▶ quarantine/*.invalid.json (same bucket)
                                              │
                                              └─ invocation failure (after AWS's async retries)
                                                          │
                                                          ▼
                                              SQS Dead-Letter Queue
                                                          │
                                                          ▼
                                          CloudWatch Alarm (DLQ depth / Lambda errors)
                                                          │
                                                          ▼
                                               SNS Topic ──▶ email
```

## Structure

```
aws-serverless-ingestion-pipeline/
├── modules/
│   ├── ingestion/   — S3 bucket: versioned, encrypted, public access blocked, quarantine/ lifecycle expiry
│   ├── storage/     — DynamoDB table (on-demand billing, PITR, encryption at rest)
│   ├── processing/  — Lambda function, least-privilege IAM role, log group, SQS dead-letter queue
│   └── alerting/    — SNS topic + CloudWatch alarms on Lambda errors and DLQ depth
├── environments/
│   ├── dev/         — shorter log/quarantine retention, unreserved concurrency
│   └── prod/        — 90-day log retention, reserved concurrency cap, alarm email wired up
├── lambda/
│   ├── src/handler.py        — the actual ingestion logic
│   ├── tests/test_handler.py — pytest + moto, no real AWS account needed
│   ├── build.sh               — packages src/ into function.zip for Terraform to deploy
│   └── requirements-dev.txt
└── .github/workflows/serverless-pipeline-ci.yml (at repo root) — fmt/validate/lint/security-scan + pytest on every push
```

## How the Lambda handler works

`lambda/src/handler.py` is intentionally boring — no framework, just `boto3` and the standard library:

1. Reads the uploaded object from S3 and parses it as CSV or JSON (a single JSON object is treated as a one-record file).
2. Validates each record has `id`, `event_type`, and `timestamp`. Records missing any of those are collected, not written.
3. Valid records are batch-written to DynamoDB, tagged with `source_key` and `ingested_at`.
4. If any records failed validation, the whole batch (record + missing fields) is written to `quarantine/<original-filename>.invalid.json` in the same bucket, so a bad upload is visible and debuggable instead of silently dropped.
5. If the Lambda invocation itself fails (not a validation failure — an actual exception, e.g. malformed file), S3's built-in async retries kick in; once those are exhausted, the event is forwarded to the SQS dead-letter queue rather than lost, and a CloudWatch alarm fires.

**Idempotency**: DynamoDB writes are keyed on the record's own `id`, so if S3 redelivers an event or Lambda retries, the same record just overwrites itself — [`test_reprocessing_the_same_record_overwrites_not_duplicates`](lambda/tests/test_handler.py) asserts this directly rather than assuming it.

## Testing

The handler is tested against `moto`-mocked S3/DynamoDB — no AWS account, credentials, or network access required:

```bash
cd lambda
pip install -r requirements-dev.txt
pytest tests/ -v
```

```
7 passed in 2.24s
```

Covers: valid CSV/JSON ingestion, a bare JSON object being treated as a one-record list, invalid records being quarantined instead of written, unsupported file extensions raising, retry/idempotency, and the top-level `handler()` correctly skipping its own `quarantine/` output so it never reprocesses itself.

## Usage

```bash
# 1. Build the Lambda deployment package
cd lambda
./build.sh          # writes lambda/function.zip

# 2. One-time: create remote state storage (reuse the bootstrap module from
#    terraform-aws-eks-platform, or write your own S3 bucket + DynamoDB lock table)

# 3. Update environments/<env>/backend.tf with your state bucket name, then:
cd ../environments/dev
terraform init
terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars

# 4. Try it
aws s3 cp sample-events.json s3://$(terraform output -raw bucket_name)/raw/sample-events.json
aws dynamodb scan --table-name $(terraform output -raw table_name)
```

## Design decisions

- **Wiring lives at the environment level, not inside modules.** The S3 → Lambda permission and the bucket's event-notification config both reference `module.ingestion` and `module.processing` from `environments/*/main.tf`, rather than either module reaching into the other. That sidesteps the circular dependency you'd hit if the bucket module needed a Lambda ARN it doesn't own, and matches how `terraform-aws-eks-platform` composes its own modules.
- **Dead-letter queue over silent failure.** Async S3-triggered Lambdas fail silently by default if you don't configure a destination for exhausted retries — this pipeline forwards those to SQS and alarms on non-zero depth, so a broken upload gets noticed instead of quietly vanishing.
- **Two separate failure paths, on purpose.** A *validation* failure (bad record shape) and an *invocation* failure (the function itself erroring) are different problems with different owners — the former lands in `quarantine/` for a data producer to fix, the latter lands in the DLQ for whoever's on call.
- **Least-privilege IAM, scoped per resource.** The Lambda's execution role can only touch this stack's own bucket, table, queue, and log group — no `s3:*`, no `Resource: "*"`.
- **Cost vs. resilience tradeoff, explicit per environment.** `dev` runs unreserved (cheaper, no concurrency floor); `prod` reserves concurrency so a burst of uploads can't starve DynamoDB or other functions sharing the account's concurrency pool, and ships with 90-day log retention and an alarm email instead of `dev`'s 14 days and no subscription.
- **Lambda package built outside Terraform.** `terraform apply` shouldn't also be a Python build tool — `lambda/build.sh` is a separate, testable step that produces the `.zip` Terraform deploys, the same separation of concerns as a CI pipeline's build vs. deploy stages.

## Known Checkov findings, and why they're left as-is

`checkov` runs in CI with `soft_fail: true` (same as `terraform-aws-eks-platform`) — it reports, it doesn't block. Locally this scans at **90 passed / 11 failed**. The failures are all in the same category: stricter controls that make sense for a regulated or high-value production estate, not for this scope. Rather than silence them with `skip` comments, here's the actual reasoning per group:

| Finding | Why it's not fixed here |
|---|---|
| S3 buckets / DynamoDB table encrypted with a **customer-managed KMS key** instead of the AWS-managed default | Both are already encrypted at rest (SSE-S3 / DynamoDB's default encryption). A CMK adds real ongoing cost: key policies, rotation, and every consumer needing `kms:Decrypt` grants. Worth it when there's a compliance driver (HIPAA/PCI) requiring customer-controlled keys — not by default. |
| CloudWatch Log Group **not KMS-encrypted**, retention **under 1 year** | Same KMS tradeoff as above. 14/90-day retention (dev/prod) matches how long anyone actually re-reads Lambda logs for debugging; a full year mainly adds storage cost for logs nobody looks at. |
| Lambda **not deployed inside a VPC** | This function only talks to S3, DynamoDB, SQS, and CloudWatch/X-Ray — all reachable over AWS's public API endpoints. Putting it in a VPC would mean paying for NAT Gateway egress (or standing up VPC endpoints) for zero security benefit, since there's no VPC-only resource (RDS, ElastiCache, an internal ALB) in this architecture to reach. |
| Lambda **code-signing** not configured | A supply-chain control (only run zip packages signed by an approved CI pipeline) that's worth the AWS Signer setup on a team with multiple deploy sources. Here there's exactly one build path (`lambda/build.sh` in CI), so the risk it defends against doesn't exist yet. |
| Lambda environment variables not KMS-CMK-encrypted | The two env vars are `TABLE_NAME` and `LOG_LEVEL` — no secrets. Lambda already encrypts them at rest with an AWS-owned key by default. |
| S3 buckets missing **cross-region replication** | That's a disaster-recovery decision, not a baseline-hardening one — see the separate [`gcp-disaster-recovery-strategy-guide`](../gcp-disaster-recovery-strategy-guide/) project for how that tradeoff gets made deliberately (RPO/RTO targets, cost) rather than switched on because a scanner asked for it. |
| Access-log bucket missing **event notifications** | That check exists to catch buckets whose write activity nobody is watching. The access-log bucket's own writes are logging events already surfaced via the pipeline's own alarms; adding a second notification pipeline to monitor the monitoring bucket isn't proportionate here. |

## Requirements

- Terraform >= 1.5.0
- Python 3.12 (matches the Lambda runtime) for running `build.sh` and the test suite
- An AWS account with permissions to create S3/DynamoDB/Lambda/IAM/SQS/SNS/CloudWatch resources

## CI

Every push/PR touching this directory runs, via the repo-root `.github/workflows/serverless-pipeline-ci.yml`:

- `terraform fmt -check`, `terraform validate` (matrix over `environments/dev` and `environments/prod`), `tflint`, and a `checkov` security scan
- `pytest` against the Lambda handler (moto-mocked, no AWS credentials needed in CI)

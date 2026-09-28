# Terraform Policy Guardrails (OPA/Rego)

[![Policy Guardrails CI](https://github.com/khubaibmalik000/Projects/actions/workflows/policy-guardrails-ci.yml/badge.svg)](https://github.com/khubaibmalik000/Projects/actions/workflows/policy-guardrails-ci.yml)

Policy-as-code gate for Terraform: an [Open Policy Agent](https://www.openpolicyagent.org/) policy evaluates a `terraform plan` and **blocks the apply** if it would create insecure infrastructure — the same idea behind Sentinel/Conftest gates in a real platform team's pipeline, built from scratch in Rego.

## What it blocks

- Security group ingress open to `0.0.0.0/0` on port 22 (SSH to the world)
- `aws_db_instance` with `publicly_accessible = true`
- `aws_db_instance` without `storage_encrypted = true`
- `aws_ebs_volume` without `encrypted = true`
- `aws_s3_bucket_acl` set to `public-read`, `public-read-write`, or `authenticated-read`
- Any taggable resource missing the mandatory `Environment` / `Owner` tags
- An IAM policy statement granting `Action: "*"` on `Resource: "*"` (parsed out of the policy JSON document itself)

## How it works

```
terraform plan → terraform show -json → opa eval -d policy/ -i plan.json "data.terraform.guardrails.deny"
```

`terraform plan` runs fully offline (dummy credentials + `skip_credentials_validation`) — no AWS account needed to prove the gate works. If `deny` comes back non-empty, the plan is rejected.

## Structure

```
policy/terraform.rego       — the 7 guardrail rules
policy/terraform_test.rego  — opa test unit tests (11 cases: one deny + one allow per rule area)
examples/noncompliant/      — violates every rule, on purpose
examples/compliant/         — the same resources, fixed
scripts/check.sh            — plan + evaluate any given directory
```

## Try it

```bash
opa test policy/ -v                       # unit-test the policy itself, no Terraform needed
bash scripts/check.sh examples/noncompliant  # expect: FAIL, violations listed
bash scripts/check.sh examples/compliant     # expect: PASS
```

Verified output:

```
$ opa test policy/ -v
PASS: 11/11

$ bash scripts/check.sh examples/noncompliant
FAIL: policy violations in examples/noncompliant
["aws_db_instance.bad: RDS instance is publicly accessible",
 "aws_db_instance.bad: RDS instance storage is not encrypted",
 "aws_s3_bucket_acl.bad: S3 bucket ACL \"public-read\" grants public access",
 ... 14 total]

$ bash scripts/check.sh examples/compliant
PASS: no policy violations in examples/compliant
```

## Requirements

- Terraform >= 1.5.0
- [OPA](https://www.openpolicyagent.org/docs/latest/#running-opa) CLI

## CI

`.github/workflows/policy-guardrails-ci.yml` (repo root) runs `opa test`, then `scripts/check.sh` against both example directories, asserting the noncompliant one fails and the compliant one passes — so the gate's own correctness is checked on every push, not just its syntax.

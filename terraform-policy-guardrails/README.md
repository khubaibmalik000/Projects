# Terraform Policy Guardrails (OPA/Rego)

[![Policy Guardrails CI](https://github.com/khubaibmalik000/Projects/actions/workflows/policy-guardrails-ci.yml/badge.svg)](https://github.com/khubaibmalik000/Projects/actions/workflows/policy-guardrails-ci.yml)

Policy-as-code gate for Terraform: an [Open Policy Agent](https://www.openpolicyagent.org/) policy evaluates a `terraform plan` and **blocks the apply** if it would create insecure infrastructure — the same idea behind Sentinel/Conftest gates in a real platform team's pipeline, built from scratch in Rego.

It runs two ways:

1. **Local CLI** — `scripts/check.sh` plans a directory and evaluates it in one shot. Good for a single repo's own pipeline.
2. **Signed bundle served as a policy-decision API** — the same Rego, compiled and cryptographically signed into an OPA bundle, served over HTTP so *many* pipelines can query one centrally governed policy instead of every repo vendoring its own copy of the rules. This is the same distribution model tools like Styra DAS use in production.

## What it blocks

Every violation carries a rule id and severity (`critical` / `high` / `medium`), not just a message — see [Severity, structured reports & waivers](#severity-structured-reports--waivers) below.

| Rule id | Severity | Condition |
|---|---|---|
| `ssh-open-to-world` | critical | Security group ingress open to `0.0.0.0/0` on port 22 |
| `rds-publicly-accessible` | critical | `aws_db_instance` with `publicly_accessible = true` |
| `s3-bucket-public-acl` | critical | `aws_s3_bucket_acl` set to `public-read`, `public-read-write`, or `authenticated-read` |
| `iam-wildcard-policy` | critical | IAM policy statement granting `Action: "*"` on `Resource: "*"` (parsed out of the policy JSON document itself) |
| `rds-storage-not-encrypted` | high | `aws_db_instance` without `storage_encrypted = true` |
| `ebs-not-encrypted` | high | `aws_ebs_volume` without `encrypted = true` |
| `missing-mandatory-tags` | medium | Any taggable resource missing the mandatory `Environment` / `Owner` tags |

## How it works

```
terraform plan → terraform show -json → opa eval -d policy/ -i plan.json "data.terraform.guardrails.deny"
```

`terraform plan` runs fully offline (dummy credentials + `skip_credentials_validation`) — no AWS account needed to prove the gate works. If `deny` comes back non-empty, the plan is rejected.

## Structure

```
policy/terraform.rego              — the 7 guardrail rules + severity, waiver filtering, and the report
policy/waivers.rego                — documented, time-bound exceptions (see below)
policy/terraform_test.rego         — opa test unit tests (15 cases)
examples/noncompliant/             — violates every rule, on purpose
examples/compliant/                — the same resources, fixed
scripts/check.sh                   — local mode: plan + evaluate a directory, printing the report
scripts/build-signed-bundle.sh     — packages policy/ into an RS256-signed OPA bundle
scripts/serve.sh                   — serves the signed bundle as a live policy-decision API
scripts/query.sh                   — plans a directory and asks the running server for a decision
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
PASS: 15/15

$ bash scripts/check.sh examples/noncompliant
Report: {"by_severity":{"critical":4,"high":2,"medium":8},"total":14,"waived":0, ...}
FAIL: policy violations in examples/noncompliant
["aws_db_instance.bad: RDS instance is publicly accessible",
 "aws_db_instance.bad: RDS instance storage is not encrypted",
 "aws_s3_bucket_acl.bad: S3 bucket ACL \"public-read\" grants public access",
 ... 14 total]

$ bash scripts/check.sh examples/compliant
Report: {"by_severity":{"critical":0,"high":0,"medium":0},"total":0,"waived":0,"violations":[]}
PASS: no policy violations in examples/compliant
```

## Severity, structured reports & waivers

Every violation is a structured object (`rule`, `resource`, `severity`, `message`), not just a string — `data.terraform.guardrails.report` summarizes them:

```json
{
  "total": 14,
  "waived": 0,
  "by_severity": { "critical": 4, "high": 2, "medium": 8 },
  "violations": [ { "rule": "ssh-open-to-world", "resource": "aws_security_group.bad", "severity": "critical", "message": "..." }, ... ]
}
```

`deny` (the flat message list `check.sh`/`query.sh` gate on) stays backward compatible — it's just `report.violations` mapped to their `message` field, with waived violations already excluded.

**Waivers** (`policy/waivers.rego`) are documented, time-bound exceptions — never a blanket bypass. Each entry names the exact resource, the exact rule, an expiry timestamp, and a reason:

```rego
{
	"resource": "aws_security_group.bastion",
	"rule": "ssh-open-to-world",
	"expires": "2026-12-31T00:00:00Z",
	"reason": "Temporary bastion SSH access for the Q4 migration, approved by @platform-lead",
}
```

A waiver only suppresses that one rule on that one resource, and only until it expires — proven with real time-comparison tests, not just described: `test_waiver_suppresses_matching_violation_before_expiry`, `test_waiver_stops_suppressing_after_expiry`, and `test_waiver_does_not_suppress_a_different_resource` in `policy/terraform_test.rego` pin `input.now_ns` to specific instants before/after the expiry and assert the violation reappears once the waiver lapses.

## Signed bundle + policy decision server

Instead of every pipeline running its own copy of `policy/terraform.rego`, the policy can be compiled into a single **cryptographically signed bundle** and served centrally — pipelines query it over HTTP and never see the Rego source at all. OPA verifies the bundle's RS256 signature *before it will even load it*: a bundle that has been tampered with — or was never signed — is refused outright, not silently trusted.

```bash
bash scripts/build-signed-bundle.sh    # generates an RSA keypair (first run only) and signs bundle.tar.gz
bash scripts/serve.sh &                # serves it on :8181, verifying the signature on load
bash scripts/query.sh examples/noncompliant   # asks the server for a decision over HTTP
bash scripts/query.sh examples/compliant
```

Verified output:

```
$ bash scripts/build-signed-bundle.sh
Generated a new signing keypair in .keys/ (gitignored, not for reuse outside this demo)
Built and signed bundle.tar.gz against .keys/private.pem

$ bash scripts/serve.sh &
{"addrs":[":8181"], ... "msg":"Initializing server."}

$ bash scripts/query.sh examples/noncompliant
FAIL (via policy server): violations in examples/noncompliant
["aws_db_instance.bad: RDS instance is publicly accessible", ... 14 total]

$ bash scripts/query.sh examples/compliant
PASS (via policy server): no violations in examples/compliant
```

**The tamper-proof claim isn't just asserted — it's tested.** Take the signed bundle, modify a policy file inside it *without re-signing*, and try to load it:

```
$ opa run --server --bundle bundle.tampered.tar.gz --verification-key .keys/public.pem --verification-key-id portfolio-demo
error: load error: bundle bundle.tampered.tar.gz: file policy/terraform.rego not included in bundle signature
```

OPA refuses to start. This exact check runs in CI on every push — it's not a one-time manual test, it's a regression test for the security property itself.

## Requirements

- Terraform >= 1.5.0
- [OPA](https://www.openpolicyagent.org/docs/latest/#running-opa) CLI
- `openssl` and `curl` (only for the signed-bundle-server mode)

## CI

`.github/workflows/policy-guardrails-ci.yml` (repo root) runs three jobs on every push:

1. `opa test` — the policy's own unit tests (15 cases: guardrails, waiver expiry, report structure)
2. `scripts/check.sh` against both example directories (matrix), asserting the noncompliant one fails and the compliant one passes
3. **Signed Bundle + Policy Decision Server** — builds and signs a bundle, starts the server, queries it over HTTP for both examples, then deliberately tampers with the bundle and asserts OPA refuses to load it

So the gate's correctness *and* its supply-chain integrity guarantee are both checked on every push, not just its syntax.

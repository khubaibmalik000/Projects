# Terraform Policy Guardrails (OPA/Rego)

[![Policy Guardrails CI](https://github.com/khubaibmalik000/Projects/actions/workflows/policy-guardrails-ci.yml/badge.svg)](https://github.com/khubaibmalik000/Projects/actions/workflows/policy-guardrails-ci.yml)

Policy-as-code gate for Terraform: an [Open Policy Agent](https://www.openpolicyagent.org/) policy evaluates a `terraform plan` and **blocks the apply** if it would create insecure infrastructure — the same idea behind Sentinel/Conftest gates in a real platform team's pipeline, built from scratch in Rego.

It runs two ways:

1. **Local CLI** — `scripts/check.sh` plans a directory and evaluates it in one shot. Good for a single repo's own pipeline.
2. **Signed bundle served as a policy-decision API** — the same Rego, compiled and cryptographically signed into an OPA bundle, served over HTTP so *many* pipelines can query one centrally governed policy instead of every repo vendoring its own copy of the rules. This is the same distribution model tools like Styra DAS use in production.

## What it blocks

Every violation carries a rule id and severity (`critical` / `high` / `medium`), not just a message — see [Severity levels, structured reports, and waivers](#severity-levels-structured-reports-and-waivers) below.

| Rule id | Severity | Condition |
|---|---|---|
| `ssh-open-to-world` | critical | Security group ingress open to `0.0.0.0/0` on port 22 |
| `rds-publicly-accessible` | critical | `aws_db_instance` with `publicly_accessible = true` |
| `s3-bucket-public-acl` | critical | `aws_s3_bucket_acl` set to `public-read`, `public-read-write`, or `authenticated-read` |
| `iam-wildcard-policy` | critical | IAM policy statement granting `Action: "*"` on `Resource: "*"` (parsed out of the policy JSON document itself) |
| `no-destroy-critical-resource` | critical | Plan would **delete or replace** an `aws_db_instance`, `aws_ebs_volume`, or `aws_s3_bucket` — checks `change.actions`, not `change.after` (see below) |
| `rds-storage-not-encrypted` | high | `aws_db_instance` without `storage_encrypted = true` |
| `ebs-not-encrypted` | high | `aws_ebs_volume` without `encrypted = true` |
| `missing-mandatory-tags` | medium | Any taggable resource missing the mandatory `Environment` / `Owner` tags |

`no-destroy-critical-resource` is a different kind of check from the other six: it doesn't look at how a resource is *configured*, it looks at what the plan is about to *do* to it (`change.actions` — `["delete"]` for a destroy, `["delete","create"]`/`["create","delete"]` for a replace). Blast-radius protection, not attribute validation — a resource can be perfectly configured and still be one Terraform apply away from data loss if a `.tf` file gets edited wrong. Reproducing a real destroy/replace plan needs pre-existing Terraform state, which the example directories deliberately don't have (they're stateless, fully-offline `terraform plan` proofs) — so this rule is verified via `opa test` directly against the documented plan-JSON schema instead; see `policy/terraform_test.rego`.

## How it works

```text
terraform plan → terraform show -json → opa eval -d policy/ -i plan.json "data.terraform.guardrails.deny"
```

`terraform plan` runs fully offline (dummy credentials + `skip_credentials_validation`) — no AWS account needed to prove the gate works. If `deny` comes back non-empty, the plan is rejected.

## Structure

```text
policy/terraform.rego              — the 8 guardrail rules + severity, waiver filtering, and the report
policy/waivers.rego                — documented, time-bound exceptions (see below)
policy/terraform_test.rego         — opa test unit tests (21 cases)
examples/noncompliant/             — violates every rule, on purpose
examples/compliant/                — the same resources, fixed
scripts/check.sh                   — local mode: plan + evaluate a directory, printing the report
scripts/build-signed-bundle.sh     — packages policy/ into an RS256-signed OPA bundle
scripts/serve.sh                   — serves the signed bundle as a live policy-decision API
scripts/query.sh                   — plans a directory and asks the running server for a decision
.regal/config.yaml                 — Rego lint config (one rule deliberately ignored, documented inline)
.yamllint.yml                      — YAML lint config, tuned for GitHub Actions YAML
.pymarkdown.json                   — Markdown lint config (line-length disabled; doesn't fit this doc's style)
```

## Try it

```bash
opa test policy/ -v                       # unit-test the policy itself, no Terraform needed
bash scripts/check.sh examples/noncompliant  # expect: FAIL, violations listed
bash scripts/check.sh examples/compliant     # expect: PASS
```

Verified output:

```text
$ opa test policy/ -v
PASS: 21/21

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

## Severity levels, structured reports, and waivers

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

```text
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

```text
$ opa run --server --bundle bundle.tampered.tar.gz --verification-key .keys/public.pem --verification-key-id portfolio-demo
error: load error: bundle bundle.tampered.tar.gz: file policy/terraform.rego not included in bundle signature
```

OPA refuses to start. This exact check runs in CI on every push — it's not a one-time manual test, it's a regression test for the security property itself.

## Requirements

- Terraform >= 1.5.0
- [OPA](https://www.openpolicyagent.org/docs/latest/#running-opa) CLI
- `openssl` and `curl` (only for the signed-bundle-server mode)
- Optional, only to run the same checks CI does, locally: [Regal](https://github.com/open-policy-agent/regal), [ShellCheck](https://www.shellcheck.net/), [actionlint](https://github.com/rhysd/actionlint), [Gitleaks](https://github.com/gitleaks/gitleaks), `pip install yamllint pymarkdownlnt`

## CI

`.github/workflows/policy-guardrails-ci.yml` (repo root) runs 11 jobs (13 job runs, counting the two ×2 matrices) on every push:

### Policy correctness

1. **OPA Unit Tests** — `opa fmt --fail` (format check) then `opa test` (21 cases: guardrails, waiver expiry, report structure, blast-radius protection)
2. **Gate Check** (matrix ×2) — `scripts/check.sh` against both example directories, asserting the noncompliant one fails and the compliant one passes
3. **Signed Bundle + Policy Decision Server** — builds and signs a bundle, starts the server, queries it over HTTP for both examples, then deliberately tampers with the bundle and asserts OPA refuses to load it

### Code quality

1. **Rego Lint (Regal)** — [Regal](https://github.com/open-policy-agent/regal), the official Rego linter, at zero violations (`.regal/config.yaml` documents the one rule deliberately ignored, and why)
2. **ShellCheck** — lints all four `scripts/*.sh`
3. **Actionlint** — lints the workflow file itself (yes, the CI pipeline checks its own YAML)
4. **YAML Lint** — the workflow and `.regal/config.yaml`, with a config tuned for GitHub Actions YAML's known false-positive triggers (`.yamllint.yml`)
5. **Markdown Lint** — this README, via `pymarkdown` (`.pymarkdown.json`)
6. **Terraform Format & Validate** (matrix ×2) — `terraform fmt -check` + `terraform validate` against both example directories, standalone from the plan-based Gate Check

### Security

1. **Secret Scan (Gitleaks)** — scans the current working tree (not full git history — old commits predate a fix described below) for hardcoded credentials
2. **Checkov** — a second, independent security-scanning engine against `examples/compliant`, catching a different class of finding than the hand-written Rego rules (soft-fail, same convention as `terraform-aws-eks-platform`'s own CI)

So the gate's correctness, code quality, and supply-chain integrity guarantee — plus the CI pipeline's own YAML and this README — are all checked on every push, not just whether the Rego parses.

**A real finding this caught**: adding Gitleaks surfaced a hardcoded `password = "changeme12345"` in both example `.tf` files (a fake placeholder, not a real credential, but exactly the pattern a secret scanner exists to catch). Fixed by moving it to a `sensitive` Terraform variable instead — better practice regardless of the scanner, and the actual reason it's documented here rather than just quietly fixed.

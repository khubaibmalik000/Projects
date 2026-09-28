package terraform.guardrails

# Evaluates `terraform show -json <plan>` output and denies anything that
# violates a guardrail — run pre-apply so bad infra never gets created.
#
# Each rule below produces a structured violation (rule id, resource,
# severity, message) instead of a bare string, so violations can be
# filtered by severity, matched against waivers, and summarized in
# `report`. `deny` stays a flat set of message strings for backward
# compatibility with scripts/check.sh and scripts/query.sh.

resource_changes := input.resource_changes

# Callers may pin the evaluation clock (used for waiver expiry) via
# `input.now_ns` — the test suite does this for determinism. Falls back to
# wall-clock time for real `terraform plan` evaluation.
now_ns := object.get(input, "now_ns", time.now_ns())

raw_violations contains v if {
	some rc in resource_changes
	rc.type == "aws_security_group"
	some rule in rc.change.after.ingress
	rule.from_port <= 22
	rule.to_port >= 22
	some cidr in rule.cidr_blocks
	cidr == "0.0.0.0/0"
	v := violation("ssh-open-to-world", rc.address, "critical",
		sprintf("%s: security group ingress allows SSH (port 22) from 0.0.0.0/0", [rc.address]))
}

raw_violations contains v if {
	some rc in resource_changes
	rc.type == "aws_db_instance"
	rc.change.after.publicly_accessible == true
	v := violation("rds-publicly-accessible", rc.address, "critical",
		sprintf("%s: RDS instance is publicly accessible", [rc.address]))
}

raw_violations contains v if {
	some rc in resource_changes
	rc.type == "aws_db_instance"
	rc.change.after.storage_encrypted != true
	v := violation("rds-storage-not-encrypted", rc.address, "high",
		sprintf("%s: RDS instance storage is not encrypted", [rc.address]))
}

public_acls := {"public-read", "public-read-write", "authenticated-read"}

raw_violations contains v if {
	some rc in resource_changes
	rc.type == "aws_s3_bucket_acl"
	rc.change.after.acl in public_acls
	v := violation("s3-bucket-public-acl", rc.address, "critical",
		sprintf("%s: S3 bucket ACL %q grants public access", [rc.address, rc.change.after.acl]))
}

raw_violations contains v if {
	some rc in resource_changes
	rc.type == "aws_ebs_volume"
	rc.change.after.encrypted != true
	v := violation("ebs-not-encrypted", rc.address, "high",
		sprintf("%s: EBS volume is not encrypted", [rc.address]))
}

required_tags := {"Environment", "Owner"}

taggable_types := {"aws_security_group", "aws_db_instance", "aws_ebs_volume", "aws_instance", "aws_s3_bucket"}

raw_violations contains v if {
	some rc in resource_changes
	rc.type in taggable_types
	tags := object.get(rc.change.after, "tags", {})
	some tag in required_tags
	not tags[tag]
	v := violation("missing-mandatory-tags", rc.address, "medium",
		sprintf("%s: missing required tag %q", [rc.address, tag]))
}

raw_violations contains v if {
	some rc in resource_changes
	rc.type in {"aws_iam_policy", "aws_iam_role_policy"}
	policy := json.unmarshal(rc.change.after.policy)
	some stmt in policy.Statement
	stmt.Effect == "Allow"
	action_is_wildcard(stmt.Action)
	resource_is_wildcard(stmt.Resource)
	v := violation("iam-wildcard-policy", rc.address, "critical",
		sprintf("%s: IAM policy statement grants Action:\"*\" on Resource:\"*\"", [rc.address]))
}

action_is_wildcard(a) if a == "*"

action_is_wildcard(a) if a[_] == "*"

resource_is_wildcard(r) if r == "*"

resource_is_wildcard(r) if r[_] == "*"

violation(rule, resource, severity, message) := {
	"rule": rule,
	"resource": resource,
	"severity": severity,
	"message": message,
}

# A waiver suppresses one specific rule on one specific resource, and only
# until it expires — see policy/waivers.rego.
is_waived(v) if {
	some w in waivers
	w.resource == v.resource
	w.rule == v.rule
	time.parse_rfc3339_ns(w.expires) > now_ns
}

violations contains v if {
	some v in raw_violations
	not is_waived(v)
}

waived contains v if {
	some v in raw_violations
	is_waived(v)
}

deny contains v.message if some v in violations

severities := {"critical", "high", "medium"}

report := {
	"total": count(violations),
	"waived": count(waived),
	"by_severity": {sev: n |
		some sev in severities
		n := count([v | some v in violations; v.severity == sev])
	},
	"violations": violations,
}

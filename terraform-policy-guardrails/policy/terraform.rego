package terraform.guardrails

# Evaluates `terraform show -json <plan>` output and denies anything that
# violates a guardrail — run pre-apply so bad infra never gets created.

resource_changes := input.resource_changes

# No security group may allow SSH (22) from the whole internet.
deny contains msg if {
	some rc in resource_changes
	rc.type == "aws_security_group"
	some rule in rc.change.after.ingress
	rule.from_port <= 22
	rule.to_port >= 22
	some cidr in rule.cidr_blocks
	cidr == "0.0.0.0/0"
	msg := sprintf("%s: security group ingress allows SSH (port 22) from 0.0.0.0/0", [rc.address])
}

# RDS instances must not be publicly accessible.
deny contains msg if {
	some rc in resource_changes
	rc.type == "aws_db_instance"
	rc.change.after.publicly_accessible == true
	msg := sprintf("%s: RDS instance is publicly accessible", [rc.address])
}

# RDS storage must be encrypted at rest.
deny contains msg if {
	some rc in resource_changes
	rc.type == "aws_db_instance"
	rc.change.after.storage_encrypted != true
	msg := sprintf("%s: RDS instance storage is not encrypted", [rc.address])
}

# S3 bucket ACLs must not grant public read/write.
public_acls := {"public-read", "public-read-write", "authenticated-read"}

deny contains msg if {
	some rc in resource_changes
	rc.type == "aws_s3_bucket_acl"
	rc.change.after.acl in public_acls
	msg := sprintf("%s: S3 bucket ACL %q grants public access", [rc.address, rc.change.after.acl])
}

# EBS volumes must be encrypted at rest.
deny contains msg if {
	some rc in resource_changes
	rc.type == "aws_ebs_volume"
	rc.change.after.encrypted != true
	msg := sprintf("%s: EBS volume is not encrypted", [rc.address])
}

# Taggable resources must carry the org's mandatory tags.
required_tags := {"Environment", "Owner"}

taggable_types := {"aws_security_group", "aws_db_instance", "aws_ebs_volume", "aws_instance", "aws_s3_bucket"}

deny contains msg if {
	some rc in resource_changes
	rc.type in taggable_types
	tags := object.get(rc.change.after, "tags", {})
	some tag in required_tags
	not tags[tag]
	msg := sprintf("%s: missing required tag %q", [rc.address, tag])
}

# IAM policies must not grant Action:"*" on Resource:"*".
deny contains msg if {
	some rc in resource_changes
	rc.type in {"aws_iam_policy", "aws_iam_role_policy"}
	policy := json.unmarshal(rc.change.after.policy)
	some stmt in policy.Statement
	stmt.Effect == "Allow"
	action_is_wildcard(stmt.Action)
	resource_is_wildcard(stmt.Resource)
	msg := sprintf("%s: IAM policy statement grants Action:\"*\" on Resource:\"*\"", [rc.address])
}

action_is_wildcard(a) if a == "*"

action_is_wildcard(a) if a[_] == "*"

resource_is_wildcard(r) if r == "*"

resource_is_wildcard(r) if r[_] == "*"

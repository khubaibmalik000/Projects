package terraform.guardrails_test

import data.terraform.guardrails.deny
import data.terraform.guardrails.report

good_tags := {"Environment": "dev", "Owner": "platform-team"}

test_denies_ssh_open_to_world if {
	plan := {"resource_changes": [{
		"address": "aws_security_group.bad",
		"type": "aws_security_group",
		"change": {"after": {
			"tags": good_tags,
			"ingress": [{"from_port": 22, "to_port": 22, "cidr_blocks": ["0.0.0.0/0"]}],
		}},
	}]}

	violations := deny with input as plan
	count(violations) == 1
}

test_allows_ssh_from_restricted_cidr if {
	plan := {"resource_changes": [{
		"address": "aws_security_group.good",
		"type": "aws_security_group",
		"change": {"after": {
			"tags": good_tags,
			"ingress": [{"from_port": 22, "to_port": 22, "cidr_blocks": ["10.0.0.0/16"]}],
		}},
	}]}

	violations := deny with input as plan
	count(violations) == 0
}

test_denies_public_rds if {
	plan := {"resource_changes": [{
		"address": "aws_db_instance.bad",
		"type": "aws_db_instance",
		"change": {"after": {"tags": good_tags, "publicly_accessible": true, "storage_encrypted": true}},
	}]}

	violations := deny with input as plan
	count(violations) == 1
}

test_denies_unencrypted_rds_storage if {
	plan := {"resource_changes": [{
		"address": "aws_db_instance.bad",
		"type": "aws_db_instance",
		"change": {"after": {"tags": good_tags, "publicly_accessible": false, "storage_encrypted": false}},
	}]}

	violations := deny with input as plan
	count(violations) == 1
}

test_allows_encrypted_private_rds if {
	plan := {"resource_changes": [{
		"address": "aws_db_instance.good",
		"type": "aws_db_instance",
		"change": {"after": {"tags": good_tags, "publicly_accessible": false, "storage_encrypted": true}},
	}]}

	violations := deny with input as plan
	count(violations) == 0
}

test_denies_public_s3_acl if {
	plan := {"resource_changes": [{
		"address": "aws_s3_bucket_acl.bad",
		"type": "aws_s3_bucket_acl",
		"change": {"after": {"acl": "public-read"}},
	}]}

	violations := deny with input as plan
	count(violations) == 1
}

test_allows_private_s3_acl if {
	plan := {"resource_changes": [{
		"address": "aws_s3_bucket_acl.good",
		"type": "aws_s3_bucket_acl",
		"change": {"after": {"acl": "private"}},
	}]}

	violations := deny with input as plan
	count(violations) == 0
}

test_denies_unencrypted_ebs if {
	plan := {"resource_changes": [{
		"address": "aws_ebs_volume.bad",
		"type": "aws_ebs_volume",
		"change": {"after": {"tags": good_tags, "encrypted": false}},
	}]}

	violations := deny with input as plan
	count(violations) == 1
}

test_denies_missing_mandatory_tags if {
	plan := {"resource_changes": [{
		"address": "aws_ebs_volume.untagged",
		"type": "aws_ebs_volume",
		"change": {"after": {"tags": {}, "encrypted": true}},
	}]}

	violations := deny with input as plan
	count(violations) == 2 # missing both Environment and Owner
}

test_denies_wildcard_iam_policy if {
	plan := {"resource_changes": [{
		"address": "aws_iam_policy.bad",
		"type": "aws_iam_policy",
		"change": {"after": {"policy": "{\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"*\",\"Resource\":\"*\"}]}"}},
	}]}

	violations := deny with input as plan
	count(violations) == 1
}

test_allows_scoped_iam_policy if {
	plan := {"resource_changes": [{
		"address": "aws_iam_policy.good",
		"type": "aws_iam_policy",
		"change": {"after": {"policy": "{\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::my-bucket/*\"}]}"}},
	}]}

	violations := deny with input as plan
	count(violations) == 0
}

# --- Waivers (policy/waivers.rego has one entry: aws_security_group.bastion,
# rule ssh-open-to-world, expires 2026-12-31T00:00:00Z) ---

bastion_ssh_open(now) := {
	"now_ns": time.parse_rfc3339_ns(now),
	"resource_changes": [{
		"address": "aws_security_group.bastion",
		"type": "aws_security_group",
		"change": {"after": {
			"tags": good_tags,
			"ingress": [{"from_port": 22, "to_port": 22, "cidr_blocks": ["0.0.0.0/0"]}],
		}},
	}],
}

test_waiver_suppresses_matching_violation_before_expiry if {
	violations := deny with input as bastion_ssh_open("2026-06-01T00:00:00Z")
	count(violations) == 0
}

test_waiver_stops_suppressing_after_expiry if {
	violations := deny with input as bastion_ssh_open("2027-01-01T00:00:00Z")
	count(violations) == 1
}

test_waiver_does_not_suppress_a_different_resource if {
	plan := {
		"now_ns": time.parse_rfc3339_ns("2026-06-01T00:00:00Z"),
		"resource_changes": [{
			"address": "aws_security_group.other", # not the waived address
			"type": "aws_security_group",
			"change": {"after": {
				"tags": good_tags,
				"ingress": [{"from_port": 22, "to_port": 22, "cidr_blocks": ["0.0.0.0/0"]}],
			}},
		}],
	}

	violations := deny with input as plan
	count(violations) == 1
}

# --- Structured report (severity breakdown + waived count) ---

test_report_reflects_severity_and_waived_counts if {
	plan := {
		"now_ns": time.parse_rfc3339_ns("2026-06-01T00:00:00Z"),
		"resource_changes": [
			{
				"address": "aws_security_group.bastion", # waived, excluded from counts
				"type": "aws_security_group",
				"change": {"after": {
					"tags": good_tags,
					"ingress": [{"from_port": 22, "to_port": 22, "cidr_blocks": ["0.0.0.0/0"]}],
				}},
			},
			{
				"address": "aws_db_instance.bad", # critical, not waived
				"type": "aws_db_instance",
				"change": {"after": {"tags": good_tags, "publicly_accessible": true, "storage_encrypted": true}},
			},
		],
	}

	r := report with input as plan
	r.total == 1
	r.waived == 1
	r.by_severity.critical == 1
	r.by_severity.high == 0
	r.by_severity.medium == 0
}

# --- Blast-radius protection (change.actions, not change.after) ---

critical_resource_plan(actions) := {"resource_changes": [{
	"address": "aws_db_instance.prod",
	"type": "aws_db_instance",
	"change": {"actions": actions, "after": {"tags": good_tags, "publicly_accessible": false, "storage_encrypted": true}},
}]}

test_denies_straight_destroy_of_critical_resource if {
	violations := deny with input as critical_resource_plan(["delete"])
	count(violations) == 1
}

test_denies_replace_of_critical_resource if {
	violations := deny with input as critical_resource_plan(["delete", "create"])
	count(violations) == 1
}

test_allows_in_place_update_of_critical_resource if {
	violations := deny with input as critical_resource_plan(["update"])
	count(violations) == 0
}

test_allows_create_of_critical_resource if {
	violations := deny with input as critical_resource_plan(["create"])
	count(violations) == 0
}

test_allows_no_op_of_critical_resource if {
	violations := deny with input as critical_resource_plan(["no-op"])
	count(violations) == 0
}

test_does_not_flag_destroy_of_a_non_critical_resource_type if {
	plan := {"resource_changes": [{
		"address": "aws_security_group.temp",
		"type": "aws_security_group",
		"change": {"actions": ["delete"], "after": null},
	}]}

	violations := deny with input as plan
	count(violations) == 0
}

package terraform.guardrails_test

import data.terraform.guardrails.deny

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

package terraform.guardrails

# Documented, time-bound exceptions. Each entry suppresses ONE specific
# rule on ONE specific resource, and only until `expires` — never a
# blanket bypass, and never silent (the reason/approver are part of the
# record). An expired waiver stops suppressing anything automatically;
# nothing needs to remember to remove it.
waivers := [
	{
		"resource": "aws_security_group.bastion",
		"rule": "ssh-open-to-world",
		"expires": "2026-12-31T00:00:00Z",
		"reason": "Temporary bastion SSH access for the Q4 migration, approved by @platform-lead",
	},
]

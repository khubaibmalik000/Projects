output "cluster_role_arn" {
  description = "ARN of the EKS cluster (control plane) IAM role"
  value       = aws_iam_role.cluster.arn
}

output "node_role_arn" {
  description = "ARN of the EKS node group IAM role"
  value       = aws_iam_role.node.arn
}

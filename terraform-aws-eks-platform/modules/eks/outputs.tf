output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the cluster"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS control plane"
  value       = aws_security_group.cluster.id
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider, for wiring up IRSA roles"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "node_group_status" {
  description = "Status of the default managed node group"
  value       = aws_eks_node_group.default.status
}

# Terraform AWS EKS Platform

[![Terraform CI](https://github.com/khubaibmalik000/Projects/actions/workflows/terraform-ci.yml/badge.svg)](https://github.com/khubaibmalik000/Projects/actions/workflows/terraform-ci.yml)

A modular, environment-aware Terraform project that provisions a production-grade Amazon EKS platform from scratch: networking, IAM, and the Kubernetes control plane + managed node group — structured the way a real infrastructure team would organize it, not a single flat `main.tf`.

## Architecture

```
                         ┌─────────────────────────────┐
                         │           VPC                │
                         │  ┌───────────┐ ┌───────────┐ │
                         │  │  Public   │ │  Public   │ │   Internet Gateway
                         │  │ Subnet AZ1│ │ Subnet AZ2│ │◄──────────────────
                         │  └─────┬─────┘ └─────┬─────┘ │
                         │        │ NAT GW       │ NAT GW│
                         │  ┌─────▼─────┐ ┌─────▼─────┐ │
                         │  │  Private  │ │  Private  │ │
                         │  │ Subnet AZ1│ │ Subnet AZ2│ │
                         │  │  (nodes)  │ │  (nodes)  │ │
                         │  └───────────┘ └───────────┘ │
                         └──────────────┬───────────────┘
                                        │
                              ┌─────────▼─────────┐
                              │   EKS Control      │
                              │   Plane + OIDC      │
                              │   + Managed Node    │
                              │   Group             │
                              └────────────────────┘
```

## Structure

```
terraform-aws-eks-platform/
├── modules/
│   ├── vpc/     — VPC, public/private subnets across AZs, IGW, NAT Gateway(s), route tables
│   ├── iam/     — IAM roles for the EKS control plane and worker nodes
│   └── eks/     — EKS cluster, managed node group, cluster security group, OIDC provider (for IRSA)
├── environments/
│   ├── dev/     — smaller, cost-optimized (single NAT GW, SPOT nodes)
│   └── prod/    — HA (NAT GW per AZ), on-demand nodes, 3 AZs
├── bootstrap/   — one-time setup: S3 bucket + DynamoDB table for remote state
└── .github/workflows/terraform-ci.yml (at repo root) — fmt/validate/lint/security-scan on every push
```

## Usage

```bash
# 1. One-time: create the remote state backend
cd bootstrap
terraform init && terraform apply -var="state_bucket_name=your-unique-bucket-name"

# 2. Update environments/<env>/backend.tf with your bucket name, then:
cd ../environments/dev
terraform init
terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars

# 3. Point kubectl at the new cluster (see the configure_kubectl output)
aws eks update-kubeconfig --region us-east-1 --name platform-dev
```

## Design decisions

- **Modules over copy-paste**: `vpc`/`iam`/`eks` are reusable building blocks; `dev` and `prod` just wire them together with different inputs.
- **Private worker nodes**: nodes run in private subnets with no public IPs; only the EKS-managed control plane ENIs and load balancers touch public subnets.
- **IRSA-ready**: an OIDC provider is created alongside the cluster so pods can later assume fine-grained IAM roles via service account annotations, instead of sharing the node's IAM role.
- **Cost vs. HA tradeoff, made explicit per environment**: `dev` uses a single shared NAT Gateway and SPOT capacity; `prod` uses one NAT Gateway per AZ and on-demand capacity across 3 AZs.
- **State locking**: remote state in S3 with DynamoDB-backed locking, so concurrent `apply` runs can't corrupt state.

## Requirements

- Terraform >= 1.5.0
- An AWS account with permissions to create VPC/IAM/EKS resources
- `aws` CLI and `kubectl` for interacting with the cluster after creation

## CI

Every push/PR touching this directory runs through `terraform fmt -check`, `terraform validate`, `tflint`, and a `checkov` security scan via GitHub Actions (see the repo-root `.github/workflows/terraform-ci.yml`).

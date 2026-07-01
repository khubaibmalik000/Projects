provider "aws" {
  region = var.region
}

locals {
  tags = {
    Environment = var.environment
    Project     = "eks-platform"
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name                 = var.cluster_name
  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = true # cheaper for a dev environment
  tags                 = local.tags
}

module "iam" {
  source = "../../modules/iam"

  name = var.cluster_name
  tags = local.tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name        = var.cluster_name
  cluster_version     = var.cluster_version
  cluster_role_arn    = module.iam.cluster_role_arn
  node_role_arn       = module.iam.node_role_arn
  subnet_ids          = module.vpc.private_subnet_ids
  node_instance_types = var.node_instance_types
  node_capacity_type  = "SPOT" # cost-optimized for dev
  desired_size        = var.node_desired_size
  min_size            = var.node_min_size
  max_size            = var.node_max_size
  tags                = local.tags
}

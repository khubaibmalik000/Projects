region       = "us-east-1"
environment  = "prod"
cluster_name = "platform-prod"

azs                  = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnet_cidrs  = ["10.1.0.0/24", "10.1.1.0/24", "10.1.2.0/24"]
private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24", "10.1.12.0/24"]

node_instance_types = ["m5.large"]
node_desired_size   = 3
node_min_size       = 3
node_max_size       = 10

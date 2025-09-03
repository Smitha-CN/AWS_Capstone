module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
  database_subnets = var.database_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true    
  one_nat_gateway_per_az = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  create_database_subnet_group = true

  tags = local.tags
}

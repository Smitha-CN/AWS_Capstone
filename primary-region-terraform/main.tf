terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}
data "aws_availability_zones" "az" {}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "three-tier-vpc" }
}
resource "aws_internet_gateway" "igw" { vpc_id = aws_vpc.main.id }
resource "aws_eip" "nat" { domain = "vpc" }
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
}
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.az.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name                                       = "PublicSubnet${count.index + 1}"
    "kubernetes.io/role/elb"                   = "1"
    "kubernetes.io/cluster/three-tier-cluster" = "shared"
  }
}
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 2)
  availability_zone = data.aws_availability_zones.az.names[count.index]
  tags = {
    Name                                       = "PrivateSubnet${count.index + 1}"
    "kubernetes.io/role/internal-elb"          = "1"
    "kubernetes.io/cluster/three-tier-cluster" = "shared"
  }
}
# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}


resource "aws_s3_bucket" "artifact" {
  bucket = "three-tier-cft-pipeline-artifacts-${random_id.rand.hex}"
}
resource "random_id" "rand" { byte_length = 4 }



resource "aws_security_group" "rds_sg" {
  name        = "rds-mysql-sg"
  description = "Allow MySQL from VPC"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  tags = { Name = "rds-mysql-sg" }
}
resource "aws_db_subnet_group" "rds_subnet" {
  name       = "three-tier-db-subnet-group"
  subnet_ids = aws_subnet.private.*.id
}
resource "aws_db_instance" "mysql" {
  identifier              = "three-tier-mysql"
  engine                  = "mysql"
  engine_version          = "8.0.36"
  instance_class          = "db.t3.small"
  allocated_storage       = 20
  username                = var.db_username
  password                = var.db_password
  vpc_security_group_ids  = [aws_security_group.rds_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.rds_subnet.name
  publicly_accessible     = false
  multi_az                = false
  backup_retention_period = 1
  tags                    = { Name = "three-tier-rds-instance" }
}






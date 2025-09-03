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
  tags = { Name = "three-tier-vpc" }
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
  
}
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index+2)
  availability_zone = data.aws_availability_zones.az.names[count.index]
  
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
    cidr_block = "0.0.0.0/0"
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
 
resource "aws_ecr_repository" "frontend" {
name = "frontend"
}
resource "aws_ecr_repository" "backend"  { 
name = "backend"
}
 
resource "aws_iam_role" "codebuild_role" {
  name = "CodeBuildServiceRole_tf"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "codebuild.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}
 
resource "aws_iam_role_policy_attachment" "codebuild_policy_attachments" {
  for_each = toset([
    "AmazonEC2ContainerRegistryPowerUser",
    "AmazonS3FullAccess",
    "AdministratorAccess",
    "AWSCodeBuildDeveloperAccess",
    "AWSCodeBuildAdminAccess"
  ])
 
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/${each.value}"
}
resource "aws_codebuild_project" "build" {
  name         = "ThreeTierAppBuildProject"
  service_role = aws_iam_role.codebuild_role.arn
  artifacts { type = "CODEPIPELINE" }
  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:6.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
    environment_variable {
      name  = "ACCOUNT_ID"
      value = "${data.aws_caller_identity.current.account_id}"
    }
    environment_variable {
      name  = "REGION"
      value = var.region
    }
  
  }
  source {
    type = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
  build_timeout = 30
}
data "aws_caller_identity" "current" {}
 
resource "aws_codebuild_project" "deploy" {
  name         = "ThreeTierDeployProject"
  service_role = aws_iam_role.codepipeline_deploy_role.arn
 
  artifacts {
    type = "CODEPIPELINE"
  }
 
    environment_variable {
      name  = "REGION"
      value = var.region
    }
  }
 
  source {
    type = "CODEPIPELINE"
    buildspec = "buildspec-deploy.yml"
  }
 
  build_timeout = 30
}

 

 


 
 
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
  tags = { Name = "three-tier-rds-instance" }
}
 
 
resource "aws_iam_role" "codepipeline_service_role" {
  name = "CodePipelineServiceRole-tf"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}


resource "aws_iam_role_policy_attachment" "codepipeline_service_policy_attachment" {
  role       = aws_iam_role.codepipeline_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
 
resource "aws_iam_role_policy" "codepipeline_inline_policy" {
  name   = "CodePipelineFullAccess"
  role   = aws_iam_role.codepipeline_service_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:*", "codebuild:*", "codecommit:*", "codedeploy:*",
          "codestar-connections:UseConnection", "iam:PassRole", "eks:Describe*"
        ]
        Resource = "*"
      }
    ]
  })
}
resource "aws_iam_role" "codepipeline_deploy_role" {
  name = "CodePipelineEKSDeployRole-tf"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
  tags = {
    Name = "three-tier-codepipeline-deploy-role"
  }
}
 
resource "aws_iam_role_policy_attachment" "codepipeline_deploy_role_attachments" {
  for_each = toset([
    "AmazonEKSClusterPolicy",
    "AmazonEKSWorkerNodePolicy",
    "AmazonEC2ContainerRegistryPowerUser",
    "AmazonS3FullAccess",
    "CloudWatchFullAccess",
    "AWSCodeBuildDeveloperAccess",
    "AdministratorAccess"
  ])
 
  role       = aws_iam_role.codepipeline_deploy_role.name
  policy_arn = "arn:aws:iam::aws:policy/${each.value}"
}
  
resource "aws_codepipeline" "pipeline" {
  name     = "ThreeTierPipeline"
  role_arn = aws_iam_role.codepipeline_service_role.arn
  artifact_store {
    location = aws_s3_bucket.artifact.bucket
    type     = "S3"
  }
  stage {
    name = "Source"
    action {
      name             = "GitHubSource"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]
      configuration = {
        ConnectionArn     = var.github_connection_arn
        FullRepositoryId  = var.github_repo
        BranchName        = var.github_branch
        DetectChanges     = "true"
      }
      run_order = 1
    }
  }
  stage {
    name = "Build"
    action {
      name             = "CodeBuildBuild"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]
      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
      run_order = 1
    }
  }
  stage {
    name = "Deploy"
    action {
      name             = "DeployWithCodeBuild"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["BuildOutput"]
      configuration = {
        ProjectName = aws_codebuild_project.deploy.name
      }
      run_order = 1
    }
  }
 
}
 
 
 
output "vpc_id"     { value = aws_vpc.main.id }
output "eks_endpoint" { value = aws_eks_cluster.cluster.endpoint }
output "rds_endpoint" { value = aws_db_instance.mysql.address }

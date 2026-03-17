terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "aurora_postgresql" {
  source = "../.."

  project_short_name = "demo"
  environment_name   = "prd"
  environment_tier   = "Production"
  engine_version     = "16.3"

  min_capacity        = 1
  max_capacity        = 4
  instance_count      = 2
  deletion_protection = true

  backup_central_account_id      = "123456789012"
  backup_cross_account_role_name = "AWSServiceRoleForBackup"
  enable_http_endpoint           = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"

  name             = "aw-demo-euw2-dev-vpc-main"
  cidr             = "10.0.0.0/16"
  azs              = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
  private_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  database_subnets = ["10.0.50.0/24", "10.0.51.0/24", "10.50.52.0/24"]
  public_subnets   = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  private_subnet_tags = {
    "Type" = "Private"
  }

  public_subnet_tags = {
    "Type" = "Public"
  }

  database_subnet_tags = {
    "Type" = "Database"
  }
}

output "db_master_secret_arn" {
  value = module.aurora_postgresql.db_master_secret_arn
}

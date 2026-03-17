

locals {
  aws_region_short_map = {
    eu-west-2 = "euw2"
    eu-west-1 = "euw1"
    us-east-1 = "use1"
  }
  aws_short_region = lookup(local.aws_region_short_map, data.aws_region.current.region, replace(data.aws_region.current.region, "-", ""))
  name_prefix      = "aw-${var.project_short_name}-${local.aws_short_region}-${var.environment_name}"
  cluster_name     = "${local.name_prefix}-rds-pg"
  db_port          = 5432

  names = {
    vpc_main              = "${local.name_prefix}-vpc-main"
    cluster               = local.cluster_name
    bastion_ec2           = "${local.name_prefix}-ec2-bastion"
    bastion_role          = "${local.name_prefix}-iamrole-db-bastion"
    bastion_instance_prof = "${local.name_prefix}-instanceprofile-db-bastion"
    bastion_sg            = "${local.name_prefix}-sg-bastion"
    cluster_param_group   = local.cluster_name
  }

  environment_defaults = {
    Development = {
      backup_retention_period      = 7
      preferred_backup_window      = "03:00-04:00"
      preferred_maintenance_window = "sun:04:00-sun:05:00"
    }
    PreProduction = {
      backup_retention_period      = 14
      preferred_backup_window      = "02:00-03:00"
      preferred_maintenance_window = "sun:03:00-sun:04:00"
    }
    Production = {
      backup_retention_period      = 35
      preferred_backup_window      = "01:00-02:00"
      preferred_maintenance_window = "sun:02:00-sun:03:00"
    }
  }

  selected_environment_defaults = local.environment_defaults[var.environment_tier]
  engine_major_version          = regex("^\\d+", var.engine_version)
  aurora_instances = {
    for i in range(var.instance_count) : "instance-${i + 1}" => {
      auto_minor_version_upgrade = true
      publicly_accessible        = false
    }
  }
  control_tower_backup_tag_flags = {
    aws-control-tower-backuphourly  = var.enable_control_tower_backup_hourly
    aws-control-tower-backupdaily   = var.enable_control_tower_backup_daily
    aws-control-tower-backupweekly  = var.enable_control_tower_backup_weekly
    aws-control-tower-backupmonthly = var.enable_control_tower_backup_monthly
  }
}

check "window_separation" {
  assert {
    condition = coalesce(var.preferred_backup_window, local.selected_environment_defaults.preferred_backup_window) != coalesce(
      var.preferred_maintenance_window,
      local.selected_environment_defaults.preferred_maintenance_window
    )
    error_message = "preferred_backup_window and preferred_maintenance_window must not be identical."
  }
}

check "production_backup_tags_enabled" {
  assert {
    condition = var.environment_tier != "Production" || (
      var.enable_control_tower_backup_hourly ||
      var.enable_control_tower_backup_daily ||
      var.enable_control_tower_backup_weekly ||
      var.enable_control_tower_backup_monthly
    )
    error_message = "For Production, at least one Control Tower backup schedule tag must be enabled."
  }
}

################################################################################
# Data Lookups
################################################################################
data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = [local.names.vpc_main]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  filter {
    name   = "tag:Type"
    values = ["Private"]
  }
}

data "aws_subnets" "database" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  filter {
    name   = "tag:Type"
    values = ["Database"]
  }
}

data "aws_db_subnet_group" "db" {
  name = coalesce(var.db_subnet_group_name, local.names.vpc_main)
}

data "aws_subnet" "private" {
  for_each = toset(data.aws_subnets.private.ids)
  id       = each.value
}

check "private_subnets_present" {
  assert {
    condition     = length(data.aws_subnets.private.ids) > 0
    error_message = "No subnets tagged Type=Private were found in the target VPC."
  }
}

check "database_subnets_present" {
  assert {
    condition     = length(data.aws_subnets.database.ids) > 0
    error_message = "No subnets tagged Type=Database were found in the target VPC."
  }
}

################################################################################
# RDS
################################################################################
data "aws_rds_engine_version" "postgresql" {
  engine  = "aurora-postgresql"
  version = var.engine_version
}

module "cluster" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "10.2.0"

  name                                = local.names.cluster
  engine                              = data.aws_rds_engine_version.postgresql.engine
  engine_mode                         = "provisioned"
  engine_version                      = data.aws_rds_engine_version.postgresql.version
  storage_encrypted                   = true
  kms_key_id                          = module.kms.key_arn
  master_username                     = var.master_username
  manage_master_user_password         = true
  iam_database_authentication_enabled = true

  master_user_password_rotation_automatically_after_days = 30

  deletion_protection = var.deletion_protection

  backup_retention_period      = coalesce(var.backup_retention_period, local.selected_environment_defaults.backup_retention_period)
  preferred_backup_window      = coalesce(var.preferred_backup_window, local.selected_environment_defaults.preferred_backup_window)
  preferred_maintenance_window = coalesce(var.preferred_maintenance_window, local.selected_environment_defaults.preferred_maintenance_window)

  vpc_id               = data.aws_vpc.main.id
  db_subnet_group_name = data.aws_db_subnet_group.db.name

  cluster_parameter_group = {
    name        = local.names.cluster_param_group
    family      = "aurora-postgresql${local.engine_major_version}"
    description = "Opinionated security baseline for ${local.names.cluster}"
    parameters = [
      {
        name         = "log_min_duration_statement"
        value        = 4000
        apply_method = "immediate"
      },
      {
        name         = "rds.force_ssl"
        value        = 1
        apply_method = "immediate"
      },
      {
        name         = "log_disconnections"
        value        = "1"
        apply_method = "immediate"
      },
      {
        name         = "log_connections"
        value        = "1"
        apply_method = "immediate"
      }
    ]
  }

  security_group_ingress_rules = {
    for idx, cidr in [for s in data.aws_subnet.private : s.cidr_block] :
    "private_subnet_${idx}" => {
      description = "Private subnet DB access"
      from_port   = local.db_port
      to_port     = local.db_port
      cidr_ipv4   = cidr
      ip_protocol = "tcp"
    }
  }
  security_group_egress_rules = {
    self_only = {
      description                  = "Allow egress only to the Aurora cluster security group"
      ip_protocol                  = "-1"
      from_port                    = -1
      to_port                      = -1
      referenced_security_group_id = "self"
    }
  }

  create_cloudwatch_log_group                   = true
  cluster_performance_insights_enabled          = true
  cluster_performance_insights_retention_period = 7
  create_monitoring_role                        = true
  cluster_monitoring_interval                   = 60

  apply_immediately = false

  enable_http_endpoint = var.enable_http_endpoint

  serverlessv2_scaling_configuration = {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  cluster_instance_class = "db.serverless"
  instances              = local.aurora_instances

  cluster_tags = {
    for tag_name, enabled in local.control_tower_backup_tag_flags :
    tag_name => "true" if enabled
  }
}

module "kms" {
  source  = "terraform-aws-modules/kms/aws"
  version = "4.2.0"

  deletion_window_in_days = 7
  enable_key_rotation     = true
  is_enabled              = true
  key_usage               = "ENCRYPT_DECRYPT"

  aliases = ["rds/${local.names.cluster}"]

  key_statements = var.backup_cross_account_role_name == null ? {} : {
    AllowUseOfKeyByAuthorizedBackupPrincipal = {
      sid    = "AllowUseOfKeyByAuthorizedBackupPrincipal"
      effect = "Allow"
      actions = [
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey",
        "kms:GenerateDataKeyWithoutPlaintext"
      ]
      resources = ["*"]
      principals = [
        {
          type        = "AWS"
          identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.backup_cross_account_role_name}"]
        }
      ]
      condition = [
        {
          test     = "StringEquals"
          variable = "kms:ViaService"
          values   = ["backup.amazonaws.com"]
        }
      ]
    }
  }
}

################################################################################
# Developer bastion
################################################################################
################################################################################
# SSM Bastion
################################################################################
data "aws_ami" "amazon_linux_23" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }
}

resource "aws_instance" "bastion_ec2" {
  ami                         = data.aws_ami.amazon_linux_23.id
  instance_type               = "t2.micro"
  subnet_id                   = sort(data.aws_subnets.private.ids)[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  disable_api_termination     = false
  associate_public_ip_address = false

  iam_instance_profile = aws_iam_instance_profile.bastion_ssm_profile.name

  root_block_device {
    encrypted = true
  }

  monitoring = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name = local.names.bastion_ec2
  }
}

resource "aws_iam_role" "bastion_ssm_role" {
  name = local.names.bastion_role

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm_attach" {
  role       = aws_iam_role.bastion_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_security_group" "bastion" {
  name        = local.names.bastion_sg
  description = "Allow outbound connections from Bastion server"
  vpc_id      = data.aws_vpc.main.id
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.bastion.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_iam_instance_profile" "bastion_ssm_profile" {
  name = local.names.bastion_instance_prof
  role = aws_iam_role.bastion_ssm_role.name
}

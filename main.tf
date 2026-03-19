

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
  backup_kms_principal_identifiers = var.backup_central_account_id == null ? [] : [
    "arn:aws:iam::${var.backup_central_account_id}:role/aws-service-role/backup.amazonaws.com/AWSServiceRoleForBackup",
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  ]
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

data "aws_rds_engine_version" "postgresql" {
  engine  = "aurora-postgresql"
  version = var.engine_version
}
data "aws_iam_policy_document" "monitoring_rds_assume_role" {


  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = [data.aws_service_principal.monitoring_rds.name]
    }
  }
}

data "aws_partition" "current" {}

data "aws_service_principal" "monitoring_rds" {
  service_name = "monitoring.rds"
}

################################################################################
# RDS Cluster
################################################################################
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name                  = "${local.names.cluster}-monitor"
  assume_role_policy    = data.aws_iam_policy_document.monitoring_rds_assume_role.json
  force_detach_policies = true
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_rds_cluster" "this" {
  engine                              = data.aws_rds_engine_version.postgresql.engine
  engine_mode                         = "provisioned"
  engine_version                      = data.aws_rds_engine_version.postgresql.version
  storage_encrypted                   = true
  kms_key_id                          = module.kms.key_arn
  master_username                     = var.master_username
  manage_master_user_password         = true
  iam_database_authentication_enabled = true

  deletion_protection = var.deletion_protection

  cluster_identifier                    = local.names.cluster
  copy_tags_to_snapshot                 = true
  backup_retention_period               = coalesce(var.backup_retention_period, local.selected_environment_defaults.backup_retention_period)
  db_cluster_parameter_group_name       = aws_rds_cluster_parameter_group.this.id
  db_subnet_group_name                  = data.aws_db_subnet_group.db.name
  enable_http_endpoint                  = var.enable_http_endpoint
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_enhanced_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  port                                  = local.db_port
  preferred_backup_window               = coalesce(var.preferred_backup_window, local.selected_environment_defaults.preferred_backup_window)
  preferred_maintenance_window          = coalesce(var.preferred_maintenance_window, local.selected_environment_defaults.preferred_maintenance_window)
  tags = {
    for tag_name, enabled in local.control_tower_backup_tag_flags :
    tag_name => "true" if enabled
  }
  vpc_security_group_ids = [aws_security_group.this.id]

  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  lifecycle {
    # These are managed by AWS Backup and can cause unnecessary diffs if AWS Backup changes the preferred backup window.
    ignore_changes = [ preferred_backup_window, backup_retention_period ]
  }
}

resource "aws_rds_cluster_parameter_group" "this" {
  name_prefix = "${local.names.cluster_param_group}-"
  family      = "aurora-postgresql${local.engine_major_version}"
  description = "Opinionated security baseline for ${local.names.cluster}"

  parameter {
    name         = "log_min_duration_statement"
    value        = 4000
    apply_method = "immediate"
  }

  parameter {
    name         = "rds.force_ssl"
    value        = 1
    apply_method = "immediate"
  }

  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "this" {
  name_prefix = "${local.names.cluster}-"
  vpc_id      = data.aws_vpc.main.id
  description = "Control traffic to/from RDS Aurora ${local.names.cluster}"

  tags = {
    Name = local.names.cluster
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = toset(["self_only"])

  description                  = "Allow egress only to the Aurora cluster security group"
  from_port                    = -1
  to_port                      = -1
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.this.id
  security_group_id            = aws_security_group.this.id
  tags = {
    Name = "${local.names.cluster}-${each.key}"
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = {
    for idx, subnet in data.aws_subnet.private :
    "private_subnet_${idx}" => subnet
  }

  description       = "Private subnet DB access"
  from_port         = local.db_port
  to_port           = local.db_port
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = each.value.cidr_block
  tags = {
    Name = "${local.names.cluster}-${each.key}"
  }
}

###################################################################################
## RDS Cluster Instances
###################################################################################
resource "aws_rds_cluster_instance" "this" {
  for_each = { for k, v in local.aurora_instances : k => v }

  auto_minor_version_upgrade            = each.value.auto_minor_version_upgrade
  cluster_identifier                    = aws_rds_cluster.this.id
  copy_tags_to_snapshot                 = true
  db_subnet_group_name                  = data.aws_db_subnet_group.db.name
  engine                                = data.aws_rds_engine_version.postgresql.engine
  engine_version                        = data.aws_rds_engine_version.postgresql.version
  identifier                            = "${local.names.cluster}-${each.key}"
  instance_class                        = "db.serverless"
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_enhanced_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  preferred_maintenance_window          = coalesce(var.preferred_maintenance_window, local.selected_environment_defaults.preferred_maintenance_window)
  promotion_tier                        = 0
  publicly_accessible                   = each.value.publicly_accessible

  lifecycle {
    create_before_destroy = true
  }
}

module "kms" {
  source  = "terraform-aws-modules/kms/aws"
  version = "4.2.0"

  deletion_window_in_days = 30
  enable_key_rotation     = true
  is_enabled              = true
  key_usage               = "ENCRYPT_DECRYPT"

  aliases = ["rds/${local.names.cluster}"]

  key_statements = var.backup_central_account_id == null ? null : [
    {
      sid    = "IAMUserPermissions"
      effect = "Allow"
      actions = [
        "kms:List*",
        "kms:Get*",
        "kms:Describe*"
      ]
      resources = ["*"]
      principals = [
        {
          type        = "AWS"
          identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
        }
      ]
    },
    {
      sid    = "AllowBackupAndWorkloadKeyUsage"
      effect = "Allow"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ]
      resources = ["*"]
      principals = [
        {
          type        = "AWS"
          identifiers = local.backup_kms_principal_identifiers
        }
      ]
    },
    {
      sid    = "AllowBackupAndWorkloadGrantManagement"
      effect = "Allow"
      actions = [
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:RevokeGrant"
      ]
      resources = ["*"]
      principals = [
        {
          type        = "AWS"
          identifiers = local.backup_kms_principal_identifiers
        }
      ]
      condition = [
        {
          test     = "Bool"
          variable = "kms:GrantIsForAWSResource"
          values   = ["true"]
        }
      ]
    }
  ]
}

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

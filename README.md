# Aurora Postgres Terraform Module

Opinionated Terraform module for provisioning and managing an AWS Aurora PostgreSQL cluster for OHID workloads.

## Scope and assumptions

This module assumes:

- A pre-existing VPC with an account/region-unique name.
- Database subnets in the target VPC, tagged `Type: Database`.
- Private subnets in the target VPC, tagged `Type: Private`.
- A DB subnet group aligned to the database subnets. By default, this module looks up a DB subnet group named `<name_prefix>-vpc-main`; set `db_subnet_group_name` to override.
- An environment classification via environment_tier. This should be either Production, PreProduction or Development.

The module does not create core networking (VPCs, subnets, routing, NAT, VPC endpoints) and is assumed to be already existing.

## Non-goals

This module intentionally does not try to be a generic Aurora abstraction. The below are not intended to be achieved by this:

- Managing CloudWatch alarms. Alerting is handled by external platform tooling.
- Supporting public database access patterns (for example, public subnets or Internet-facing DB endpoints).
- Supporting non-Aurora PostgreSQL engines (for example, standard RDS PostgreSQL, MySQL, MariaDB).
- Supporting every possible Aurora topology or advanced feature from day one (for example, global databases, cross-region replication, blue/green deployment orchestration).
- Exposing all upstream module knobs as pass-through variables.
- Owning application-level database objects or migrations (schemas, roles, grants, extensions, seed data).

## Design intent

- Encode secure defaults and consistent operational behavior.
- Optimise for repeatable environment provisioning.
- Keep the input contract small and explicit.

## Opinionated defaults

- Naming is centralised in Terraform `locals` and derived from environment metadata.
- Maintenance and backup windows are standardised by `environment_tier` (`Development`, `PreProduction`, `Production`) with optional overrides.
- A security-focused Aurora cluster parameter group is managed by this module (SSL enforced, connection/disconnection logging enabled).
- Master credentials are managed by RDS and stored in AWS Secrets Manager. These are automatically rotated on a 30 day schedule.
- IAM database authentication is enabled and Data API is disabled by default.
- Control Tower backup schedule tags (hourly/daily/weekly/monthly) are disabled by default but can be toggled individually.
- In `Production`, at least one Control Tower backup schedule tag must remain enabled.

## Example run

See [`examples/basic`](./examples/basic) for a complete runnable example against existing network resources.

```bash
cd examples/basic
terraform init
terraform plan
```

## Engine version tracking

Set `engine_version` to the Aurora PostgreSQL major version only, for example `16`.

The module enables `auto_minor_version_upgrade` on every cluster instance and sets `engine_version` on the cluster and instances to that major line, so AWS can apply minor upgrades during the maintenance window without Terraform reporting drift.

Example:

```hcl
module "aurora_postgresql" {
  source = "../.."

  engine_version = "16"
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.7 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_kms"></a> [kms](#module\_kms) | terraform-aws-modules/kms/aws | 4.2.0 |

## Resources

| Name | Type |
|------|------|
| [aws_iam_instance_profile.bastion_ssm_profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.bastion_ssm_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.rds_enhanced_monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.bastion_ssm_attach](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.rds_enhanced_monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.bastion_ec2](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_rds_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster) | resource |
| [aws_rds_cluster_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance) | resource |
| [aws_rds_cluster_parameter_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_parameter_group) | resource |
| [aws_security_group.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.allow_all_traffic_ipv4](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_ami.amazon_linux_23](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_db_subnet_group.db](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/db_subnet_group) | data source |
| [aws_iam_policy_document.monitoring_rds_assume_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_rds_engine_version.postgresql](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/rds_engine_version) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_service_principal.monitoring_rds](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/service_principal) | data source |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
| [aws_subnets.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets) | data source |
| [aws_subnets.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets) | data source |
| [aws_vpc.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_backup_central_account_id"></a> [backup\_central\_account\_id](#input\_backup\_central\_account\_id) | Optional AWS account ID for the central backup account that will copy recovery points encrypted by this Aurora KMS key. | `string` | `null` | no |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup\_retention\_period) | Optional override for backup retention days. If null, environment\_tier defaults are used. | `number` | `null` | no |
| <a name="input_db_subnet_group_name"></a> [db\_subnet\_group\_name](#input\_db\_subnet\_group\_name) | Optional existing DB subnet group name. If null, defaults to the VPC name pattern (<name\_prefix>-vpc-main). | `string` | `null` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Flag to protect the RDS instance from accidental deletion. | `bool` | `true` | no |
| <a name="input_enable_control_tower_backup_daily"></a> [enable\_control\_tower\_backup\_daily](#input\_enable\_control\_tower\_backup\_daily) | Enable Control Tower daily backup tag on the cluster. | `bool` | `false` | no |
| <a name="input_enable_control_tower_backup_hourly"></a> [enable\_control\_tower\_backup\_hourly](#input\_enable\_control\_tower\_backup\_hourly) | Enable Control Tower hourly backup tag on the cluster. | `bool` | `false` | no |
| <a name="input_enable_control_tower_backup_monthly"></a> [enable\_control\_tower\_backup\_monthly](#input\_enable\_control\_tower\_backup\_monthly) | Enable Control Tower monthly backup tag on the cluster. | `bool` | `false` | no |
| <a name="input_enable_control_tower_backup_weekly"></a> [enable\_control\_tower\_backup\_weekly](#input\_enable\_control\_tower\_backup\_weekly) | Enable Control Tower weekly backup tag on the cluster. | `bool` | `false` | no |
| <a name="input_enable_http_endpoint"></a> [enable\_http\_endpoint](#input\_enable\_http\_endpoint) | Enable Aurora Data API (disabled by default for tighter security posture) | `bool` | `false` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | Major version of the Aurora engine. | `string` | n/a | yes |
| <a name="input_environment_name"></a> [environment\_name](#input\_environment\_name) | The name of the environment | `string` | `"dev"` | no |
| <a name="input_environment_tier"></a> [environment\_tier](#input\_environment\_tier) | Environment policy tier that controls opinionated defaults. | `string` | `"Development"` | no |
| <a name="input_instance_count"></a> [instance\_count](#input\_instance\_count) | Number of Aurora cluster instances to create. | `number` | `1` | no |
| <a name="input_master_username"></a> [master\_username](#input\_master\_username) | Master username for Aurora cluster. | `string` | `"root"` | no |
| <a name="input_max_capacity"></a> [max\_capacity](#input\_max\_capacity) | The maximum number of Aurora capacity units (ACUs) for a DB instance in an Aurora Serverless v2 cluster. | `number` | n/a | yes |
| <a name="input_min_capacity"></a> [min\_capacity](#input\_min\_capacity) | The minimum number of Aurora capacity units (ACUs) for a DB instance in an Aurora Serverless v2 cluster. | `number` | n/a | yes |
| <a name="input_preferred_backup_window"></a> [preferred\_backup\_window](#input\_preferred\_backup\_window) | Optional override for backup window (UTC), e.g. 03:00-04:00. | `string` | `null` | no |
| <a name="input_preferred_maintenance_window"></a> [preferred\_maintenance\_window](#input\_preferred\_maintenance\_window) | Optional override for maintenance window (UTC), e.g. sun:04:00-sun:05:00. | `string` | `null` | no |
| <a name="input_project_short_name"></a> [project\_short\_name](#input\_project\_short\_name) | Short project identifier used in resource naming prefix (e.g. c25k). | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_db_master_secret_arn"></a> [db\_master\_secret\_arn](#output\_db\_master\_secret\_arn) | Secrets Manager ARN containing Aurora master username/password. |
<!-- END_TF_DOCS -->

output "db_master_secret_arn" {
  description = "Secrets Manager ARN containing Aurora master username/password."
  value       = try(module.cluster.cluster_master_user_secret[0].secret_arn, null)
}

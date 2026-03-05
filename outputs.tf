output "db_master_secret_arn" {
  description = "Secrets Manager ARN containing Aurora master username/password."
  value       = module.cluster.cluster_master_user_secret.secret_arn
}

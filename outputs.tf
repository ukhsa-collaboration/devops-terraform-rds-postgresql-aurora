output "db_master_secret_arn" {
  description = "Secrets Manager ARN containing Aurora master username/password."
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
}

output "postgres_namespace" {
  description = "Namespace containing PostgreSQL HA resources."
  value       = var.postgres_namespace
}

output "postgres_release_name" {
  description = "Helm release name for PostgreSQL HA."
  value       = var.postgres_release_name
}

output "pgpool_service_name" {
  description = "Pgpool service name used for application connections."
  value       = local.pgpool_service_name
}

output "pgpool_service_fqdn" {
  description = "Cluster DNS name for Pgpool."
  value       = local.pgpool_service_fqdn
}

output "backup_bucket_name" {
  description = "S3 bucket used for PostgreSQL backups when enable_s3_backup is true."
  value       = var.enable_s3_backup ? local.backup_bucket_name : null
}

output "backup_cronjob_name" {
  description = "CronJob name used for logical PostgreSQL backups to S3."
  value       = var.enable_s3_backup ? kubernetes_cron_job_v1.backup[0].metadata[0].name : null
}

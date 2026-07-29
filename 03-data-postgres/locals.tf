locals {
  postgresql_secret_name = "${var.postgres_release_name}-postgresql-auth"
  pgpool_secret_name     = "${var.postgres_release_name}-pgpool-auth"
  backup_service_account = "${var.postgres_release_name}-backup"
  backup_bucket_name     = var.create_backup_bucket ? "${var.postgres_release_name}-backup-${data.aws_caller_identity.current.account_id}-${var.aws_region}" : var.backup_s3_bucket_name
  service_monitor_ns     = var.service_monitor_namespace != "" ? var.service_monitor_namespace : var.postgres_namespace
  pgpool_service_name    = "${var.postgres_release_name}-pgpool"
  pgpool_service_fqdn    = "${local.pgpool_service_name}.${var.postgres_namespace}.svc.cluster.local"
}

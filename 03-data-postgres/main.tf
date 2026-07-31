resource "kubernetes_namespace_v1" "postgres" {
  metadata {
    name = var.postgres_namespace
  }
}

resource "kubernetes_secret_v1" "postgresql_auth" {
  metadata {
    name      = local.postgresql_secret_name
    namespace = kubernetes_namespace_v1.postgres.metadata[0].name
  }

  data = {
    "password"          = var.postgresql_password
    "postgres-password" = var.postgresql_postgres_password
    "repmgr-password"   = var.postgresql_repmgr_password
  }

  type = "Opaque"
}

resource "kubernetes_secret_v1" "pgpool_auth" {
  metadata {
    name      = local.pgpool_secret_name
    namespace = kubernetes_namespace_v1.postgres.metadata[0].name
  }

  data = {
    "admin-password"    = var.pgpool_admin_password
    "sr-check-password" = var.pgpool_sr_check_password
  }

  type = "Opaque"
}

resource "helm_release" "postgresql_ha" {
  name       = var.postgres_release_name
  namespace  = kubernetes_namespace_v1.postgres.metadata[0].name
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "postgresql-ha"
  version    = var.postgres_chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 1800
  wait            = true

  values = [
    templatefile(
      "${path.module}/helm-values/postgresql-ha-values.yaml.tftpl",
      {
        fullname_override           = var.postgres_release_name
        postgresql_username         = var.postgresql_username
        postgresql_database         = var.postgresql_database
        postgresql_secret_name      = local.postgresql_secret_name
        pgpool_secret_name          = local.pgpool_secret_name
        pgpool_admin_username       = var.pgpool_admin_username
        pgpool_sr_check_username    = var.pgpool_sr_check_username
        postgresql_replica_count    = var.postgresql_replica_count
        postgresql_sync_replication = tostring(var.postgresql_sync_replication)
        postgresql_storage_class    = var.postgresql_storage_class
        postgresql_storage_size     = var.postgresql_storage_size
        pgpool_replica_count        = var.pgpool_replica_count
        pgpool_service_type         = var.pgpool_service_type
        postgresql_requests_cpu     = var.postgresql_requests_cpu
        postgresql_requests_memory  = var.postgresql_requests_memory
        postgresql_limits_cpu       = var.postgresql_limits_cpu
        postgresql_limits_memory    = var.postgresql_limits_memory
        pgpool_requests_cpu         = var.pgpool_requests_cpu
        pgpool_requests_memory      = var.pgpool_requests_memory
        pgpool_limits_cpu           = var.pgpool_limits_cpu
        pgpool_limits_memory        = var.pgpool_limits_memory
        enable_metrics              = tostring(var.enable_metrics)
        enable_service_monitor      = tostring(var.enable_metrics && var.enable_service_monitor)
        service_monitor_namespace   = local.service_monitor_ns
      }
    )
  ]

  depends_on = [
    kubernetes_secret_v1.postgresql_auth,
    kubernetes_secret_v1.pgpool_auth
  ]
}

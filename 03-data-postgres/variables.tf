variable "aws_region" {
  type        = string
  description = "AWS Region containing the EKS cluster and Terraform state."
  default     = "ap-southeast-1"
}

variable "infrastructure_state_bucket" {
  type        = string
  description = "S3 bucket containing the 01-infrastructure Terraform state."
}

variable "infrastructure_state_key" {
  type        = string
  description = "S3 key containing the 01-infrastructure Terraform state."
  default     = "longnd/dev/infrastructure.tfstate"
}

variable "postgres_namespace" {
  type        = string
  description = "Namespace used for PostgreSQL resources."
  default     = "data"
}

variable "postgres_release_name" {
  type        = string
  description = "Helm release name for PostgreSQL HA."
  default     = "postgresql-ha"
}

variable "postgres_chart_version" {
  type        = string
  description = "Bitnami PostgreSQL HA chart version."
  default     = "16.3.2"
}

variable "postgresql_replica_count" {
  type        = number
  description = "Number of PostgreSQL replicas. Use an odd number; 3 is the minimum for HA quorum."
  default     = 3

  validation {
  condition     = var.postgresql_replica_count >= 1
  error_message = "postgresql_replica_count must be at least 1."
}
}

variable "postgresql_sync_replication" {
  type        = bool
  description = "Enable synchronous replication for PostgreSQL HA."
  default     = true
}

variable "postgresql_storage_class" {
  type        = string
  description = "StorageClass for PostgreSQL persistent volumes."
  default     = "gp3"
}

variable "postgresql_storage_size" {
  type        = string
  description = "Persistent volume size for each PostgreSQL replica."
  default     = "20Gi"
}

variable "postgresql_username" {
  type        = string
  description = "Application PostgreSQL username."
  default     = "appuser"
}

variable "postgresql_password" {
  type        = string
  description = "Application PostgreSQL user password."
  sensitive   = true
}

variable "postgresql_database" {
  type        = string
  description = "Application PostgreSQL database name."
  default     = "appdb"
}

variable "postgresql_postgres_password" {
  type        = string
  description = "Password for the postgres superuser."
  sensitive   = true
}

variable "postgresql_repmgr_password" {
  type        = string
  description = "Password for the repmgr user used by PostgreSQL HA."
  sensitive   = true
}

variable "pgpool_admin_username" {
  type        = string
  description = "Pgpool admin username."
  default     = "admin"
}

variable "pgpool_admin_password" {
  type        = string
  description = "Pgpool admin password."
  sensitive   = true
}

variable "pgpool_sr_check_username" {
  type        = string
  description = "Pgpool sr-check username."
  default     = "sr_check_user"
}

variable "pgpool_sr_check_password" {
  type        = string
  description = "Pgpool sr-check password."
  sensitive   = true
}

variable "pgpool_replica_count" {
  type        = number
  description = "Number of Pgpool replicas."
  default     = 1

  validation {
    condition     = var.pgpool_replica_count >= 1
    error_message = "pgpool_replica_count must be at least 1."
  }
}

variable "pgpool_service_type" {
  type        = string
  description = "Kubernetes Service type for Pgpool. Use ClusterIP for internal-only access."
  default     = "ClusterIP"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.pgpool_service_type)
    error_message = "pgpool_service_type must be ClusterIP, NodePort, or LoadBalancer."
  }
}

variable "postgresql_requests_cpu" {
  type        = string
  description = "CPU request for PostgreSQL pods."
  default     = "250m"
}

variable "postgresql_requests_memory" {
  type        = string
  description = "Memory request for PostgreSQL pods."
  default     = "512Mi"
}

variable "postgresql_limits_cpu" {
  type        = string
  description = "CPU limit for PostgreSQL pods."
  default     = "1000m"
}

variable "postgresql_limits_memory" {
  type        = string
  description = "Memory limit for PostgreSQL pods."
  default     = "2Gi"
}

variable "pgpool_requests_cpu" {
  type        = string
  description = "CPU request for Pgpool pods."
  default     = "100m"
}

variable "pgpool_requests_memory" {
  type        = string
  description = "Memory request for Pgpool pods."
  default     = "256Mi"
}

variable "pgpool_limits_cpu" {
  type        = string
  description = "CPU limit for Pgpool pods."
  default     = "500m"
}

variable "pgpool_limits_memory" {
  type        = string
  description = "Memory limit for Pgpool pods."
  default     = "512Mi"
}

variable "enable_metrics" {
  type        = bool
  description = "Enable postgres exporter metrics in the chart."
  default     = true
}

variable "enable_service_monitor" {
  type        = bool
  description = "Create ServiceMonitor resources for Prometheus Operator."
  default     = false
}

variable "service_monitor_namespace" {
  type        = string
  description = "Optional namespace for ServiceMonitor resources. Leave empty to use the PostgreSQL namespace."
  default     = ""
}

variable "create_backup_bucket" {
  type        = bool
  description = "Create a dedicated S3 bucket for PostgreSQL backups."
  default     = false
}

variable "backup_s3_bucket_name" {
  type        = string
  description = "Existing S3 bucket name for PostgreSQL backups when create_backup_bucket is false."
  default     = ""
}

variable "backup_s3_prefix" {
  type        = string
  description = "S3 key prefix for PostgreSQL backups."
  default     = "postgresql-ha"
}

variable "enable_s3_backup" {
  type        = bool
  description = "Create a CronJob that writes logical PostgreSQL backups to S3."
  default     = true
}

variable "backup_schedule" {
  type        = string
  description = "Cron schedule used by the PostgreSQL backup CronJob."
  default     = "0 2 * * *"
}

variable "backup_retention_days" {
  type        = number
  description = "Lifecycle retention in days for objects in the dedicated backup bucket when create_backup_bucket is true."
  default     = 14
}

variable "backup_postgres_image" {
  type        = string
  description = "Container image used to produce pg_dumpall backups."
  default     = "docker.io/bitnamilegacy/postgresql:17.6.0-debian-12-r2"
}

variable "backup_awscli_image" {
  type        = string
  description = "Container image used to upload backup files to S3."
  default     = "public.ecr.aws/aws-cli/aws-cli:2.27.50"
}

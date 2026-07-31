resource "aws_s3_bucket" "backup" {
  count  = var.enable_s3_backup && var.create_backup_bucket ? 1 : 0
  bucket = local.backup_bucket_name
}

resource "aws_s3_bucket_ownership_controls" "backup" {
  count  = var.enable_s3_backup && var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.backup[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  count  = var.enable_s3_backup && var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.backup[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backup" {
  count  = var.enable_s3_backup && var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.backup[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  count  = var.enable_s3_backup && var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.backup[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  count  = var.enable_s3_backup && var.create_backup_bucket ? 1 : 0
  bucket = aws_s3_bucket.backup[0].id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {}

    expiration {
      days = var.backup_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.backup_retention_days
    }
  }
}

data "aws_iam_policy_document" "backup_irsa_assume_role" {
  count = var.enable_s3_backup ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.infrastructure.outputs.eks_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_issuer_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_issuer_hostpath}:sub"
      values   = ["system:serviceaccount:${var.postgres_namespace}:${local.backup_service_account}"]
    }
  }
}

data "aws_iam_policy_document" "backup_s3" {
  count = var.enable_s3_backup ? 1 : 0

  statement {
    sid    = "ListBackupBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = ["arn:aws:s3:::${local.backup_bucket_name}"]
  }

  statement {
    sid    = "WriteBackupObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:AbortMultipartUpload"
    ]
    resources = ["arn:aws:s3:::${local.backup_bucket_name}/${var.backup_s3_prefix}/*"]
  }
}

resource "aws_iam_role" "backup" {
  count              = var.enable_s3_backup ? 1 : 0
  name               = "${var.postgres_release_name}-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_irsa_assume_role[0].json

  lifecycle {
    precondition {
      condition     = local.backup_bucket_name != ""
      error_message = "backup_s3_bucket_name must be set when enable_s3_backup is true and create_backup_bucket is false."
    }
  }
}

resource "aws_iam_role_policy" "backup_s3" {
  count  = var.enable_s3_backup ? 1 : 0
  name   = "${var.postgres_release_name}-backup-s3"
  role   = aws_iam_role.backup[0].id
  policy = data.aws_iam_policy_document.backup_s3[0].json
}

resource "kubernetes_service_account_v1" "backup" {
  count = var.enable_s3_backup ? 1 : 0

  metadata {
    name      = local.backup_service_account
    namespace = kubernetes_namespace_v1.postgres.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.backup[0].arn
    }
  }
}

resource "kubernetes_cron_job_v1" "backup" {
  count = var.enable_s3_backup ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.backup_bucket_name != ""
      error_message = "backup_s3_bucket_name must be set when enable_s3_backup is true and create_backup_bucket is false."
    }
  }

  metadata {
    name      = "${var.postgres_release_name}-s3-backup"
    namespace = kubernetes_namespace_v1.postgres.metadata[0].name
  }

  depends_on = [
    helm_release.postgresql_ha,
    kubernetes_service_account_v1.backup
  ]

  spec {
    schedule                      = var.backup_schedule
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        labels = {
          app = "${var.postgres_release_name}-backup"
        }
      }

      spec {
        backoff_limit = 1

        template {
          metadata {
            labels = {
              app = "${var.postgres_release_name}-backup"
            }
          }

          spec {
            service_account_name = kubernetes_service_account_v1.backup[0].metadata[0].name
            restart_policy       = "Never"

            volume {
              name = "backup"

              empty_dir {}
            }

            container {
              name    = "dump"
              image   = var.backup_postgres_image
              command = ["/bin/sh", "-ec"]
              args = [<<-EOT
                TS="$(date -u +%Y%m%dT%H%M%SZ)"
                FILE="/backup/$${TS}-pgdumpall.sql.gz"
                export PGPASSWORD="$PGPASSWORD"
                pg_dumpall -h ${local.postgresql_primary_host} -p 5432 -U postgres | gzip -c > "$FILE"
                test -s "$FILE"
              EOT
              ]

              env {
                name = "PGPASSWORD"

                value_from {
                  secret_key_ref {
                    name = local.postgresql_secret_name
                    key  = "postgres-password"
                  }
                }
              }

              volume_mount {
                name       = "backup"
                mount_path = "/backup"
              }
            }

            container {
              name    = "upload"
              image   = var.backup_awscli_image
              command = ["/bin/sh", "-ec"]
              args = [<<-EOT
                for _ in $(seq 1 120); do
                  FILE="$(find /backup -maxdepth 1 -name '*.sql.gz' -type f | head -n 1)"
                  if [ -n "$FILE" ] && [ -s "$FILE" ]; then
                    aws s3 cp "$FILE" "s3://${local.backup_bucket_name}/${var.backup_s3_prefix}/$(basename "$FILE")"
                    exit 0
                  fi
                  sleep 5
                done
                echo "backup file not found" >&2
                exit 1
              EOT
              ]

              volume_mount {
                name       = "backup"
                mount_path = "/backup"
              }
            }
          }
        }
      }
    }
  }
}

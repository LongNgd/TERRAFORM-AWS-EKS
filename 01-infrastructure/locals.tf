locals {
  name = "${var.project_name}-${var.environment}"

  availability_zones = length(var.availability_zones) == 2 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Stack       = "infrastructure"
    },
    var.additional_tags
  )

  cluster_name    = "${local.name}-eks"
  app_bucket_name = var.app_bucket_name != "" ? var.app_bucket_name : "${local.name}-app-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

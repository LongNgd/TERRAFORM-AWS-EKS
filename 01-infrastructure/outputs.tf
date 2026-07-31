output "app_bucket_name" {
  description = "Private S3 bucket used by application pods."
  value       = aws_s3_bucket.application.id
}

output "aws_region" {
  description = "AWS Region used by this stack."
  value       = var.aws_region
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded EKS cluster CA data."
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_endpoint" {
  description = "EKS Kubernetes API endpoint."
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.main.name
}

output "load_balancer_controller_role_arn" {
  description = "IAM role ARN used by AWS Load Balancer Controller via IRSA."
  value       = aws_iam_role.load_balancer_controller.arn
}

output "eks_oidc_provider_arn" {
  description = "IAM OIDC provider ARN used for IRSA on this EKS cluster."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by EKS and RDS."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs used by the internet-facing ALB and NAT Gateways."
  value       = aws_subnet.public[*].id
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint and port."
  value       = var.enable_rds ? aws_db_instance.postgresql[0].endpoint : null
}

output "rds_master_secret_arn" {
  description = "Secrets Manager ARN managed by RDS for the master credentials."
  value       = var.enable_rds ? try(aws_db_instance.postgresql[0].master_user_secret[0].secret_arn, null) : null
}

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}

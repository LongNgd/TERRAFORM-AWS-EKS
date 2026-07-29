resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS Kubernetes secrets encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${local.name}-eks"
  target_key_id = aws_kms_key.eks.key_id
}

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = 30
}

resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_version

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }

    resources = ["secrets"]
  }

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = true
    endpoint_public_access  = var.eks_endpoint_public_access
    public_access_cidrs     = var.cluster_public_access_cidrs
  }

  depends_on = [
    aws_cloudwatch_log_group.eks,
    aws_iam_role_policy_attachment.eks_cluster
  ]
}

resource "aws_eks_node_group" "general" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "general"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = aws_subnet.private[*].id
  version         = var.eks_version

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = var.node_capacity_type
  disk_size      = 50
  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
    min_size     = var.node_min_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    workload = "general"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker,
    aws_iam_role_policy_attachment.eks_node_ecr,
    aws_iam_role_policy_attachment.eks_node_cni
  ]
}

locals {
  eks_addons = toset([
    "coredns",
    "eks-pod-identity-agent",
    "kube-proxy",
    "vpc-cni"
  ])
}

resource "aws_eks_addon" "main" {
  for_each = local.eks_addons

  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_node_group.general]
}

resource "aws_eks_pod_identity_association" "application" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "app"
  service_account = "app-sa"
  role_arn        = aws_iam_role.application.arn

  depends_on = [aws_eks_addon.main["eks-pod-identity-agent"]]
}

resource "aws_eks_access_entry" "admin" {
  for_each = var.additional_admin_role_arns

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = var.additional_admin_role_arns

  cluster_name  = aws_eks_cluster.main.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

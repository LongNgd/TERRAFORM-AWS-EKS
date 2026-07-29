data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${local.name}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "${local.name}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json
}

resource "aws_iam_role_policy_attachment" "eks_node_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}

resource "aws_iam_role_policy_attachment" "eks_node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

data "aws_iam_policy_document" "pod_identity_assume_role" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[length(data.tls_certificate.eks_oidc.certificates) - 1].sha1_fingerprint]
}

data "aws_iam_policy_document" "load_balancer_controller_irsa_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_issuer_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_issuer_hostpath}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_policy" "load_balancer_controller" {
  name        = "${local.name}-aws-load-balancer-controller"
  description = "Permissions for AWS Load Balancer Controller v3.4.2."
  policy      = file("${path.module}/policies/aws-load-balancer-controller-v3.4.2.json")
}

resource "aws_iam_role" "load_balancer_controller" {
  name               = "${local.name}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.load_balancer_controller_irsa_assume_role.json
}

resource "aws_iam_role_policy_attachment" "load_balancer_controller" {
  role       = aws_iam_role.load_balancer_controller.name
  policy_arn = aws_iam_policy.load_balancer_controller.arn
}

data "aws_iam_policy_document" "application_s3" {
  statement {
    sid    = "ListApplicationBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = [aws_s3_bucket.application.arn]
  }

  statement {
    sid    = "ReadWriteApplicationObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = ["${aws_s3_bucket.application.arn}/*"]
  }
}

resource "aws_iam_role" "application" {
  name               = "${local.name}-application-pod"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume_role.json
}

resource "aws_iam_role_policy" "application_s3" {
  name   = "application-s3"
  role   = aws_iam_role.application.id
  policy = data.aws_iam_policy_document.application_s3.json
}

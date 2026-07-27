provider "aws" {
  region = var.aws_region
}

data "terraform_remote_state" "infrastructure" {
  backend = "s3"

  config = {
    bucket       = var.infrastructure_state_bucket
    key          = var.infrastructure_state_key
    region       = var.aws_region
    use_lockfile = true
  }
}

data "aws_eks_cluster" "main" {
  name = data.terraform_remote_state.infrastructure.outputs.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--region",
      var.aws_region,
      "--cluster-name",
      data.aws_eks_cluster.main.name
    ]
  }
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--region",
        var.aws_region,
        "--cluster-name",
        data.aws_eks_cluster.main.name
      ]
    }
  }
}

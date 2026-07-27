resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.load_balancer_controller_chart_version

  atomic          = true
  cleanup_on_fail = true
  timeout         = 900
  wait            = true

  values = [
    templatefile(
      "${path.module}/helm-values/aws-load-balancer-controller-values.yaml.tftpl",
      {
        cluster_name  = data.terraform_remote_state.infrastructure.outputs.cluster_name
        aws_region    = var.aws_region
        vpc_id        = data.terraform_remote_state.infrastructure.outputs.vpc_id
        replica_count = var.load_balancer_controller_replica_count
      }
    )
  ]
}

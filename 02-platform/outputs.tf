output "sample_alb_hostname" {
  description = "ALB hostname created by the sample Kubernetes Ingress. It can take several minutes to appear."
  value = var.deploy_sample_app ? try(
    kubernetes_ingress_v1.sample[0].status[0].load_balancer[0].ingress[0].hostname,
    null
  ) : null
}

locals {
  sample_ingress_annotations = merge(
    {
      "alb.ingress.kubernetes.io/scheme"          = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"     = "ip"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/"
      "alb.ingress.kubernetes.io/subnets"         = join(",", data.terraform_remote_state.infrastructure.outputs.public_subnet_ids)
    },
    var.certificate_arn == "" ? {
      "alb.ingress.kubernetes.io/listen-ports" = "[{\"HTTP\":80}]"
    } : {
      "alb.ingress.kubernetes.io/listen-ports"    = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/certificate-arn" = var.certificate_arn
      "alb.ingress.kubernetes.io/ssl-redirect"    = "443"
    }
  )
}

resource "kubernetes_namespace_v1" "app" {
  count = var.deploy_sample_app ? 1 : 0

  metadata {
    name = "app"
  }
}

resource "kubernetes_service_account_v1" "app" {
  count = var.deploy_sample_app ? 1 : 0

  metadata {
    name      = "app-sa"
    namespace = kubernetes_namespace_v1.app[0].metadata[0].name
  }
}

resource "kubernetes_deployment_v1" "sample" {
  count = var.deploy_sample_app ? 1 : 0

  metadata {
    name      = "sample-echo"
    namespace = kubernetes_namespace_v1.app[0].metadata[0].name
    labels = {
      app = "sample-echo"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "sample-echo"
      }
    }

    template {
      metadata {
        labels = {
          app = "sample-echo"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.app[0].metadata[0].name

        container {
          name  = "echoserver"
          image = "registry.k8s.io/echoserver:1.10"

          port {
            name           = "http"
            container_port = 8080
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 8080
            }

            initial_delay_seconds = 5
            period_seconds        = 10
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }

            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "sample" {
  count = var.deploy_sample_app ? 1 : 0

  metadata {
    name      = "sample-echo"
    namespace = kubernetes_namespace_v1.app[0].metadata[0].name
  }

  spec {
    selector = {
      app = kubernetes_deployment_v1.sample[0].metadata[0].labels.app
    }

    port {
      name        = "http"
      port        = 80
      target_port = 8080
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "sample" {
  count = var.deploy_sample_app ? 1 : 0

  metadata {
    name        = "sample-echo"
    namespace   = kubernetes_namespace_v1.app[0].metadata[0].name
    annotations = local.sample_ingress_annotations
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        path {
          path      = "/test"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.sample[0].metadata[0].name

              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}

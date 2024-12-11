terraform {
  required_version = ">= 1.0.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "customer-1" {
  metadata {
    name = "customer-1"
  }
}

resource "kubernetes_namespace" "customer-2" {
  metadata {
    name = "customer-2"
  }
}

locals {
  deployments = {
    default = {
      name      = "info-app"
      namespace = "default"
      host      = "app.localhost"
    },
    customer_1 = {
      name      = "customer-1"
      namespace = "customer-1"
      host      = "customer-1.localhost"
    },
    customer_2 = {
      name      = "customer-2"
      namespace = "customer-2"
      host      = "customer-2.localhost"
    }
  }
}

resource "kubernetes_deployment" "info_app" {
  for_each = local.deployments

  metadata {
    name      = each.value.name
    namespace = each.value.namespace
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = each.value.name
      }
    }

    template {
      metadata {
        labels = {
          app = each.value.name
        }
      }

      spec {
        container {
          name  = each.value.name
          image = "sakuraocha/info-app:v1"

          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }

          env {
            name = "POD_IP"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }

          env {
            name = "NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          env {
            name = "NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          env {
            name = "NODE_IP"
            value_from {
              field_ref {
                field_path = "status.hostIP"
              }
            }
          }

          port {
            container_port = 3000
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "info_app_service" {
  for_each = local.deployments

  metadata {
    name      = "info-app-service"
    namespace = each.value.namespace
  }

  spec {
    selector = {
      app = each.value.name
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 3000
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "info_app_autoscaler" {
  for_each = local.deployments

  metadata {
    name      = "info-app-autoscaler"
    namespace = each.value.namespace
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = each.value.name
    }

    min_replicas = 1
    max_replicas = 5

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 10
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 25
        }
      }
    }
  }
}

resource "kubernetes_network_policy" "block_egress" {
  for_each = local.deployments

  metadata {
    name      = "block-egress"
    namespace = each.value.namespace
  }

  spec {
    pod_selector {
      match_labels = {
        app = each.value.name
      }
    }

    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }

      ports {
        protocol = "UDP"
        port     = "53"
      }

      ports {
        protocol = "TCP"
        port     = "53"
      }
    }
  }
}

resource "kubernetes_manifest" "ingress_route" {
  for_each = local.deployments

  manifest = {
    apiVersion = "traefik.containo.us/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "info-app-ingressroute"
      namespace = each.value.namespace
    }
    spec = {
      entryPoints = ["web"]
      routes = [
        {
          match = "Host(`${each.value.host}`)"
          kind  = "Rule"
          services = [
            {
              name = "info-app-service"
              port = 80
            }
          ]
        }
      ]
    }
  }
}

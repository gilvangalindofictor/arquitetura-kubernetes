# Test Applications Module
# Marco 2 Fase 7 - Validação End-to-End da Plataforma

# Namespace para test applications
resource "kubernetes_namespace" "test_apps" {
  metadata {
    name = var.namespace
    labels = {
      name                       = var.namespace
      "app.kubernetes.io/name"   = "test-applications"
      "app.kubernetes.io/part-of" = "marco2-fase7"
    }
  }
}

# Apply NGINX Test manifest
data "kubectl_file_documents" "nginx_test" {
  content = file("${path.module}/manifests/nginx-test.yaml")
}

resource "kubectl_manifest" "nginx_test" {
  for_each  = data.kubectl_file_documents.nginx_test.manifests
  yaml_body = each.value

  depends_on = [kubernetes_namespace.test_apps]
}

# Apply Echo Server manifest
data "kubectl_file_documents" "echo_server" {
  content = file("${path.module}/manifests/echo-server.yaml")
}

resource "kubectl_manifest" "echo_server" {
  for_each  = data.kubectl_file_documents.echo_server.manifests
  yaml_body = each.value

  depends_on = [kubernetes_namespace.test_apps]
}

# Network Policy para permitir tráfego do ALB e Prometheus
resource "kubernetes_network_policy" "allow_ingress_monitoring" {
  metadata {
    name      = "allow-alb-and-monitoring"
    namespace = kubernetes_namespace.test_apps.metadata[0].name
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress", "Egress"]

    # Allow ingress from kube-system (ALB Controller)
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "80"
      }
      ports {
        protocol = "TCP"
        port     = "8080"
      }
      ports {
        protocol = "TCP"
        port     = "9113"
      }
    }

    # Allow ingress from monitoring (Prometheus)
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "monitoring"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "9113"
      }
      ports {
        protocol = "TCP"
        port     = "80"
      }
    }

    # Allow DNS egress
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
      ports {
        protocol = "UDP"
        port     = "53"
      }
    }

    # Allow Kubernetes API server
    egress {
      to {
        namespace_selector {}
      }
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }

    # Allow all TCP egress (apps podem precisar acessar internet)
    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }
      ports {
        protocol = "TCP"
      }
    }
  }
}

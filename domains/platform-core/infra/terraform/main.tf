# Platform Core Domain - Cloud-Agnostic Terraform
# Providers: kubernetes + helm ONLY (conformidade ADR-003)

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

# ===== PROVIDERS (Cloud-Agnostic) =====

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = var.cluster_endpoint
    cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
  }
}

# ===== NAMESPACES =====

resource "kubernetes_namespace" "kong" {
  metadata {
    name = "platform-kong"
    labels = {
      "domain"     = "platform-core"
      "component"  = "api-gateway"
      "managed-by" = "terraform"
    }
  }
}

resource "kubernetes_namespace" "keycloak" {
  metadata {
    name = "platform-keycloak"
    labels = {
      "domain"     = "platform-core"
      "component"  = "authentication"
      "managed-by" = "terraform"
    }
  }
}

resource "kubernetes_namespace" "linkerd" {
  metadata {
    name = "linkerd"
    labels = {
      "domain"                       = "platform-core"
      "component"                    = "service-mesh"
      "managed-by"                   = "terraform"
      "linkerd.io/is-control-plane" = "true"
    }
  }
}

resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
    labels = {
      "domain"     = "platform-core"
      "component"  = "certificates"
      "managed-by" = "terraform"
    }
  }
}

resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
    labels = {
      "domain"     = "platform-core"
      "component"  = "ingress"
      "managed-by" = "terraform"
    }
  }
}

# ===== CERT-MANAGER (Deploy First - Required by others) =====

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_version
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "global.leaderElection.namespace"
    value = kubernetes_namespace.cert_manager.metadata[0].name
  }

  # Cloud-agnostic: usa HTTP-01 challenge (não DNS)
  values = [
    yamlencode({
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }
    })
  ]
}

# ClusterIssuer (Let's Encrypt Production)
resource "kubernetes_manifest" "letsencrypt_prod" {
  depends_on = [helm_release.cert_manager]

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-prod-key"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  }
}

# ===== NGINX INGRESS CONTROLLER =====

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.ingress_nginx_version
  namespace  = kubernetes_namespace.ingress_nginx.metadata[0].name

  values = [
    yamlencode({
      controller = {
        replicaCount = 2
        resources = {
          requests = {
            cpu    = "200m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
        service = {
          type = "LoadBalancer"
          annotations = {
            # Cloud-agnostic: funciona em AWS, Azure, GCP
            "service.beta.kubernetes.io/aws-load-balancer-type"              = "nlb"
            "service.beta.kubernetes.io/azure-load-balancer-health-probe-interval" = "5"
          }
        }
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = var.enable_monitoring
          }
        }
      }
    })
  ]
}

# ===== LINKERD SERVICE MESH =====

# Linkerd CRDs (instalados manualmente ou via linkerd CLI)
# Aqui apenas configuramos o namespace e recursos

resource "helm_release" "linkerd_control_plane" {
  name       = "linkerd-control-plane"
  repository = "https://helm.linkerd.io/stable"
  chart      = "linkerd-control-plane"
  version    = var.linkerd_version
  namespace  = kubernetes_namespace.linkerd.metadata[0].name

  # Linkerd requer certificados pré-configurados
  # Em produção: usar cert-manager para gerar certificados
  values = [
    yamlencode({
      identityTrustAnchorsPEM = var.linkerd_trust_anchor_pem
      identity = {
        issuer = {
          crtExpiry = "8760h" # 1 ano
        }
      }
      proxy = {
        resources = {
          cpu = {
            request = "100m"
            limit   = "200m"
          }
          memory = {
            request = "50Mi"
            limit   = "100Mi"
          }
        }
      }
      controllerReplicas = 2
      enablePodAntiAffinity = true
    })
  ]
}

# Linkerd Viz (Observability Dashboard)
resource "helm_release" "linkerd_viz" {
  depends_on = [helm_release.linkerd_control_plane]

  name       = "linkerd-viz"
  repository = "https://helm.linkerd.io/stable"
  chart      = "linkerd-viz"
  version    = var.linkerd_viz_version
  namespace  = kubernetes_namespace.linkerd.metadata[0].name

  values = [
    yamlencode({
      dashboard = {
        enforcedHostRegexp = ".*"
      }
      prometheus = {
        enabled = var.enable_monitoring
      }
      tap = {
        resources = {
          cpu = {
            request = "100m"
            limit   = "200m"
          }
          memory = {
            request = "100Mi"
            limit   = "200Mi"
          }
        }
      }
    })
  ]
}

# ===== KEYCLOAK (Identity Provider) =====

# PostgreSQL para Keycloak (embedded - produção deve usar data-services domain)
resource "helm_release" "keycloak" {
  depends_on = [helm_release.cert_manager]

  name       = "keycloak"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "keycloak"
  version    = var.keycloak_version
  namespace  = kubernetes_namespace.keycloak.metadata[0].name

  values = [
    yamlencode({
      auth = {
        adminUser     = var.keycloak_admin_user
        adminPassword = var.keycloak_admin_password # Produção: usar External Secrets
      }
      replicaCount = 2
      resources = {
        requests = {
          cpu    = "500m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
      }
      postgresql = {
        enabled = true
        auth = {
          username = "keycloak"
          password = var.keycloak_db_password # Produção: usar External Secrets
          database = "keycloak"
        }
        primary = {
          persistence = {
            enabled      = true
            storageClass = var.storage_class_name # Cloud-agnostic
            size         = "10Gi"
          }
        }
      }
      ingress = {
        enabled   = true
        ingressClassName = "nginx"
        hostname  = var.keycloak_domain
        tls       = true
        annotations = {
          "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
        }
      }
      metrics = {
        enabled = var.enable_monitoring
        serviceMonitor = {
          enabled = var.enable_monitoring
        }
      }
    })
  ]
}

# ===== KONG API GATEWAY =====

resource "helm_release" "kong" {
  depends_on = [
    helm_release.cert_manager,
    helm_release.keycloak
  ]

  name       = "kong"
  repository = "https://charts.konghq.com"
  chart      = "kong"
  version    = var.kong_version
  namespace  = kubernetes_namespace.kong.metadata[0].name

  values = [
    yamlencode({
      ingressController = {
        enabled = true
        installCRDs = true
      }
      replicaCount = 2
      resources = {
        requests = {
          cpu    = "500m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
      }
      proxy = {
        type = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
        }
      }
      env = {
        database = "postgres"
      }
      postgresql = {
        enabled = true
        auth = {
          username = "kong"
          password = var.kong_db_password # Produção: usar External Secrets
          database = "kong"
        }
        primary = {
          persistence = {
            enabled      = true
            storageClass = var.storage_class_name # Cloud-agnostic
            size         = "10Gi"
          }
        }
      }
      # Integração com Keycloak (OIDC plugin)
      plugins = {
        configMaps = [
          {
            name = "kong-oidc-config"
            pluginName = "oidc"
          }
        ]
      }
      admin = {
        enabled = true
        http = {
          enabled = true
        }
      }
      metrics = {
        enabled = var.enable_monitoring
        serviceMonitor = {
          enabled = var.enable_monitoring
        }
      }
    })
  ]
}

# ===== OUTPUTS =====

output "keycloak_url" {
  value       = "https://${var.keycloak_domain}"
  description = "Keycloak URL for authentication"
}

output "kong_admin_url" {
  value       = "http://kong-kong-admin.${kubernetes_namespace.kong.metadata[0].name}.svc.cluster.local:8001"
  description = "Kong Admin API URL (internal)"
}

output "linkerd_dashboard_url" {
  value       = "http://web.${kubernetes_namespace.linkerd.metadata[0].name}.svc.cluster.local:8084"
  description = "Linkerd Dashboard URL (internal)"
}

output "namespaces" {
  value = {
    kong         = kubernetes_namespace.kong.metadata[0].name
    keycloak     = kubernetes_namespace.keycloak.metadata[0].name
    linkerd      = kubernetes_namespace.linkerd.metadata[0].name
    cert_manager = kubernetes_namespace.cert_manager.metadata[0].name
    ingress      = kubernetes_namespace.ingress_nginx.metadata[0].name
  }
  description = "Platform Core namespaces"
}

output "usage_instructions" {
  value = <<-EOT
    Platform Core deployed successfully!
    
    1. Access Keycloak:
       URL: https://${var.keycloak_domain}
       User: ${var.keycloak_admin_user}
       Password: (check terraform.tfvars)
    
    2. Configure OIDC clients in Keycloak for other domains
    
    3. Inject Linkerd proxy in other domains:
       kubectl annotate namespace <namespace> linkerd.io/inject=enabled
    
    4. Kong Admin API (internal):
       kubectl port-forward -n ${kubernetes_namespace.kong.metadata[0].name} svc/kong-kong-admin 8001:8001
    
    5. Linkerd Dashboard (internal):
       linkerd viz dashboard
  EOT
  description = "Post-deployment instructions"
}

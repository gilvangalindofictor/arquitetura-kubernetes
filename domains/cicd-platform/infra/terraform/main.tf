# CI/CD Platform Domain - Cloud-Agnostic Terraform
# Providers: kubernetes + helm ONLY (conformidade ADR-003)
# Components: GitLab, SonarQube, Harbor, ArgoCD, Backstage

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

resource "kubernetes_namespace" "gitlab" {
  metadata {
    name = "cicd-gitlab"
    labels = {
      "domain"                = "cicd-platform"
      "component"             = "git-ci"
      "managed-by"            = "terraform"
      "linkerd.io/inject"     = "enabled"  # Service mesh injection
    }
  }
}

resource "kubernetes_namespace" "sonarqube" {
  metadata {
    name = "cicd-sonarqube"
    labels = {
      "domain"            = "cicd-platform"
      "component"         = "code-quality"
      "managed-by"        = "terraform"
      "linkerd.io/inject" = "enabled"
    }
  }
}

resource "kubernetes_namespace" "harbor" {
  metadata {
    name = "cicd-harbor"
    labels = {
      "domain"            = "cicd-platform"
      "component"         = "registry"
      "managed-by"        = "terraform"
      "linkerd.io/inject" = "enabled"
    }
  }
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "cicd-argocd"
    labels = {
      "domain"            = "cicd-platform"
      "component"         = "gitops"
      "managed-by"        = "terraform"
      "linkerd.io/inject" = "enabled"
    }
  }
}

resource "kubernetes_namespace" "backstage" {
  metadata {
    name = "cicd-backstage"
    labels = {
      "domain"            = "cicd-platform"
      "component"         = "developer-portal"
      "managed-by"        = "terraform"
      "linkerd.io/inject" = "enabled"
    }
  }
}

# ===== GITLAB (Git Repository + CI/CD) =====

resource "helm_release" "gitlab" {
  name       = "gitlab"
  repository = "https://charts.gitlab.io"
  chart      = "gitlab"
  version    = var.gitlab_version
  namespace  = kubernetes_namespace.gitlab.metadata[0].name
  timeout    = 900  # 15 min (GitLab é complexo)

  values = [
    yamlencode({
      global = {
        hosts = {
          domain = var.gitlab_domain
        }
        edition = "ce"  # Community Edition
        ingress = {
          enabled          = true
          class            = "nginx"
          annotations = {
            "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
          }
          tls = {
            enabled = true
          }
        }
        psql = {
          password = {
            secret = "gitlab-postgresql-password"
            key    = "password"
          }
        }
        redis = {
          password = {
            enabled = true
            secret  = "gitlab-redis-secret"
            key     = "password"
          }
        }
        minio = {
          enabled = true  # Object storage (S3-compatible)
        }
      }
      # GitLab components
      gitlab = {
        webservice = {
          replicaCount = 2
          resources = {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "2000m"
              memory = "2Gi"
            }
          }
        }
        sidekiq = {
          replicaCount = 1
          resources = {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
        }
        gitlab-shell = {
          replicaCount = 2
        }
      }
      # PostgreSQL
      postgresql = {
        install = true
        persistence = {
          storageClass = var.storage_class_name  # Cloud-agnostic
          size         = "20Gi"
        }
      }
      # Redis
      redis = {
        install = true
        master = {
          persistence = {
            storageClass = var.storage_class_name
            size         = "5Gi"
          }
        }
      }
      # Minio (S3-compatible)
      minio = {
        persistence = {
          storageClass = var.storage_class_name
          size         = "50Gi"
        }
      }
      # GitLab Runner
      gitlab-runner = {
        install = true
        runners = {
          config = <<-EOT
            [[runners]]
              [runners.kubernetes]
                namespace = "${kubernetes_namespace.gitlab.metadata[0].name}"
                image = "ubuntu:22.04"
                privileged = false
          EOT
        }
      }
      # Monitoring
      prometheus = {
        install = var.enable_monitoring
      }
      # Certmanager (usa o do platform-core)
      certmanager = {
        install = false
      }
      nginx-ingress = {
        enabled = false  # Usa NGINX do platform-core
      }
    })
  ]
}

# ===== SONARQUBE (Code Quality) =====

resource "helm_release" "sonarqube" {
  name       = "sonarqube"
  repository = "https://SonarSource.github.io/helm-chart-sonarqube"
  chart      = "sonarqube"
  version    = var.sonarqube_version
  namespace  = kubernetes_namespace.sonarqube.metadata[0].name

  values = [
    yamlencode({
      replicaCount = 1
      resources = {
        requests = {
          cpu    = "500m"
          memory = "2Gi"
        }
        limits = {
          cpu    = "2000m"
          memory = "4Gi"
        }
      }
      persistence = {
        enabled      = true
        storageClass = var.storage_class_name
        size         = "20Gi"
      }
      postgresql = {
        enabled = true
        persistence = {
          enabled      = true
          storageClass = var.storage_class_name
          size         = "10Gi"
        }
      }
      ingress = {
        enabled   = true
        ingressClassName = "nginx"
        hosts = [
          {
            name = var.sonarqube_domain
          }
        ]
        tls = [
          {
            secretName = "sonarqube-tls"
            hosts      = [var.sonarqube_domain]
          }
        ]
        annotations = {
          "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
        }
      }
      prometheusExporter = {
        enabled = var.enable_monitoring
      }
    })
  ]
}

# ===== HARBOR (Container Registry) =====

resource "helm_release" "harbor" {
  name       = "harbor"
  repository = "https://helm.goharbor.io"
  chart      = "harbor"
  version    = var.harbor_version
  namespace  = kubernetes_namespace.harbor.metadata[0].name
  timeout    = 600  # 10 min

  values = [
    yamlencode({
      expose = {
        type = "ingress"
        tls = {
          enabled = true
          certSource = "secret"
        }
        ingress = {
          hosts = {
            core = var.harbor_domain
          }
          className = "nginx"
          annotations = {
            "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
          }
        }
      }
      externalURL = "https://${var.harbor_domain}"
      persistence = {
        persistentVolumeClaim = {
          registry = {
            storageClass = var.storage_class_name
            size         = "100Gi"
          }
          chartmuseum = {
            storageClass = var.storage_class_name
            size         = "10Gi"
          }
          database = {
            storageClass = var.storage_class_name
            size         = "10Gi"
          }
          redis = {
            storageClass = var.storage_class_name
            size         = "1Gi"
          }
        }
      }
      harborAdminPassword = var.harbor_admin_password
      database = {
        type = "internal"
      }
      redis = {
        type = "internal"
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

# ===== ARGOCD (GitOps) =====

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    yamlencode({
      global = {
        domain = var.argocd_domain
      }
      server = {
        replicas = 2
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
        ingress = {
          enabled   = true
          ingressClassName = "nginx"
          hostname  = var.argocd_domain
          tls       = true
          annotations = {
            "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
            "nginx.ingress.kubernetes.io/ssl-passthrough" = "true"
            "nginx.ingress.kubernetes.io/backend-protocol" = "HTTPS"
          }
        }
        metrics = {
          enabled = var.enable_monitoring
          serviceMonitor = {
            enabled = var.enable_monitoring
          }
        }
      }
      controller = {
        replicas = 2
        resources = {
          requests = {
            cpu    = "500m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "2000m"
            memory = "2Gi"
          }
        }
        metrics = {
          enabled = var.enable_monitoring
          serviceMonitor = {
            enabled = var.enable_monitoring
          }
        }
      }
      repoServer = {
        replicas = 2
        resources = {
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "1000m"
            memory = "1Gi"
          }
        }
      }
      redis = {
        enabled = true
      }
      # Integração com Keycloak (platform-core)
      configs = {
        cm = {
          "admin.enabled" = "true"
          "url" = "https://${var.argocd_domain}"
          "dex.config" = <<-EOT
            connectors:
              - type: oidc
                id: keycloak
                name: Keycloak
                config:
                  issuer: ${var.keycloak_url}/realms/master
                  clientID: argocd
                  clientSecret: $oidc.keycloak.clientSecret
                  requestedScopes:
                    - openid
                    - profile
                    - email
          EOT
        }
      }
    })
  ]
}

# ===== BACKSTAGE (Developer Portal) =====

resource "helm_release" "backstage" {
  depends_on = [
    helm_release.gitlab,
    helm_release.argocd
  ]

  name       = "backstage"
  repository = "https://backstage.github.io/charts"
  chart      = "backstage"
  version    = var.backstage_version
  namespace  = kubernetes_namespace.backstage.metadata[0].name

  values = [
    yamlencode({
      backstage = {
        image = {
          repository = "spotify/backstage"
          tag        = "latest"
        }
        replicaCount = 2
        resources = {
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "1000m"
            memory = "1Gi"
          }
        }
        appConfig = {
          app = {
            title    = "Platform Engineering Portal"
            baseUrl  = "https://${var.backstage_domain}"
          }
          backend = {
            baseUrl = "https://${var.backstage_domain}"
            database = {
              client = "pg"
              connection = {
                host     = "backstage-postgresql"
                port     = 5432
                user     = "backstage"
                password = var.backstage_db_password
              }
            }
          }
          # Integração com GitLab
          integrations = {
            gitlab = [
              {
                host  = var.gitlab_domain
                token = var.gitlab_token
              }
            ]
          }
          # Software Templates
          catalog = {
            rules = [
              { allow = ["Component", "System", "API", "Resource", "Location"] }
            ]
          }
        }
      }
      postgresql = {
        enabled = true
        persistence = {
          enabled      = true
          storageClass = var.storage_class_name
          size         = "10Gi"
        }
      }
      ingress = {
        enabled   = true
        className = "nginx"
        host      = var.backstage_domain
        tls = {
          enabled    = true
          secretName = "backstage-tls"
        }
        annotations = {
          "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
        }
      }
    })
  ]
}

# ===== OUTPUTS =====

output "gitlab_url" {
  value       = "https://${var.gitlab_domain}"
  description = "GitLab URL"
}

output "sonarqube_url" {
  value       = "https://${var.sonarqube_domain}"
  description = "SonarQube URL"
}

output "harbor_url" {
  value       = "https://${var.harbor_domain}"
  description = "Harbor Registry URL"
}

output "argocd_url" {
  value       = "https://${var.argocd_domain}"
  description = "ArgoCD URL"
}

output "backstage_url" {
  value       = "https://${var.backstage_domain}"
  description = "Backstage Developer Portal URL"
}

output "namespaces" {
  value = {
    gitlab     = kubernetes_namespace.gitlab.metadata[0].name
    sonarqube  = kubernetes_namespace.sonarqube.metadata[0].name
    harbor     = kubernetes_namespace.harbor.metadata[0].name
    argocd     = kubernetes_namespace.argocd.metadata[0].name
    backstage  = kubernetes_namespace.backstage.metadata[0].name
  }
  description = "CI/CD Platform namespaces"
}

output "usage_instructions" {
  value = <<-EOT
    CI/CD Platform deployed successfully!
    
    1. GitLab: https://${var.gitlab_domain}
       - Initial root password: kubectl get secret -n ${kubernetes_namespace.gitlab.metadata[0].name} gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}' | base64 -d
    
    2. SonarQube: https://${var.sonarqube_domain}
       - Default credentials: admin/admin (change on first login)
    
    3. Harbor: https://${var.harbor_domain}
       - User: admin
       - Password: ${var.harbor_admin_password}
    
    4. ArgoCD: https://${var.argocd_domain}
       - User: admin
       - Password: kubectl get secret -n ${kubernetes_namespace.argocd.metadata[0].name} argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
    
    5. Backstage: https://${var.backstage_domain}
       - Integrated with GitLab catalog
    
    Next Steps:
    - Configure GitLab CI integration with SonarQube
    - Configure GitLab to push images to Harbor
    - Create ArgoCD Applications for domains
    - Register services in Backstage catalog
  EOT
  description = "Post-deployment instructions"
}

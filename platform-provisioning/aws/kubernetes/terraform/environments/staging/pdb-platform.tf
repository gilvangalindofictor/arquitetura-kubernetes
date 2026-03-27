# =============================================================================
# GAP-CONF-019 (P2): PodDisruptionBudgets — Platform Components (Staging)
# =============================================================================
# Problema: PDBs ausentes na maioria dos workloads de plataforma. Sem PDBs,
#   kubectl drain / node upgrades / cluster autoscaler podem terminar todos os
#   pods simultaneamente, causando downtime.
#
# Solucao: minAvailable=1 para todos os componentes criticos de plataforma.
#   Garante que ao menos 1 pod permanece Running durante voluntary disruptions
#   (drain, rolling update, spot reclamation).
#
# Componentes cobertos: ArgoCD, Keycloak, Harbor, GitLab, Backstage
#
# NOTA: Componentes com PDB ja existente (Cluster Autoscaler, Prometheus) nao
#   sao duplicados aqui — verificar cluster-autoscaler-protection.tf e modulo
#   kube-prometheus-stack.
#
# Ref: Kubernetes PDB documentation
#   https://kubernetes.io/docs/concepts/workloads/pods/disruptions/
# =============================================================================

# --- ArgoCD Server ---
# FinOps right-sizing (2026-03-27): switched to maxUnavailable=1 for single-replica staging.
# minAvailable=1 with 1 pod = allowedDisruptions=0 = blocks node drains.
resource "kubernetes_pod_disruption_budget_v1" "argocd_server" {
  metadata {
    name      = "argocd-server"
    namespace = "staging-platform-argocd"
    labels = {
      "app.kubernetes.io/name"       = "argocd-server"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-019"
    }
  }
  spec {
    max_unavailable = "1"
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "argocd-server"
      }
    }
  }
}

# --- ArgoCD Repo Server ---
# FinOps right-sizing (2026-03-27): switched to maxUnavailable=1 for single-replica staging.
resource "kubernetes_pod_disruption_budget_v1" "argocd_repo_server" {
  metadata {
    name      = "argocd-repo-server"
    namespace = "staging-platform-argocd"
    labels = {
      "app.kubernetes.io/name"       = "argocd-repo-server"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-019"
    }
  }
  spec {
    max_unavailable = "1"
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "argocd-repo-server"
      }
    }
  }
}

# --- ArgoCD Application Controller ---
resource "kubernetes_pod_disruption_budget_v1" "argocd_application_controller" {
  metadata {
    name      = "argocd-application-controller"
    namespace = "staging-platform-argocd"
    labels = {
      "app.kubernetes.io/name"       = "argocd-application-controller"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-019"
    }
  }
  spec {
    min_available = "1"
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "argocd-application-controller"
      }
    }
  }
}

# --- Keycloak ---
resource "kubernetes_pod_disruption_budget_v1" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = "staging-platform-keycloak"
    labels = {
      "app.kubernetes.io/name"       = "keycloak"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-019"
    }
  }
  spec {
    min_available = "1"
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "keycloakx"
      }
    }
  }
}

# --- Harbor Core ---
resource "kubernetes_pod_disruption_budget_v1" "harbor_core" {
  metadata {
    name      = "harbor-core"
    namespace = "harbor-system"
    labels = {
      "app.kubernetes.io/name"       = "harbor-core"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-019"
    }
  }
  spec {
    min_available = "1"
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "harbor"
        "app.kubernetes.io/component" = "core"
      }
    }
  }
}

# --- Harbor Registry ---
resource "kubernetes_pod_disruption_budget_v1" "harbor_registry" {
  metadata {
    name      = "harbor-registry"
    namespace = "harbor-system"
    labels = {
      "app.kubernetes.io/name"       = "harbor-registry"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-019"
    }
  }
  spec {
    min_available = "1"
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "harbor"
        "app.kubernetes.io/component" = "registry"
      }
    }
  }
}

# --- GitLab Webservice ---
resource "kubernetes_pod_disruption_budget_v1" "gitlab_webservice" {
  metadata {
    name      = "gitlab-webservice"
    namespace = "staging-platform-gitlab"
    labels = {
      "app.kubernetes.io/name"       = "gitlab-webservice"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-019"
    }
  }
  spec {
    min_available = "1"
    selector {
      match_labels = {
        "app" = "webservice"
      }
    }
  }
}

# --- GitLab Sidekiq ---
resource "kubernetes_pod_disruption_budget_v1" "gitlab_sidekiq" {
  metadata {
    name      = "gitlab-sidekiq"
    namespace = "staging-platform-gitlab"
    labels = {
      "app.kubernetes.io/name"       = "gitlab-sidekiq"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-019"
    }
  }
  spec {
    min_available = "1"
    selector {
      match_labels = {
        "app" = "sidekiq"
      }
    }
  }
}

# --- Backstage ---
resource "kubernetes_pod_disruption_budget_v1" "backstage" {
  metadata {
    name      = "backstage"
    namespace = "staging-platform-backstage"
    labels = {
      "app.kubernetes.io/name"       = "backstage"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-019"
    }
  }
  spec {
    min_available = "1"
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "backstage"
      }
    }
  }
}

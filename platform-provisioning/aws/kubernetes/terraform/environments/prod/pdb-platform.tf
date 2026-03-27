# =============================================================================
# GAP-CONF-019 (P2): PodDisruptionBudgets — Platform Components (Prod)
# =============================================================================
# Espelha staging/pdb-platform.tf para namespaces prod.
# minAvailable=1 para todos os componentes criticos de plataforma.
#
# Componentes cobertos: ArgoCD, Keycloak, Harbor, GitLab (shared), Backstage
#
# NOTA: GitLab e shared (staging namespace, gerenciado por prod TF) — PDB ja
#   esta em staging/pdb-platform.tf. Incluido aqui apenas para ArgoCD/Harbor/Keycloak prod.
# =============================================================================

# --- ArgoCD Server (prod) ---
resource "kubernetes_pod_disruption_budget_v1" "argocd_server_prod" {
  metadata {
    name      = "argocd-server"
    namespace = "prod-platform-argocd"
    labels = {
      "app.kubernetes.io/name"       = "argocd-server"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-019"
    }
  }
  spec {
    min_available = "1"
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "argocd-server"
      }
    }
  }
}

# --- ArgoCD Repo Server (prod) ---
resource "kubernetes_pod_disruption_budget_v1" "argocd_repo_server_prod" {
  metadata {
    name      = "argocd-repo-server"
    namespace = "prod-platform-argocd"
    labels = {
      "app.kubernetes.io/name"       = "argocd-repo-server"
      "app.kubernetes.io/managed-by" = "terraform"
      "gap"                          = "GAP-CONF-019"
    }
  }
  spec {
    min_available = "1"
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "argocd-repo-server"
      }
    }
  }
}

# --- ArgoCD Application Controller (prod) ---
resource "kubernetes_pod_disruption_budget_v1" "argocd_application_controller_prod" {
  metadata {
    name      = "argocd-application-controller"
    namespace = "prod-platform-argocd"
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

# --- Keycloak (prod) ---
resource "kubernetes_pod_disruption_budget_v1" "keycloak_prod" {
  metadata {
    name      = "keycloak"
    namespace = "prod-platform-keycloak"
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

# --- Harbor Core (prod) ---
resource "kubernetes_pod_disruption_budget_v1" "harbor_core_prod" {
  metadata {
    name      = "harbor-core"
    namespace = "prod-platform-harbor"
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

# --- Harbor Registry (prod) ---
resource "kubernetes_pod_disruption_budget_v1" "harbor_registry_prod" {
  metadata {
    name      = "harbor-registry"
    namespace = "prod-platform-harbor"
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

# --- Backstage (prod) ---
# NOTA: prod-platform-backstage atualmente vazio (GAP-BACKSTAGE-PROD-EMPTY).
# PDB criado preventivamente para quando o deploy ocorrer.
resource "kubernetes_pod_disruption_budget_v1" "backstage_prod" {
  metadata {
    name      = "backstage"
    namespace = "prod-platform-backstage"
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

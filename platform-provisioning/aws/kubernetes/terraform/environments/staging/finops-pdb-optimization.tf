# =============================================================================
# FinOps PDB Optimization — Staging
# =============================================================================
# Objetivo: PodDisruptionBudgets com minAvailable=0 para workloads críticos
#           Reduz tempo de node drain de 30min → <5min
#           Habilita Cluster Autoscaler scale-down eficiente
#
# Savings estimados:
#   Direto:   ~R$ 25/ano (redução de downtime em drains)
#   Indireto: ~R$ 4.380/ano (potencial eliminação de 1 node t3.large ociosos)
#
# ADR:     DEC-076 — FinOps PDB Optimization
# Logbook: 2026-02-24-finops-pdb-optimization.md
# Autor:   DevOps Platform Team
# =============================================================================

module "finops_pdb_optimization" {
  source = "../../modules/finops-pdb-optimization"

  workloads = {

    # -------------------------------------------------------------------------
    # Alta Prioridade — Workloads Stateless
    # -------------------------------------------------------------------------

    # Grafana — Monitoring dashboards (stateless, persiste config no PVC)
    # Labels validados: app.kubernetes.io/name=grafana (2026-02-24)
    grafana = {
      namespace     = "monitoring"
      min_available = 0
      selector = {
        "app.kubernetes.io/name"     = "grafana"
        "app.kubernetes.io/instance" = "kube-prometheus-stack"
      }
    }

    # ArgoCD Server — GitOps controller (stateless, estado no Git)
    # Labels validados: app.kubernetes.io/name=argocd-server, 2 replicas (2026-02-24)
    argocd-server = {
      namespace     = "argocd"
      min_available = 0
      selector = {
        "app.kubernetes.io/name" = "argocd-server"
      }
    }

    # Harbor Core — Container registry API (stateless, data no PostgreSQL/S3)
    # Labels validados: app=harbor,component=core, 2 replicas (2026-02-24)
    harbor-core = {
      namespace     = "harbor-system"
      min_available = 0
      selector = {
        app       = "harbor"
        component = "core"
      }
    }

    # GitLab Webservice — Web UI/API (stateless, estado no PostgreSQL/Redis)
    # Labels validados: app=webservice,release=gitlab, 2 replicas (2026-02-24)
    # NOTA: Deployment real: gitlab-webservice-default (não gitlab-webservice)
    gitlab-webservice = {
      namespace     = "gitlab-staging"
      min_available = 0
      selector = {
        app     = "webservice"
        release = "gitlab"
      }
    }

    # Keycloak — Identity Provider (stateful, estado no PostgreSQL)
    # Labels validados: app.kubernetes.io/name=keycloakx, StatefulSet (2026-02-24)
    # NOTA: Label real é "keycloakx" (chart keycloakx), não "keycloak"
    keycloak = {
      namespace     = "keycloak"
      min_available = 0
      selector = {
        "app.kubernetes.io/name"     = "keycloakx"
        "app.kubernetes.io/instance" = "keycloak"
      }
    }

    # SonarQube — Code quality (stateful, dados no PostgreSQL/PVC)
    # Labels validados: app=sonarqube, StatefulSet (2026-02-24)
    sonarqube = {
      namespace     = "sonarqube"
      min_available = 0
      selector = {
        app = "sonarqube"
      }
    }

    # -------------------------------------------------------------------------
    # Média Prioridade — Workloads Stateful com PVC
    # -------------------------------------------------------------------------

    # Vault — Secrets manager (stateful, dados no Raft/PVC)
    # Labels validados: app.kubernetes.io/name=vault, StatefulSet (2026-02-24)
    # CUIDADO: Vault pode precisar de unseal manual após restart
    vault = {
      namespace     = "staging-security-vault"
      min_available = 0
      selector = {
        "app.kubernetes.io/name"     = "vault"
        "app.kubernetes.io/instance" = "vault"
      }
    }

    # Prometheus — TSDB metrics (stateful, dados no PVC)
    # Labels validados: app.kubernetes.io/name=prometheus, StatefulSet (2026-02-24)
    # CUIDADO: Dados TSDB persistidos; drain causa gap de scraping (~5min tolerável)
    prometheus = {
      namespace     = "monitoring"
      min_available = 0
      selector = {
        "app.kubernetes.io/name"     = "prometheus"
        "app.kubernetes.io/instance" = "kube-prometheus-stack-prometheus"
      }
    }

    # Loki Backend — Log storage (stateful, dados no PVC/S3)
    # Labels validados: app.kubernetes.io/name=loki,component=backend (2026-02-24)
    # NOTA: PDB aplicado ao backend (índices); read/write têm PDBs próprios via Helm
    loki-backend = {
      namespace     = "monitoring"
      min_available = 0
      selector = {
        "app.kubernetes.io/name"      = "loki"
        "app.kubernetes.io/instance"  = "loki"
        "app.kubernetes.io/component" = "backend"
      }
    }

  }
}

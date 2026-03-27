# =============================================================================
# GAP-CONF-006: ArgoCD Prod — Application Manifests
#
# PROBLEMA: ArgoCD prod (prod-platform-argocd) tem ZERO Applications gerenciadas.
# Os workloads prod foram deployados manualmente via helm e estao fora do GitOps loop.
#
# SOLUCAO: Criar ArgoCD Application manifests para os workloads prod existentes:
#   1. Harbor prod (prod-platform-harbor)
#   2. Keycloak prod (prod-platform-keycloak)
#   3. Observability stack prod (prod-observability-monitoring)
#   4. Vault prod (prod-security-vault) — somente sync, NAO prune
#
# Padrao: baseado no Hatch ETL Application (docs/plan/backstage/argocd-hatch-etl-application.yaml)
# Sync: automated com prune + selfHeal (exceto Vault)
# Provider: kubectl_manifest (gavinbunney/kubectl)
#
# IMPORTANTE — PRE-REQUISITOS:
#   1. ArgoCD prod deve estar Running (2/2 Running confirmado 2026-03-26)
#   2. AppProject "platform" deve existir em prod-platform-argocd
#      Se nao existir, criar antes do apply:
#      kubectl apply -f - <<EOF
#      apiVersion: argoproj.io/v1alpha1
#      kind: AppProject
#      metadata:
#        name: platform
#        namespace: prod-platform-argocd
#      spec:
#        description: "Platform core services managed by GitOps"
#        sourceRepos: ["*"]
#        destinations:
#          - namespace: "prod-*"
#            server: "https://kubernetes.default.svc"
#        clusterResourceWhitelist:
#          - group: ""
#            kind: Namespace
#        namespaceResourceWhitelist:
#          - group: "*"
#            kind: "*"
#      EOF
#   3. Verificar se os repos Git abaixo sao acessiveis pelo ArgoCD
#
# NOTA: Estas Applications apontam para o repo IaC central.
# Os Helm releases sao gerenciados pelo Terraform (helm_release resources).
# As ArgoCD Applications servem como OBSERVADORES — sync policy=automated garante
# que drift manual seja revertido automaticamente.
# =============================================================================

# -----------------------------------------------------------------------------
# AppProject: platform (prod)
# Escopo: todos os namespaces prod-* com qualquer recurso
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "argocd_prod_appproject_platform" {
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: AppProject
    metadata:
      name: platform
      namespace: prod-platform-argocd
      labels:
        environment: prod
        domain: platform
        owner: platform-team
        app.kubernetes.io/managed-by: terraform
    spec:
      description: "Platform core services managed by GitOps (GAP-CONF-006)"
      sourceRepos:
        - "*"
      destinations:
        - namespace: "prod-*"
          server: "https://kubernetes.default.svc"
        - namespace: "kube-system"
          server: "https://kubernetes.default.svc"
      clusterResourceWhitelist:
        - group: ""
          kind: Namespace
        - group: rbac.authorization.k8s.io
          kind: ClusterRole
        - group: rbac.authorization.k8s.io
          kind: ClusterRoleBinding
      namespaceResourceWhitelist:
        - group: "*"
          kind: "*"
  YAML
}

# -----------------------------------------------------------------------------
# Application: Harbor Prod
# Namespace: prod-platform-harbor
# Helm release gerenciado por TF (helm_release.harbor_prod em main.tf L621)
# ArgoCD Application observa drift e reverte automaticamente
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "argocd_app_harbor_prod" {
  depends_on = [kubectl_manifest.argocd_prod_appproject_platform]

  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: harbor-prod
      namespace: prod-platform-argocd
      labels:
        environment: prod
        domain: platform
        owner: platform-team
        app: harbor
        app.kubernetes.io/name: harbor-prod
        app.kubernetes.io/part-of: platform-core
        managed-by: argocd
      annotations:
        argocd.argoproj.io/sync-wave: "10"
    spec:
      project: platform
      source:
        repoURL: https://helm.goharbor.io
        chart: harbor
        targetRevision: "1.18.2"
        helm:
          releaseName: harbor
          valueFiles: []
      destination:
        server: https://kubernetes.default.svc
        namespace: prod-platform-harbor
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
          allowEmpty: false
        syncOptions:
          - Validate=true
          - CreateNamespace=false
          - ServerSideApply=true
          - PrunePropagationPolicy=foreground
          - PruneLast=true
          - RespectIgnoreDifferences=true
        retry:
          limit: 3
          backoff:
            duration: 10s
            factor: 2
            maxDuration: 5m
      revisionHistoryLimit: 5
      ignoreDifferences:
        - group: apps
          kind: Deployment
          jsonPointers:
            - /spec/replicas
        - group: external-secrets.io
          kind: ExternalSecret
          jsonPointers:
            - /status
  YAML
}

# -----------------------------------------------------------------------------
# Application: Keycloak Prod
# Namespace: prod-platform-keycloak
# Helm release gerenciado por TF (module.keycloak_prod em main.tf L1101)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "argocd_app_keycloak_prod" {
  depends_on = [kubectl_manifest.argocd_prod_appproject_platform]

  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: keycloak-prod
      namespace: prod-platform-argocd
      labels:
        environment: prod
        domain: platform
        owner: platform-team
        app: keycloak
        app.kubernetes.io/name: keycloak-prod
        app.kubernetes.io/part-of: platform-core
        managed-by: argocd
      annotations:
        argocd.argoproj.io/sync-wave: "5"
    spec:
      project: platform
      source:
        repoURL: https://codecentric.github.io/helm-charts
        chart: keycloakx
        targetRevision: "7.1.7"
        helm:
          releaseName: keycloak
          valueFiles: []
      destination:
        server: https://kubernetes.default.svc
        namespace: prod-platform-keycloak
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
          allowEmpty: false
        syncOptions:
          - Validate=true
          - CreateNamespace=false
          - ServerSideApply=true
          - PrunePropagationPolicy=foreground
          - PruneLast=true
          - RespectIgnoreDifferences=true
        retry:
          limit: 3
          backoff:
            duration: 10s
            factor: 2
            maxDuration: 5m
      revisionHistoryLimit: 5
      ignoreDifferences:
        - group: apps
          kind: StatefulSet
          jsonPointers:
            - /spec/replicas
        - group: external-secrets.io
          kind: ExternalSecret
          jsonPointers:
            - /status
  YAML
}

# -----------------------------------------------------------------------------
# Application: Observability Stack Prod (kube-prometheus-stack)
# Namespace: prod-observability-monitoring
# Helm release sera gerenciado por TF (GAP-CONF-005 kube-prometheus-stack-helm.tf)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "argocd_app_observability_prod" {
  depends_on = [kubectl_manifest.argocd_prod_appproject_platform]

  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: observability-prod
      namespace: prod-platform-argocd
      labels:
        environment: prod
        domain: operations
        owner: platform-team
        app: kube-prometheus-stack
        app.kubernetes.io/name: observability-prod
        app.kubernetes.io/part-of: observability
        managed-by: argocd
      annotations:
        argocd.argoproj.io/sync-wave: "3"
    spec:
      project: platform
      source:
        repoURL: https://prometheus-community.github.io/helm-charts
        chart: kube-prometheus-stack
        targetRevision: "82.4.0"
        helm:
          releaseName: kube-prometheus-stack
          valueFiles: []
      destination:
        server: https://kubernetes.default.svc
        namespace: prod-observability-monitoring
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
          allowEmpty: false
        syncOptions:
          - Validate=true
          - CreateNamespace=false
          - ServerSideApply=true
          - PrunePropagationPolicy=foreground
          - PruneLast=true
          - RespectIgnoreDifferences=true
        retry:
          limit: 3
          backoff:
            duration: 10s
            factor: 2
            maxDuration: 5m
      revisionHistoryLimit: 5
      ignoreDifferences:
        - group: apps
          kind: Deployment
          jsonPointers:
            - /spec/replicas
        - group: apps
          kind: StatefulSet
          jsonPointers:
            - /spec/replicas
        - group: monitoring.coreos.com
          kind: Prometheus
          jsonPointers:
            - /spec/replicas
  YAML
}

# -----------------------------------------------------------------------------
# Application: Vault Prod
# Namespace: prod-security-vault
# Helm release gerenciado por TF (module.vault_prod em main.tf L495)
# IMPORTANTE: prune=false para Vault — NUNCA deletar PVCs/secrets via ArgoCD
# selfHeal=true para reverter drift manual
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "argocd_app_vault_prod" {
  depends_on = [kubectl_manifest.argocd_prod_appproject_platform]

  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: vault-prod
      namespace: prod-platform-argocd
      labels:
        environment: prod
        domain: security
        owner: platform-team
        app: vault
        app.kubernetes.io/name: vault-prod
        app.kubernetes.io/part-of: security
        managed-by: argocd
      annotations:
        argocd.argoproj.io/sync-wave: "1"
    spec:
      project: platform
      source:
        repoURL: https://helm.releases.hashicorp.com
        chart: vault
        targetRevision: "0.28.1"
        helm:
          releaseName: vault-prod
          valueFiles: []
      destination:
        server: https://kubernetes.default.svc
        namespace: prod-security-vault
      syncPolicy:
        automated:
          # PRUNE DESABILITADO para Vault — protecao contra delecao acidental de PVCs e secrets
          prune: false
          selfHeal: true
          allowEmpty: false
        syncOptions:
          - Validate=true
          - CreateNamespace=false
          - ServerSideApply=true
          - RespectIgnoreDifferences=true
        retry:
          limit: 3
          backoff:
            duration: 10s
            factor: 2
            maxDuration: 5m
      revisionHistoryLimit: 5
      ignoreDifferences:
        - group: apps
          kind: StatefulSet
          jsonPointers:
            - /spec/replicas
        - group: ""
          kind: Secret
          jsonPointers:
            - /data
  YAML
}

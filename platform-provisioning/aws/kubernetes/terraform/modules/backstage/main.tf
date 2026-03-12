# -----------------------------------------------------------------------------
# Backstage IDP Module
# Developer portal with Kubernetes, ArgoCD, SonarQube, GitLab, Vault plugins
# Secrets: Vault KV v2 + ESO (ADR-055)
# Decisions: ADR-055 (Backstage IDP), ADR-032 (ESO pattern), ADR-031 (Vault)
# Equalizado: 2026-03-06 (implantado manualmente em 2026-03-05)
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.25"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Kubernetes Namespace
# ADR-055: staging-platform-backstage (naming convention DEC-074/DEC-075)
# lifecycle.prevent_destroy: namespace contém dados de estado ESO e RBAC
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "backstage" {
  metadata {
    name = var.namespace

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"       = "backstage"
      "app.kubernetes.io/instance"   = "${var.cluster_name}-backstage"
      "app.kubernetes.io/component"  = "developer-portal"
      "app.kubernetes.io/part-of"    = "platform-core"
      "app.kubernetes.io/managed-by" = "terraform"
      # Labels do namespace original (implantado manualmente)
      "environment" = "staging"
      "domain"      = "platform"
      "product"     = "backstage"
    })

    annotations = {
      # Linkerd mTLS injection (ADR-011 / GAP-011)
      "linkerd.io/inject" = "enabled"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# ClusterRole: backstage-kubernetes-reader
# Read-only access to cluster resources for Backstage Kubernetes plugin
# lifecycle.prevent_destroy: RBAC crítico — remoção causa falha do plugin K8s
# -----------------------------------------------------------------------------

resource "kubernetes_cluster_role" "backstage_kubernetes_reader" {
  metadata {
    name = "backstage-kubernetes-reader"

    labels = {
      "app.kubernetes.io/name"       = "backstage"
      "app.kubernetes.io/instance"   = "${var.cluster_name}-backstage"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  # Core resources
  rule {
    api_groups = [""]
    resources  = ["pods", "configmaps", "services", "resourcequotas", "limitranges", "events", "serviceaccounts"]
    verbs      = ["get", "list", "watch"]
  }

  # Apps
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs      = ["get", "list", "watch"]
  }

  # Autoscaling
  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list", "watch"]
  }

  # Networking
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["get", "list", "watch"]
  }

  # Batch
  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch"]
  }

  # Metrics (Kubernetes metrics-server)
  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["pods", "nodes"]
    verbs      = ["get", "list"]
  }

  # ArgoCD CRDs (plugin ArgoCD)
  rule {
    api_groups = ["argoproj.io"]
    resources  = ["applications", "rollouts", "appprojects"]
    verbs      = ["get", "list", "watch"]
  }

  # External Secrets CRDs
  rule {
    api_groups = ["external-secrets.io"]
    resources  = ["externalsecrets", "clustersecretstores"]
    verbs      = ["get", "list", "watch"]
  }

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# ClusterRoleBinding: backstage-kubernetes-reader
# Binds ClusterRole to Backstage ServiceAccount (criado pelo Helm chart)
# -----------------------------------------------------------------------------

resource "kubernetes_cluster_role_binding" "backstage_kubernetes_reader" {
  metadata {
    name = "backstage-kubernetes-reader"

    labels = {
      "app.kubernetes.io/name"       = "backstage"
      "app.kubernetes.io/instance"   = "${var.cluster_name}-backstage"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.backstage_kubernetes_reader.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "backstage" # SA criado pelo Helm chart (serviceAccount.name=backstage)
    namespace = kubernetes_namespace.backstage.metadata[0].name
  }

  depends_on = [kubernetes_cluster_role.backstage_kubernetes_reader]
}

# -----------------------------------------------------------------------------
# Kyverno PolicyException: backstage-linkerd-exception
# Linkerd proxy-init requer NET_ADMIN/NET_RAW para regras iptables
# Escopo: SOMENTE namespace staging-platform-backstage (ADR-055 / MEDIO-2)
# Revisão agendada: 2026-09-05 (migrar para Linkerd native sidecars v2.15+)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "backstage_linkerd_exception" {
  depends_on = [kubernetes_namespace.backstage]

  yaml_body = <<-YAML
    apiVersion: kyverno.io/v2beta1
    kind: PolicyException
    metadata:
      name: backstage-linkerd-exception
      namespace: ${var.namespace}
      annotations:
        backstage.io/reason: "Linkerd proxy-init requires NET_ADMIN/NET_RAW for iptables rules"
        backstage.io/review-date: "2026-09-05"
        backstage.io/owner: platform-team
    spec:
      exceptions:
        - policyName: disallow-privilege-escalation
          ruleNames: [privilege-escalation]
        - policyName: disallow-capabilities
          ruleNames: [adding-capabilities]
      match:
        any:
          - resources:
              kinds: [Pod]
              namespaces: [${var.namespace}]
  YAML
}

# -----------------------------------------------------------------------------
# PodDisruptionBudget: backstage-pdb
# minAvailable=1 garante disponibilidade durante node drains / rolling updates
# M4: aumentar replicaCount para 2 (HA) quando aprovado
# -----------------------------------------------------------------------------

resource "kubernetes_pod_disruption_budget_v1" "backstage_pdb" {
  depends_on = [kubernetes_namespace.backstage]

  metadata {
    name      = "backstage-pdb"
    namespace = kubernetes_namespace.backstage.metadata[0].name

    labels = {
      "app.kubernetes.io/name"       = "backstage"
      "app.kubernetes.io/instance"   = "${var.cluster_name}-backstage"
      "app.kubernetes.io/managed-by" = "terraform"
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

# -----------------------------------------------------------------------------
# Vault Policy: backstage-policy
# Acesso a secrets do backstage + scaffolder capabilities (ADR-055)
# Vault path: secret/staging/backstage/*
# NOTA (MEDIO-1): create/update em secret/data/staging/+/* para Scaffolder
# RFC #32600: action customizada catalog:vault:write-namespace
# -----------------------------------------------------------------------------

resource "vault_policy" "backstage" {
  name = "backstage-policy"

  policy = <<-HCL
    # Lista paths disponíveis (plugin Vault UI — navegação sem expor valores)
    path "secret/metadata/*" {
      capabilities = ["list"]
    }

    # Ler secrets da plataforma (integrações externas — uso dos plugins)
    # Ex: tokens ArgoCD, SonarQube, Harbor robot account
    path "secret/data/platform/integrations/*" {
      capabilities = ["read"]
    }

    # Listar secrets por app (UI list-only — não expõe valores)
    path "secret/metadata/staging/+/*" {
      capabilities = ["list"]
    }

    # Scaffolder: criar namespace de nova app no Vault KV v2
    # Usado pela action customizada catalog:vault:write-namespace (MEDIO-1)
    path "secret/data/staging/+/*" {
      capabilities = ["create", "update"]
    }

    # Scaffolder: criar policy de nova app
    # Necessário para o template criar policy isolada por serviço
    path "sys/policies/acl/app-*" {
      capabilities = ["create", "update", "read"]
    }

    # Scaffolder: criar AppRole de nova app
    # Necessário para o template criar AppRole isolada por serviço
    path "auth/approle/role/app-*" {
      capabilities = ["create", "update", "read"]
    }
  HCL
}

# -----------------------------------------------------------------------------
# Vault Kubernetes Auth Role: backstage
# Vincula ServiceAccount backstage/staging-platform-backstage à policy
# TTL: 1h (menor exposição em caso de comprometimento do token)
# -----------------------------------------------------------------------------

resource "vault_kubernetes_auth_backend_role" "backstage" {
  backend   = "kubernetes"
  role_name = "backstage"

  bound_service_account_names      = ["backstage"]
  bound_service_account_namespaces = [var.namespace]

  token_policies = [vault_policy.backstage.name]
  token_ttl      = 3600  # 1h (ADR-055)
  token_max_ttl  = 14400 # 4h

  depends_on = [vault_policy.backstage]
}

# -----------------------------------------------------------------------------
# Vault KV v2 Secrets: estrutura (sem valores hardcoded)
# Os valores SENSÍVEIS são fornecidos via variáveis Terraform (sensitive=true)
# Vault paths: secret/staging/backstage/{database,keycloak,gitlab,argocd,
#              sonarqube,vault,eks,session}
# -----------------------------------------------------------------------------

# Database (PostgreSQL RDS)
resource "vault_kv_secret_v2" "backstage_database" {
  mount = "secret"
  name  = "staging/backstage/database"

  data_json = jsonencode({
    postgres-host     = var.backstage_db_host
    postgres-user     = var.backstage_db_user
    postgres-password = var.backstage_db_password
    postgres-port     = tostring(var.backstage_db_port)
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by = "terraform"
      service    = "backstage"
      cluster    = var.cluster_name
      adr        = "ADR-055"
    }
  }
}

# Keycloak OIDC (ADR-046)
resource "vault_kv_secret_v2" "backstage_keycloak" {
  mount = "secret"
  name  = "staging/backstage/keycloak"

  data_json = jsonencode({
    client-id     = var.backstage_keycloak_client_id
    client-secret = var.backstage_keycloak_client_secret
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by = "terraform"
      service    = "backstage"
      cluster    = var.cluster_name
      adr        = "ADR-055"
    }
  }
}

# GitLab integration token (Group Access Token — ALTO-2)
resource "vault_kv_secret_v2" "backstage_gitlab" {
  mount = "secret"
  name  = "staging/backstage/gitlab"

  data_json = jsonencode({
    token = var.backstage_gitlab_token
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by = "terraform"
      service    = "backstage"
      cluster    = var.cluster_name
      adr        = "ADR-055"
    }
  }
}

# ArgoCD plugin credentials
resource "vault_kv_secret_v2" "backstage_argocd" {
  mount = "secret"
  name  = "staging/backstage/argocd"

  data_json = jsonencode({
    url   = var.backstage_argocd_url
    token = var.backstage_argocd_token
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by = "terraform"
      service    = "backstage"
      cluster    = var.cluster_name
      adr        = "ADR-055"
    }
  }
}

# SonarQube plugin credentials
resource "vault_kv_secret_v2" "backstage_sonarqube" {
  mount = "secret"
  name  = "staging/backstage/sonarqube"

  data_json = jsonencode({
    url   = var.backstage_sonarqube_url
    token = var.backstage_sonarqube_token
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by = "terraform"
      service    = "backstage"
      cluster    = var.cluster_name
      adr        = "ADR-055"
    }
  }
}

# Vault plugin address (endereço interno do cluster)
resource "vault_kv_secret_v2" "backstage_vault" {
  mount = "secret"
  name  = "staging/backstage/vault"

  data_json = jsonencode({
    addr = var.backstage_vault_addr
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by = "terraform"
      service    = "backstage"
      cluster    = var.cluster_name
      adr        = "ADR-055"
    }
  }
}

# EKS Cluster URL (Kubernetes plugin)
resource "vault_kv_secret_v2" "backstage_eks" {
  mount = "secret"
  name  = "staging/backstage/eks"

  data_json = jsonencode({
    cluster-url = var.backstage_eks_cluster_url
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by = "terraform"
      service    = "backstage"
      cluster    = var.cluster_name
      adr        = "ADR-055"
    }
  }
}

# Session secret (autenticação Backstage)
resource "vault_kv_secret_v2" "backstage_session" {
  mount = "secret"
  name  = "staging/backstage/session"

  data_json = jsonencode({
    auth-session-secret = var.backstage_auth_session_secret
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by = "terraform"
      service    = "backstage"
      cluster    = var.cluster_name
      adr        = "ADR-055"
    }
  }
}

# Harbor registry credentials (Harbor plugin + Scaffolder M2)
resource "vault_kv_secret_v2" "backstage_harbor" {
  mount = "secret"
  name  = "staging/backstage/harbor"

  data_json = jsonencode({
    url          = var.backstage_harbor_url
    robot-token  = var.backstage_harbor_robot_token
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by = "terraform"
      service    = "backstage"
      cluster    = var.cluster_name
      adr        = "ADR-055"
    }
  }
}

# -----------------------------------------------------------------------------
# ExternalSecret: backstage-secrets
# Sincroniza todos os secrets do Vault para K8s Secret backstage-secrets
# ClusterSecretStore: vault-backend (eso-reader policy — paths adicionados abaixo)
# 13 data entries cobrindo todas as integrações do Backstage
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "backstage_externalsecret" {
  depends_on = [
    kubernetes_namespace.backstage,
    vault_kv_secret_v2.backstage_database,
    vault_kv_secret_v2.backstage_keycloak,
    vault_kv_secret_v2.backstage_gitlab,
    vault_kv_secret_v2.backstage_argocd,
    vault_kv_secret_v2.backstage_sonarqube,
    vault_kv_secret_v2.backstage_vault,
    vault_kv_secret_v2.backstage_eks,
    vault_kv_secret_v2.backstage_session,
    vault_kv_secret_v2.backstage_harbor,
  ]

  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: backstage-secrets
      namespace: ${var.namespace}
      labels:
        app.kubernetes.io/name: backstage
        app.kubernetes.io/instance: ${var.cluster_name}-backstage
        app.kubernetes.io/managed-by: terraform
      annotations:
        description: "Backstage IDP credentials synced from Vault KV v2 (ADR-055)"
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: vault-backend
        kind: ClusterSecretStore
      target:
        name: backstage-secrets
        creationPolicy: Owner
        template:
          engineVersion: v2
          metadata:
            labels:
              app.kubernetes.io/name: backstage
              app.kubernetes.io/instance: ${var.cluster_name}-backstage
      data:
        # ── PostgreSQL (RDS) ──────────────────────────────────────────────────
        - secretKey: postgres-host
          remoteRef:
            key: secret/staging/backstage/database
            property: postgres-host
        - secretKey: postgres-user
          remoteRef:
            key: secret/staging/backstage/database
            property: postgres-user
        - secretKey: postgres-password
          remoteRef:
            key: secret/staging/backstage/database
            property: postgres-password
        # ── Keycloak OIDC ─────────────────────────────────────────────────────
        - secretKey: keycloak-client-id
          remoteRef:
            key: secret/staging/backstage/keycloak
            property: client-id
        - secretKey: keycloak-client-secret
          remoteRef:
            key: secret/staging/backstage/keycloak
            property: client-secret
        # ── GitLab ────────────────────────────────────────────────────────────
        - secretKey: gitlab-token
          remoteRef:
            key: secret/staging/backstage/gitlab
            property: token
        # ── Vault addr (plugin) ───────────────────────────────────────────────
        - secretKey: vault-addr
          remoteRef:
            key: secret/staging/backstage/vault
            property: addr
        # ── ArgoCD ───────────────────────────────────────────────────────────
        - secretKey: argocd-url
          remoteRef:
            key: secret/staging/backstage/argocd
            property: url
        - secretKey: argocd-token
          remoteRef:
            key: secret/staging/backstage/argocd
            property: token
        # ── SonarQube ─────────────────────────────────────────────────────────
        - secretKey: sonarqube-url
          remoteRef:
            key: secret/staging/backstage/sonarqube
            property: url
        - secretKey: sonarqube-token
          remoteRef:
            key: secret/staging/backstage/sonarqube
            property: token
        # ── EKS Cluster URL (plugin Kubernetes) ───────────────────────────────
        - secretKey: eks-cluster-url
          remoteRef:
            key: secret/staging/backstage/eks
            property: cluster-url
        # ── Session Secret ────────────────────────────────────────────────────
        - secretKey: auth-session-secret
          remoteRef:
            key: secret/staging/backstage/session
            property: auth-session-secret
        # ── Harbor ────────────────────────────────────────────────────────────
        - secretKey: harbor-url
          remoteRef:
            key: secret/staging/backstage/harbor
            property: url
        - secretKey: harbor-robot-token
          remoteRef:
            key: secret/staging/backstage/harbor
            property: robot-token
  YAML
}

# -----------------------------------------------------------------------------
# Helm Release: Backstage
# Chart: backstage/backstage v2.6.3
# Image: harbor.staging.internal/platform/backstage:1.48.0
# Values: helm-values-staging.yaml (documentado em docs/plan/backstage/)
# ATENCAO (ALTO-1): skip-outbound-ports 443 obrigatório (Harbor + Linkerd mTLS)
# ATENCAO (ALTO-2): GitLab token deve ser Group Access Token (issue #30650)
# ATENCAO (ALTO-3): Validar metadataUrl Keycloak antes do deploy
# -----------------------------------------------------------------------------

resource "helm_release" "backstage" {
  name       = "backstage"
  repository = "https://backstage.github.io/charts"
  chart      = "backstage"
  version    = var.backstage_chart_version
  namespace  = kubernetes_namespace.backstage.metadata[0].name

  values = [templatefile("${path.module}/values.yaml.tpl", {
    cluster_name            = var.cluster_name
    namespace               = var.namespace
    image_tag               = var.backstage_image_tag
    image_registry          = var.backstage_image_registry
    backstage_chart_version = var.backstage_chart_version
    replicas                = var.replicas
    keycloak_host           = var.keycloak_host
    gitlab_host             = var.gitlab_host
    aws_account_id          = var.aws_account_id
    aws_region              = var.aws_region
  })]

  depends_on = [
    kubectl_manifest.backstage_externalsecret,
    kubernetes_cluster_role_binding.backstage_kubernetes_reader,
  ]

  timeout       = 600 # 10 min (pull de imagem harbor pode ser lento)
  recreate_pods = false

  # Ignora mudanças no appConfig (gerenciado fora do TF para evitar restarts desnecessários)
  lifecycle {
    ignore_changes = [
      set,
    ]
  }
}

# -----------------------------------------------------------------------------
# IRSA (IAM Role for Service Account): backstage-irsa-role
# Permite que o ServiceAccount backstage acesse S3 TechDocs
# Binding: eks.amazonaws.com/role-arn annotation no ServiceAccount (values.yaml.tpl)
# ADR-055 / GAP-006
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "backstage_irsa_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${var.aws_account_id}:oidc-provider/oidc.eks.${var.aws_region}.amazonaws.com/id/EC913B145BF356481CBE823532F09150"]
    }

    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${var.aws_region}.amazonaws.com/id/EC913B145BF356481CBE823532F09150:sub"
      values   = ["system:serviceaccount:${var.namespace}:backstage"]
    }

    condition {
      test     = "StringEquals"
      variable = "oidc.eks.${var.aws_region}.amazonaws.com/id/EC913B145BF356481CBE823532F09150:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backstage_irsa" {
  name               = "backstage-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.backstage_irsa_assume_role.json

  tags = merge(var.common_tags, {
    Name      = "backstage-irsa-role"
    Service   = "Backstage"
    Cluster   = var.cluster_name
    ManagedBy = "terraform"
    ADR       = "ADR-055"
  })
}

data "aws_iam_policy_document" "backstage_techdocs_s3" {
  statement {
    effect  = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::backstage-techdocs-${var.aws_account_id}",
      "arn:aws:s3:::backstage-techdocs-${var.aws_account_id}/*",
    ]
  }
}

resource "aws_iam_role_policy" "backstage_techdocs_s3" {
  name   = "backstage-techdocs-s3"
  role   = aws_iam_role.backstage_irsa.id
  policy = data.aws_iam_policy_document.backstage_techdocs_s3.json
}

# -----------------------------------------------------------------------------
# ArgoCD SA: backstage-scaffolder (GAP-009)
# SA separado com escopo mínimo de Create em Applications
# Separado do backstage-reader (read-only) — menor privilégio
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "argocd_scaffolder_sa" {
  depends_on = [kubernetes_namespace.backstage]

  yaml_body = <<-YAML
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: backstage-scaffolder
      namespace: staging-platform-argocd
      labels:
        app.kubernetes.io/name: backstage
        app.kubernetes.io/component: scaffolder
        app.kubernetes.io/managed-by: terraform
  YAML
}

resource "kubectl_manifest" "argocd_scaffolder_role" {
  depends_on = [kubectl_manifest.argocd_scaffolder_sa]

  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: Role
    metadata:
      name: backstage-scaffolder
      namespace: staging-platform-argocd
    rules:
      - apiGroups: ["argoproj.io"]
        resources: ["applications"]
        verbs: ["create", "get"]
      - apiGroups: [""]
        resources: ["secrets"]
        verbs: ["get"]
  YAML
}

resource "kubectl_manifest" "argocd_scaffolder_rolebinding" {
  depends_on = [kubectl_manifest.argocd_scaffolder_role]

  yaml_body = <<-YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: RoleBinding
    metadata:
      name: backstage-scaffolder
      namespace: staging-platform-argocd
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: Role
      name: backstage-scaffolder
    subjects:
      - kind: ServiceAccount
        name: backstage-scaffolder
        namespace: staging-platform-argocd
  YAML
}

# -----------------------------------------------------------------------------
# NetworkPolicy: Redis ← Backstage (GAP-013)
# Backstage usa Redis no keyspace /1 para session cache e plugin cache
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "redis_allow_backstage" {
  depends_on = [kubernetes_namespace.backstage]

  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: redis-allow-backstage
      namespace: staging-security-redis
      labels:
        app.kubernetes.io/managed-by: terraform
        purpose: backstage-session-cache
    spec:
      podSelector:
        matchLabels:
          app: redis-ha
      policyTypes:
        - Ingress
      ingress:
        - from:
            - namespaceSelector:
                matchLabels:
                  kubernetes.io/metadata.name: staging-platform-backstage
              podSelector:
                matchLabels:
                  app.kubernetes.io/name: backstage
          ports:
            - protocol: TCP
              port: 6379
  YAML
}

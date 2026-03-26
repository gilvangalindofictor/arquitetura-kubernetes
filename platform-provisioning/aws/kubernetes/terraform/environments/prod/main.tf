# PROD Environment Configuration
# Production-grade resources with HA, Multi-AZ, and 24/7 availability
# FinOps automation: deployment-scale strategy (node groups NOT touched — shared cluster)

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    # P0-07: Providers faltantes — equalizados com staging
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.25"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    # TASK-002: Keycloak IaC provider for realm, clients and groups management
    keycloak = {
      source  = "mrparkers/keycloak"
      version = "~> 4.4.0"
    }
    # GAP-011: Linkerd mTLS — TLS provider for trust anchor + issuer PKI generation
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    # FinOps prod automation Lambda ZIP packaging (2026-03-24)
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

# Local variables combining common.tfvars with environment-specific values
locals {
  environment  = "prod"
  cluster_name = "k8s-platform-prod" # Shared EKS cluster

  # Tag value for AWS Cost Explorer segmentation (prod → "production" for clarity)
  environment_tag = "production"

  common_tags = merge(var.base_tags, {
    Environment        = local.environment_tag
    DataClassification = "Sensitive"
    LGPD               = "PII" # Production data may contain PII
    CostCenter         = "production"
    Team               = "platform"
  })

  # K8s-safe common_tags: Environment="prod" (Kyverno only allows dev/staging/prod).
  # AWS tags use "production" for Cost Explorer; K8s labels must use "prod".
  k8s_common_tags = merge(local.common_tags, {
    Environment = local.environment  # "prod" — Kyverno-compliant (not "production")
  })
}

provider "aws" {
  region  = var.aws_region
  # profile = "k8s-platform-prod" # COMMENTED-SSO-WORKAROUND

  default_tags {
    tags = local.common_tags
  }
}

# Provider for sa-east-1 (LGPD compliance - FCT proposals bucket TASK-004)
provider "aws" {
  alias   = "sa_east_1"
  region  = "sa-east-1"
  # profile = "k8s-platform-prod" # COMMENTED-SSO-WORKAROUND

  default_tags {
    tags = local.common_tags
  }
}

# Get EKS cluster info (shared cluster from Marco 1)
data "aws_eks_cluster" "cluster" {
  name = local.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = local.cluster_name
}

# P0-07: Get OIDC Provider for IRSA (equalizado com staging)
data "aws_iam_openid_connect_provider" "eks" {
  url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}

# VPC and Subnets (existing from Marco 0)
data "aws_vpc" "existing" {
  id = var.vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name   = "tag:Name"
    values = ["*private*"]
  }
}

# Import EKS data from Marco1 (for OIDC provider, node groups, etc)
data "terraform_remote_state" "marco1" {
  backend = "s3"
  config = {
    bucket  = var.state_bucket
    key     = "marco1/terraform.tfstate"
    region  = var.aws_region
    # profile = "k8s-platform-prod" # COMMENTED-SSO-WORKAROUND
  }
}

#------------------------------------------------------------------------------
# DATA SERVICES - PROD (Production-Grade with HA)
#------------------------------------------------------------------------------

# PostgreSQL RDS - PROD (db.t3.medium, Multi-AZ, DT-004: production-grade HA)
module "postgresql_prod" {
  source = "../../modules/postgresql"

  cluster_name          = local.cluster_name
  vpc_id                = var.vpc_id
  vpc_cidr              = data.aws_vpc.existing.cidr_block
  private_subnet_ids    = data.aws_subnets.private.ids
  private_subnet_cidrs  = var.private_subnet_cidrs
  instance_class        = var.postgresql_instance_class        # db.t3.medium
  allocated_storage     = var.postgresql_allocated_storage     # 100 GB
  max_allocated_storage = var.postgresql_max_allocated_storage # 500 GB
  multi_az              = false                                # DEC-2026-03-24: defer Multi-AZ para go-live (staging-first strategy)
  deletion_protection   = true                                 # DT-004: Protect against accidental deletion in production
  environment           = "prod"                               # Secrets Manager prefix: prod/postgresql/...
  common_tags           = local.common_tags

  # LOCAL PORT-FORWARD OVERRIDES — 2026-03-24: permite TF runs locais via pg-tunnel pod
  # REMOVER APÓS IMPORTS CONCLUIDOS: postgresql_host_override / postgresql_port_override / master_password_override
  postgresql_host_override     = var.postgresql_host_override
  postgresql_port_override     = var.postgresql_port_override
  master_password_override     = var.master_password_override
}

# Redis Operator - PROD (3 replicas + Sentinel HA)
# GAP-HARBOR-REDIS-001 (2026-03-23): namespace + operator_namespace adicionados para
# isolar Redis prod de staging. Ambos usavam "data-services" (default do módulo).
# GAP-ADR048-REDIS-001 (2026-03-24): namespace corrigido de "data-services-prod" para
# "prod-data-infrastructure" — ADR-048 {env}-{domain}-{product} (Kyverno bloquearia)
# Espelha padrão de staging: staging-data-infrastructure.
module "redis_prod" {
  source = "../../modules/redis"

  cluster_name         = local.cluster_name
  namespace            = "prod-data-infrastructure"      # ADR-048: {env}-{domain}-{product} (era "data-services-prod" — violava Kyverno)
  operator_namespace   = "prod-data-redis-operator"      # GAP-HARBOR-REDIS-001: separado de staging-data-redis-operator
  monitoring_namespace = "prod-observability-monitoring" # ADR-048: prod monitoring namespace (default "monitoring" nao existe em prod)
  replicas             = var.redis_replicas               # 3
  pvc_size             = var.redis_pvc_size               # 10Gi
  storage_class        = "gp3"
  common_tags          = local.k8s_common_tags           # Kyverno-compliant: Environment="prod" (local.common_tags usa "production" para AWS Cost Explorer)
  install_operator     = false                           # Operator ja existe cluster-wide (staging-data-redis-operator). CRDs compartilhados. ClusterRole unica.
}

# ⚠️ GAP-RABBITMQ-NS-001 fix (2026-03-23): namespace adicionado explicitamente.
# NAMESPACE: prod-data-rabbitmq (ADR-048: {env}-{domain}-{product} — Kyverno bloqueia "data-services-prod")
# ANTES DE APPLY: executar runbook MIGRATION-rabbitmq-state.sh — migração controlada de data-services → prod-data-rabbitmq
# Estado atual cluster: RabbitMQ em "data-services" (idle: 0 conexões, 0 filas, 0 msgs)
# PV ReclaimPolicy: Retain (patchado pré-migração) | StorageClass novo: gp3/10Gi (era gp2/5Gi)

# RabbitMQ Operator - PROD (3 replicas with quorum)
module "rabbitmq_prod" {
  source = "../../modules/rabbitmq"

  cluster_name  = local.cluster_name
  namespace     = "prod-data-rabbitmq"  # GAP-RABBITMQ-NS-001 + ADR-048: {env}-{domain}-{product}
  replicas      = var.rabbitmq_replicas # 3
  pvc_size      = var.rabbitmq_pvc_size # 10Gi
  storage_class = "gp3"
  common_tags   = local.common_tags
  # NOTA: operator_namespace não existe neste módulo — operator instala em "rabbitmq-system" (fixo via kubectl).
}

# S3 Buckets - PROD (30d lifecycle)
module "s3_buckets_prod" {
  source = "../../modules/s3-buckets"

  providers = {
    aws           = aws
    aws.sa_east_1 = aws.sa_east_1
  }

  cluster_name   = local.cluster_name
  aws_account_id = var.aws_account_id
  common_tags    = local.common_tags
}

#------------------------------------------------------------------------------
# SECRETS MANAGEMENT (AWS Secrets Manager integration)
#------------------------------------------------------------------------------

# TODO: Create secret in AWS Secrets Manager: prod/postgresql/gitlab-password
# For now, using existing K8s secret gitlab-postgresql-password in gitlab namespace

# # PostgreSQL Password from AWS Secrets Manager
# data "aws_secretsmanager_secret" "postgresql_password" {
#   name = "prod/postgresql/gitlab-password"
# }

# data "aws_secretsmanager_secret_version" "postgresql_password" {
#   secret_id = data.aws_secretsmanager_secret.postgresql_password.id
# }

# resource "kubernetes_secret" "gitlab_postgresql_password" {
#   metadata {
#     name      = "gitlab-postgresql-password"
#     namespace = "data-services-prod"

#     labels = merge(local.common_tags, {
#       "app.kubernetes.io/name"     = "postgresql"
#       "app.kubernetes.io/instance" = "${local.cluster_name}-postgresql-prod"
#     })
#   }

#   data = {
#     password = data.aws_secretsmanager_secret_version.postgresql_password.secret_string
#   }

#   type = "Opaque"
# }

#------------------------------------------------------------------------------
# GITLAB CE (SHARED - One instance serving both STAGING and PROD)
# Deployed from PROD environment, used by both environments via project groups
# GitLab CE: shared instance, managed in staging state (DEC-2026-03-24)
# Namespace real: staging-platform-gitlab | Versão atual: 9.10.0 (upgrades manuais via helm)
#------------------------------------------------------------------------------

module "gitlab" {
  source = "../../modules/gitlab"

  depends_on = [
    module.postgresql_prod,
    module.redis_prod,
    module.s3_buckets_prod
  ]

  # Cluster info
  cluster_name   = local.cluster_name
  aws_account_id = var.aws_account_id
  aws_region     = var.aws_region
  namespace      = "staging-platform-gitlab"  # REAL namespace no cluster (DEC-074 drift corrigido 2026-03-24)
  environment    = "shared"               # Shared across STAGING and PROD

  # GitLab configuration
  gitlab_edition         = "ce"
  gitlab_version         = "9.10.0"
  gitlab_replicas        = var.gitlab_replicas        # 2
  gitlab_runner_replicas = var.gitlab_runner_replicas # 2

  # TLS configuration (ADR-021 Phase 1: disabled)
  enable_tls  = false
  domain_name = ""

  # PostgreSQL (external - uses PROD RDS for GitLab metadata)
  # Using RDS endpoint directly (ExternalName service temporarily commented)
  postgresql_host            = module.postgresql_prod.rds_address
  postgresql_port            = 5432
  postgresql_database        = "gitlab"
  postgresql_username        = "gitlab_user"
  postgresql_password_secret = "gitlab-postgresql-password" # Existing K8s secret

  # Redis (external - uses PROD Redis for GitLab cache/sessions)
  redis_host            = "${module.redis_prod.redis_master_service}.${module.redis_prod.namespace}.svc.cluster.local"
  redis_port            = module.redis_prod.redis_port
  redis_password_secret = module.redis_prod.redis_password_secret_name

  # S3 (IRSA)
  s3_artifacts_bucket = module.s3_buckets_prod.gitlab_artifacts_bucket_name
  s3_uploads_bucket   = module.s3_buckets_prod.gitlab_artifacts_bucket_name # Same bucket, different prefixes
  s3_policy_arn       = module.s3_buckets_prod.gitlab_s3_policy_arn

  # Monitoring
  enable_monitoring    = true
  monitoring_namespace = "prod-observability-monitoring"  # ADR-048: prod namespace (staging usa "monitoring")

  # Tags
  common_tags = local.common_tags
}

#------------------------------------------------------------------------------
# NETWORK POLICIES (Cross-Environment Isolation)
# PROD apps can ONLY access PROD data services
#------------------------------------------------------------------------------

# NetworkPolicy: Redis + PostgreSQL (prod-data-infrastructure)
# GAP-ADR048-REDIS-001 (2026-03-24): namespace corrigido de "data-services-prod" para "prod-data-infrastructure"
resource "kubectl_manifest" "netpol_deny_staging_access" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: deny-access-from-staging
      namespace: prod-data-infrastructure
    spec:
      podSelector: {}
      policyTypes:
        - Ingress
      ingress:
        # Allow PROD apps ONLY
        - from:
          - namespaceSelector:
              matchLabels:
                environment: prod
          ports:
            - protocol: TCP
              port: 6379  # Redis

        # Allow GitLab (shared namespace — P0-08: DEC-074 convention)
        - from:
          - namespaceSelector:
              matchLabels:
                name: prod-platform-gitlab
          ports:
            - protocol: TCP
              port: 6379  # GitLab uses PROD Redis

        # Allow monitoring (Prometheus scraping)
        - from:
          - namespaceSelector:
              matchLabels:
                name: prod-observability-monitoring
          ports:
            - protocol: TCP
              port: 9121  # Redis exporter
  YAML

  depends_on = [
    module.redis_prod
  ]
}

# NetworkPolicy: RabbitMQ (prod-data-rabbitmq) — ADR-048 namespace
# GAP-RABBITMQ-NS-001: segregado de staging, ADR-048 naming convention
resource "kubectl_manifest" "netpol_deny_staging_access_rabbitmq" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: deny-access-from-staging
      namespace: prod-data-rabbitmq
    spec:
      podSelector: {}
      policyTypes:
        - Ingress
      ingress:
        # Allow PROD apps ONLY
        - from:
          - namespaceSelector:
              matchLabels:
                environment: prod
          ports:
            - protocol: TCP
              port: 5672  # RabbitMQ AMQP
            - protocol: TCP
              port: 15672 # RabbitMQ Management UI

        # Allow monitoring (Prometheus scraping)
        - from:
          - namespaceSelector:
              matchLabels:
                name: prod-observability-monitoring
          ports:
            - protocol: TCP
              port: 15692 # RabbitMQ Prometheus metrics (plugin rabbitmq_prometheus)
  YAML

  depends_on = [
    module.rabbitmq_prod
  ]
}

#------------------------------------------------------------------------------
# OBSERVABILITY INTEGRATION (Hybrid - Shared Prometheus with Labels)
# Metrics/Logs from PROD will be labeled with environment=prod
#------------------------------------------------------------------------------

# ServiceMonitor for PROD PostgreSQL
# GAP-ADR048-REDIS-001 (2026-03-24): namespace corrigido de "data-services-prod" para "prod-data-infrastructure"
resource "kubectl_manifest" "servicemonitor_postgresql_prod" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: postgresql-prod
      namespace: prod-data-infrastructure
      labels:
        app: postgresql
        environment: prod
    spec:
      selector:
        matchLabels:
          app: postgresql
      endpoints:
        - port: metrics
          interval: 30s
          relabelings:
            - sourceLabels: [__meta_kubernetes_namespace]
              targetLabel: environment
              replacement: prod
  YAML

  depends_on = [module.postgresql_prod]
}

# ServiceMonitor for GitLab (shared)
resource "kubectl_manifest" "servicemonitor_gitlab" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: gitlab
      namespace: prod-platform-gitlab  # P0-08: DEC-074 namespace convention
      labels:
        app: gitlab
        environment: shared
    spec:
      selector:
        matchLabels:
          app: gitlab
      endpoints:
        - port: metrics
          interval: 30s
          relabelings:
            - sourceLabels: [__meta_kubernetes_namespace]
              targetLabel: environment
              replacement: shared
  YAML

  depends_on = [module.gitlab]
}

#------------------------------------------------------------------------------
# VAULT — PROD (HA 3 replicas, KMS auto-unseal, Raft storage)
#------------------------------------------------------------------------------
module "vault_prod" {
  source = "../../modules/vault"

  cluster_name      = local.cluster_name
  aws_account_id    = var.aws_account_id
  aws_region        = var.aws_region
  environment       = "prod"
  namespace         = "prod-security-vault"
  oidc_provider_arn = data.aws_iam_openid_connect_provider.eks.arn

  replicas      = 3
  storage_class = "gp3"
  pvc_size      = "20Gi"

  helm_release_name = "vault-prod"                    # Unique name to avoid cluster-scoped resource conflicts with staging
  injector_enabled  = false                            # Staging already has injector (cluster-scoped resources conflict)
  enable_monitoring = true
  iam_name_override = "VaultIRSA-k8s-platform-prod"   # Brownfield: role pre-exists without env prefix (avoid destroy+recreate)

  # GAP-SCHED-002 Phase 2: pin vault-prod-0/1/2 to workload nodes (already running there — codifying intent)
  node_selector = {
    "eks.amazonaws.com/nodegroup" = "workloads"
  }

  common_tags = local.common_tags
}

#------------------------------------------------------------------------------
# EXTERNAL SECRETS OPERATOR — PROD (Vault backend)
#------------------------------------------------------------------------------
module "external_secrets_prod" {
  source = "../../modules/external-secrets"

  depends_on = [module.vault_prod]

  cluster_name              = local.cluster_name
  environment               = "prod"
  namespace                 = "prod-security-externalsecrets"
  replicas                  = 2
  vault_addr                = "http://vault-prod.prod-security-vault.svc.cluster.local:8200"
  monitoring_namespace      = "prod-observability-monitoring"
  enable_monitoring         = true
  cluster_secret_store_name = "vault-backend-prod" # GAP-SEC-ESO-001: CSS isolado (não compartilha com staging vault-backend)

  common_tags = local.common_tags
}

#------------------------------------------------------------------------------
# VAULT CONFIG — PROD (K8s auth, policies, secrets seeding)
#------------------------------------------------------------------------------
module "vault_config_prod" {
  source = "../../modules/vault-config"

  # NOTE: depends_on incompatible — vault-config defines internal provider
  # Apply sequentially AFTER vault_prod and external_secrets_prod

  vault_addr  = "http://localhost:8200" # Requires: kubectl port-forward -n prod-security-vault svc/vault 8200:8200
  vault_token = var.vault_root_token

  environment        = "prod"
  vault_external_url = "http://vault.prod.internal"

  cluster_name       = local.cluster_name
  kubernetes_host    = data.aws_eks_cluster.cluster.endpoint
  kubernetes_ca_cert = data.aws_eks_cluster.cluster.certificate_authority[0].data
  eso_namespace      = "prod-security-externalsecrets"
  eso_service_account = "external-secrets"

  keycloak_postgresql_password = var.keycloak_postgresql_password
  keycloak_postgresql_username = "keycloak_user"
  keycloak_postgresql_host     = module.postgresql_prod.rds_address
  keycloak_postgresql_port     = "5432"
  keycloak_postgresql_database = "keycloak"

  oidc_enabled             = false # Enable after Keycloak prod is running
  keycloak_oidc_url        = ""
  vault_oidc_client_id     = "vault"
  vault_oidc_client_secret = var.vault_oidc_client_secret

  grafana_oidc_client_id     = "grafana"
  grafana_oidc_client_secret = var.grafana_oidc_client_secret
  grafana_admin_password     = var.grafana_admin_password

  sonarqube_postgresql_password = var.sonarqube_postgresql_password
  sonarqube_postgresql_host     = module.postgresql_prod.rds_address

  harbor_postgresql_password = var.harbor_postgresql_password
  harbor_postgresql_host     = module.postgresql_prod.rds_address
  harbor_admin_password      = var.harbor_admin_password
  harbor_redis_password      = var.harbor_redis_password

  argocd_postgresql_password = var.argocd_postgresql_password
  argocd_postgresql_host     = module.postgresql_prod.rds_address
  argocd_oidc_client_secret  = var.argocd_oidc_client_secret

  keycloak_admin_password = var.keycloak_admin_password

  hatch_etl_enabled = false

  common_tags = local.common_tags
}

#------------------------------------------------------------------------------
# HARBOR PROD — Helm release IaC codification (GAP-SCHED-001 fix 2026-03-23)
# Harbor prod was deployed manually via Helm into prod-platform-harbor.
# The module harbor/main.tf is staging-only (uses vault-backend).
# Codified here for zero-drift compliance. Import command:
#   terraform import helm_release.harbor_prod prod-platform-harbor/harbor
#
# Secrets (existingSecret) are managed by kubectl_manifest resources below.
# nodeSelector: workloads added 2026-03-23 (GAP-SCHED-001 — was on system nodes)
#
# KNOWN ISSUE: helm upgrade --dry-run fails with existingSecret + redis template.
# This is a harbor chart 1.18.2 bug: template tries to render Secret contents in
# dry-run but the Secret API call is blocked. Real apply works (secret exists in cluster).
#------------------------------------------------------------------------------

resource "helm_release" "harbor_prod" {
  name             = "harbor"
  repository       = "https://helm.goharbor.io"
  chart            = "harbor"
  version          = "1.18.2"
  namespace        = "prod-platform-harbor"
  create_namespace = false

  depends_on = [
    kubectl_manifest.harbor_prod_postgresql_externalsecret,
    kubectl_manifest.harbor_prod_exporter_externalsecret,
    kubectl_manifest.harbor_prod_redis_externalsecret, # FIX-004: Redis ESO must exist before Helm reads existingSecret
  ]

  values = [<<-YAML
    fullnameOverride: harbor-prod
    chartmuseum:
      enabled: false
    notary:
      enabled: false
    updateStrategy:
      type: RollingUpdate

    existingSecretAdminPassword: harbor-admin-credentials
    existingSecretAdminPasswordKey: HARBOR_ADMIN_PASSWORD

    externalURL: http://harbor.prod.internal

    expose:
      type: ingress
      tls:
        enabled: false
      ingress:
        className: alb
        hosts:
          core: harbor.prod.internal
        annotations:
          alb.ingress.kubernetes.io/scheme: internal
          alb.ingress.kubernetes.io/target-type: ip
          alb.ingress.kubernetes.io/backend-protocol: HTTP
          alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
          alb.ingress.kubernetes.io/healthcheck-path: /api/v2.0/health
          # FIX-005 (2026-03-25): Moved Harbor to dedicated IngressGroup.
          # Was: platform-prod (shared with ArgoCD/Keycloak which use scheme=internet-facing).
          # Harbor uses scheme=internal, causing FailedBuildModel events (205+ events)
          # because ALB controller cannot reconcile conflicting scheme annotations
          # within the same IngressGroup. Separate group = separate internal ALB.
          alb.ingress.kubernetes.io/group.name: platform-prod-internal

    database:
      type: external
      external:
        host: ${module.postgresql_prod.rds_address}
        port: 5432
        username: harbor_user
        existingSecret: harbor-postgresql-credentials
        coreDatabase: harbor
        notaryServerDatabase: notaryserver
        notarySignerDatabase: notarysigner
        sslmode: require

    redis:
      type: external
      external:
        # GAP-HARBOR-REDIS-001 (2026-03-23): usar TF output para seguir namespace do módulo.
        # Antes: hardcoded "redis.data-services.svc.cluster.local:6379" → apontava para staging Redis.
        # Após fix namespace isolation (data-services-prod), aplicar via helm upgrade manual:
        #   helm upgrade harbor harbor/harbor -n prod-platform-harbor \
        #     --reuse-values --set redis.external.addr="${module.redis_prod.redis_master_service}.${module.redis_prod.namespace}.svc.cluster.local:${module.redis_prod.redis_port}"
        addr: "${module.redis_prod.redis_master_service}.${module.redis_prod.namespace}.svc.cluster.local:${module.redis_prod.redis_port}"
        existingSecret: harbor-redis-credentials

    persistence:
      enabled: true
      persistentVolumeClaim:
        registry:
          storageClass: gp3
          size: 10Gi
        jobservice:
          storageClass: gp3
          size: 2Gi

    imageChartStorage:
      type: s3
      s3:
        region: us-east-1
        bucket: k8s-platform-harbor-images-891377105802
        regionendpoint: https://s3.us-east-1.amazonaws.com
        encrypt: true
        secure: true

    core:
      serviceAccountName: harbor
      replicas: 2
      podAnnotations:
        config.linkerd.io/skip-outbound-ports: "6379,5432"
      podLabels:
        domain: platform
        environment: prod
      resources:
        requests:
          memory: 512Mi
          cpu: 200m
        limits:
          memory: 1500Mi
          cpu: "1"
      tolerations:
        - key: node-type
          operator: Equal
          value: system
          effect: NoSchedule
        - key: workload
          operator: Equal
          value: critical
          effect: NoSchedule
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                topologyKey: topology.kubernetes.io/zone
                labelSelector:
                  matchExpressions:
                    - key: component
                      operator: In
                      values: [core]

    jobservice:
      serviceAccountName: harbor
      replicas: 1
      strategy:
        type: Recreate
      podAnnotations:
        config.linkerd.io/skip-outbound-ports: "80"
      podLabels:
        domain: platform
        environment: prod
      resources:
        requests:
          memory: 256Mi
          cpu: 100m
        limits:
          memory: 768Mi
          cpu: 500m
      tolerations:
        - key: node-type
          operator: Equal
          value: system
          effect: NoSchedule
        - key: workload
          operator: Equal
          value: critical
          effect: NoSchedule

    registry:
      serviceAccountName: harbor
      strategy:
        type: Recreate
      podLabels:
        domain: platform
        environment: prod
      registry:
        resources:
          requests:
            memory: 256Mi
            cpu: 100m
          limits:
            memory: 1Gi
            cpu: 500m
      controller:
        resources:
          requests:
            memory: 256Mi
            cpu: 100m
          limits:
            memory: 768Mi
            cpu: 500m
      tolerations:
        - key: node-type
          operator: Equal
          value: system
          effect: NoSchedule
        - key: workload
          operator: Equal
          value: critical
          effect: NoSchedule

    portal:
      replicas: 2
      podLabels:
        domain: platform
        environment: prod
      resources:
        requests:
          memory: 128Mi
          cpu: 50m
        limits:
          memory: 256Mi
          cpu: 200m
      tolerations:
        - key: node-type
          operator: Equal
          value: system
          effect: NoSchedule
        - key: workload
          operator: Equal
          value: critical
          effect: NoSchedule
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                topologyKey: topology.kubernetes.io/zone
                labelSelector:
                  matchExpressions:
                    - key: component
                      operator: In
                      values: [portal]

    trivy:
      enabled: true
      persistence:
        enabled: true
        storageClass: gp3
        size: 10Gi
      podLabels:
        domain: platform
        environment: prod
      resources:
        requests:
          cpu: 200m
          memory: 512Mi
        limits:
          cpu: "1"
          memory: 2Gi
      tolerations:
        - key: node-type
          operator: Equal
          value: system
          effect: NoSchedule
        - key: workload
          operator: Equal
          value: critical
          effect: NoSchedule

    # GAP-SCHED-001 (2026-03-23): nodeSelector added — was landing on system nodes
    exporter:
      podLabels:
        domain: platform
        environment: prod
      resources:
        requests:
          memory: 128Mi
          cpu: 50m
        limits:
          memory: 256Mi
          cpu: 200m
      nodeSelector:
        eks.amazonaws.com/nodegroup: workloads
      tolerations:
        - key: node-type
          operator: Equal
          value: system
          effect: NoSchedule
        - key: workload
          operator: Equal
          value: critical
          effect: NoSchedule

    metrics:
      enabled: true
      serviceMonitor:
        enabled: true
        additionalLabels:
          environment: prod
  YAML
  ]

  lifecycle {
    # Ignore chart version updates until manually reviewed (prod stability)
    # GAP-TRIVY-DNS (2026-03-24): removed `values` from ignore_changes so that
    # redis.external.addr and other values are managed by TF going forward.
    # Redis addr corrected: data-services → prod-data-infrastructure.
    ignore_changes = [
      version,
    ]
  }
}

#------------------------------------------------------------------------------
# HARBOR PROD — ExternalSecrets (GAP-HARBOR-PROD-01 fix 2026-03-21)
# These ExternalSecrets use vault-backend-prod (Vault prod KV).
# Manual fix applied 2026-03-21: RDS harbor_user password reset to match Vault.
# IaC codification: ensures idempotent re-apply won't break the namespace.
#------------------------------------------------------------------------------

resource "kubectl_manifest" "harbor_prod_postgresql_externalsecret" {
  depends_on = [module.vault_config_prod, module.external_secrets_prod]

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "harbor-postgresql-credentials"
      namespace = "prod-platform-harbor"
      labels = {
        "app.kubernetes.io/name"       = "harbor-postgresql-credentials"
        "app.kubernetes.io/managed-by" = "terraform"
        "environment"                  = "prod"
        "domain"                       = "platform"
      }
      annotations = {
        description = "Harbor prod PostgreSQL credentials from Vault KV v2 — GAP-HARBOR-PROD-01 (2026-03-21)"
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "vault-backend-prod"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "harbor-postgresql-credentials"
        creationPolicy = "Merge"
        deletionPolicy = "Retain"
      }
      data = [
        {
          secretKey = "password"
          remoteRef = {
            key      = "secret/data/harbor/postgresql"
            property = "password"
          }
        },
        {
          secretKey = "username"
          remoteRef = {
            key      = "secret/data/harbor/postgresql"
            property = "username"
          }
        },
        {
          secretKey = "host"
          remoteRef = {
            key      = "secret/data/harbor/postgresql"
            property = "host"
          }
        },
        {
          secretKey = "port"
          remoteRef = {
            key      = "secret/data/harbor/postgresql"
            property = "port"
          }
        },
        {
          secretKey = "database"
          remoteRef = {
            key      = "secret/data/harbor/postgresql"
            property = "database"
          }
        }
      ]
    }
  })
}

resource "kubectl_manifest" "harbor_prod_exporter_externalsecret" {
  depends_on = [module.vault_config_prod, module.external_secrets_prod]

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "harbor-prod-exporter"
      namespace = "prod-platform-harbor"
      labels = {
        "app.kubernetes.io/name"       = "harbor-prod-exporter"
        "app.kubernetes.io/managed-by" = "terraform"
        "environment"                  = "prod"
        "domain"                       = "platform"
      }
      annotations = {
        description = "Harbor prod exporter DB credentials from Vault KV v2 — GAP-HARBOR-PROD-01 (2026-03-21)"
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "vault-backend-prod"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "harbor-prod-exporter"
        creationPolicy = "Merge"
        deletionPolicy = "Retain"
      }
      data = [
        {
          secretKey = "HARBOR_DATABASE_PASSWORD"
          remoteRef = {
            key      = "secret/data/harbor/postgresql"
            property = "password"
          }
        },
        {
          secretKey = "password"
          remoteRef = {
            key      = "secret/data/harbor/postgresql"
            property = "password"
          }
        }
      ]
    }
  })
}

#------------------------------------------------------------------------------
# FIX-004 (2026-03-25): Harbor prod Redis ExternalSecret — anti-regression fix.
# PROBLEM: Redis password was patched manually on 5 resources (harbor-core,
#   harbor-jobservice, harbor-registry, harbor-trivy, harbor-exporter).
#   Next `helm upgrade` would revert to empty password because the Helm chart
#   reads from existingSecret: harbor-redis-credentials, but that K8s Secret
#   did NOT exist as an ESO-managed resource in prod.
# FIX: Create ExternalSecret mirroring the pattern of harbor_prod_postgresql_externalsecret.
#   Vault path: secret/data/harbor/redis (seeded by vault-config module, V-005).
#   Key: REDIS_PASSWORD (expected by Harbor chart redis.external.existingSecret).
# NOTE: Redis password uses special=false in vault-config/main.tf (GAP-TRIVY-DNS 2026-03-24),
#   so no URL-encoding is required in connection strings.
#------------------------------------------------------------------------------

resource "kubectl_manifest" "harbor_prod_redis_externalsecret" {
  depends_on = [module.vault_config_prod, module.external_secrets_prod]

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "harbor-redis-credentials"
      namespace = "prod-platform-harbor"
      labels = {
        "app.kubernetes.io/name"       = "harbor-redis-credentials"
        "app.kubernetes.io/managed-by" = "terraform"
        "environment"                  = "prod"
        "domain"                       = "platform"
      }
      annotations = {
        description = "Harbor prod Redis credentials from Vault KV v2 — FIX-004 anti-regression (2026-03-25)"
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "vault-backend-prod"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "harbor-redis-credentials"
        creationPolicy = "Merge"      # Merge: preserves manually-patched keys until ESO overwrites
        deletionPolicy = "Retain"     # Retain: deleting TF resource won't nuke the K8s Secret
      }
      data = [
        {
          # Harbor chart redis.external.existingSecret expects key: REDIS_PASSWORD
          secretKey = "REDIS_PASSWORD"
          remoteRef = {
            key      = "secret/data/harbor/redis"
            property = "password"
          }
        }
      ]
    }
  })
}

#------------------------------------------------------------------------------
# KEYCLOAK — PROD (HA 2 replicas, RDS prod)
#------------------------------------------------------------------------------
module "keycloak_prod" {
  source = "../../modules/keycloak"

  depends_on = [
    module.postgresql_prod,
    module.external_secrets_prod,
    module.vault_config_prod,
  ]

  cluster_name   = local.cluster_name
  aws_region     = var.aws_region
  environment    = "prod"
  namespace      = "prod-platform-keycloak"

  keycloak_chart_version = "7.1.7"
  replicas               = 2

  postgresql_host     = module.postgresql_prod.rds_address
  postgresql_port     = 5432
  postgresql_database = "keycloak"
  postgresql_username = "keycloak_user"

  keycloak_hostname    = "keycloak.prod.internal"
  monitoring_namespace = "prod-observability-monitoring"

  enable_monitoring   = true
  acm_certificate_arn = "" # TODO: Add prod ACM cert ARN in Fase 5
  secret_store_name   = module.external_secrets_prod.cluster_secret_store_name # GAP-SEC-ESO-001: vault-backend-prod

  common_tags = local.common_tags
}

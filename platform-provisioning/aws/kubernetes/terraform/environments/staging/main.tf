# STAGING Environment Configuration
# Cost-optimized resources for development/testing workloads
# FinOps automation enabled (auto-shutdown 18h-8h BRT)

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
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.25"
    }
  }
}

# Local variables combining common.tfvars with environment-specific values
locals {
  environment = "staging"
  # NOTE: cluster_name uses "prod" because staging shares the same EKS cluster (ADR-050).
  # This is the physical cluster name in AWS, not an environment indicator.
  cluster_name = "k8s-platform-prod"

  common_tags = merge(var.base_tags, {
    Environment        = local.environment
    DataClassification = "Internal"
    LGPD               = "Synthetic" # No PII in staging
    CostCenter         = "development"
  })
}

provider "aws" {
  region  = var.aws_region
  profile = "k8s-platform-staging"

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

# Get OIDC Provider for IRSA
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

# Get private subnet details for CIDR blocks
data "aws_subnet" "private" {
  for_each = toset(data.aws_subnets.private.ids)
  id       = each.value
}

# Import EKS data from Marco1 (for OIDC provider, node groups, etc)
data "terraform_remote_state" "marco1" {
  backend = "s3"
  config = {
    bucket  = var.state_bucket
    key     = "marco1/terraform.tfstate"
    region  = var.aws_region
    profile = "k8s-platform-staging"
  }
}

#------------------------------------------------------------------------------
# DATA SERVICES - STAGING (Cost-Optimized)
#------------------------------------------------------------------------------

# PostgreSQL RDS - STAGING (db.t3.micro, single-AZ)
module "postgresql_staging" {
  source = "../../modules/postgresql"

  cluster_name          = local.cluster_name
  vpc_id                = var.vpc_id
  vpc_cidr              = data.aws_vpc.existing.cidr_block
  private_subnet_ids    = data.aws_subnets.private.ids
  private_subnet_cidrs  = [for s in data.aws_subnet.private : s.cidr_block]
  instance_class        = var.postgresql_instance_class        # db.t3.micro
  allocated_storage     = var.postgresql_allocated_storage     # 20 GB
  max_allocated_storage = var.postgresql_max_allocated_storage # 50 GB
  common_tags           = local.common_tags

  # RDS was recreated on 2026-02-09 outside TF with a different master password.
  # This override uses the actual SM password so the PostgreSQL provider can connect.
  master_password_override = data.aws_secretsmanager_secret_version.rds_actual_master.secret_string

  # Bootstrap additional databases (Harbor, Keycloak)
  additional_databases = [
    {
      name     = "harbor"
      username = "harbor_user"
      password = data.aws_secretsmanager_secret_version.postgresql_password.secret_string
    },
    {
      name     = "keycloak"
      username = "keycloak_user"
      password = "PLACEHOLDER_VAULT_MANAGED" # Managed by Vault KV v2 + ExternalSecret
    }
  ]
}

# Redis Operator - STAGING (1 replica, no Sentinel)
module "redis_staging" {
  source = "../../modules/redis"

  cluster_name  = local.cluster_name
  replicas      = var.redis_replicas # 1
  pvc_size      = var.redis_pvc_size # 5Gi
  storage_class = "gp3"              # Using gp3 (20% cheaper, 3000 IOPS default)
  common_tags   = local.common_tags

  # Toleration for critical nodes (ADR-041 pattern)
  tolerations = [{
    key      = "workload"
    operator = "Equal"
    value    = "critical"
    effect   = "NoSchedule"
  }]
}

# RabbitMQ Operator - STAGING (1 replica, no quorum)
module "rabbitmq_staging" {
  source = "../../modules/rabbitmq"

  cluster_name  = local.cluster_name
  namespace     = "data-services"       # Fixed: was using default "default"
  replicas      = var.rabbitmq_replicas # 1
  pvc_size      = var.rabbitmq_pvc_size # 5Gi
  storage_class = "gp3"                 # Using gp3 (20% cheaper, 3000 IOPS default)
  common_tags   = local.common_tags

  # ALB Ingress for Management UI
  ingress_enabled    = true
  ingress_host       = "rabbitmq.staging.internal"
  ingress_group_name = "data-staging"
}

# S3 Buckets - STAGING (7d lifecycle)
module "s3_buckets_staging" {
  source = "../../modules/s3-buckets"

  cluster_name   = local.cluster_name
  aws_account_id = var.aws_account_id
  common_tags    = local.common_tags
}

#------------------------------------------------------------------------------
# SECRETS MANAGEMENT (AWS Secrets Manager integration)
#------------------------------------------------------------------------------

# PostgreSQL Password from AWS Secrets Manager
data "aws_secretsmanager_secret" "postgresql_password" {
  name = "staging/postgresql/gitlab-password"
}

data "aws_secretsmanager_secret_version" "postgresql_password" {
  secret_id = data.aws_secretsmanager_secret.postgresql_password.id
}

# Actual RDS master password (RDS was recreated on 2026-02-09 outside TF)
# This secret contains the current working master credentials
data "aws_secretsmanager_secret_version" "rds_actual_master" {
  secret_id = "k8s-platform-prod/postgresql-master-20260209142555506800000001"
}

# Keycloak PostgreSQL Password via Vault + ExternalSecrets
# Decision: R-029 RESOLVED - Vault backend desde inception (refactored before deploy)
# Secret managed by External Secrets Operator (ClusterSecretStore: vault-backend)
# Vault path: secret/data/keycloak/postgresql

resource "kubernetes_secret" "gitlab_postgresql_password" {
  metadata {
    name      = "gitlab-postgresql-password"
    namespace = "gitlab-staging" # Changed from data-services to gitlab-staging

    labels = merge(local.common_tags, {
      "app.kubernetes.io/name"     = "postgresql"
      "app.kubernetes.io/instance" = "${local.cluster_name}-postgresql-staging"
    })
  }

  data = {
    password = module.postgresql_staging.gitlab_user_password # Changed from master password
  }

  type = "Opaque"
}

#------------------------------------------------------------------------------
# GITLAB - STAGING (Migrated from envs/marco3)
# Using centralized module from ../../modules/gitlab
# Integrated with staging data services (PostgreSQL, Redis, S3)
#------------------------------------------------------------------------------

module "gitlab_staging" {
  source = "../../modules/gitlab"

  depends_on = [
    module.postgresql_staging,
    module.redis_staging,
    module.s3_buckets_staging,
    kubernetes_secret.gitlab_postgresql_password
  ]

  # Cluster info
  cluster_name   = local.cluster_name
  aws_account_id = var.aws_account_id
  aws_region     = var.aws_region
  namespace      = "gitlab-staging"
  environment    = local.environment

  # GitLab configuration
  gitlab_edition         = "ce"
  gitlab_version         = "8.7.0"
  gitlab_replicas        = 1 # Cost-optimized for staging
  gitlab_runner_replicas = 1 # Cost-optimized for staging

  # TLS configuration (ADR-021 Phase 1: disabled)
  enable_tls  = false
  domain_name = ""

  # PostgreSQL (external - RDS via module)
  postgresql_host            = module.postgresql_staging.rds_address
  postgresql_port            = 5432
  postgresql_database        = "gitlab"
  postgresql_username        = "gitlab_user"
  postgresql_password_secret = kubernetes_secret.gitlab_postgresql_password.metadata[0].name

  # Redis (external - Spotahome Redis Operator)
  redis_host            = "${module.redis_staging.redis_master_service}.${module.redis_staging.namespace}.svc.cluster.local"
  redis_port            = module.redis_staging.redis_port
  redis_password_secret = module.redis_staging.redis_password_secret_name

  # S3 (IRSA)
  s3_artifacts_bucket = module.s3_buckets_staging.gitlab_artifacts_bucket_name
  s3_uploads_bucket   = module.s3_buckets_staging.gitlab_artifacts_bucket_name # Same bucket, different prefixes
  s3_policy_arn       = module.s3_buckets_staging.gitlab_s3_policy_arn

  # Monitoring
  enable_monitoring = true

  # Authentication (OIDC with Keycloak)
  enable_oidc        = true
  ingress_group_name = "gitlab-staging"

  # Tags
  common_tags = local.common_tags
}

#------------------------------------------------------------------------------
# SECRETS & SECURITY INFRASTRUCTURE
# Vault HA + External Secrets Operator + Harbor Container Registry
# ADR-031, ADR-032, ADR-033
#------------------------------------------------------------------------------

# Vault - STAGING (1 replica, KMS auto-unseal, Raft single-node)
module "vault_staging" {
  source = "../../modules/vault"

  cluster_name        = local.cluster_name
  aws_account_id      = var.aws_account_id
  aws_region          = var.aws_region
  namespace           = "vault-system"
  oidc_provider_arn   = data.aws_iam_openid_connect_provider.eks.arn
  vault_chart_version = "0.27.0"
  replicas            = 1     # Single replica for staging (FinOps cost-optimized)
  storage_class       = "gp3" # Using gp3 (20% cheaper, 3000 IOPS default)
  pvc_size            = "10Gi"
  enable_monitoring   = true
  common_tags         = local.common_tags

  # Tolerate critical workload nodes (ADR-041 Option D)
  tolerations = [{
    key      = "workload"
    operator = "Equal"
    value    = "critical"
    effect   = "NoSchedule"
  }]

  # ALB Ingress for Vault UI
  ingress_enabled    = true
  ingress_host       = "vault.staging.internal"
  ingress_group_name = "platform-staging"
}

# External Secrets Operator - Vault Backend
module "external_secrets_staging" {
  source = "../../modules/external-secrets"

  depends_on = [module.vault_staging]

  cluster_name      = local.cluster_name
  namespace         = "external-secrets-system"
  eso_chart_version = "0.9.11"
  replicas          = 1 # Cost-optimized for staging
  vault_addr        = "http://vault.vault-system.svc.cluster.local:8200"
  enable_monitoring = true
  common_tags       = local.common_tags
}

# Vault Post-Deployment Configuration
# K8s auth, policies, roles, and Keycloak secrets
module "vault_config_staging" {
  source = "../../modules/vault-config"

  vault_addr  = "http://localhost:8200" # Requires: kubectl port-forward -n vault-system svc/vault 8200:8200
  vault_token = var.vault_root_token

  cluster_name        = local.cluster_name
  kubernetes_host     = data.aws_eks_cluster.cluster.endpoint
  kubernetes_ca_cert  = data.aws_eks_cluster.cluster.certificate_authority[0].data
  eso_namespace       = "external-secrets-system"
  eso_service_account = "external-secrets"

  # Keycloak PostgreSQL credentials
  keycloak_postgresql_password = var.keycloak_postgresql_password
  keycloak_postgresql_username = "keycloak_user"
  keycloak_postgresql_host     = "postgresql-external.default.svc.cluster.local"
  keycloak_postgresql_port     = "5432"
  keycloak_postgresql_database = "keycloak"

  common_tags = local.common_tags
}

# Harbor Container Registry - STAGING (IRSA S3 storage)
module "harbor_staging" {
  source = "../../modules/harbor"

  depends_on = [
    module.postgresql_staging,
    module.redis_staging,
    module.s3_buckets_staging
  ]

  cluster_name         = local.cluster_name
  aws_account_id       = var.aws_account_id
  aws_region           = var.aws_region
  namespace            = "harbor-system"
  oidc_provider_arn    = data.aws_iam_openid_connect_provider.eks.arn
  harbor_chart_version = "1.14.0"

  # S3 Storage (IRSA)
  s3_bucket_name = module.s3_buckets_staging.harbor_images_bucket_name
  s3_bucket_arn  = module.s3_buckets_staging.harbor_images_bucket_arn

  # PostgreSQL (shared RDS) - using FQDN from default namespace
  postgresql_host     = "postgresql-external.default.svc.cluster.local"
  postgresql_port     = 5432
  postgresql_database = "harbor"
  postgresql_username = "harbor_user"

  # Redis (shared Operator)
  redis_host            = "${module.redis_staging.redis_master_service}.${module.redis_staging.namespace}.svc.cluster.local"
  redis_port            = module.redis_staging.redis_port
  redis_password_secret = module.redis_staging.redis_password_secret_name

  # Options
  storage_class     = "gp2"
  enable_trivy      = false # DISABLED: chart não aplica storageClass em volumeClaimTemplate
  enable_monitoring = true
  common_tags       = local.common_tags

  # ALB Ingress for Harbor UI
  ingress_enabled    = true
  ingress_host       = "harbor.staging.internal"
  ingress_group_name = "platform-staging"

  # OIDC / SSO via Keycloak
  enable_oidc   = true
  oidc_endpoint = "http://keycloak.staging.internal/auth/realms/platform"
}

#------------------------------------------------------------------------------
# KEYCLOAK - SSO Platform (GAP-001)
# OIDC provider for ArgoCD, SonarQube, GitLab
# Pattern: Vault KV v2 + ExternalSecrets Operator (R-029 RESOLVED)
#------------------------------------------------------------------------------

module "keycloak_staging" {
  source = "../../modules/keycloak"

  depends_on = [
    module.postgresql_staging,
    module.external_secrets_staging,
    module.vault_config_staging
  ]

  # Cluster info
  cluster_name = local.cluster_name
  aws_region   = var.aws_region
  namespace    = "keycloak"

  # Keycloak configuration
  keycloak_chart_version = "7.1.7" # Updated to codecentric/keycloakx (Quarkus 26.5.1)
  replicas               = 1       # Staging: 1 replica accepted. PROD: set to 2

  # PostgreSQL (external - RDS via postgresql_staging module)
  postgresql_host     = "postgresql-external.default.svc.cluster.local"
  postgresql_port     = 5432
  postgresql_database = "keycloak"
  postgresql_username = "keycloak_user"

  # Monitoring
  enable_monitoring = true

  # Tags
  common_tags = local.common_tags
}

#------------------------------------------------------------------------------
# ARGOCD - GitOps Platform (GAP-003)
# OIDC integration with Keycloak, external PostgreSQL, RBAC
# Pattern: Following Keycloak deployment (K8s secrets due to Vault permissions issue)
#------------------------------------------------------------------------------

module "argocd_staging" {
  source = "../../modules/argocd"

  depends_on = [
    module.keycloak_staging,
    module.postgresql_staging
  ]

  # Cluster info
  cluster_name = local.cluster_name
  namespace    = "argocd"

  # ArgoCD configuration
  argocd_chart_version = "5.51.6"
  replicas             = 2 # HA for critical GitOps service

  # Keycloak OIDC integration
  keycloak_url       = "http://keycloak-http.keycloak.svc.cluster.local/auth"
  keycloak_client_id = "argocd"

  # Domain (internal only for staging)
  domain = "argocd.staging.internal"

  # ALB Ingress
  ingress_enabled    = true
  ingress_group_name = "platform-staging"

  # Monitoring
  enable_monitoring = true

  # Tags
  common_tags = local.common_tags
}

#------------------------------------------------------------------------------
# SONARQUBE - Code Quality Platform
# OIDC integration with Keycloak, external PostgreSQL
#------------------------------------------------------------------------------

module "sonarqube_staging" {
  source = "../../modules/sonarqube"

  depends_on = [
    module.postgresql_staging,
    module.keycloak_staging
  ]

  cluster_name    = local.cluster_name
  namespace       = "sonarqube"
  postgresql_host = module.postgresql_staging.rds_address

  # ALB Ingress
  ingress_enabled    = true
  domain             = "sonarqube.staging.internal"
  ingress_group_name = "platform-staging"

  # SAML 2.0 Authentication (Keycloak)
  # Replaces OIDC (Community Edition does not support native OIDC)
  saml_enabled     = true
  saml_provider_id = "http://keycloak.staging.internal/auth/realms/platform"
  saml_login_url   = "http://keycloak.staging.internal/auth/realms/platform/protocol/saml"
  saml_certificate = <<-EOT
    MIICnzCCAYcCBgGcNLCnZTANBgkqhkiG9w0BAQsFADATMREwDwYDVQQDDAhwbGF0Zm9ybTAeFw0yNjAyMDYyMDQwMThaFw0zNjAyMDYyMDQxNThaMBMxETAPBgNVBAMMCHBsYXRmb3JtMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAmRnrzQQYRhDLYpp0aSz6xPOnAUSDZLFolGT7FOl4ez4z17ssMm7W5Xw5K3Bb4fI4e2gAudpczCh67VI1G97tLQcaPSf5uzsRrq4Y3iAD9VzKp8fT1hJRQSrIxm/QJxHJN9a/+LFP0l2txSbPrJyIZimR+THtH9CGX+BuYZN0M9bUwxHpvcxb/kRO1niwqNbR+gSDHkdIv1UMcd7BDCJBZuiM9spWvBoWKbv3aqP7y9oIx3wMBg7tLQ4fbDR0PNqiQnvLedR40sN7DJrzv3bab+GPm3rSArMA8PBISHawOcZ6b94TfKl+rSLJoXjppD1hBdjuk6S5j0y9tnxgu5+XAQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQBO18QIRIi8UQZC+98WgV98q5iZchM4n+MlU25Rpxdo+xUhtbBMKSVotyWEZo6FXT3pf1rY2A83CcsGb+EKNyynC0rMir9ggu0yR13zho8T+nYoewdACSwey3oH2fwbMI9aT1oc9Z/GQyLmCrBWIcG3qNwRoyqzBOSZzfx9/YX9b8D1CIzQhgjIjMgFAM5HmmT5j8wnmBJfUnAjMtihOXJSAGDgKO8LBRaFz6w62IKFo596aJottqgYnC/SKlv44qGicnBkClejlZnrlX+ENbvmKvGMCQojmECR4q7WtOZc9KjOPxS5GfUoIT5vhhbCrQouydrSBp6He1IRnFC/cypL
  EOT

  # Storage (gp3 — match existing PVC created on 2026-02-18)
  storage_class = "gp3"

  # Monitoring
  enable_monitoring = true

  # Tags
  common_tags = local.common_tags
}

#------------------------------------------------------------------------------
# KUBE-PROMETHEUS-STACK - Observability (Grafana ALB Ingress)
# Prometheus + Grafana + Alertmanager
#------------------------------------------------------------------------------

module "kube_prometheus_stack_staging" {
  source = "../../modules/kube-prometheus-stack"

  namespace              = "monitoring"
  grafana_admin_password = "admin" # TODO: Mover para Vault/SecretsManager

  # Pin to deployed version (cluster is running 81.4.2 since 2026-02-05)
  chart_version = "81.4.2"

  # Grafana ALB Ingress
  grafana_ingress_enabled    = true
  grafana_ingress_host       = "grafana.staging.internal"
  grafana_ingress_group_name = "observability-staging"
}

#------------------------------------------------------------------------------
# FINOPS AUTOMATION (STAGING ONLY)
# Auto-shutdown: 18h BRT (21h UTC) Mon-Fri
# Auto-startup: 08h BRT (11h UTC) Mon-Fri
# Economy: ~R$ 204/mês (70% time offline)
#------------------------------------------------------------------------------

# Get STAGING ASG names (nodes tagged with environment=staging)
data "aws_autoscaling_groups" "eks_nodes_staging" {
  filter {
    name   = "tag:kubernetes.io/cluster/${local.cluster_name}"
    values = ["owned"]
  }
  filter {
    name   = "tag:environment"
    values = ["staging"]
  }
}

module "finops_automation_staging" {
  source = "../../modules/finops-automation"

  environment  = local.environment
  cluster_name = local.cluster_name

  # Schedule: shutdown 20h BRT, startup 7h30 BRT (Mon-Fri)
  # BRT (Brasil Time) = UTC-3
  enable_automation = true
  shutdown_schedule = "cron(0 23 ? * MON-FRI *)"  # 20h00 BRT = 23h00 UTC
  startup_schedule  = "cron(30 10 ? * MON-FRI *)" # 07h30 BRT = 10h30 UTC

  # Resources to manage
  rds_instance_id = module.postgresql_staging.db_instance_id
  asg_names       = data.aws_autoscaling_groups.eks_nodes_staging.names

  # Circuit breaker
  circuit_breaker_threshold = 3

  # SNS notifications
  enable_sns_notifications = false # Usar apenas tópico externo (finops-alerts-staging)
  sns_topic_arn            = aws_sns_topic.finops_alerts_staging.arn

  # Tags
  tags = local.common_tags
}

resource "aws_sns_topic" "finops_alerts_staging" {
  name = "${local.cluster_name}-finops-alerts-staging"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "finops_email" {
  topic_arn = aws_sns_topic.finops_alerts_staging.arn
  protocol  = "email"
  endpoint  = var.finops_alert_email
}

#------------------------------------------------------------------------------
# GAP-009: Weekend Shutdown - Now handled by finops-automation module
# The module includes weekend_shutdown_schedule variable (default: Saturday 00h BRT)
# Economy: R$ 96-120/ano (prevents weekend waste)
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# NETWORK POLICIES (Cross-Environment Isolation)
# STAGING apps can ONLY access STAGING data services
# TODO: Enable after creating app-staging namespace
#------------------------------------------------------------------------------

# resource "kubectl_manifest" "netpol_deny_prod_access" {
#   yaml_body = <<-YAML
#     apiVersion: networking.k8s.io/v1
#     kind: NetworkPolicy
#     metadata:
#       name: deny-access-to-prod-dataservices
#       namespace: app-staging
#     spec:
#       podSelector: {}
#       policyTypes:
#         - Egress
#       egress:
#         # Allow STAGING dataservices ONLY
#         - to:
#           - namespaceSelector:
#               matchLabels:
#                 environment: staging
#           ports:
#             - protocol: TCP
#               port: 5432  # PostgreSQL
#             - protocol: TCP
#               port: 6379  # Redis
#             - protocol: TCP
#               port: 5672  # RabbitMQ
#
#         # Allow DNS resolution
#         - to:
#           - namespaceSelector:
#               matchLabels:
#                 name: kube-system
#           ports:
#             - protocol: UDP
#               port: 53
#
#         # Allow internet access (for package downloads, etc)
#         - to:
#           - namespaceSelector: {}
#           ports:
#             - protocol: TCP
#               port: 443
#             - protocol: TCP
#               port: 80
#   YAML
#
#   depends_on = [
#     module.postgresql_staging,
#     module.redis_staging,
#     module.rabbitmq_staging
#   ]
# }

#------------------------------------------------------------------------------
# OBSERVABILITY INTEGRATION (Hybrid - Shared Prometheus with Labels)
# Metrics/Logs from STAGING will be labeled with environment=staging
#------------------------------------------------------------------------------

# ServiceMonitor for STAGING PostgreSQL
resource "kubectl_manifest" "servicemonitor_postgresql_staging" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: postgresql-staging
      namespace: monitoring
      labels:
        app: postgresql
        environment: staging
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
              replacement: staging
  YAML

  depends_on = [module.postgresql_staging]
}

#------------------------------------------------------------------------------
# OPENTELEMETRY COLLECTOR - STAGING
# Gateway mode for centralized OTLP reception and forwarding to Tempo/Loki/Prometheus
# GAP-7 Implementation - 2026-02-09
#------------------------------------------------------------------------------

module "opentelemetry_collector_staging" {
  source = "../../modules/opentelemetry-collector"

  release_name  = "opentelemetry-collector"
  chart_version = "0.108.0"
  namespace     = "monitoring"

  # HA configuration (Performance Specialist requirement)
  replicas = 2

  # Resources (cost-optimized para staging, aprovado por FinOps)
  resources = {
    requests = {
      cpu    = "100m"
      memory = "256Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }

  # Memory limiter (80% de limits, Perf Specialist recommendation)
  memory_limiter_limit_mib = 400

  # HPA (Performance Specialist requirement — previne trace drop em burst)
  enable_hpa             = true
  hpa_min_replicas       = 2
  hpa_max_replicas       = 5
  hpa_target_cpu_percent = 70

  # PDB (Performance Specialist requirement — HA durante rolling updates)
  enable_pdb = true

  # ServiceMonitor (Observability integration)
  enable_servicemonitor   = true
  servicemonitor_interval = "30s"
}

#------------------------------------------------------------------------------
# VPC Endpoint for ELB API
# Fix: AWS Load Balancer Controller TLS handshake timeout
# Root cause: No VPC Endpoint → traffic via NAT Gateway → intermittent latency
# Solution: Route ELB API traffic within VPC (latency <5ms vs ~20-50ms NAT)
# Economy: Zero cost (Interface endpoints included), eliminates NAT SPOF
# ADR: TBD (load-balancer-controller-fix)
#------------------------------------------------------------------------------

data "aws_security_group" "cluster" {
  vpc_id = var.vpc_id
  filter {
    name   = "group-name"
    values = ["eks-cluster-sg-${local.cluster_name}-*"]
  }
}

resource "aws_vpc_endpoint" "elasticloadbalancing" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.elasticloadbalancing"
  vpc_endpoint_type = "Interface"

  subnet_ids = [
    "subnet-0472ab28726cdf745", # private-us-east-1a
    "subnet-0288a67cd352effa7"  # private-us-east-1b
  ]

  security_group_ids = [
    data.aws_security_group.cluster.id
  ]

  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name        = "${local.cluster_name}-vpce-elasticloadbalancing-${local.environment}"
    Purpose     = "Fix AWS LB Controller TLS timeout"
    Cost        = "Zero (included)"
    Criticality = "High"
  })
}

#------------------------------------------------------------------------------
# VPC Endpoint for KMS API
# Fix: Vault cluster quorum loss (auto-unseal TLS timeout)
# Root cause: No VPC Endpoint → traffic via NAT Gateway → intermittent latency
# Solution: Route KMS API traffic within VPC (latency <5ms vs ~20-50ms NAT)
# Economy: Enables EBS Wave 3 (R$ 162/ano), cost $86.40/ano
# ADR: ADR-055 (vault-kms-recovery)
#------------------------------------------------------------------------------

resource "aws_vpc_endpoint" "kms" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.kms"
  vpc_endpoint_type = "Interface"

  subnet_ids = [
    "subnet-0472ab28726cdf745", # private-us-east-1a
    "subnet-0288a67cd352effa7"  # private-us-east-1b
  ]

  security_group_ids = [
    data.aws_security_group.cluster.id
  ]

  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name        = "${local.cluster_name}-vpce-kms-${local.environment}"
    Purpose     = "Vault KMS auto-unseal"
    Cost        = "$86.40/ano"
    Criticality = "High"
    ADR         = "ADR-055"
  })
}

#------------------------------------------------------------------------------
# VPC Endpoint for S3 (Gateway Type)
# Improves S3 performance for Vault snapshots and eliminates NAT Gateway data transfer costs
# Type: Gateway (zero cost, automatically routes S3 traffic via VPC)
# Economy: Zero cost + reduces NAT Gateway data transfer charges
#------------------------------------------------------------------------------

data "aws_route_table" "private_us_east_1a" {
  vpc_id = var.vpc_id
  filter {
    name   = "association.subnet-id"
    values = ["subnet-0472ab28726cdf745"] # private-us-east-1a
  }
}

data "aws_route_table" "private_us_east_1b" {
  vpc_id = var.vpc_id
  filter {
    name   = "association.subnet-id"
    values = ["subnet-0288a67cd352effa7"] # private-us-east-1b
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    data.aws_route_table.private_us_east_1a.id,
    data.aws_route_table.private_us_east_1b.id
  ]

  tags = merge(local.common_tags, {
    Name        = "${local.cluster_name}-vpce-s3-${local.environment}"
    Purpose     = "Vault S3 snapshots + Harbor images"
    Cost        = "Zero (Gateway type)"
    Criticality = "Medium"
  })
}

#------------------------------------------------------------------------------
# FinOps Observability — Grafana Dashboards + Prometheus Alerts
# Deploys ConfigMaps with Grafana sidecar label for auto-discovery.
# Dashboards: AWS Costs Overview, Resource Utilization, FinOps Alerts
# Prometheus Alerts: Init container CrashLoop detection
#------------------------------------------------------------------------------

module "observability_staging" {
  source = "../../modules/observability"

  monitoring_namespace = "monitoring"
}

#------------------------------------------------------------------------------
# ECR Lifecycle Policies — Auto-Delete Untagged Images >7 Days
# Purpose: Reduce ECR storage costs by automatically cleaning up old images
# Pattern: Time-based expiration (7 days) for untagged images
# Savings: ~$0.10/GB/month ECR storage cost reduction
# Account-level: ECR is shared across all environments (staging + prod)
#------------------------------------------------------------------------------

module "ecr" {
  source = "../../modules/ecr"

  environment = local.environment

  repositories = {
    hatch-sync = {
      image_tag_mutability = "MUTABLE"
      scan_on_push         = false
      encryption_type      = "AES256"
      kms_key_arn          = null
    }
  }

  # Auto-delete untagged images older than 7 days
  untagged_expiration_days = 7

  # Keep last 10 tagged images per prefix (v*, latest)
  tagged_image_count = 10

  common_tags = merge(local.common_tags, {
    Purpose     = "Container image storage"
    Criticality = "Medium"
  })
}

#------------------------------------------------------------------------------
# Orphan Resource Detector — Daily Scan + SNS Alerts
# Purpose: Detect orphaned AWS resources (EBS volumes, Elastic IPs, Snapshots)
# Pattern: Scheduled Lambda (daily 9am BRT) + SNS email alerts
# Savings: Proactive detection prevents R$ 2.106/ano waste (historical orphans)
# Account-level: Scans all resources in us-east-1 region
#------------------------------------------------------------------------------

module "orphan_detector" {
  source = "../../modules/orphan-detector"

  function_name       = "orphan-resource-detector-staging"
  aws_region          = var.aws_region
  schedule_expression = "cron(0 12 * * ? *)" # Daily at 9am BRT (12pm UTC)
  alert_email         = var.finops_alert_email
  log_retention_days  = 7

  common_tags = merge(local.common_tags, {
    Purpose     = "FinOps orphan resource monitoring"
    Schedule    = "Daily 9am BRT"
    Criticality = "Medium"
  })
}

#------------------------------------------------------------------------------
# Weekly FinOps Report — Comprehensive Dry-Run Scan
# Purpose: Weekly consolidated report of ALL potential orphan resources
# Pattern: Scheduled Lambda (weekly Monday 9am BRT) + SNS detailed report
# Difference from daily: Comprehensive scan with cost breakdown, human review
# Safety: Dry-run only (no auto-delete), manual cleanup after review
#------------------------------------------------------------------------------

module "weekly_finops_report" {
  source = "../../modules/orphan-detector"

  function_name       = "weekly-finops-report-staging"
  aws_region          = var.aws_region
  schedule_expression = "cron(0 12 ? * MON *)" # Weekly Monday at 9am BRT (12pm UTC)
  alert_email         = var.finops_alert_email
  log_retention_days  = 30 # Keep weekly reports for 1 month

  common_tags = merge(local.common_tags, {
    Purpose     = "FinOps weekly comprehensive report"
    Criticality = "Low"
  })
}

#------------------------------------------------------------------------------
# CoreDNS Split-Horizon DNS (ADR-039 Resolution)
# Purpose: Resolve staging.internal domains inside cluster (OIDC redirects)
# Problem: Browser OIDC redirects use external DNS (.staging.internal) that
#          is NOT resolvable from inside the cluster without this config.
# Pattern: CoreDNS rewrite rules map external → internal svc DNS
# Ref: R-039 (risks.md) | MEMORY.md CoreDNS Split-Horizon Pattern
# Status: Migrated from manual ConfigMap to Terraform (2026-02-18)
#------------------------------------------------------------------------------

resource "kubernetes_config_map_v1" "coredns_split_horizon" {
  metadata {
    name      = "coredns-custom"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "coredns-split-horizon"
    }
  }

  data = {
    "staging.internal.server" = <<-COREFILE
      staging.internal:53 {
          errors
          rewrite name keycloak.staging.internal keycloak-http.keycloak.svc.cluster.local
          rewrite name gitlab.staging.internal gitlab-webservice-default.gitlab-staging.svc.cluster.local
          rewrite name argocd.staging.internal argocd-server.argocd.svc.cluster.local
          rewrite name grafana.staging.internal kube-prometheus-stack-grafana.monitoring.svc.cluster.local
          rewrite name harbor.staging.internal harbor-core.harbor-system.svc.cluster.local
          rewrite name sonarqube.staging.internal sonarqube.sonarqube.svc.cluster.local
          rewrite name vault.staging.internal vault.vault-system.svc.cluster.local
          rewrite name rabbitmq.staging.internal rabbitmq.data-services.svc.cluster.local
          kubernetes cluster.local in-addr.arpa ip6.arpa {
              pods insecure
              fallthrough in-addr.arpa ip6.arpa
          }
          forward . /etc/resolv.conf
          cache 30
          loop
          reload
          loadbalance
      }
    COREFILE
  }

  # NOTE: EKS CoreDNS with coredns-custom ConfigMap requires
  # CoreDNS deployment to be configured with --conf /etc/coredns/Corefile
  # and Corefile to include: import /etc/coredns/custom/*.server
  # Verify: kubectl get cm coredns -n kube-system -o yaml | grep import
}

#------------------------------------------------------------------------------
# VPA — Vertical Pod Autoscaler (FinOps P1.5)
# Purpose: Recommendation mode — collect 30d metrics → enable rightsizing
# Chart: fairwinds/vpa (https://charts.fairwinds.com/stable)
# Mode: updater_enabled=false, admission_controller_enabled=false
#       (recommendation only — no auto-apply in staging)
# Savings: Habilita R$ 8.712/ano via rightsizing (após 30d metrics)
# Ref: docs/demands/2026-02-12-finops-roadmap-pos-audit.md
# Status: Deployed 2026-02-18
#------------------------------------------------------------------------------

resource "helm_release" "vpa" {
  name       = "vpa"
  repository = "https://charts.fairwinds.com/stable"
  chart      = "vpa"
  version    = "4.4.6"
  namespace  = "kube-system"
  timeout    = 300

  values = [<<-YAML
    recommender:
      enabled: true
      extraArgs:
        storage: prometheus
        prometheus-address: "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"
    updater:
      enabled: false
    admissionController:
      enabled: false
  YAML
  ]

  lifecycle {
    ignore_changes = [metadata]
  }
}

# VPA Objects — 12 critical workloads (recommendation mode only)
# updateMode: "Off" = recommendations computed but NOT applied automatically
# Review recommendations: kubectl get vpa -A
# Apply manually: kubectl patch <resource> with recommended values

resource "kubectl_manifest" "vpa_vault" {
  yaml_body  = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: vault
      namespace: vault-system
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: StatefulSet
        name: vault
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: vault
          minAllowed:
            cpu: 100m
            memory: 128Mi
          maxAllowed:
            cpu: 2000m
            memory: 4Gi
  YAML
  depends_on = [helm_release.vpa]
}

resource "kubectl_manifest" "vpa_keycloak" {
  yaml_body  = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: keycloak
      namespace: keycloak
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: StatefulSet
        name: keycloak-keycloakx
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: keycloak
          minAllowed:
            cpu: 200m
            memory: 512Mi
          maxAllowed:
            cpu: 2000m
            memory: 4Gi
  YAML
  depends_on = [helm_release.vpa]
}

resource "kubectl_manifest" "vpa_harbor_core" {
  yaml_body  = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: harbor-core
      namespace: harbor-system
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: harbor-core
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: core
          minAllowed:
            cpu: 50m
            memory: 128Mi
          maxAllowed:
            cpu: 1000m
            memory: 2Gi
  YAML
  depends_on = [helm_release.vpa]
}

resource "kubectl_manifest" "vpa_gitlab_webservice" {
  yaml_body  = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: gitlab-webservice
      namespace: gitlab-staging
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: gitlab-webservice-default
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: webservice
          minAllowed:
            cpu: 200m
            memory: 1Gi
          maxAllowed:
            cpu: 4000m
            memory: 8Gi
  YAML
  depends_on = [helm_release.vpa]
}

resource "kubectl_manifest" "vpa_gitlab_sidekiq" {
  yaml_body  = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: gitlab-sidekiq
      namespace: gitlab-staging
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: gitlab-sidekiq-all-in-1-v2
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: sidekiq
          minAllowed:
            cpu: 100m
            memory: 256Mi
          maxAllowed:
            cpu: 2000m
            memory: 4Gi
  YAML
  depends_on = [helm_release.vpa]
}

resource "kubectl_manifest" "vpa_argocd" {
  yaml_body  = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: argocd-server
      namespace: argocd
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: argocd-server
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: argocd-server
          minAllowed:
            cpu: 50m
            memory: 64Mi
          maxAllowed:
            cpu: 1000m
            memory: 2Gi
  YAML
  depends_on = [helm_release.vpa]
}

resource "kubectl_manifest" "vpa_prometheus" {
  yaml_body  = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: prometheus
      namespace: monitoring
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: StatefulSet
        name: prometheus-kube-prometheus-stack-prometheus
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: prometheus
          minAllowed:
            cpu: 100m
            memory: 256Mi
          maxAllowed:
            cpu: 2000m
            memory: 8Gi
  YAML
  depends_on = [helm_release.vpa]
}

resource "kubectl_manifest" "vpa_grafana" {
  yaml_body  = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: grafana
      namespace: monitoring
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: StatefulSet
        name: kube-prometheus-stack-grafana
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: grafana
          minAllowed:
            cpu: 50m
            memory: 64Mi
          maxAllowed:
            cpu: 500m
            memory: 1Gi
  YAML
  depends_on = [helm_release.vpa]
}

resource "kubectl_manifest" "vpa_loki" {
  yaml_body  = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: loki-write
      namespace: monitoring
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: StatefulSet
        name: loki-write
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: loki
          minAllowed:
            cpu: 50m
            memory: 64Mi
          maxAllowed:
            cpu: 1000m
            memory: 4Gi
  YAML
  depends_on = [helm_release.vpa]
}

resource "kubectl_manifest" "vpa_tempo" {
  yaml_body  = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: tempo-distributor
      namespace: monitoring
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: tempo-distributor
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: tempo
          minAllowed:
            cpu: 50m
            memory: 64Mi
          maxAllowed:
            cpu: 1000m
            memory: 2Gi
  YAML
  depends_on = [helm_release.vpa]
}

resource "kubectl_manifest" "vpa_rabbitmq" {
  yaml_body  = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: rabbitmq
      namespace: data-services
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: StatefulSet
        name: rabbitmq-server
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: rabbitmq
          minAllowed:
            cpu: 100m
            memory: 256Mi
          maxAllowed:
            cpu: 1000m
            memory: 2Gi
  YAML
  depends_on = [helm_release.vpa]
}

resource "kubectl_manifest" "vpa_redis" {
  yaml_body  = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: redis
      namespace: data-services
      labels:
        app.kubernetes.io/managed-by: terraform
        finops/component: vpa-recommendation
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: StatefulSet
        name: redis
      updatePolicy:
        updateMode: "Off"
      resourcePolicy:
        containerPolicies:
        - containerName: redis
          minAllowed:
            cpu: 50m
            memory: 64Mi
          maxAllowed:
            cpu: 500m
            memory: 1Gi
  YAML
  depends_on = [helm_release.vpa]
}

#------------------------------------------------------------------------------
# Snapshot Cleanup Lambda (FinOps P1.6)
# Purpose: Weekly deletion of old EBS migration snapshots (>30 days)
# Savings: R$ 216/ano (prevent post-gp2→gp3 snapshot accumulation)
# Schedule: Weekly Monday 03:00 UTC (midnight BRT)
# Safety: Skips snapshots used by AMIs + protected tags (FinOps:Keep=true)
# Ref: docs/demands/2026-02-12-finops-roadmap-pos-audit.md (item #5)
#------------------------------------------------------------------------------

module "snapshot_cleanup" {
  source = "../../modules/snapshot-cleanup"

  function_name       = "finops-snapshot-cleanup-staging"
  aws_region          = var.aws_region
  schedule_expression = "cron(0 3 ? * MON *)" # Every Monday 03:00 UTC (midnight BRT)
  retention_days      = 30
  dry_run             = false
  alert_email         = var.finops_alert_email
  log_retention_days  = 7

  common_tags = merge(local.common_tags, {
    Purpose     = "FinOps EBS snapshot lifecycle cleanup"
    Schedule    = "Weekly Monday 03:00 UTC"
    Criticality = "Low"
  })
}

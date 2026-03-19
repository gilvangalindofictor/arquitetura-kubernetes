# PROD Environment Configuration
# Production-grade resources with HA, Multi-AZ, and 24/7 availability
# NO FinOps automation (always on)

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
  }
}

# Local variables combining common.tfvars with environment-specific values
locals {
  environment  = "prod"
  cluster_name = "k8s-platform-prod" # Shared EKS cluster

  common_tags = merge(var.base_tags, {
    Environment        = local.environment
    DataClassification = "Sensitive"
    LGPD               = "PII" # Production data may contain PII
    CostCenter         = "production"
  })
}

provider "aws" {
  region  = var.aws_region
  profile = "k8s-platform-prod"

  default_tags {
    tags = local.common_tags
  }
}

# Provider for sa-east-1 (LGPD compliance - FCT proposals bucket TASK-004)
provider "aws" {
  alias   = "sa_east_1"
  region  = "sa-east-1"
  profile = "k8s-platform-prod"

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
    profile = "k8s-platform-prod"
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
  multi_az              = true                                 # DT-004: Multi-AZ mandatory for production (99.95% SLA)
  deletion_protection   = true                                 # DT-004: Protect against accidental deletion in production
  environment           = "prod"                               # Secrets Manager prefix: prod/postgresql/...
  common_tags           = local.common_tags
}

# Redis Operator - PROD (3 replicas + Sentinel HA)
module "redis_prod" {
  source = "../../modules/redis"

  cluster_name  = local.cluster_name
  replicas      = var.redis_replicas # 3
  pvc_size      = var.redis_pvc_size # 10Gi
  storage_class = "gp3"
  common_tags   = local.common_tags
}

# RabbitMQ Operator - PROD (3 replicas with quorum)
module "rabbitmq_prod" {
  source = "../../modules/rabbitmq"

  cluster_name  = local.cluster_name
  replicas      = var.rabbitmq_replicas # 3
  pvc_size      = var.rabbitmq_pvc_size # 10Gi
  storage_class = "gp3"
  common_tags   = local.common_tags
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
  namespace      = "prod-platform-gitlab" # P0-08: DEC-074 namespace convention
  environment    = "shared"               # Shared across STAGING and PROD

  # GitLab configuration
  gitlab_edition         = "ce"
  gitlab_version         = "8.7.0"
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
  enable_monitoring = true

  # Tags
  common_tags = local.common_tags
}

#------------------------------------------------------------------------------
# NETWORK POLICIES (Cross-Environment Isolation)
# PROD apps can ONLY access PROD data services
#------------------------------------------------------------------------------

resource "kubectl_manifest" "netpol_deny_staging_access" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: deny-access-from-staging
      namespace: data-services-prod
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
              port: 5432  # PostgreSQL
            - protocol: TCP
              port: 6379  # Redis
            - protocol: TCP
              port: 5672  # RabbitMQ

        # Allow GitLab (shared namespace — P0-08: DEC-074 convention)
        - from:
          - namespaceSelector:
              matchLabels:
                name: prod-platform-gitlab
          ports:
            - protocol: TCP
              port: 5432  # GitLab uses PROD PostgreSQL
            - protocol: TCP
              port: 6379  # GitLab uses PROD Redis

        # Allow monitoring (Prometheus scraping — P0-08: DEC-074 convention)
        - from:
          - namespaceSelector:
              matchLabels:
                name: prod-observability-monitoring
          ports:
            - protocol: TCP
              port: 9187  # PostgreSQL exporter
            - protocol: TCP
              port: 9121  # Redis exporter
  YAML

  depends_on = [
    module.postgresql_prod,
    module.redis_prod,
    module.rabbitmq_prod
  ]
}

#------------------------------------------------------------------------------
# OBSERVABILITY INTEGRATION (Hybrid - Shared Prometheus with Labels)
# Metrics/Logs from PROD will be labeled with environment=prod
#------------------------------------------------------------------------------

# ServiceMonitor for PROD PostgreSQL
resource "kubectl_manifest" "servicemonitor_postgresql_prod" {
  yaml_body = <<-YAML
    apiVersion: monitoring.coreos.com/v1
    kind: ServiceMonitor
    metadata:
      name: postgresql-prod
      namespace: data-services-prod
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

  enable_monitoring = true

  common_tags = local.common_tags
}

#------------------------------------------------------------------------------
# EXTERNAL SECRETS OPERATOR — PROD (Vault backend)
#------------------------------------------------------------------------------
module "external_secrets_prod" {
  source = "../../modules/external-secrets"

  depends_on = [module.vault_prod]

  cluster_name         = local.cluster_name
  environment          = "prod"
  namespace            = "prod-security-externalsecrets"
  replicas             = 2
  vault_addr           = "http://vault.prod-security-vault.svc.cluster.local:8200"
  monitoring_namespace = "prod-observability-monitoring"
  enable_monitoring    = true

  common_tags = local.common_tags
}

#------------------------------------------------------------------------------
# VAULT CONFIG — PROD (K8s auth, policies, secrets seeding)
#------------------------------------------------------------------------------
module "vault_config_prod" {
  source = "../../modules/vault-config"

  depends_on = [module.vault_prod, module.external_secrets_prod]

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

  harbor_postgresql_password = var.harbor_postgresql_password
  harbor_admin_password      = var.harbor_admin_password
  harbor_redis_password      = var.harbor_redis_password

  argocd_postgresql_password = var.argocd_postgresql_password
  argocd_oidc_client_secret  = var.argocd_oidc_client_secret

  keycloak_admin_password = var.keycloak_admin_password

  hatch_etl_enabled = false

  common_tags = local.common_tags
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

  common_tags = local.common_tags
}

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
  }
}

# Local variables combining common.tfvars with environment-specific values
locals {
  environment  = "staging"
  cluster_name = "k8s-platform-prod" # Shared EKS cluster

  common_tags = merge(var.base_tags, {
    Environment        = local.environment
    DataClassification = "Internal"
    LGPD               = "Synthetic" # No PII in staging
    CostCenter         = "development"
  })
}

provider "aws" {
  region  = var.aws_region
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
    profile = "k8s-platform-prod"
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

  # Bootstrap additional databases (Harbor)
  additional_databases = [
    {
      name     = "harbor"
      username = "harbor_user"
      password = data.aws_secretsmanager_secret_version.postgresql_password.secret_string
    }
  ]
}

# Redis Operator - STAGING (1 replica, no Sentinel)
module "redis_staging" {
  source = "../../modules/redis"

  cluster_name  = local.cluster_name
  replicas      = var.redis_replicas # 1
  pvc_size      = var.redis_pvc_size # 5Gi
  storage_class = "gp2"              # Changed from gp3 (not available in cluster)
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
  storage_class = "gp2"                 # Changed from gp3 (not available in cluster)
  common_tags   = local.common_tags
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

resource "kubernetes_secret" "gitlab_postgresql_password" {
  metadata {
    name      = "gitlab-postgresql-password"
    namespace = "data-services"

    labels = merge(local.common_tags, {
      "app.kubernetes.io/name"     = "postgresql"
      "app.kubernetes.io/instance" = "${local.cluster_name}-postgresql-staging"
    })
  }

  data = {
    password = data.aws_secretsmanager_secret_version.postgresql_password.secret_string
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
  postgresql_host            = module.postgresql_staging.service_name
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

  # Tags
  common_tags = local.common_tags
}

#------------------------------------------------------------------------------
# SECRETS & SECURITY INFRASTRUCTURE
# Vault HA + External Secrets Operator + Harbor Container Registry
# ADR-031, ADR-032, ADR-033
#------------------------------------------------------------------------------

# Vault HA Cluster - STAGING (1 replica, KMS auto-unseal)
module "vault_staging" {
  source = "../../modules/vault"

  cluster_name        = local.cluster_name
  aws_account_id      = var.aws_account_id
  aws_region          = var.aws_region
  namespace           = "vault-system"
  oidc_provider_arn   = data.aws_iam_openid_connect_provider.eks.arn
  vault_chart_version = "0.27.0"
  replicas            = 3 # HA production-ready (ADR-041)
  storage_class       = "gp2"
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
  enable_sns_notifications = false # Usar apenas tópico externo (k8s-platform-prod-finops-alerts-staging)
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

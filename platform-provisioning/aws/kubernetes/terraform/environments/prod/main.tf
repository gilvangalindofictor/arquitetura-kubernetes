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

# Get EKS cluster info (shared cluster from Marco 1)
data "aws_eks_cluster" "cluster" {
  name = local.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = local.cluster_name
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

# PostgreSQL RDS - PROD (db.t3.medium, Multi-AZ)
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
  namespace      = "gitlab"
  environment    = "shared" # Shared across STAGING and PROD

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

        # Allow GitLab (shared namespace)
        - from:
          - namespaceSelector:
              matchLabels:
                name: gitlab
          ports:
            - protocol: TCP
              port: 5432  # GitLab uses PROD PostgreSQL
            - protocol: TCP
              port: 6379  # GitLab uses PROD Redis

        # Allow monitoring (Prometheus scraping)
        - from:
          - namespaceSelector:
              matchLabels:
                name: observability
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
      namespace: gitlab
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

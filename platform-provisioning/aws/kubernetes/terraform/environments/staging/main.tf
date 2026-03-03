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
  profile = "k8s-platform-prod" # TEMP: Same account 891377105802, staging profile não configurado

  default_tags {
    tags = local.common_tags
  }
}

# Provider for sa-east-1 (LGPD compliance - FCT proposals bucket TASK-004)
provider "aws" {
  alias   = "sa_east_1"
  region  = "sa-east-1"
  profile = "k8s-platform-staging"

  default_tags {
    tags = local.common_tags
  }
}

# Provider for us-west-2 (GAP-012: DR Multi-Region)
# Used by:
#   - module.velero_dr_staging  (replica S3 bucket)
#   - module.rds_replica_staging (RDS read replica)
provider "aws" {
  alias   = "us-west-2"
  region  = "us-west-2"
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

# PostgreSQL RDS - STAGING (db.t3.micro, single-AZ, DT-004: cost-optimized)
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
  multi_az              = false                                # DT-004: Single-AZ accepted for staging (FinOps)
  common_tags           = local.common_tags

  # INFRA-002: PostgreSQL 14→16 major version upgrade (pre-req GitLab 18.x)
  # These flags enable in-place major version upgrade during terraform apply.
  # After successful upgrade, set both back to false to prevent accidental upgrades.
  allow_major_version_upgrade = true
  apply_immediately           = true

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

  providers = {
    aws           = aws
    aws.sa_east_1 = aws.sa_east_1
  }

  cluster_name   = local.cluster_name
  aws_account_id = var.aws_account_id
  common_tags    = local.common_tags

  # TASK-004: Enable FCT proposals bucket
  enable_fct_proposals = true
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
  gitlab_version         = "8.11.8"  # INFRA-001: Updated 2026-03-02 (4/5 steps — v17.11.7 | blocked at 9.0.x: PG16 required — INFRA-002)
  gitlab_replicas        = 1 # Cost-optimized for staging
  gitlab_runner_replicas = 1 # Cost-optimized for staging

  # TLS configuration (ADR-021 Phase 1: disabled)
  enable_tls  = false
  domain_name = "staging.internal"

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
# GITLAB CI/CD — Runner Credentials (GAP-005)
# Vault KV → ESO ExternalSecret → K8s Secret → Runner envFrom
# Vault paths:
#   secret/gitlab/ci-variables → harbor_registry_url, harbor_robot_user,
#                                 harbor_robot_password, sonar_host_url, sonar_token
# eso-reader policy: secret/data/gitlab/* (added 2026-02-19)
# Note: lifecycle.ignore_changes=all on helm_release.gitlab → envFrom via kubectl patch
#------------------------------------------------------------------------------

resource "kubernetes_manifest" "gitlab_ci_credentials_eso" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "gitlab-ci-credentials"
      namespace = "gitlab-staging"
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        kind = "ClusterSecretStore"
        name = "vault-backend"
      }
      data = [
        {
          secretKey = "HARBOR_REGISTRY"
          remoteRef = {
            key      = "secret/data/gitlab/ci-variables"
            property = "harbor_registry_url"
          }
        },
        {
          secretKey = "HARBOR_USER"
          remoteRef = {
            key      = "secret/data/gitlab/ci-variables"
            property = "harbor_robot_user"
          }
        },
        {
          secretKey = "HARBOR_PASSWORD"
          remoteRef = {
            key      = "secret/data/gitlab/ci-variables"
            property = "harbor_robot_password"
          }
        },
        {
          secretKey = "SONAR_HOST_URL"
          remoteRef = {
            key      = "secret/data/gitlab/ci-variables"
            property = "sonar_host_url"
          }
        },
        {
          secretKey = "SONAR_TOKEN"
          remoteRef = {
            key      = "secret/data/gitlab/ci-variables"
            property = "sonar_token"
          }
        }
      ]
      target = {
        name           = "gitlab-ci-credentials"
        creationPolicy = "Owner"
      }
    }
  }

  field_manager {
    force_conflicts = true
  }

  depends_on = [module.gitlab_staging]
}

resource "null_resource" "gitlab_runner_envfrom" {
  depends_on = [kubernetes_manifest.gitlab_ci_credentials_eso]

  triggers = {
    secret_name = "gitlab-ci-credentials"
    # Fix 2026-03-02: Updated namespace from gitlab-staging → staging-platform-gitlab (DEC-074 Wave 6)
    namespace   = "staging-platform-gitlab"
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl patch deployment gitlab-gitlab-runner -n staging-platform-gitlab --type='json' -p='[
        {"op":"add","path":"/spec/template/spec/containers/0/envFrom","value":[{"secretRef":{"name":"gitlab-ci-credentials"}}]}
      ]' || true
    EOT
  }
}

# Fix: executor namespace was "gitlab" (non-existent) → "gitlab-staging" → "staging-platform-gitlab"
# Helm lifecycle.ignore_changes=all → must patch configmap directly
# Uses python3 interpreter to avoid bash quoting issues with TOML content
# Fix 2026-03-02: Updated namespace from gitlab-staging → staging-platform-gitlab (DEC-074 Wave 6)
resource "null_resource" "gitlab_runner_namespace_fix" {
  depends_on = [module.gitlab_staging]

  triggers = {
    executor_namespace = "staging-platform-gitlab"
    s3_bucket          = "k8s-platform-gitlab-artifacts-891377105802"
  }

  provisioner "local-exec" {
    interpreter = ["python3", "-c"]
    command     = <<-EOT
      import json, subprocess
      toml = "\n".join([
        "[[runners]]",
        "  clone_url = \"http://gitlab-webservice-default.staging-platform-gitlab.svc.cluster.local:8181\"",
        "  [runners.kubernetes]",
        "    namespace = \"staging-platform-gitlab\"",
        "    image = \"ubuntu:22.04\"",
        "    privileged = false",
        "    cpu_request = \"100m\"",
        "    memory_request = \"256Mi\"",
        "    service_cpu_request = \"50m\"",
        "    service_memory_request = \"128Mi\"",
        "    helper_cpu_request = \"50m\"",
        "    helper_memory_request = \"128Mi\"",
        "  [runners.cache]",
        "    Type = \"s3\"",
        "    Shared = true",
        "    [runners.cache.s3]",
        "      BucketName = \"k8s-platform-gitlab-artifacts-891377105802\"",
        "      BucketLocation = \"us-east-1\"",
        ""
      ])
      patch = json.dumps({"data": {"config.template.toml": toml}})
      r = subprocess.run(
        ["kubectl", "patch", "configmap", "gitlab-gitlab-runner",
         "-n", "staging-platform-gitlab", "--type", "merge", "-p", patch],
        capture_output=True
      )
      print(r.stdout.decode() + r.stderr.decode())
    EOT
  }
}

# Tighten runner RBAC: replace Helm wildcard with least-privilege rules
# Original: resources=['*'], verbs=['*'] (Helm chart gitlab-runner-0.71.0)
# force_conflicts=true to override Helm field manager
resource "kubernetes_manifest" "gitlab_runner_role_least_privilege" {
  manifest = {
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "Role"
    metadata = {
      name      = "gitlab-gitlab-runner"
      # Fix 2026-03-02: Updated namespace from gitlab-staging → staging-platform-gitlab (DEC-074 Wave 6)
      namespace = "staging-platform-gitlab"
      labels = {
        "app"                          = "gitlab-gitlab-runner"
        "app.kubernetes.io/managed-by" = "Terraform"
        "chart"                        = "gitlab-runner-0.71.0"
      }
    }
    rules = [
      {
        apiGroups = [""]
        resources = ["pods", "pods/exec", "pods/log"]
        verbs     = ["get", "list", "watch", "create", "delete", "patch", "update"]
      },
      {
        apiGroups = [""]
        resources = ["secrets"]
        verbs     = ["get", "list", "watch", "create", "delete", "update"]
      },
      {
        apiGroups = [""]
        resources = ["configmaps", "serviceaccounts"]
        verbs     = ["get", "list", "watch"]
      }
    ]
  }

  field_manager {
    force_conflicts = true
  }

  depends_on = [module.gitlab_staging]
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
  namespace         = "staging-security-externalsecrets" # DEC-074: migrated from external-secrets-system (2026-03-02)
  eso_chart_version = "0.12.1"                          # Updated from 0.9.11 to match active Helm release
  replicas          = 1 # Cost-optimized for staging
  vault_addr        = "http://vault.staging-security-vault.svc.cluster.local:8200" # Updated to canonical vault addr
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
  eso_namespace       = "staging-security-externalsecrets" # DEC-074: migrated from external-secrets-system (2026-03-02)
  eso_service_account = "external-secrets"

  # Keycloak PostgreSQL credentials
  keycloak_postgresql_password = var.keycloak_postgresql_password
  keycloak_postgresql_username = "keycloak_user"
  keycloak_postgresql_host     = "postgresql-external.default.svc.cluster.local"
  keycloak_postgresql_port     = "5432"
  keycloak_postgresql_database = "keycloak"

  # Vault OIDC SSO via Keycloak (Vault UI + CLI login)
  oidc_enabled             = true
  keycloak_oidc_url        = "http://keycloak.staging.internal/auth/realms/platform"
  vault_oidc_client_id     = "vault"
  vault_oidc_client_secret = var.vault_oidc_client_secret

  # Grafana OIDC — migrado de hardcode para Vault KV (P0-A ESO gap, 2026-02-19)
  grafana_oidc_client_id     = "grafana"
  grafana_oidc_client_secret = var.grafana_oidc_client_secret

  # Grafana Admin Password — V-001 remediation (2026-02-20)
  # Seed Vault KV secret/grafana/admin with a strong password
  grafana_admin_password = var.grafana_admin_password

  # SonarQube PostgreSQL — resolve TODO sonarqube/main.tf (P0-B ESO gap, 2026-02-19)
  sonarqube_postgresql_password = var.sonarqube_postgresql_password
  sonarqube_postgresql_username = "sonarqube_user"
  sonarqube_postgresql_host     = "postgresql-external.default.svc.cluster.local"
  sonarqube_postgresql_port     = "5432"
  sonarqube_postgresql_database = "sonarqube"

  # Harbor PostgreSQL — migrado de AWS SM para Vault KV (P1 ESO gap, 2026-02-19)
  harbor_postgresql_password = var.harbor_postgresql_password
  harbor_postgresql_username = "harbor_user"
  harbor_postgresql_host     = "postgresql-external.default.svc.cluster.local"
  harbor_postgresql_port     = "5432"
  harbor_postgresql_database = "harbor"

  # ArgoCD PostgreSQL — V-002 remediation (2026-02-20)
  # Vault KV: secret/argocd/postgresql → ESO ExternalSecret: argocd-postgresql-credentials
  argocd_postgresql_password = var.argocd_postgresql_password
  argocd_postgresql_username = "argocd_user"
  argocd_postgresql_host     = "postgresql-external.default.svc.cluster.local"
  argocd_postgresql_port     = "5432"
  argocd_postgresql_database = "argocd"

  # ArgoCD OIDC — V-002 remediation (2026-02-20)
  # Vault KV: secret/argocd/oidc → ESO ExternalSecret: argocd-oidc-credentials
  argocd_oidc_client_id     = "argocd"
  argocd_oidc_client_secret = var.argocd_oidc_client_secret

  # Harbor Admin Password — V-004 remediation (2026-02-25)
  # Vault KV: secret/harbor/admin → ESO ExternalSecret: harbor-admin-credentials
  # Pass existing password from TF_VAR_harbor_admin_password to preserve Harbor login
  harbor_admin_password = var.harbor_admin_password

  # Harbor Redis Password — V-005 remediation (2026-02-25)
  # Vault KV: secret/harbor/redis → ESO ExternalSecret: harbor-redis-credentials
  # Pass existing password from TF_VAR_harbor_redis_password to avoid Harbor Redis auth failures
  harbor_redis_password = var.harbor_redis_password

  # Keycloak Admin Password — V-006 remediation (2026-02-25)
  # Vault KV: secret/keycloak/admin → ESO ExternalSecret: keycloak-admin-credentials
  # Pass existing password from TF_VAR_keycloak_admin_password to preserve Keycloak admin login
  keycloak_admin_password = var.keycloak_admin_password

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

  # PostgreSQL (shared RDS) — password migrado de AWS SM para Vault KV (P1 ESO gap, 2026-02-19)
  # Vault KV: secret/harbor/postgresql (vault-config/main.tf)
  postgresql_host     = "postgresql-external.default.svc.cluster.local"
  postgresql_port     = 5432
  postgresql_database = "harbor"
  postgresql_username = "harbor_user"
  postgresql_password = var.harbor_postgresql_password

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

#------------------------------------------------------------------------------
# KEYCLOAK CLIENTS — IaC for Realm, OIDC Clients, Groups (TASK-002)
# Provider: mrparkers/keycloak ~> 4.4.0
# Manages: realm/platform, clients/gitlab+argocd+grafana, group/grafana-admins
# Pattern: import-only (prevent_destroy=true), WSL-safe port-forward
# Migration: null_resource.keycloak_grafana_admins_group → native provider
#
# PREREQ: kubectl port-forward svc/keycloak-keycloakx-http 18080:80 -n keycloak
# IMPORT: run scripts/keycloak/import-clients.sh before first terraform apply
# ADR: TASK-002 (docs/tasks/TASK-002-terraform-keycloak-provider.md)
#------------------------------------------------------------------------------

# TEMPORARILY DISABLED (2026-02-26) — TASK-002 Keycloak Clients Module
# Blocker: modules/keycloak-clients/main.tf references 17 undeclared resources
# Root cause: Clients were created manually (TASK-002 import incomplete?)
# Created: TASK-YYY to complete Terraform import of existing clients
# Re-enable after: terraform import keycloak_realm.platform <realm-id> (+ 16 client imports)
#
# module "keycloak_clients_staging" {
#   source = "../../modules/keycloak-clients"
#
#   # NOTE: depends_on removed - legacy module with provider config incompatible with depends_on
#   # Manual ordering: apply keycloak_staging first, then keycloak_clients_staging
#
#   # WSL-safe: uses localhost port-forward
#   # kubectl port-forward svc/keycloak-keycloakx-http 18080:80 -n keycloak
#   keycloak_url = "http://localhost:18080"
#
#   # Admin password from K8s secret (V-006: migrado para ESO 2026-02-24)
#   # Pass via: export TF_VAR_keycloak_admin_password=$(kubectl get secret keycloak-admin-credentials -n keycloak -o jsonpath='{.data.password}' | base64 -d)
#   keycloak_admin_password = var.keycloak_admin_password
#
#   # Realm
#   realm = "platform"
#
#   # Domain (staging.internal)
#   domain_suffix = "staging.internal"
#   environment   = local.environment
#   cluster_name  = local.cluster_name
#
#   # Enable all clients (TASK-002: full 6-client IaC coverage)
#   gitlab_enabled     = true
#   argocd_enabled     = true
#   grafana_enabled    = true
#   harbor_enabled     = true
#   vault_enabled      = true
#   sonarqube_enabled  = true
#
#   # Kubernetes namespaces
#   gitlab_namespace     = "staging-platform-gitlab"  # DEC-074 Wave 6: renamed from gitlab-staging
#   argocd_namespace     = "argocd"
#   grafana_namespace    = "monitoring"
#   harbor_namespace     = "harbor-system"
#   vault_namespace      = "staging-security-vault"   # DEC-074 Wave 3: renamed from vault-system
#   sonarqube_namespace  = "sonarqube"
#
#   # grafana-admins group + oidc-group-membership-mapper
#   # Replaces null_resource.keycloak_grafana_admins_group (Python port-forward)
#   grafana_admins_group_enabled = true
#
#   common_tags = local.common_tags
# }

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
# Secrets: Vault KV v2 + ESO (V-002 remediation, 2026-02-20)
# ESO ExternalSecrets: argocd-postgresql-credentials, argocd-oidc-credentials
#------------------------------------------------------------------------------

module "argocd_staging" {
  source = "../../modules/argocd"

  depends_on = [
    module.keycloak_staging,
    module.postgresql_staging,
    module.external_secrets_staging,
    module.vault_config_staging
  ]

  # Cluster info
  cluster_name = local.cluster_name
  namespace    = "staging-platform-argocd" # DEC-075 namespace standardization

  # ArgoCD configuration
  argocd_chart_version = "5.51.6"
  replicas             = 2 # HA for critical GitOps service

  # Keycloak OIDC integration
  keycloak_url       = "http://keycloak.staging.internal/auth"
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
# ARGO ROLLOUTS - Progressive Delivery (CICD-005)
# Canary and Blue-Green deployments with automated analysis
# Deployed in ArgoCD namespace (co-located per ADR-085)
#------------------------------------------------------------------------------

# TEMPORARILY DISABLED (2026-02-26) — CICD-005 Argo Rollouts Module
# Blocker: modules/argo-rollouts/main.tf uses templatefile() with missing values.yaml.tpl
# Missing file: modules/argo-rollouts/values.yaml.tpl
# Created: TASK-ZZZ to add values.yaml.tpl template file
# Alternative: Deploy manually via Helm (already done, 2 controller pods running)
# Re-enable after: values.yaml.tpl created in module directory
#
# module "argo_rollouts_staging" {
#   source = "../../modules/argo-rollouts"
#
#   depends_on = [
#     module.argocd_staging,
#     module.kube_prometheus_stack_staging
#   ]
#
#   # Cluster info
#   cluster_name = local.cluster_name
#   namespace    = "staging-platform-argocd" # DEC-074 namespace migration
#
#   # Argo Rollouts configuration
#   chart_version       = "2.35.0"
#   controller_replicas = 2 # HA
#
#   # Prometheus integration for AnalysisRun
#   metrics_enabled = true
#   prometheus_url  = "http://kube-prometheus-stack-prometheus.staging-observability-monitoring.svc.cluster.local:9090"
#
#   # Dashboard
#   dashboard_enabled = true
#   dashboard_port    = 3100
#
#   # Metrics port
#   metrics_port = 8090
#
#   # Tags
#   common_tags = local.common_tags
# }

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

  # SAML SP certificate (SonarQube's own cert for signing AuthnRequests)
  # SP private key stored in Vault KV secret/sonarqube/saml → ESO → sonarqube-sp-saml (secret.properties)
  saml_sp_certificate = "MIIDXzCCAkegAwIBAgIUbbZIogu+BKzOTxoMG1jIbAqe0tUwDQYJKoZIhvcNAQELBQAwPzEVMBMGA1UEAwwMc29uYXJxdWJlLXNwMRkwFwYDVQQKDBBwbGF0Zm9ybS1zdGFnaW5nMQswCQYDVQQGEwJCUjAeFw0yNjAyMTgyMjA5NDBaFw0zNjAyMTYyMjA5NDBaMD8xFTATBgNVBAMMDHNvbmFycXViZS1zcDEZMBcGA1UECgwQcGxhdGZvcm0tc3RhZ2luZzELMAkGA1UEBhMCQlIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDF3AMuBGobOHWiiPwCdSD4KCX0En9thFa8hi1b0OCmz2C6vy1VeOWlQwWX5yJ1u1RvOl8f6ewbd86r2Jk+GlQbr7SYDQzi0Tj9LlC0FTU0Sine5BqpRz0/EScXK7wCENHF7Y7yWrraM6QitNeFn2IPu83Gxdq04qyfgghmFqAzr5r3+HLvciF5myH6UhfHdFazE1FE7U5kpGoabm66bPEGS3V7xgMsxnTNBwsRP0pCsQpmJ+42oGko+B0aVTX9lhX4zP/Z8RBGmWKLtX2Z5QBzBeFL34DIKYiqcs6o07PTES7AEpAKBaskjFjVJz0mVGMRmIrJ3kInIy0VIMbF88kxAgMBAAGjUzBRMB0GA1UdDgQWBBRH5KIS2G1P/eScorFc1qGA0BtKyDAfBgNVHSMEGDAWgBRH5KIS2G1P/eScorFc1qGA0BtKyDAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQBk+M9AynJIEd23XLMO3jug0+XNWenwt9iFGc6FBEyzA9M0jckQSiB538QZE02oAwfrE1Vejb+041idvrL+nZeQd7iS8rCR00ji6LSNQRUj1S4axxioBfj6OniieGpjzS/61YYrtfaXS1FIPOP2WMqSRglEK4ZeJsYCoX8MwRIi976dKHjJMKDAFzDT+1FptmSAIBLBW+py1sGmiKx+JYaOeGl5cD0m+HGmYdupZLmZ7Z14OCp2Fnt1MMY9U3uPdmx/03698w3cQFSRXJVA6uySYmWyRrOkcAkz/PkKiTsas/JQBeUJ31CyQaeCFTBvQ4QwMjjuEq3wMnD8ugTnRpsH"
  saml_sp_secret_name = "sonarqube-sp-saml" # Created by ESO ExternalSecret (see resource below)

  # GitLab OAuth2 Authentication
  # applicationId + secret injected via sonarSecretProperties (ESO sonarqube-sp-saml → secret.properties)
  # Vault KV: secret/sonarqube/gitlab → application_id + application_secret
  gitlab_oauth_enabled = true
  gitlab_url           = "http://gitlab.staging.internal"
  gitlab_allow_signup  = false
  gitlab_groups_sync   = true

  # Storage (gp3 — match existing PVC created on 2026-02-18)
  storage_class = "gp3"

  # Monitoring
  enable_monitoring = true

  # Tags
  common_tags = local.common_tags
}

#------------------------------------------------------------------------------
# SONARQUBE Auth Secrets — ExternalSecret (Vault → K8s Secret)
# Vault KV sources:
#   secret/sonarqube/saml  → sp_certificate + sp_private_key_pkcs8 (SAML SP signing)
#   secret/sonarqube/gitlab → application_id + application_secret (GitLab OAuth2)
# Target: sonarqube-sp-saml (key: secret.properties, merged by concat-properties init)
# Used by sonarSecretProperties in helm chart
# eso-reader policy: secret/data/sonarqube/* (ADR-032)
#------------------------------------------------------------------------------

resource "kubernetes_manifest" "sonarqube_sp_saml_externalsecret" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "sonarqube-sp-saml"
      namespace = "sonarqube"
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        kind = "ClusterSecretStore"
        name = "vault-backend"
      }
      data = [
        {
          secretKey = "sp_private_key_pkcs8"
          remoteRef = {
            key      = "secret/data/sonarqube/saml"
            property = "sp_private_key_pkcs8"
          }
        },
        {
          secretKey = "sp_certificate"
          remoteRef = {
            key      = "secret/data/sonarqube/saml"
            property = "sp_certificate"
          }
        },
        {
          secretKey = "gitlab_application_id"
          remoteRef = {
            key      = "secret/data/sonarqube/gitlab"
            property = "application_id"
          }
        },
        {
          secretKey = "gitlab_application_secret"
          remoteRef = {
            key      = "secret/data/sonarqube/gitlab"
            property = "application_secret"
          }
        }
      ]
      target = {
        name           = "sonarqube-sp-saml"
        creationPolicy = "Owner"
        template = {
          engineVersion = "v2"
          data = {
            "secret.properties" = "sonar.auth.saml.sp.certificate.secured={{ .sp_certificate }}\nsonar.auth.saml.sp.privateKey.secured={{ .sp_private_key_pkcs8 }}\nsonar.auth.gitlab.applicationId={{ .gitlab_application_id }}\nsonar.auth.gitlab.secret={{ .gitlab_application_secret }}\n"
          }
        }
      }
    }
  }

  field_manager {
    force_conflicts = true
  }

  depends_on = [module.sonarqube_staging]
}

#------------------------------------------------------------------------------
# KUBE-PROMETHEUS-STACK - Observability (Grafana ALB Ingress)
# Prometheus + Grafana + Alertmanager
#------------------------------------------------------------------------------

module "kube_prometheus_stack_staging" {
  source = "../../modules/kube-prometheus-stack"

  namespace = "staging-observability-monitoring"
  # V-001 REMEDIATED: grafana_admin_password hardcoded "admin" removed (2026-02-20)
  # Admin password now managed by: Vault KV (secret/grafana/admin) → ESO → K8s Secret → existingSecret
  grafana_admin_use_existing_secret = true

  # Pin to deployed version (cluster is running 81.4.2 since 2026-02-05)
  chart_version = "81.4.2"

  # Grafana ALB Ingress
  grafana_ingress_enabled    = true
  grafana_ingress_host       = "grafana.staging.internal"
  grafana_ingress_group_name = "observability-staging"

  # Grafana OIDC — Keycloak SSO (ativado 2026-02-18)
  # client_secret MIGRADO para Vault KV: secret/grafana/oidc (2026-02-19)
  # ESO: grafana-oidc-credentials K8s Secret → Grafana extraEnvFrom → $__env{client_secret}
  grafana_oidc_enabled       = true
  grafana_keycloak_url       = "http://keycloak.staging.internal/auth" # externo: browser precisa resolver
  grafana_keycloak_client_id = "grafana"
  # grafana_keycloak_client_secret removido — agora via ESO (Vault: secret/grafana/oidc)

  # Corporate Labels (ADR-048) — Re-enabled 2026-03-02 (variables confirmed in module variables.tf)
  domain      = "operations"
  owner       = "platform-team"
  environment = "staging"
}

#------------------------------------------------------------------------------
# KEYCLOAK POST-CONFIG — grafana-admins group + groups claim mapper
# Dependency: module.keycloak_staging + module.kube_prometheus_stack_staging
# Purpose: Grafana OIDC role_attribute_path checks groups[*] claim.
#          Without this group + mapper, all OIDC users land as Viewer (never Admin).
# Pattern: python3 urllib (curl falha com chars especiais na senha Keycloak)
#          port-forward local → keycloak.staging.internal não resolve fora do cluster
#------------------------------------------------------------------------------

resource "null_resource" "keycloak_grafana_admins_group" {
  depends_on = [
    module.keycloak_staging,
    module.kube_prometheus_stack_staging
  ]

  triggers = {
    group_name   = "grafana-admins"
    realm        = "platform"
    mapper_claim = "groups"
  }

  provisioner "local-exec" {
    interpreter = ["python3", "-c"]
    command     = <<-EOT
      import json, subprocess, urllib.request, urllib.parse, urllib.error
      import base64, sys, time

      # Port-forward: keycloak.staging.internal nao resolve fora do cluster (WSL2)
      pf = subprocess.Popen(
        ["kubectl", "port-forward", "svc/keycloak-keycloakx-http",
         "18080:80", "-n", "keycloak"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
      )
      time.sleep(3)
      base_url  = "http://localhost:18080/auth"
      admin_api = "http://localhost:18080/auth/admin/realms/platform"

      try:
        # Admin password do K8s secret (random_password gerenciado pelo TF)
        r = subprocess.run(
          ["kubectl", "get", "secret", "keycloak-admin-password",
           "-n", "keycloak", "-o", "jsonpath={.data.password}"],
          capture_output=True, text=True, check=True
        )
        admin_password = base64.b64decode(r.stdout.strip()).decode()

        # Token admin-cli (realm master)
        token_data = urllib.parse.urlencode({
          "client_id": "admin-cli",
          "username":  "admin",
          "password":  admin_password,
          "grant_type": "password"
        }).encode()
        req = urllib.request.Request(
          base_url + "/realms/master/protocol/openid-connect/token",
          data=token_data, method="POST"
        )
        with urllib.request.urlopen(req) as resp:
          token = json.loads(resp.read())["access_token"]

        hdrs = {
          "Authorization":  "Bearer " + token,
          "Content-Type":   "application/json"
        }

        def api(url, data=None, method=None):
          req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
          try:
            with urllib.request.urlopen(req) as r:
              return r.status, r.read(), dict(r.headers)
          except urllib.error.HTTPError as e:
            return e.code, e.read(), {}

        # --- 1. Criar grupo grafana-admins (realm platform) ---
        status, body, resp_hdrs = api(
          admin_api + "/groups",
          data=json.dumps({"name": "grafana-admins"}).encode(),
          method="POST"
        )
        if status == 201:
          print("[OK] grafana-admins group created:", resp_hdrs.get("Location",""))
        elif status == 409:
          print("[OK] grafana-admins group already exists")
        else:
          print("[ERROR] creating group:", status, body)
          sys.exit(1)

        # --- 2. UUID do client grafana ---
        status, body, _ = api(
          admin_api + "/clients?clientId=grafana"
        )
        clients = json.loads(body)
        if not clients:
          print("[ERROR] grafana client not found in realm platform")
          sys.exit(1)
        client_uuid = clients[0]["id"]
        print("[OK] grafana client UUID:", client_uuid)

        # --- 3. Mapper oidc-group-membership (inclui groups claim no token) ---
        status, body, _ = api(
          admin_api + "/clients/" + client_uuid + "/protocol-mappers/models"
        )
        existing = json.loads(body) if status == 200 else []
        if any(m.get("name") == "groups" for m in existing):
          print("[OK] groups mapper already exists on grafana client")
        else:
          mapper = {
            "name":            "groups",
            "protocol":        "openid-connect",
            "protocolMapper":  "oidc-group-membership-mapper",
            "consentRequired": False,
            "config": {
              "full.path":           "false",
              "id.token.claim":      "true",
              "access.token.claim":  "true",
              "claim.name":          "groups",
              "userinfo.token.claim": "true"
            }
          }
          status, body, _ = api(
            admin_api + "/clients/" + client_uuid + "/protocol-mappers/models",
            data=json.dumps(mapper).encode(),
            method="POST"
          )
          if status == 201:
            print("[OK] groups mapper added to grafana client")
          else:
            print("[WARN] mapper add returned:", status, body)

        print("[DONE] Keycloak grafana-admins setup complete")

      finally:
        pf.terminate()
        pf.wait()
    EOT
  }
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

  # FinOps Protection (2026-02-27): Never scale system/critical node groups to 0
  # Fix: Prevent monitoring pods from becoming Pending/Unschedulable
  excluded_node_groups      = ["system", "critical"]
  min_system_nodes          = 2 # prometheus-node-exporter (11 pods), loki-canary (9 pods)
  min_critical_nodes        = 2 # ArgoCD, Vault, other critical services
  enable_scaling_protection = true

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

  release_name            = "opentelemetry-collector"
  chart_version           = "0.108.0"
  namespace               = "staging-observability-monitoring"
  observability_namespace = "staging-observability-monitoring"

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

  # Network Policies (Security Specialist requirement — GAP-007 Fix)
  enable_network_policies = true

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

  monitoring_namespace = "staging-observability-monitoring"
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
          rewrite name keycloak.staging.internal keycloak-keycloakx-http.keycloak.svc.cluster.local
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

#------------------------------------------------------------------------------
# Data Lifecycle Manager (DLM) — Automated Snapshot Retention
# Purpose: Automate EBS snapshot retention policies (Velero 30d, Manual 14d, Migration 7d)
# Savings: R$ 252/ano (30% reduction post-stabilization, 3 months)
# Current state: 22 snapshots (213 GB, R$ 766/ano), no snapshots > 30 days
# Replaces: Manual snapshot management with automated DLM policies
#------------------------------------------------------------------------------

module "snapshot_lifecycle" {
  source = "../../modules/snapshot-lifecycle"

  policy_name_prefix       = "k8s-platform-staging"
  velero_retention_days    = 30 # Velero backup snapshots
  manual_retention_days    = 14 # Manually created snapshots
  migration_retention_days = 7  # Migration/temporary snapshots

  common_tags = merge(local.common_tags, {
    Purpose     = "Automated EBS snapshot retention via DLM"
    Criticality = "High"
  })
}

#------------------------------------------------------------------------------
# TASK-004 Validation: FCT Proposals Bucket Access Test
# Purpose: Verify bucket creation, encryption, tagging, and IAM policy ARNs
# Pattern: null_resource local-exec with Python (WSL-safe, no DNS issues)
#------------------------------------------------------------------------------

resource "null_resource" "fct_proposals_validation" {
  depends_on = [module.s3_buckets_staging]

  triggers = {
    bucket_name = module.s3_buckets_staging.fct_proposals_bucket_name
    bucket_arn  = module.s3_buckets_staging.fct_proposals_bucket_arn
  }

  provisioner "local-exec" {
    interpreter = ["python3", "-c"]
    command     = <<-EOT
      import boto3, json, sys
      from datetime import datetime

      # Validation: bucket exists and is accessible
      s3 = boto3.client('s3', region_name='sa-east-1')
      bucket = "${module.s3_buckets_staging.fct_proposals_bucket_name}"

      try:
          # 1. Verify bucket location
          location = s3.get_bucket_location(Bucket=bucket)
          assert location['LocationConstraint'] == 'sa-east-1', "Bucket not in sa-east-1"
          print(f"[OK] Bucket {bucket} in sa-east-1")

          # 2. Verify public access block
          access_block = s3.get_public_access_block(Bucket=bucket)
          config = access_block['PublicAccessBlockConfiguration']
          assert all([config['BlockPublicAcls'], config['IgnorePublicAcls'],
                     config['BlockPublicPolicy'], config['RestrictPublicBuckets']])
          print("[OK] Public access blocked")

          # 3. Verify encryption
          encryption = s3.get_bucket_encryption(Bucket=bucket)
          sse_algo = encryption['Rules'][0]['ApplyServerSideEncryptionByDefault']['SSEAlgorithm']
          assert sse_algo == 'AES256', f"Encryption not AES256: {sse_algo}"
          print("[OK] SSE-S3 encryption enabled")

          # 4. Verify Intelligent-Tiering
          tiering = s3.get_bucket_intelligent_tiering_configuration(
              Bucket=bucket, Id='proposals-tiering'
          )
          assert tiering['Status'] == 'Enabled'
          assert any(t['Days'] == 30 and t['AccessTier'] == 'ARCHIVE_ACCESS'
                    for t in tiering['Tierings'])
          print("[OK] Intelligent-Tiering configured (30d Archive, 90d Deep Archive)")

          # 5. Test object upload with tagging
          test_key = f"_validation_test/{datetime.now().isoformat()}.json"
          s3.put_object(
              Bucket=bucket,
              Key=test_key,
              Body=json.dumps({"validation": "TASK-004", "timestamp": datetime.now().isoformat()}),
              Tagging="source=terraform-validation&env=test"
          )

          # 6. Verify tagging
          tags = s3.get_object_tagging(Bucket=bucket, Key=test_key)
          assert len(tags['TagSet']) == 2
          print(f"[OK] Object tagging functional: {tags['TagSet']}")

          # 7. Cleanup test object
          s3.delete_object(Bucket=bucket, Key=test_key)
          print("[OK] Test object cleaned up")

          print(f"\n[SUCCESS] TASK-004 validation complete")
          print(f"Bucket: s3://{bucket}")
          print(f"Region: sa-east-1")
          print(f"Hatch ETL Policy ARN: ${module.s3_buckets_staging.hatch_etl_policy_arn}")
          print(f"BucketConnector Policy ARN: ${module.s3_buckets_staging.bucketconnector_policy_arn}")

      except Exception as e:
          print(f"[ERROR] Validation failed: {e}", file=sys.stderr)
          sys.exit(1)
    EOT
  }
}

#------------------------------------------------------------------------------
# Velero DR Multi-Region - GAP-012 (2026-02-26)
# Upgrades single-region backup to full DR architecture:
#   - S3 CRR: us-east-1 → us-west-2 (RTC 15-min SLA)
#   - Velero IRSA: access to primary (R/W) + replica (R/O) buckets
#   - CloudWatch alarms: replication failures + pending bytes
# RTO: 4h  |  RPO: 1h (hourly backup) / 15min (S3 CRR replication lag)
# Cost: ~$10/month additional (S3 CRR + RTC + CloudWatch)
#------------------------------------------------------------------------------

module "velero_dr_staging" {
  source = "../../modules/velero-dr"

  # Multi-region provider aliases (required by module versions.tf)
  providers = {
    aws         = aws
    aws.replica = aws.us-west-2
  }

  cluster_name      = local.cluster_name
  environment       = local.environment
  velero_namespace  = "velero"
  oidc_provider_arn = data.aws_iam_openid_connect_provider.eks.arn
  oidc_provider_url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer

  # Region configuration
  primary_region = "us-east-1"
  replica_region = "us-west-2"

  # Retention: 30d primary, 90d replica (DR compliance)
  retention_days_primary = 30
  retention_days_replica = 90

  # RTC: 15-min replication SLA (~$0.75/month)
  enable_replication_time_control = true

  # Monitoring: reuse existing FinOps SNS topic (saves one SNS topic)
  enable_cloudwatch_alarms = true
  create_sns_topic         = false
  existing_sns_topic_arn   = aws_sns_topic.finops_alerts_staging.arn

  common_tags = local.common_tags
}

#------------------------------------------------------------------------------
# RDS Cross-Region Read Replica - GAP-012 (2026-02-26)
# PostgreSQL read replica in us-west-2 for DR failover.
# Replication lag alarm: > 60s → SNS → PagerDuty
# Cost: ~$50/month (db.t4g.medium + 20 GB gp3 storage)
#
# PRE-REQUISITE: var.dr_vpc_id, var.dr_subnet_ids, var.dr_allowed_cidrs
# must be populated in terraform.tfvars before applying this module.
# Set dr_enable_rds_replica = false to defer RDS replica creation.
#------------------------------------------------------------------------------

module "rds_replica_staging" {
  count  = var.dr_enable_rds_replica ? 1 : 0
  source = "../../modules/rds-replica"

  # All resources are created in us-west-2
  providers = {
    aws = aws.us-west-2
  }

  cluster_name   = local.cluster_name
  environment    = local.environment
  replica_region = "us-west-2"

  # Source (primary) RDS instance in us-east-1
  source_db_identifier = module.postgresql_staging.db_instance_id

  # Replica sizing (FinOps: t4g.medium = ~$47/month, sufficient for staging DR)
  replica_instance_class  = var.dr_rds_replica_instance_class
  max_allocated_storage   = 100
  backup_retention_period = 7

  # Networking in us-west-2 (must be pre-provisioned or via separate VPC module)
  replica_vpc_id        = var.dr_vpc_id
  replica_subnet_ids    = var.dr_subnet_ids
  replica_allowed_cidrs = var.dr_allowed_cidrs

  # Monitoring: replication lag alarm fires at 60s
  enable_cloudwatch_alarms          = true
  replication_lag_threshold_seconds = 60
  storage_free_threshold_bytes      = 4294967296 # 4 GB

  # Reuse FinOps SNS topic — avoid creating a second topic for staging
  create_sns_topic       = false
  existing_sns_topic_arn = aws_sns_topic.finops_alerts_staging.arn

  common_tags = local.common_tags

  depends_on = [module.postgresql_staging]
}

#------------------------------------------------------------------------------
# WAF v2 + DDoS Protection - GAP-010 (2026-02-26)
# Protects iPaaS public endpoint via ALB Ingress Controller association.
# Rules (priority order):
#   10 → Rate limit: 1000 req/5min per IP (BLOCK 429)
#   20 → Geo-block: CN, RU, KP (BLOCK)
#   30 → OWASP Common Rule Set — AWSManagedRulesCommonRuleSet (BLOCK)
#   40 → SQLi Protection — AWSManagedRulesSQLiRuleSet (BLOCK)
#   50 → Known Bad Inputs — AWSManagedRulesKnownBadInputsRuleSet (BLOCK)
#
# ALB ARN: retrieved dynamically via data source.
# Logging: dedicated S3 bucket created by the module (aws-waf-logs-* prefix).
# Cost estimate: ~$10-13/month (WAF WebACL + 5 rules + requests).
#
# IMPORTANT: The data.aws_lb.ingress_alb data source below resolves the ALB
# ARN by the tag set added by the AWS Load Balancer Controller. Verify tags
# after the first ALB is created:
#   aws elbv2 describe-load-balancers --query 'LoadBalancers[*].{Name:LoadBalancerName,ARN:LoadBalancerArn}'
#
# If the ALB does not yet exist (fresh deploy), set var.waf_alb_arn explicitly
# in terraform.tfvars or secrets.auto.tfvars instead of using the data source.
#------------------------------------------------------------------------------

# Data source: resolve the iPaaS ALB ARN from AWS Load Balancer Controller tags.
# TEMPORARILY DISABLED (2026-02-26) — no ALB with stack=ipaas-public exists yet
# Using waf_alb_arn variable instead: platform-staging ALB
# Re-enable after: iPaaS deployed OR update to search for stack=platform-staging
#
# data "aws_lb" "ingress_alb" {
#   # Look up the ALB by its cluster ownership tag injected by AWS LBC
#   tags = {
#     "kubernetes.io/cluster/${local.cluster_name}" = "owned"
#     "ingress.k8s.aws/stack"                       = "ipaas-public"
#   }
# }

module "waf_staging" {
  source = "../../modules/waf"

  # Identity
  environment  = local.environment
  cluster_name = local.cluster_name
  common_tags  = local.common_tags

  # ALB to protect — using var.waf_alb_arn directly (data source disabled)
  # TEMPORARY: data.aws_lb.ingress_alb commented out, requires waf_alb_arn variable
  alb_arn = var.waf_alb_arn

  # Rate limiting
  rate_limit = var.waf_rate_limit

  # Geographic blocking
  enable_geo_blocking = var.waf_enable_geo_blocking
  blocked_countries   = var.waf_blocked_countries

  # Managed rule groups (all enabled in staging to validate before production)
  enable_owasp_common_ruleset     = true
  enable_sqli_ruleset             = true
  enable_known_bad_inputs_ruleset = true

  # Logging — module creates the S3 bucket (aws-waf-logs-k8s-platform-prod-staging)
  enable_logging     = true
  create_log_bucket  = true
  log_retention_days = var.waf_log_retention_days

  # Observability
  cloudwatch_metrics_enabled = true
  enable_sampled_requests    = true
}

#------------------------------------------------------------------------------
# GAP-011: Linkerd Service Mesh — mTLS End-to-End (BACEN BCB 85/2021)
#
# Implements mutual TLS between all annotated iPaaS pods using SPIFFE identity.
# Control plane only; data plane injection is opt-in via pod/namespace annotation:
#   linkerd.io/inject: enabled
#
# Timeline: 3 semanas | Custo adicional: ~$5/mes (overhead minimal de proxy CPU)
# ADR: GAP-011 | Compliance: BCB 85/2021 Art. 6 SS IV (criptografia em transito)
#
# Ordem de apply:
#   1. linkerd-crds (CRDs)
#   2. linkerd-control-plane
#   3. linkerd-viz (se enable_viz=true)
#   Dependencias gerenciadas internamente pelo modulo via depends_on.
#
# Verificacao pos-deploy:
#   linkerd check
#   linkerd viz dashboard
#   linkerd tap deploy/<app> -n ipaas
#------------------------------------------------------------------------------

# GAP-011 Linkerd Module — RE-ENABLED (2026-03-03)
# Blocker RESOLVED: 4 dashboard JSON files created (linkerd-top-line, service-mesh, deployment, namespace)
# Original blocker: file() always evaluated even with count=0 — now resolved (files exist)
#------------------------------------------------------------------------------
# CICD-003: Automated Secret Rotation (ADR-083)
# Quarterly CronJob that rotates PostgreSQL, Keycloak, Harbor and OIDC secrets.
# Pre-requisites:
#   1. Vault policy applied:  vault policy write secret-rotation scripts/vault/vault-rotation-policy.hcl
#   2. Vault KV path created: vault kv put secret/secret-rotator/token token=<service-token>
#   3. Vault KV path created: vault kv put secret/postgresql-admin/password username=<user> password=<pass>
# First execution: 2026-04-01T02:00:00Z (quarterly schedule 0 2 1 */3 *)
#------------------------------------------------------------------------------
module "secret_rotation" {
  source = "../../modules/secret-rotation"

  namespace   = "staging-security-vault"
  environment = local.environment

  # Quarterly rotation — PCI-DSS 8.2.4 compliance
  rotation_schedule = "0 2 1 */3 *"

  # Vault connection (cluster-internal)
  vault_addr = "http://vault.staging-security-vault.svc.cluster.local:8200"

  # RDS endpoint (staging shares prod RDS — ADR-050)
  rds_endpoint = "k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com"

  # Keycloak connection
  keycloak_url   = "http://keycloak-keycloakx-http.staging-platform-keycloak.svc.cluster.local"
  keycloak_realm = "platform"

  # Staging: dry_run=false (real rotation). Set to true for first test.
  dry_run   = false
  log_level = "INFO"
}

# Re-enabled (2026-03-03) — Dashboard blocker resolved
module "linkerd" {
  source = "../../modules/linkerd"

  cluster_name = local.cluster_name
  environment  = local.environment
  common_tags  = local.common_tags

  # --- Versoes Helm (stable-2.16.x channel) ---
  # Verificar versoes atuais em: https://artifacthub.io/packages/helm/linkerd2
  linkerd_crds_chart_version = "1.8.0"
  linkerd_version            = "1.16.11"
  linkerd_viz_chart_version  = "30.12.11"

  # --- PKI (TLS provider — auto-gerado pelo Terraform) ---
  # trust_anchor: root CA, validade 365 dias (renovar antes do vencimento)
  # issuer: intermediario, assina certs de workload (24h TTL, auto-rotacao)
  trust_domain              = "cluster.local"
  certificate_validity_days = 365

  # --- Proxy Resources (staging: limites minimos) ---
  proxy_cpu_request    = "100m"
  proxy_memory_request = "64Mi"
  proxy_cpu_limit      = "500m"
  proxy_memory_limit   = "256Mi"

  # --- HA Mode ---
  # staging: false (1 replica por componente, sem PDB)
  # production: true (3 replicas, PodDisruptionBudgets habilitados)
  ha_mode = false

  # --- Viz Extension ---
  # Usa Prometheus externo (kube-prometheus-stack) — NAO sobe instancia proprio
  enable_viz              = true
  viz_prometheus_enabled  = false
  external_prometheus_url = "http://kube-prometheus-stack-prometheus.staging-observability-monitoring.svc.cluster.local:9090"

  # --- Grafana Dashboards ---
  # ENABLED (2026-03-03) — 4 dashboard JSONs created (top-line, service-mesh, deployment, namespace)
  enable_grafana_dashboards       = true
  grafana_dashboard_namespace     = "staging-observability-monitoring"

  # --- Jaeger / Tracing ---
  # Desabilitado em staging (OpenTelemetry Collector ja existe em monitoring)
  # Para habilitar: enable_jaeger=true e configurar collector_backend_addr
  enable_jaeger = false

  # --- Opt-in Proxy Injection por Namespace ---
  # Namespaces para inject automatico de sidecar Linkerd.
  # NOTA: Namespaces devem existir no cluster antes de serem listados aqui.
  # Adicionar namespace novo: incluir aqui + fazer rolling restart dos pods:
  #   kubectl rollout restart deployment -n <namespace>
  # Habilitado quando namespaces ipaas/integration forem criados:
  #   proxy_inject_namespaces = ["staging-integration-ipaas", "staging-integration-workers"]
  proxy_inject_namespaces = []
}

# -----------------------------------------------------------------------------
# Harbor Container Registry Module
# Private container registry with Trivy scanning and S3 storage (IRSA)
# -----------------------------------------------------------------------------

terraform {
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
  }
}

# -----------------------------------------------------------------------------
# V-004 REMEDIATED: Harbor admin password migrado para Vault + ESO (2026-02-24)
# Removido: random_password.harbor_admin + kubernetes_secret.harbor_admin_password
# Source of truth: vault_kv_secret_v2.harbor_admin (vault-config/main.tf)
# ESO: harbor-admin-credentials ExternalSecret (created below)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# V-003 REMEDIATED: PostgreSQL password via Vault KV (2026-02-24)
# Source of truth: vault_kv_secret_v2.harbor_postgresql (vault-config/main.tf)
# ESO: harbor-postgresql-credentials ExternalSecret (created below)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# V-005 REMEDIATED: Redis password migrado para Vault + ESO (2026-02-24)
# Removido: data.kubernetes_secret.redis_password
# Source of truth: vault_kv_secret_v2.harbor_redis (vault-config/main.tf)
# ESO: harbor-redis-credentials ExternalSecret (created below)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# IAM Role for Harbor IRSA (S3 permissions)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "harbor_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:sub"
      values = [
        "system:serviceaccount:${var.namespace}:harbor",
        "system:serviceaccount:${var.namespace}:harbor-core",
        "system:serviceaccount:${var.namespace}:harbor-jobservice",
        "system:serviceaccount:${var.namespace}:harbor-registry"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_arn, "/^(.*provider/)/", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "harbor" {
  name               = "HarborIRSA-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.harbor_assume_role.json

  tags = merge(var.common_tags, {
    Name                     = "HarborIRSA-${var.cluster_name}"
    "app.kubernetes.io/name" = "harbor"
  })
}

data "aws_iam_policy_document" "harbor_permissions" {
  # S3 permissions for image storage
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      var.s3_bucket_arn,
      "${var.s3_bucket_arn}/*"
    ]
  }
}

resource "aws_iam_policy" "harbor" {
  name        = "HarborIRSA-${var.cluster_name}"
  description = "IAM policy for Harbor IRSA (S3 image storage)"
  policy      = data.aws_iam_policy_document.harbor_permissions.json

  tags = merge(var.common_tags, {
    Name                     = "HarborIRSA-${var.cluster_name}"
    "app.kubernetes.io/name" = "harbor"
  })
}

resource "aws_iam_role_policy_attachment" "harbor" {
  role       = aws_iam_role.harbor.name
  policy_arn = aws_iam_policy.harbor.arn
}

# -----------------------------------------------------------------------------
# Kubernetes Namespace
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "harbor" {
  metadata {
    name = var.namespace

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"       = "harbor"
      "app.kubernetes.io/instance"   = "${var.cluster_name}-harbor"
      "app.kubernetes.io/managed-by" = "terraform"
    })
  }
}

# -----------------------------------------------------------------------------
# Harbor ServiceAccount with IRSA annotation
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "harbor" {
  metadata {
    name      = "harbor"
    namespace = kubernetes_namespace.harbor.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.harbor.arn
    }

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"     = "harbor"
      "app.kubernetes.io/instance" = "${var.cluster_name}-harbor"
    })
  }
}

# -----------------------------------------------------------------------------
# Harbor Helm Release
# -----------------------------------------------------------------------------

resource "helm_release" "harbor" {
  name       = "harbor"
  repository = "https://helm.goharbor.io"
  chart      = "harbor"
  version    = var.harbor_chart_version
  namespace  = kubernetes_namespace.harbor.metadata[0].name

  values = [templatefile("${path.module}/values.yaml.tpl", {
    cluster_name    = var.cluster_name
    namespace       = var.namespace
    service_account = kubernetes_service_account.harbor.metadata[0].name
    # V-003/V-004/V-005: passwords movidos para Vault + ESO (2026-02-24)
    postgresql_host     = var.postgresql_host
    postgresql_port     = var.postgresql_port
    postgresql_database = var.postgresql_database
    postgresql_username = var.postgresql_username
    redis_host          = var.redis_host
    redis_port          = var.redis_port
    s3_bucket           = var.s3_bucket_name
    s3_region           = var.aws_region
    storage_class       = var.storage_class
    enable_trivy        = var.enable_trivy
    enable_monitoring   = var.enable_monitoring
    ingress_enabled     = var.ingress_enabled
    ingress_host        = var.ingress_host
    ingress_group_name  = var.ingress_group_name
  })]

  depends_on = [
    kubernetes_service_account.harbor,
    aws_iam_role_policy_attachment.harbor,
    kubectl_manifest.harbor_postgresql_externalsecret, # V-003
    kubectl_manifest.harbor_admin_externalsecret,      # V-004
    kubectl_manifest.harbor_redis_externalsecret       # V-005
  ]

  timeout = 600 # 10 minutes
}

# -----------------------------------------------------------------------------
# ConfigMap with Harbor robot account setup instructions
# -----------------------------------------------------------------------------

resource "kubernetes_config_map" "harbor_setup" {
  metadata {
    name      = "harbor-setup-instructions"
    namespace = kubernetes_namespace.harbor.metadata[0].name

    labels = merge(var.common_tags, {
      "app.kubernetes.io/name"     = "harbor"
      "app.kubernetes.io/instance" = "${var.cluster_name}-harbor"
    })
  }

  data = {
    "create-robot-account.sh" = file("${path.module}/scripts/create-robot-account.sh")
  }
}

# -----------------------------------------------------------------------------
# Harbor PostgreSQL credentials — ExternalSecret (Vault backend)
# Vault path: secret/data/harbor/postgresql
# Keys: postgresql-password, username, host, port, database
# Source of truth: vault_kv_secret_v2.harbor_postgresql (vault-config/main.tf)
# Purpose: Runtime secret rotation — Helm chart reads from var.postgresql_password
#   on first apply; subsequent rotations handled via ESO refresh (1h)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "harbor_postgresql_externalsecret" {
  depends_on = [kubernetes_namespace.harbor]

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "harbor-postgresql-credentials"
      namespace = kubernetes_namespace.harbor.metadata[0].name
      labels = {
        "app.kubernetes.io/name"       = "harbor-postgresql-credentials"
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "vault-backend"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "harbor-postgresql-credentials"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "postgresql-password"
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

# -----------------------------------------------------------------------------
# OIDC / SSO via Keycloak (ExternalSecret + API config)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "harbor_oidc_externalsecret" {
  count = var.enable_oidc ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "harbor-oidc-credentials"
      namespace = kubernetes_namespace.harbor.metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "vault-backend"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "harbor-oidc-credentials"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "client_id"
          remoteRef = {
            key      = "secret/data/harbor/oidc"
            property = "client_id"
          }
        },
        {
          secretKey = "client_secret"
          remoteRef = {
            key      = "secret/data/harbor/oidc"
            property = "client_secret"
          }
        }
      ]
    }
  })

  depends_on = [kubernetes_namespace.harbor]
}

# -----------------------------------------------------------------------------
# ExternalSecret: Harbor Admin Password (V-004 Remediation)
# Vault path: secret/data/harbor/admin
# Keys: password
# Target: harbor-admin-credentials (K8s Secret in harbor-system namespace)
# Migration: random_password.harbor_admin → Vault KV + ESO (2026-02-24)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "harbor_admin_externalsecret" {
  depends_on = [kubernetes_namespace.harbor]

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "harbor-admin-credentials"
      namespace = kubernetes_namespace.harbor.metadata[0].name
      labels = {
        "app.kubernetes.io/name"       = "harbor-admin-credentials"
        "app.kubernetes.io/managed-by" = "terraform"
      }
      annotations = {
        description = "Harbor admin credentials synced from Vault KV v2 (V-004)"
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "vault-backend"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "harbor-admin-credentials"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "HARBOR_ADMIN_PASSWORD" # Key required by Harbor chart
          remoteRef = {
            key      = "secret/data/harbor/admin"
            property = "password"
          }
        }
      ]
    }
  })
}

# -----------------------------------------------------------------------------
# ExternalSecret: Harbor Redis Password (V-005 Remediation)
# Vault path: secret/data/harbor/redis
# Keys: password
# Target: harbor-redis-credentials (K8s Secret in harbor-system namespace)
# Migration: data.kubernetes_secret.redis_password → Vault KV + ESO (2026-02-24)
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "harbor_redis_externalsecret" {
  depends_on = [kubernetes_namespace.harbor]

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "harbor-redis-credentials"
      namespace = kubernetes_namespace.harbor.metadata[0].name
      labels = {
        "app.kubernetes.io/name"       = "harbor-redis-credentials"
        "app.kubernetes.io/managed-by" = "terraform"
      }
      annotations = {
        description = "Harbor Redis credentials synced from Vault KV v2 (V-005)"
      }
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "vault-backend"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "harbor-redis-credentials"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "REDIS_PASSWORD" # Key required by Harbor chart
          remoteRef = {
            key      = "secret/data/harbor/redis"
            property = "password"
          }
        }
      ]
    }
  })
}

resource "null_resource" "harbor_oidc_config" {
  count = var.enable_oidc ? 1 : 0

  triggers = {
    oidc_endpoint = var.oidc_endpoint
    admin_group   = var.oidc_admin_group
  }

  provisioner "local-exec" {
    command = <<-EOT
      CORE_POD=$(kubectl get pods -n ${kubernetes_namespace.harbor.metadata[0].name} \
        -l app=harbor,component=core -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

      if [ -z "$CORE_POD" ]; then
        echo "ERROR: Harbor core pod not found"
        exit 1
      fi

      # Read OIDC credentials from ExternalSecret-synced K8s secret
      CLIENT_ID=$(kubectl get secret harbor-oidc-credentials \
        -n ${kubernetes_namespace.harbor.metadata[0].name} \
        -o jsonpath='{.data.client_id}' 2>/dev/null | base64 -d)
      CLIENT_SECRET=$(kubectl get secret harbor-oidc-credentials \
        -n ${kubernetes_namespace.harbor.metadata[0].name} \
        -o jsonpath='{.data.client_secret}' 2>/dev/null | base64 -d)

      # Fallback: if ExternalSecret not synced yet, skip gracefully
      if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
        echo "WARN: harbor-oidc-credentials not synced yet. OIDC config skipped."
        echo "Run 'terraform apply' again after Vault secret is seeded."
        exit 0
      fi

      # V-004: harbor-admin-password → harbor-admin-credentials (ESO)
      ADMIN_PWD=$(kubectl get secret harbor-admin-credentials \
        -n ${kubernetes_namespace.harbor.metadata[0].name} \
        -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d)

      kubectl exec -n ${kubernetes_namespace.harbor.metadata[0].name} "$CORE_POD" -- \
        curl -sf -X PUT http://localhost:8080/api/v2.0/configurations \
          -u "admin:$ADMIN_PWD" \
          -H "Content-Type: application/json" \
          -d "{
            \"auth_mode\": \"oidc_auth\",
            \"oidc_name\": \"Keycloak\",
            \"oidc_endpoint\": \"${var.oidc_endpoint}\",
            \"oidc_client_id\": \"$CLIENT_ID\",
            \"oidc_client_secret\": \"$CLIENT_SECRET\",
            \"oidc_scope\": \"openid,profile,email\",
            \"oidc_verify_cert\": false,
            \"oidc_auto_onboard\": true,
            \"oidc_user_claim\": \"preferred_username\",
            \"oidc_groups_claim\": \"groups\",
            \"oidc_admin_group\": \"${var.oidc_admin_group}\"
          }"

      echo ""
      echo "Harbor OIDC configured successfully via API"
    EOT
  }

  depends_on = [
    helm_release.harbor,
    kubectl_manifest.harbor_oidc_externalsecret
  ]
}

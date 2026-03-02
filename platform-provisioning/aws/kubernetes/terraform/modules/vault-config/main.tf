# -----------------------------------------------------------------------------
# Vault Post-Deployment Configuration Module
# Configures K8s auth, policies, roles, and initial secrets
# MUST run after Vault is initialized and unsealed
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.25"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# -----------------------------------------------------------------------------
# Vault Provider Configuration
# Uses root token for initial setup (can be transitioned to AppRole later)
# -----------------------------------------------------------------------------

provider "vault" {
  address = var.vault_addr
  token   = var.vault_token
}

# -----------------------------------------------------------------------------
# Enable Kubernetes Auth Method
# -----------------------------------------------------------------------------

resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"

  description = "Kubernetes auth for ${var.cluster_name} workloads"
}

# -----------------------------------------------------------------------------
# Configure Kubernetes Auth Backend
# Connects Vault to the K8s API server for SA token validation
# -----------------------------------------------------------------------------

resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = var.kubernetes_host
  kubernetes_ca_cert = base64decode(var.kubernetes_ca_cert)

  # Disable local JWT validation (use K8s API for validation)
  disable_local_ca_jwt = false
}

# -----------------------------------------------------------------------------
# Policy: ESO Reader (read-only access to secret/*)
# -----------------------------------------------------------------------------

resource "vault_policy" "eso_reader" {
  name   = "eso-reader"
  policy = file("${path.module}/vault_policies/eso-reader.hcl")
}

# -----------------------------------------------------------------------------
# Kubernetes Auth Role: eso-reader
# Binds ESO ServiceAccount to eso-reader policy
# -----------------------------------------------------------------------------

resource "vault_kubernetes_auth_backend_role" "eso_reader" {
  backend   = vault_auth_backend.kubernetes.path
  role_name = "eso-reader"

  bound_service_account_names      = [var.eso_service_account]
  bound_service_account_namespaces = [var.eso_namespace]

  token_ttl      = 900  # 15 min (Security: reduced exposure window)
  token_max_ttl  = 3600 # 1 hour (was 24h)
  token_policies = [vault_policy.eso_reader.name]

  audience = null # Use default K8s audience
}

# -----------------------------------------------------------------------------
# KV v2 Secrets Engine Mount
# -----------------------------------------------------------------------------

resource "vault_mount" "kv" {
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "KV v2 secrets engine for platform secrets"
}

# -----------------------------------------------------------------------------
# Random Password for Keycloak PostgreSQL (if not provided)
# -----------------------------------------------------------------------------

resource "random_password" "keycloak_postgresql" {
  count = var.keycloak_postgresql_password == "" ? 1 : 0

  length  = 32
  special = true

  lifecycle {
    ignore_changes = [length, special]
  }
}

locals {
  keycloak_password = var.keycloak_postgresql_password != "" ? var.keycloak_postgresql_password : random_password.keycloak_postgresql[0].result
}

# -----------------------------------------------------------------------------
# Vault KV v2 Secret: Keycloak PostgreSQL Credentials
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# OIDC Auth Method — Keycloak SSO for Vault UI + CLI
# Pattern: same external URL rule as Grafana/Harbor (never svc.cluster.local)
# Redirect URIs: Vault UI callback + vault CLI callback
# -----------------------------------------------------------------------------

resource "vault_jwt_auth_backend" "oidc" {
  count = var.oidc_enabled ? 1 : 0

  path               = "oidc"
  type               = "oidc"
  oidc_discovery_url = var.keycloak_oidc_url
  oidc_client_id     = var.vault_oidc_client_id
  oidc_client_secret = var.vault_oidc_client_secret
  default_role       = "reader"
  description        = "Keycloak OIDC SSO for ${var.cluster_name}"

  depends_on = [vault_mount.kv]
}

# Policy: vault-admin (platform admins — Keycloak group: vault-admins)
resource "vault_policy" "vault_admin" {
  count  = var.oidc_enabled ? 1 : 0
  name   = "vault-admin"
  policy = file("${path.module}/vault_policies/vault-admin.hcl")
}

# Policy: vault-reader (any authenticated Keycloak user)
resource "vault_policy" "vault_reader" {
  count  = var.oidc_enabled ? 1 : 0
  name   = "vault-reader"
  policy = file("${path.module}/vault_policies/vault-reader.hcl")
}

# OIDC Role: admin (bound to Keycloak group vault-admins)
resource "vault_jwt_auth_backend_role" "admin" {
  count = var.oidc_enabled ? 1 : 0

  backend   = vault_jwt_auth_backend.oidc[0].path
  role_name = "admin"
  role_type = "oidc"

  token_policies = [vault_policy.vault_admin[0].name]
  token_ttl      = 28800 # 8h
  token_max_ttl  = 86400 # 24h

  oidc_scopes  = ["openid", "email", "profile"]
  user_claim   = "email"
  groups_claim = "groups"

  # Restrict to vault-admins Keycloak group
  bound_claims = {
    groups = "vault-admins"
  }

  allowed_redirect_uris = [
    "http://vault.staging.internal/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ]
}

# OIDC Role: reader (any authenticated Keycloak user — no bound_claims)
resource "vault_jwt_auth_backend_role" "reader" {
  count = var.oidc_enabled ? 1 : 0

  backend   = vault_jwt_auth_backend.oidc[0].path
  role_name = "reader"
  role_type = "oidc"

  token_policies = [vault_policy.vault_reader[0].name]
  token_ttl      = 14400 # 4h
  token_max_ttl  = 28800 # 8h

  oidc_scopes = ["openid", "email", "profile"]
  user_claim  = "email"

  allowed_redirect_uris = [
    "http://vault.staging.internal/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ]
}

# -----------------------------------------------------------------------------
# Random Passwords — Auto-generated secrets (V-001/V-002)
# Used when var.XXX_password is empty (default="")
# Pattern: random_password → vault_kv_secret_v2 → ESO → K8s Secret
# -----------------------------------------------------------------------------

resource "random_password" "grafana_admin" {
  count            = var.grafana_admin_password == "" ? 1 : 0
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "argocd_postgresql" {
  count            = var.argocd_postgresql_password == "" ? 1 : 0
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "argocd_oidc" {
  count            = var.argocd_oidc_client_secret == "" ? 1 : 0
  length           = 48
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# -----------------------------------------------------------------------------
# Vault KV v2 — Grafana Admin Password (V-001 Remediation)
# Vault path: secret/grafana/admin
# ESO ExternalSecret: grafana-admin-credentials (kube-prometheus-stack/main.tf)
# Migration: hardcoded "admin" → Vault KV + ESO + existingSecret (2026-02-20)
# eso-reader policy already covers secret/data/grafana/* (eso-reader.hcl)
# -----------------------------------------------------------------------------
resource "vault_kv_secret_v2" "grafana_admin" {
  count      = var.grafana_admin_password != "" || length(random_password.grafana_admin) > 0 ? 1 : 0
  mount      = vault_mount.kv.path
  name       = "grafana/admin"
  depends_on = [vault_mount.kv]

  data_json = jsonencode({
    password = var.grafana_admin_password != "" ? var.grafana_admin_password : random_password.grafana_admin[0].result
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by  = "terraform"
      service     = "grafana"
      cluster     = var.cluster_name
      remediation = "V-001"
    }
  }
}

# -----------------------------------------------------------------------------
# Vault KV v2 — Grafana OIDC credentials
# Vault path: secret/grafana/oidc
# ESO ExternalSecret: grafana-oidc-credentials (kube-prometheus-stack/main.tf)
# Migration: valor migrado de staging/main.tf hardcode (2026-02-19)
# -----------------------------------------------------------------------------
resource "vault_kv_secret_v2" "grafana_oidc" {
  count      = var.grafana_oidc_client_secret != "" ? 1 : 0
  mount      = vault_mount.kv.path
  name       = "grafana/oidc"
  depends_on = [vault_mount.kv]

  data_json = jsonencode({
    client_id     = var.grafana_oidc_client_id
    client_secret = var.grafana_oidc_client_secret
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by = "terraform"
      service    = "grafana"
      cluster    = var.cluster_name
    }
  }
}

# -----------------------------------------------------------------------------
# Vault KV v2 — SonarQube PostgreSQL credentials
# Vault path: secret/sonarqube/postgresql
# ESO ExternalSecret: sonarqube-postgresql (modules/sonarqube/main.tf)
# Resolves: TODO comment sonarqube/main.tf:50-52
# -----------------------------------------------------------------------------
resource "vault_kv_secret_v2" "sonarqube_postgresql" {
  count      = var.sonarqube_postgresql_password != "" ? 1 : 0
  mount      = vault_mount.kv.path
  name       = "sonarqube/postgresql"
  depends_on = [vault_mount.kv]

  data_json = jsonencode({
    password = var.sonarqube_postgresql_password
    username = var.sonarqube_postgresql_username
    host     = var.sonarqube_postgresql_host
    port     = var.sonarqube_postgresql_port
    database = var.sonarqube_postgresql_database
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by = "terraform"
      service    = "sonarqube"
      cluster    = var.cluster_name
    }
  }
}

# -----------------------------------------------------------------------------
# Vault KV v2 — Harbor PostgreSQL credentials
# Vault path: secret/harbor/postgresql
# ESO ExternalSecret: harbor-postgresql-credentials (modules/harbor/main.tf)
# Migration: substitui data.aws_secretsmanager_secret "staging/postgresql/gitlab-password"
# -----------------------------------------------------------------------------
resource "vault_kv_secret_v2" "harbor_postgresql" {
  count      = var.harbor_postgresql_password != "" ? 1 : 0
  mount      = vault_mount.kv.path
  name       = "harbor/postgresql"
  depends_on = [vault_mount.kv]

  data_json = jsonencode({
    password = var.harbor_postgresql_password
    username = var.harbor_postgresql_username
    host     = var.harbor_postgresql_host
    port     = var.harbor_postgresql_port
    database = var.harbor_postgresql_database
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by = "terraform"
      service    = "harbor"
      cluster    = var.cluster_name
    }
  }
}

# -----------------------------------------------------------------------------
resource "vault_kv_secret_v2" "keycloak_postgresql" {
  mount      = vault_mount.kv.path
  name       = "keycloak/postgresql"
  depends_on = [vault_mount.kv]

  data_json = jsonencode({
    password = local.keycloak_password
    username = var.keycloak_postgresql_username
    host     = var.keycloak_postgresql_host
    port     = var.keycloak_postgresql_port
    database = var.keycloak_postgresql_database
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by = "terraform"
      service    = "keycloak"
      cluster    = var.cluster_name
    }
  }
}

# -----------------------------------------------------------------------------
# Vault KV v2 — ArgoCD PostgreSQL credentials
# Vault path: secret/argocd/postgresql
# ESO ExternalSecret: argocd-postgresql-credentials (modules/argocd/main.tf)
# V-002 remediation: ArgoCD PostgreSQL credentials to Vault+ESO
# -----------------------------------------------------------------------------
resource "vault_kv_secret_v2" "argocd_postgresql" {
  count      = var.argocd_postgresql_password != "" || length(random_password.argocd_postgresql) > 0 ? 1 : 0
  mount      = vault_mount.kv.path
  name       = "argocd/postgresql"
  depends_on = [vault_mount.kv]

  data_json = jsonencode({
    password = var.argocd_postgresql_password != "" ? var.argocd_postgresql_password : random_password.argocd_postgresql[0].result
    username = var.argocd_postgresql_username
    host     = var.argocd_postgresql_host
    port     = var.argocd_postgresql_port
    database = var.argocd_postgresql_database
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by  = "terraform"
      service     = "argocd"
      cluster     = var.cluster_name
      remediation = "V-002"
    }
  }
}

# -----------------------------------------------------------------------------
# Vault KV v2 — ArgoCD OIDC client secret (Keycloak)
# Vault path: secret/argocd/oidc
# ESO ExternalSecret: argocd-oidc-credentials (modules/argocd/main.tf)
# V-002 remediation: ArgoCD OIDC client secret to Vault+ESO
# -----------------------------------------------------------------------------
resource "vault_kv_secret_v2" "argocd_oidc" {
  count      = var.argocd_oidc_client_secret != "" || length(random_password.argocd_oidc) > 0 ? 1 : 0
  mount      = vault_mount.kv.path
  name       = "argocd/oidc"
  depends_on = [vault_mount.kv]

  data_json = jsonencode({
    client_id     = var.argocd_oidc_client_id
    client_secret = var.argocd_oidc_client_secret != "" ? var.argocd_oidc_client_secret : random_password.argocd_oidc[0].result
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by  = "terraform"
      service     = "argocd"
      cluster     = var.cluster_name
      remediation = "V-002"
    }
  }
}

# -----------------------------------------------------------------------------
# Vault KV v2 — Harbor Admin Password (V-004 Remediation)
# Vault path: secret/harbor/admin
# ESO ExternalSecret: harbor-admin-credentials (modules/harbor/main.tf)
# Migration: random_password.harbor_admin → Vault KV + ESO (2026-02-24)
# -----------------------------------------------------------------------------
resource "random_password" "harbor_admin" {
  count            = var.harbor_admin_password == "" ? 1 : 0
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "vault_kv_secret_v2" "harbor_admin" {
  count      = 1
  mount      = vault_mount.kv.path
  name       = "harbor/admin"
  depends_on = [vault_mount.kv]

  data_json = jsonencode({
    password = var.harbor_admin_password != "" ? var.harbor_admin_password : random_password.harbor_admin[0].result
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by  = "terraform"
      service     = "harbor"
      cluster     = var.cluster_name
      remediation = "V-004"
    }
  }
}

# -----------------------------------------------------------------------------
# Vault KV v2 — Harbor Redis Password (V-005 Remediation)
# Vault path: secret/harbor/redis
# ESO ExternalSecret: harbor-redis-credentials (modules/harbor/main.tf)
# Migration: data.kubernetes_secret.redis_password → Vault KV + ESO (2026-02-24)
# -----------------------------------------------------------------------------
resource "random_password" "harbor_redis" {
  count            = var.harbor_redis_password == "" ? 1 : 0
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "vault_kv_secret_v2" "harbor_redis" {
  count      = 1
  mount      = vault_mount.kv.path
  name       = "harbor/redis"
  depends_on = [vault_mount.kv]

  data_json = jsonencode({
    password = var.harbor_redis_password != "" ? var.harbor_redis_password : random_password.harbor_redis[0].result
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by  = "terraform"
      service     = "harbor"
      cluster     = var.cluster_name
      remediation = "V-005"
    }
  }
}

# -----------------------------------------------------------------------------
# Vault KV v2 — Keycloak Admin Password (V-006 Remediation)
# Vault path: secret/keycloak/admin
# ESO ExternalSecret: keycloak-admin-credentials (modules/keycloak/main.tf)
# Migration: random_password.keycloak_admin → Vault KV + ESO (2026-02-24)
# -----------------------------------------------------------------------------
resource "random_password" "keycloak_admin" {
  count            = var.keycloak_admin_password == "" ? 1 : 0
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "vault_kv_secret_v2" "keycloak_admin" {
  count      = 1
  mount      = vault_mount.kv.path
  name       = "keycloak/admin"
  depends_on = [vault_mount.kv]

  data_json = jsonencode({
    username = "admin"
    password = var.keycloak_admin_password != "" ? var.keycloak_admin_password : random_password.keycloak_admin[0].result
  })

  custom_metadata {
    max_versions = 5
    data = {
      managed_by  = "terraform"
      service     = "keycloak"
      cluster     = var.cluster_name
      remediation = "V-006"
    }
  }
}

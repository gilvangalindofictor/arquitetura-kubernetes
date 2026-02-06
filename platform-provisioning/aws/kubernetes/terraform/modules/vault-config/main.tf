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

  token_ttl      = 900   # 15 min (Security: reduced exposure window)
  token_max_ttl  = 3600  # 1 hour (was 24h)
  token_policies = [vault_policy.eso_reader.name]

  audience = null # Use default K8s audience
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

resource "vault_kv_secret_v2" "keycloak_postgresql" {
  mount = "secret"
  name  = "keycloak/postgresql"

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

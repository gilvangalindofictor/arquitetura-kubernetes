# -----------------------------------------------------------------------------
# SonarQube Module
# Code quality and security scanning with PostgreSQL backend
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
  }
}

# -----------------------------------------------------------------------------
# Kubernetes Namespace
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "sonarqube" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "sonarqube"
      "app.kubernetes.io/instance"   = "${var.cluster_name}-sonarqube"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# PostgreSQL Database Bootstrap
# Note: Database and user were bootstrapped via postgresql module (sonarqube_user)
# Password managed by Terraform SM anti-drift: staging/postgresql/sonarqube-password
# Vault KV: secret/sonarqube/postgresql (seeded by vault-config module)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Kubernetes Secret: PostgreSQL Connection — via ExternalSecret (Vault backend)
# Vault path: secret/data/sonarqube/postgresql
# Keys: postgresql-password, username, host, port, database
# ClusterSecretStore: vault-backend (Vault K8s auth, eso-reader policy)
# Prerequisite: vault_kv_secret_v2.sonarqube_postgresql in vault-config/main.tf
# -----------------------------------------------------------------------------

resource "kubectl_manifest" "sonarqube_postgresql_externalsecret" {
  depends_on = [kubernetes_namespace.sonarqube]

  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: sonarqube-postgresql
      namespace: ${var.namespace}
      labels:
        app.kubernetes.io/name: sonarqube-postgresql
        app.kubernetes.io/managed-by: terraform
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: vault-backend
        kind: ClusterSecretStore
      target:
        name: sonarqube-postgresql
        creationPolicy: Owner
      data:
        - secretKey: postgresql-password
          remoteRef:
            key: secret/data/sonarqube/postgresql
            property: password
        - secretKey: username
          remoteRef:
            key: secret/data/sonarqube/postgresql
            property: username
        - secretKey: host
          remoteRef:
            key: secret/data/sonarqube/postgresql
            property: host
        - secretKey: port
          remoteRef:
            key: secret/data/sonarqube/postgresql
            property: port
        - secretKey: database
          remoteRef:
            key: secret/data/sonarqube/postgresql
            property: database
  YAML
}

# -----------------------------------------------------------------------------
# SonarQube Helm Release
# -----------------------------------------------------------------------------

resource "helm_release" "sonarqube" {
  name       = "sonarqube"
  repository = "https://SonarSource.github.io/helm-chart-sonarqube"
  chart      = "sonarqube"
  version    = var.sonarqube_chart_version
  namespace  = kubernetes_namespace.sonarqube.metadata[0].name

  values = [templatefile("${path.module}/values.yaml.tpl", {
    cluster_name               = var.cluster_name
    replicas                   = var.replicas
    postgresql_host            = var.postgresql_host
    postgresql_port            = var.postgresql_port
    postgresql_database        = var.postgresql_database
    storage_class              = var.storage_class
    pvc_size                   = var.pvc_size
    ingress_enabled            = var.ingress_enabled
    domain                     = var.domain
    ingress_group_name         = var.ingress_group_name
    enable_monitoring          = var.enable_monitoring
    enable_prometheus_exporter = var.enable_prometheus_exporter
    # SAML variables
    saml_enabled              = var.saml_enabled
    saml_application_id       = var.saml_application_id
    saml_provider_id          = var.saml_provider_id
    saml_login_url            = var.saml_login_url
    saml_certificate          = var.saml_certificate
    saml_user_login_attribute = var.saml_user_login_attribute
    saml_user_email_attribute = var.saml_user_email_attribute
    saml_user_name_attribute  = var.saml_user_name_attribute
    saml_group_attribute      = var.saml_group_attribute
    saml_sp_certificate       = var.saml_sp_certificate
    saml_sp_secret_name       = var.saml_sp_secret_name
    # GitLab OAuth2 variables
    gitlab_oauth_enabled = var.gitlab_oauth_enabled
    gitlab_url           = var.gitlab_url
    gitlab_allow_signup  = var.gitlab_allow_signup
    gitlab_groups_sync   = var.gitlab_groups_sync
    # ECR Pull-Through Cache
    ecr_registry = var.ecr_registry
  })]

  depends_on = [
    kubernetes_namespace.sonarqube,
    kubectl_manifest.sonarqube_postgresql_externalsecret
  ]

  timeout = 600 # 10 minutes
}

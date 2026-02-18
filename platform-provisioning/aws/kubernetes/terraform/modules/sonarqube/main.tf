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
# -----------------------------------------------------------------------------

# TODO: Bootstrap database via postgresql module
# Requires: CREATE DATABASE sonarqube; CREATE USER sonarqube_user;

# -----------------------------------------------------------------------------
# Kubernetes Secret: PostgreSQL Connection
# -----------------------------------------------------------------------------

# TODO: Create via ExternalSecret (Vault backend)
# Secret name: sonarqube-postgresql
# Keys: postgresql-username, postgresql-password, postgresql-host, postgresql-port

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
  })]

  depends_on = [
    kubernetes_namespace.sonarqube
  ]

  timeout = 600 # 10 minutes
}

# =============================================================================
# GAP-CONF-009 (P1): Pod Security Admission (PSA) Labels — PROD
# Data: 2026-03-26 | Security & Resilience Specialist
# =============================================================================
#
# Aplica labels PSA nos namespaces de workload PROD:
#   - pod-security.kubernetes.io/enforce=baseline   (bloqueia pods que violam baseline)
#   - pod-security.kubernetes.io/warn=restricted     (avisa quando pods violam restricted)
#
# Referência: https://kubernetes.io/docs/concepts/security/pod-security-standards/
# Usa kubectl_manifest com server_side_apply=true para merge labels sem conflito.
# =============================================================================

# --- prod-platform-argocd ---
resource "kubectl_manifest" "psa_prod_argocd" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: prod-platform-argocd
      labels:
        pod-security.kubernetes.io/enforce: baseline
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: restricted
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
}

# --- prod-platform-harbor ---
resource "kubectl_manifest" "psa_prod_harbor" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: prod-platform-harbor
      labels:
        pod-security.kubernetes.io/enforce: baseline
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: restricted
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
}

# --- prod-platform-keycloak ---
resource "kubectl_manifest" "psa_prod_keycloak" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: prod-platform-keycloak
      labels:
        pod-security.kubernetes.io/enforce: baseline
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: restricted
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
}

# --- prod-platform-sonarqube ---
resource "kubectl_manifest" "psa_prod_sonarqube" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: prod-platform-sonarqube
      labels:
        pod-security.kubernetes.io/enforce: baseline
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: restricted
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
}

# --- prod-platform-backstage ---
resource "kubectl_manifest" "psa_prod_backstage" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: prod-platform-backstage
      labels:
        pod-security.kubernetes.io/enforce: baseline
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: restricted
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
}

# --- prod-observability-monitoring ---
resource "kubectl_manifest" "psa_prod_monitoring" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: prod-observability-monitoring
      labels:
        pod-security.kubernetes.io/enforce: baseline
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: restricted
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
}

# --- prod-security-vault ---
resource "kubectl_manifest" "psa_prod_vault" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: prod-security-vault
      labels:
        pod-security.kubernetes.io/enforce: baseline
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: restricted
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
}

# --- prod-security-externalsecrets ---
resource "kubectl_manifest" "psa_prod_eso" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: prod-security-externalsecrets
      labels:
        pod-security.kubernetes.io/enforce: baseline
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: restricted
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
}

# --- prod-data-infrastructure ---
resource "kubectl_manifest" "psa_prod_data_infra" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: prod-data-infrastructure
      labels:
        pod-security.kubernetes.io/enforce: baseline
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: restricted
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
  force_conflicts   = true
}

# --- prod-data-rabbitmq ---
resource "kubectl_manifest" "psa_prod_rabbitmq" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: prod-data-rabbitmq
      labels:
        pod-security.kubernetes.io/enforce: baseline
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: restricted
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
}

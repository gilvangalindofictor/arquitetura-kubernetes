# =============================================================================
# GAP-CONF-009 (P1): Pod Security Admission (PSA) Labels — STAGING
# Data: 2026-03-26 | Security & Resilience Specialist
# =============================================================================
#
# Aplica labels PSA nos namespaces de workload:
#   - pod-security.kubernetes.io/enforce=baseline   (bloqueia pods que violam baseline)
#   - pod-security.kubernetes.io/warn=restricted     (avisa quando pods violam restricted)
#
# Namespaces system/linkerd: MANTIDOS como privileged (necessitam hostNetwork, etc.)
# Referência: https://kubernetes.io/docs/concepts/security/pod-security-standards/
#
# Usa kubectl_manifest com server_side_apply=true para merge labels sem conflito.
# =============================================================================

# --- staging-platform-argocd ---
resource "kubectl_manifest" "psa_staging_argocd" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: staging-platform-argocd
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

# --- staging-platform-gitlab ---
resource "kubectl_manifest" "psa_staging_gitlab" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: staging-platform-gitlab
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

# --- staging-platform-keycloak ---
resource "kubectl_manifest" "psa_staging_keycloak" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: staging-platform-keycloak
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

# --- staging-platform-sonarqube ---
resource "kubectl_manifest" "psa_staging_sonarqube" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: staging-platform-sonarqube
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

# --- staging-platform-backstage ---
resource "kubectl_manifest" "psa_staging_backstage" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: staging-platform-backstage
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

# --- harbor-system ---
resource "kubectl_manifest" "psa_harbor_system" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: harbor-system
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

# --- staging-observability-monitoring ---
resource "kubectl_manifest" "psa_staging_monitoring" {
  # Promtail DaemonSet requires hostPath volumes for log collection,
  # which is only allowed under "privileged" PSA level.
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: staging-observability-monitoring
      labels:
        pod-security.kubernetes.io/enforce: privileged
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: baseline
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
  force_conflicts   = true
}

# --- staging-security-vault ---
resource "kubectl_manifest" "psa_staging_vault" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: staging-security-vault
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

# --- staging-data-hatch-etl ---
resource "kubectl_manifest" "psa_staging_hatch_etl" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: staging-data-hatch-etl
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

# --- staging-data-vemsoft-etl ---
resource "kubectl_manifest" "psa_staging_vemsoft_etl" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: staging-data-vemsoft-etl
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

# --- staging-data-infrastructure ---
resource "kubectl_manifest" "psa_staging_data_infra" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: staging-data-infrastructure
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

# --- external-secrets-system (ESO controller — needs baseline, not privileged) ---
resource "kubectl_manifest" "psa_eso_system" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: external-secrets-system
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

# =============================================================================
# System/Linkerd namespaces: PRIVILEGED (hostNetwork, hostPID, etc.)
# These namespaces are NOT enforced at baseline — they need privileged access.
# =============================================================================

# --- kube-system (system components — privileged) ---
resource "kubectl_manifest" "psa_kube_system" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: kube-system
      labels:
        pod-security.kubernetes.io/enforce: privileged
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: baseline
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
  force_conflicts   = true
}

# --- linkerd (control plane — privileged) ---
resource "kubectl_manifest" "psa_linkerd" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: linkerd
      labels:
        pod-security.kubernetes.io/enforce: privileged
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: baseline
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
  force_conflicts   = true
}

# --- linkerd-viz (dashboards — privileged for proxy) ---
resource "kubectl_manifest" "psa_linkerd_viz" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: linkerd-viz
      labels:
        pod-security.kubernetes.io/enforce: privileged
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: baseline
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
  force_conflicts   = true
}

# --- linkerd-cni (CNI plugin — privileged) ---
resource "kubectl_manifest" "psa_linkerd_cni" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: linkerd-cni
      labels:
        pod-security.kubernetes.io/enforce: privileged
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: baseline
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
  force_conflicts   = true
}

# --- ingress-nginx (needs hostNetwork — privileged) ---
resource "kubectl_manifest" "psa_ingress_nginx" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: ingress-nginx
      labels:
        pod-security.kubernetes.io/enforce: privileged
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: baseline
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
  force_conflicts   = true
}

# --- calico-system (CNI — privileged) ---
resource "kubectl_manifest" "psa_calico_system" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Namespace
    metadata:
      name: calico-system
      labels:
        pod-security.kubernetes.io/enforce: privileged
        pod-security.kubernetes.io/enforce-version: latest
        pod-security.kubernetes.io/warn: baseline
        pod-security.kubernetes.io/warn-version: latest
  YAML

  force_new         = false
  server_side_apply = true
  force_conflicts   = true
}

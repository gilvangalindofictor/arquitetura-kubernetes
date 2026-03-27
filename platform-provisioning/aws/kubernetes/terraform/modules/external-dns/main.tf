# -----------------------------------------------------------------------------
# External DNS Module
# Fase 5: Automatic DNS record management for Kubernetes services/ingresses
#
# Architecture:
#   1. IRSA (iam.tf): IAM role with Route53 permissions bound to K8s ServiceAccount
#   2. Namespace: dedicated namespace for external-dns workload
#   3. Helm release: kubernetes-sigs/external-dns chart (CNCF official) with IRSA annotation
#   4. Ownership: TXT records with txtOwnerId to prevent cross-cluster conflicts
#
# Chart: https://kubernetes-sigs.github.io/external-dns/ (replaces Bitnami — GAP-EXTERNALDNS-IMAGE-01)
# Image: registry.k8s.io/external-dns/external-dns:v0.15.0
#   Pulled via ECR pull-through cache (prefix "k8s" -> registry.k8s.io):
#   891377105802.dkr.ecr.us-east-1.amazonaws.com/k8s/external-dns/external-dns:v0.15.0
#
# DNS records are created/updated/deleted automatically when:
#   - Service type=LoadBalancer with external-dns.alpha.kubernetes.io/hostname annotation
#   - Ingress with host rules matching domain_filters
# -----------------------------------------------------------------------------

# --- Kubernetes Namespace ---
resource "kubernetes_namespace" "external_dns" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "external-dns"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "dns-automation"
      environment                    = var.environment
      domain                         = "platform"
    }
  }

  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }
}

# --- Helm Release: External DNS (kubernetes-sigs official chart) ---
# GAP-EXTERNALDNS-IMAGE-01: Substituido chart Bitnami por chart CNCF oficial (kubernetes-sigs).
# Imagem oficial registry.k8s.io/external-dns/external-dns:v0.15.0 via ECR pull-through cache k8s.
# Chart v1.15.0 (app v0.15.0) — schema diferente do Bitnami: provider.name em vez de provider,
# region via env var AWS_DEFAULT_REGION em vez de aws.region.
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = var.chart_version
  namespace  = var.namespace

  timeout = 300
  wait    = true

  # Ensure namespace exists before deploying
  depends_on = [kubernetes_namespace.external_dns]

  values = [<<-YAML
    # Unique name per environment to avoid ClusterRole name collisions
    # (ClusterRole/ClusterRoleBinding are cluster-scoped, not namespace-scoped)
    fullnameOverride: external-dns-${var.environment}

    # AWS Route53 provider (kubernetes-sigs chart v1.13.0+ uses provider.name)
    provider:
      name: aws

    # AWS region via environment variable (standard for IRSA / pod identity)
    env:
      - name: AWS_DEFAULT_REGION
        value: us-east-1
      - name: AWS_REGION
        value: us-east-1

    # Domain filters — only manage records for these domains
    domainFilters:
      ${indent(6, join("\n", [for d in var.domain_filters : "- ${d}"]))}

    # Zone ID filters — restrict to specific hosted zones
    # NOTE: kubernetes-sigs chart does NOT have zoneIdFilters value; use extraArgs instead
    extraArgs:
      ${indent(6, join("\n", [for z in var.hosted_zone_ids : "- --zone-id-filter=${z}"]))}

    # Record management policy
    policy: ${var.policy}

    # TXT ownership records (prevent cross-cluster DNS conflicts)
    registry: ${var.registry}
    txtOwnerId: ${var.cluster_name}-${var.environment}
    txtPrefix: ${var.txt_prefix}

    # Polling interval
    interval: ${var.interval}

    # Logging
    logLevel: ${var.log_level}
    logFormat: json

    # Sources: watch Services and Ingresses for DNS annotations
    sources:
      - service
      - ingress

    # IRSA: ServiceAccount with IAM role annotation
    serviceAccount:
      create: true
      name: ${var.service_account_name}
      annotations:
        eks.amazonaws.com/role-arn: ${aws_iam_role.external_dns.arn}

    # ADR-048: Labels obrigatorias em todos os recursos K8s (Kyverno policy)
    # commonLabels: applied to Deployment, Service, ServiceAccount metadata
    # podLabels: applied to Pod template (required — kubernetes-sigs chart does NOT
    #   propagate commonLabels to pod templates, unlike Bitnami chart)
    commonLabels:
      domain: platform
      owner: platform-team
      environment: ${var.environment}
      app.kubernetes.io/name: external-dns
      app.kubernetes.io/part-of: dns-automation
      app.kubernetes.io/managed-by: terraform

    # Pod-level labels (Kyverno require-corporate-labels validates Pod labels)
    podLabels:
      domain: platform
      owner: platform-team
      environment: ${var.environment}
      app.kubernetes.io/name: external-dns
      app.kubernetes.io/part-of: dns-automation
      app.kubernetes.io/managed-by: terraform

    # Resource limits (conservative for DNS controller)
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
      limits:
        cpu: 200m
        memory: 128Mi

    # ServiceMonitor for Prometheus scraping (kubernetes-sigs chart: top-level, not under metrics)
    serviceMonitor:
      enabled: true
      namespace: ${var.namespace}

    # Image: registry.k8s.io/external-dns/external-dns:v0.15.0
    # Pulled via ECR pull-through cache "k8s" -> registry.k8s.io (criado 2026-03-19)
    # 891377105802.dkr.ecr.us-east-1.amazonaws.com/k8s/external-dns/external-dns:v0.15.0
    # NOTE: kubernetes-sigs chart uses image.repository as FULL path (registry/repo),
    #       unlike Bitnami which separates registry and repository fields.
    image:
      repository: ${var.image_registry}/${var.image_repository}
      tag: ${var.image_tag}
  YAML
  ]
}

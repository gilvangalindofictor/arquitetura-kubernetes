# External Secrets Operator Helm Chart Values
# Terraform-managed configuration

installCRDs: true

replicaCount: ${replicas}

# Corporate labels required by Kyverno ADR-048 policy
commonLabels:
  app.kubernetes.io/part-of: external-secrets
  domain: platform
  owner: platform-team
  environment: ${environment}

image:
  # Uses ghcr.io directly — ECR pull-through cache for GHCR requires GitHub PAT
  # which is not configured. GHCR is public and has no rate-limit issues.
  repository: "ghcr.io/external-secrets/external-secrets"
  pullPolicy: IfNotPresent
  tag: v0.9.11

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

serviceAccount:
  create: true
  name: "external-secrets"
  annotations: {}

securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000

podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000

# D59 (2026-03-27): System node scheduling — shared services must survive FinOps shutdown
%{~ if length(node_selector) > 0 ~}
nodeSelector:
  %{~ for k, v in node_selector ~}
  ${k}: "${v}"
  %{~ endfor ~}
%{~ endif ~}
%{~ if length(system_tolerations) > 0 ~}
tolerations:
  %{~ for t in system_tolerations ~}
  - key: "${t.key}"
    operator: "${t.operator}"
    value: "${t.value}"
    effect: "${t.effect}"
  %{~ endfor ~}
%{~ endif ~}

# ServiceMonitor for Prometheus
%{ if enable_monitoring }
serviceMonitor:
  enabled: true
  namespace: ${monitoring_namespace}
  interval: 30s
  scrapeTimeout: 10s
  labels:
    release: kube-prometheus-stack
%{ endif }

# Webhook configuration
webhook:
  create: true
  port: 9443
  replicaCount: ${replicas}
  %{~ if length(node_selector) > 0 ~}
  nodeSelector:
    %{~ for k, v in node_selector ~}
    ${k}: "${v}"
    %{~ endfor ~}
  %{~ endif ~}
  %{~ if length(system_tolerations) > 0 ~}
  tolerations:
    %{~ for t in system_tolerations ~}
    - key: "${t.key}"
      operator: "${t.operator}"
      value: "${t.value}"
      effect: "${t.effect}"
    %{~ endfor ~}
  %{~ endif ~}

  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi

# Cert Controller
certController:
  create: true
  replicaCount: ${replicas}
  %{~ if length(node_selector) > 0 ~}
  nodeSelector:
    %{~ for k, v in node_selector ~}
    ${k}: "${v}"
    %{~ endfor ~}
  %{~ endif ~}
  %{~ if length(system_tolerations) > 0 ~}
  tolerations:
    %{~ for t in system_tolerations ~}
    - key: "${t.key}"
      operator: "${t.operator}"
      value: "${t.value}"
      effect: "${t.effect}"
    %{~ endfor ~}
  %{~ endif ~}

  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi

# Logging
logging:
  level: info
  format: json

# RBAC
rbac:
  create: true

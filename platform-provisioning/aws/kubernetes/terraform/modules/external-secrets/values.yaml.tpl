# External Secrets Operator Helm Chart Values
# Terraform-managed configuration

installCRDs: true

replicaCount: ${replicas}

image:
  repository: ghcr.io/external-secrets/external-secrets
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

# ServiceMonitor for Prometheus
%{ if enable_monitoring }
serviceMonitor:
  enabled: true
  namespace: monitoring
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

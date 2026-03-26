# Vault Helm Chart Values
# Terraform-managed configuration

global:
  enabled: true
  tlsDisable: true # Staging: HTTP internal (Linkerd mTLS)

injector:
  enabled: ${injector_enabled}
  replicas: 1

  # ADR-048: Corporate labels obrigatórias — compliance Kyverno ENFORCE mode
  podLabels:
    app.kubernetes.io/part-of: k8s-platform
    domain: platform
    environment: ${environment}
    owner: platform-team

  resources:
    requests:
      memory: 256Mi
      cpu: 250m
    limits:
      memory: 512Mi
      cpu: 500m

server:
  enabled: true
  image:
    repository: "${ecr_registry != "" ? "${ecr_registry}/docker-hub/hashicorp/vault" : "hashicorp/vault"}"
    tag: "1.15.4"
    pullPolicy: IfNotPresent

  # ADR-048: Corporate labels obrigatórias — compliance Kyverno ENFORCE mode
  # Fix: 2026-03-04 — labels propagadas para pods Vault
  # NOTA: Vault restart manual necessário para activar (evitar sealed state)
  podLabels:
    app.kubernetes.io/part-of: k8s-platform
    domain: platform
    environment: ${environment}
    owner: platform-team

  resources:
    requests:
      memory: 512Mi
      cpu: 500m
    limits:
      memory: 1Gi
      cpu: 1000m

  # IRSA ServiceAccount
  serviceAccount:
    create: false
    name: ${service_account}

  # HA mode with Raft storage (always true: Raft single-node or multi-node)
  # NOTE: ha.enabled MUST be true even for replicas=1 — required for Raft storage + KMS auto-unseal
  ha:
    enabled: true
    replicas: ${replicas}

    raft:
      enabled: true
      setNodeId: true

      config: |
        ui = true

        listener "tcp" {
          tls_disable = 1
          address = "[::]:8200"
          cluster_address = "[::]:8201"
        }

        storage "raft" {
          path = "/vault/data"

%{ if replicas > 1 }
%{ for i in range(replicas) ~}
          retry_join {
            leader_api_addr = "http://${helm_release_name}-${i}.${helm_release_name}-internal:8200"
          }
%{ endfor ~}
%{ else }
          # Single-node: no retry_join to avoid invalid cluster addresses
%{ endif }
        }

        seal "awskms" {
          region     = "${aws_region}"
          kms_key_id = "${kms_key_id}"
        }

        service_registration "kubernetes" {}

        # Fix 2026-03-12: enable unauthenticated metrics access so Prometheus can
        # scrape /v1/sys/metrics without a Vault token — avoids VaultDown false positive
        telemetry {
          prometheus_retention_time = "30s"
          disable_hostname = true
          unauthenticated_metrics_access = true
        }

  # Persistence
  dataStorage:
    enabled: true
    size: ${pvc_size}
    storageClass: ${storage_class}
    accessMode: ReadWriteOnce

  auditStorage:
    enabled: true
    size: 5Gi
    storageClass: ${storage_class}
    accessMode: ReadWriteOnce

  # Service
  service:
    enabled: true
    type: ClusterIP
    port: 8200
    targetPort: 8200

  # Ingress (ALB)
  %{ if ingress_enabled }
  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80},{"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: "443"
      alb.ingress.kubernetes.io/healthcheck-path: /v1/sys/health?standbyok=true&sealedcode=204&uninitcode=204
      alb.ingress.kubernetes.io/success-codes: "200,204"
      %{ if ingress_group_name != "" }alb.ingress.kubernetes.io/group.name: ${ingress_group_name}%{ endif }
      %{ if length(ingress_certificate_arns) > 0 }alb.ingress.kubernetes.io/certificate-arn: ${join(",", ingress_certificate_arns)}%{ endif }
    hosts:
      - host: ${ingress_host}
        paths:
          - /
%{ for extra_host in ingress_extra_hosts ~}
      - host: ${extra_host}
        paths:
          - /
%{ endfor ~}
  %{ endif }

  # Readiness/Liveness probes
  readinessProbe:
    enabled: true
    path: "/v1/sys/health?standbyok=true&sealedcode=204&uninitcode=204"

  livenessProbe:
    enabled: true
    path: "/v1/sys/health?standbyok=true&uninitcode=200&sealedcode=200"
    initialDelaySeconds: 120
    periodSeconds: 30
    failureThreshold: 10

  # Security context
  securityContext:
    runAsNonRoot: true
    runAsUser: 100
    fsGroup: 1000

  # Tolerations
  %{ if length(tolerations) > 0 }
  tolerations:
  %{ for t in tolerations }
    - key: ${t.key}
      operator: ${t.operator}
      %{ if t.value != null }value: ${t.value}%{ endif }
      effect: ${t.effect}
  %{ endfor }
  %{ endif }

  # Node Selector — GAP-SCHED-002: pin vault-prod pods to workload nodes
  %{ if length(node_selector) > 0 }
  nodeSelector:
  %{ for k, v in node_selector }
    ${k}: ${v}
  %{ endfor }
  %{ endif }

  # Annotations for monitoring
  %{ if enable_monitoring }
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8200"
    prometheus.io/path: "/v1/sys/metrics"
  %{ endif }

ui:
  enabled: true
  serviceType: ClusterIP

# Prometheus ServiceMonitor
%{ if enable_monitoring }
serverTelemetry:
  serviceMonitor:
    enabled: true
    namespace: monitoring
    selectors:
      release: kube-prometheus-stack
%{ endif }

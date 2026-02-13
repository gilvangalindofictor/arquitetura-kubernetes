# Vault Helm Chart Values
# Terraform-managed configuration

global:
  enabled: true
  tlsDisable: true # Staging: HTTP internal (Linkerd mTLS)

injector:
  enabled: true
  replicas: 1

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
    repository: "hashicorp/vault"
    tag: "1.15.4"
    pullPolicy: IfNotPresent

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

  # HA mode with Raft storage
  ha:
    enabled: ${replicas > 1 ? "true" : "false"}
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

          retry_join {
            leader_api_addr = "http://vault-0.vault-internal:8200"
          }
          retry_join {
            leader_api_addr = "http://vault-1.vault-internal:8200"
          }
          retry_join {
            leader_api_addr = "http://vault-2.vault-internal:8200"
          }
        }

        seal "awskms" {
          region     = "${aws_region}"
          kms_key_id = "${kms_key_id}"
        }

        service_registration "kubernetes" {}

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
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
      alb.ingress.kubernetes.io/healthcheck-path: /v1/sys/health?standbyok=true&sealedcode=204&uninitcode=204
      alb.ingress.kubernetes.io/success-codes: "200,204"
      %{ if ingress_group_name != "" }alb.ingress.kubernetes.io/group.name: ${ingress_group_name}%{ endif }
    hosts:
      - host: ${ingress_host}
        paths:
          - /
  %{ endif }

  # Readiness/Liveness probes
  readinessProbe:
    enabled: true
    path: "/v1/sys/health?standbyok=true&sealedcode=204&uninitcode=204"

  livenessProbe:
    enabled: true
    path: "/v1/sys/health?standbyok=true"
    initialDelaySeconds: 60

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

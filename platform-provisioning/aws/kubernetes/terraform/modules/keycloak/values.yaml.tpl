# -----------------------------------------------------------------------------
# Keycloak Helm Chart Values (KeycloakX 7.1.7 - Keycloak 26.5.1 Quarkus)
# Migration: WildFly 17.x → Quarkus 26.x
# Chart: codecentric/keycloakx (avoid Bitnami $72k/yr Tanzu license)
# -----------------------------------------------------------------------------

# ECR Pull-Through Cache: override default image from quay.io/keycloak/keycloak
%{ if ecr_registry != "" }
image:
  repository: ${ecr_registry}/quay/keycloak/keycloak
%{ endif }

# Replica count (HA enabled)
replicas: ${replicas}

# ADR-048: Corporate labels obrigatórias — compliance Kyverno ENFORCE mode
# Fix: 2026-03-04 — labels propagadas para pods via podLabels
podLabels:
  app.kubernetes.io/part-of: k8s-platform
  domain: platform
  environment: ${environment}
  owner: platform-team

# FIX (2026-03-09): skip-outbound-ports=5432 para que wait-for-db (init container) possa
# conectar ao PostgreSQL antes do Linkerd proxy estar ativo.
# Root cause dos 646 restarts: wait-for-db bloqueado por iptables Linkerd sem esta annotation.
podAnnotations:
  config.linkerd.io/skip-outbound-ports: "5432"

# Quarkus runtime arguments
# NOTE (2026-03-09): --optimized NÃO pode ser usado com imagem vanilla quay.io/keycloak/keycloak.
# Requer imagem customizada com `RUN kc.sh build` no Dockerfile.
# Com imagem vanilla, Keycloak faz augmentation (~39s) a cada restart — normal e esperado.
# O startupProbe window (170s) cobre o augmentation com margem de 4x.
command:
  - "/opt/keycloak/bin/kc.sh"
  - "start"
  - "--http-relative-path=/auth"  # Backward compatibility OIDC clients
  - "--health-enabled=true"       # Enable smallrye-health (required for probes)

# Wait for PostgreSQL before starting Keycloak (FinOps startup race condition)
extraInitContainers: |
  - name: wait-for-db
    image: ${ecr_registry != "" ? "${ecr_registry}/docker-hub/library/busybox:1.36" : "busybox:1.36"}
    command:
      - sh
      - -c
      - |
        echo "Waiting for PostgreSQL..."
        until nc -z ${postgresql_host} ${postgresql_port}; do
          echo "DB not ready, retrying in 5s..."
          sleep 5
        done
        echo "DB is ready!"
    resources:
      requests:
        cpu: 10m
        memory: 16Mi
      limits:
        cpu: 50m
        memory: 32Mi

# Keycloak admin credentials (Quarkus format)
# V-006 REMEDIATED: Admin password moved to Vault + ESO (2026-02-24)
# ExternalSecret: keycloak-admin-credentials (keycloak/main.tf)
# Vault path: secret/keycloak/admin
extraEnv: |
  - name: KEYCLOAK_ADMIN
    valueFrom:
      secretKeyRef:
        name: keycloak-admin-credentials
        key: username
  - name: KEYCLOAK_ADMIN_PASSWORD
    valueFrom:
      secretKeyRef:
        name: keycloak-admin-credentials
        key: password
  - name: KC_DB
    value: postgres
  - name: KC_DB_URL_HOST
    valueFrom:
      secretKeyRef:
        name: keycloak-postgresql-credentials
        key: host
  - name: KC_DB_URL_PORT
    valueFrom:
      secretKeyRef:
        name: keycloak-postgresql-credentials
        key: port
  - name: KC_DB_URL_DATABASE
    valueFrom:
      secretKeyRef:
        name: keycloak-postgresql-credentials
        key: database
  - name: KC_DB_USERNAME
    valueFrom:
      secretKeyRef:
        name: keycloak-postgresql-credentials
        key: username
  - name: KC_DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: keycloak-postgresql-credentials
        key: password
  - name: KC_DB_URL_PROPERTIES
    value: "?sslmode=require"
  - name: KC_PROXY
    value: "edge"
  - name: KC_HTTP_ENABLED
    value: "true"
  - name: KC_HOSTNAME_STRICT
    value: "false"
  - name: KC_LOG_LEVEL
    value: "INFO"
  - name: KC_HTTP_MANAGEMENT_HEALTH_ENABLED
    value: "false"  # Expose health on main HTTP port 8080 (mgmt port 9000 auto-disabled)
  # S6-A (2026-03-12): KC_HOSTNAME fix — issuer deve ser URL externa (HTTPS) para browser.
  # KC_HOSTNAME_BACKCHANNEL_DYNAMIC=true: backend usa URL interna svc.cluster.local;
  # browser recebe issuer https://keycloak.staging.internal (ALB internet-facing porta 80 → HTTPS).
  - name: KC_HOSTNAME
    value: "https://${keycloak_hostname}"
  - name: KC_HOSTNAME_BACKCHANNEL_DYNAMIC
    value: "true"

# HTTP configuration
http:
  relativePath: "/auth"  # Chart-level backward compatibility

# Disable internal PostgreSQL
postgresql:
  enabled: false

# Startup probe (Quarkus health endpoints + DB migration margin)
# Health endpoints exposed on HTTP port 8080 (KC_HTTP_MANAGEMENT_HEALTH_ENABLED=false)
# Paths: /auth/health/ready, /auth/health/live (inherit http-relative-path prefix)
# Requires: --health-enabled=true in command args
#
# FIX (2026-03-09): Window ajustado para 170s (vs 330s anterior).
# Fluxo: augmentation (~39s) + startup JVM (~21s) = ~60s total observado.
# Window: initialDelaySeconds=20 + (5s * 30) = 170s (margem 2.8x sobre 60s observado).
# Root cause dos 646 restarts: wait-for-db bloqueado por Linkerd CNI sem skip-outbound-ports.
# Fix: annotation config.linkerd.io/skip-outbound-ports=5432 no pod (via podAnnotations).
startupProbe: |
  httpGet:
    path: /auth/health/ready
    port: 8080
  initialDelaySeconds: 20
  periodSeconds: 5
  timeoutSeconds: 5
  failureThreshold: 30

# Liveness probe (startupProbe gates liveness, so no initialDelaySeconds needed)
livenessProbe: |
  httpGet:
    path: /auth/health/live
    port: 8080
  initialDelaySeconds: 0
  periodSeconds: 30
  timeoutSeconds: 5
  failureThreshold: 3

# Readiness probe
readinessProbe: |
  httpGet:
    path: /auth/health/ready
    port: 8080
  initialDelaySeconds: 0
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

# Resources — alinhados com consumo real observado + margem para Quarkus JVM warmup.
# FIX (2026-03-09): Cluster estava com drift (200m/681Mi) vs TF (1000m/2Gi).
# Ajustado para refletir uso real (CPU idle=4m, Memory=850Mi) com margem adequada.
# CPU request elevado para 500m para reduzir throttling durante startup JVM.
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 2Gi

# Service configuration
service:
  type: ClusterIP
  # Corporate labels for Kyverno compliance (ADR-048)
  labels:
    domain: platform
    owner: platform-team
    environment: ${environment}
    app.kubernetes.io/part-of: k8s-platform

# Tolerations (ADR-042 pattern: prefer system, fallback to critical)
tolerations:
  - key: workload
    operator: Equal
    value: critical
    effect: NoSchedule

# Pod Disruption Budget (HA protection)
podDisruptionBudget:
  enabled: true
  minAvailable: 1

# Metrics (Prometheus integration)
%{ if enable_monitoring ~}
metrics:
  enabled: true
serviceMonitor:
  enabled: true
  namespace: ${monitoring_namespace}
  labels:
    release: prometheus
%{ endif ~}

# -----------------------------------------------------------------------------
# Ingress — AWS ALB (internet-facing) com TLS terminado no ALB via ACM
# CLEANUP-S6A (2026-03-12): certificate-arn movido para variável TF `acm_certificate_arn`.
# -----------------------------------------------------------------------------
ingress:
  enabled: true
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/certificate-arn: "${acm_certificate_arn}"

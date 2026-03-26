# Harbor Helm Chart Values
# https://github.com/goharbor/harbor-helm

# ECR Pull-Through Cache: override image registry for all Harbor components
%{ if ecr_registry != "" }
global:
  imageRegistry: ${ecr_registry}/ecr-public
%{ endif }

%{ if ingress_enabled }
expose:
  type: ingress
  tls:
    enabled: false
  ingress:
    hosts:
      core: ${ingress_host}
    className: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
      alb.ingress.kubernetes.io/healthcheck-path: /api/v2.0/health
      %{ if ingress_group_name != "" }alb.ingress.kubernetes.io/group.name: ${ingress_group_name}%{ endif }

externalURL: http://${ingress_host}
%{ else }
expose:
  type: clusterIP
  tls:
    enabled: false
  clusterIP:
    name: harbor

externalURL: http://harbor-core.${namespace}.svc.cluster.local
%{ endif }

persistence:
  enabled: true
  persistentVolumeClaim:
    registry:
      storageClass: ${storage_class}
      size: 5Gi
    chartmuseum:
      storageClass: ${storage_class}
      size: 5Gi
    jobservice:
      storageClass: ${storage_class}
      size: 1Gi

imageChartStorage:
  type: s3
  s3:
    region: ${s3_region}
    bucket: ${s3_bucket}
    regionendpoint: https://s3.${s3_region}.amazonaws.com
    encrypt: true
    secure: true

# V-004 REMEDIATED: Admin password moved to Vault + ESO (2026-02-24)
# ExternalSecret: harbor-admin-credentials (harbor/main.tf)
# Vault path: secret/harbor/admin
existingSecretAdminPassword: harbor-admin-credentials
existingSecretAdminPasswordKey: HARBOR_ADMIN_PASSWORD

database:
  type: external
  external:
    host: ${postgresql_host}
    port: ${postgresql_port}
    username: ${postgresql_username}
    # V-003 REMEDIATED: PostgreSQL password moved to Vault + ESO (2026-02-24)
    # ExternalSecret: harbor-postgresql-credentials (harbor/main.tf)
    # Vault path: secret/harbor/postgresql
    existingSecret: harbor-postgresql-credentials
    coreDatabase: ${postgresql_database}
    notaryServerDatabase: notaryserver
    notarySignerDatabase: notarysigner
    sslmode: require

redis:
  type: external
  external:
    addr: ${redis_host}:${redis_port}
    # V-005 REMEDIATED: Redis password moved to Vault + ESO (2026-02-24)
    # ExternalSecret: harbor-redis-credentials (harbor/main.tf)
    # Vault path: secret/harbor/redis
    # Key must be: REDIS_PASSWORD
    existingSecret: harbor-redis-credentials

core:
  serviceAccountName: ${service_account}
  replicas: 2
  podAnnotations:
    # Linkerd: core connects to Redis:6379 and PostgreSQL:5432 — skip to avoid Linkerd interception of non-HTTP traffic
    config.linkerd.io/skip-outbound-ports: "6379,5432"
  podLabels:
    domain: platform
    # ADR-048: Kyverno label enforcement (2026-03-04)
  resources:
    requests:
      memory: 512Mi  # OOMKill fix 2026-03-04
      cpu: 100m
    limits:
      memory: 1500Mi  # OOMKill fix 2026-03-04
      cpu: 500m
  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

jobservice:
  serviceAccountName: ${service_account}
  replicas: 1  # FIXED: RWO PVC doesn't support multiple replicas (ADR-039)
  strategy:
    type: Recreate  # ADR-044: RWO PVC requires Recreate to avoid attach conflict
  # GAP-HARBOR-JOBSERVICE-LOOP (2026-03-26): jobservice crashava (138x, exit code 2) com
  # "connect: connection refused" para harbor-core durante startup. Causa raiz: harbor-core
  # em rolling update — janela onde 0 pods estavam ready. O jobservice tenta GET em
  # http://harbor-core:80/api/v2.0/internalconfig ANTES de subir o servidor HTTP,
  # portanto startupProbe/livenessProbe (delay=300s) NÃO protege este crash.
  # Harbor chart v1.18.x nao expoe initContainer configuravel para aguardar harbor-core.
  # MITIGACAO: harbor-core mantido em replicas=2 + RollingUpdate para manter >=1 pod ready.
  # ESTABILIZACAO: 2026-03-26 07:45 UTC-3 — harbor-core stable 2/2 → jobservice estavel 167min.
  podAnnotations:
    # Linkerd: jobservice connects to harbor-core:80 (HTTP) and Redis:6379 (job queue)
    # Redis (prod-data-infrastructure) is outside the mesh — skip both ports to avoid mTLS interception
    config.linkerd.io/skip-outbound-ports: "80,6379"
  podLabels:
    domain: platform
    # ADR-048: Kyverno label enforcement (2026-03-04)
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
    limits:
      memory: 768Mi  # OOMKill fix 2026-03-04
      cpu: 500m
  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

registry:
  serviceAccountName: ${service_account}
  strategy:
    type: Recreate  # ADR-044: RWO PVC requires Recreate to avoid attach conflict
  podAnnotations:
    # Linkerd: registry connects to Redis:6379 for layer cache (prod-data-infrastructure — outside mesh)
    config.linkerd.io/skip-outbound-ports: "6379"
  podLabels:
    domain: platform
    # ADR-048: Kyverno label enforcement (2026-03-04)
  registry:
    resources:
      requests:
        memory: 256Mi
        cpu: 100m
      limits:
        memory: 768Mi  # OOMKill fix 2026-03-04
        cpu: 500m
  controller:
    resources:
      requests:
        memory: 256Mi
        cpu: 100m
      limits:
        memory: 768Mi  # OOMKill fix 2026-03-04
        cpu: 500m
  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

portal:
  replicas: 2
  # Linkerd: portal is a static Nginx server (serves /index.html only) — no outbound connections
  # to external services. No skip-outbound-ports required. mTLS covers inbound traffic after injection.
  podLabels:
    domain: platform
    # ADR-048: Kyverno label enforcement (2026-03-04)
  resources:
    requests:
      memory: 128Mi
      cpu: 50m
    limits:
      memory: 256Mi
      cpu: 200m
  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

trivy:
  enabled: ${enable_trivy}
  persistence:
    enabled: true
    storageClass: ${storage_class}
    size: 5Gi
  podAnnotations:
    # Linkerd: trivy connects to Redis:6379 for scan cache, store, and job queue
    # Redis (prod-data-infrastructure) is outside the mesh — skip to avoid mTLS interception
    config.linkerd.io/skip-outbound-ports: "6379"
  podLabels:
    domain: platform
    # ADR-048: Kyverno label enforcement (2026-03-04)
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      cpu: 1
      memory: 2Gi  # OOMKill fix 2026-03-04
  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

exporter:
  podAnnotations:
    # Linkerd: exporter connects to PostgreSQL:5432 (RDS external) and Redis:6379 (prod-data-infrastructure — outside mesh)
    # harbor-core:80 is intra-cluster HTTP — will be covered by mTLS after injection (no skip needed)
    config.linkerd.io/skip-outbound-ports: "5432,6379"

metrics:
  enabled: ${enable_monitoring}
  serviceMonitor:
    enabled: ${enable_monitoring}

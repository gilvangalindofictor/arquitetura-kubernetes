# =============================================================================
# GitLab Helm Chart Values - Marco 3 Fase 2
# Chart: gitlab/gitlab 8.7.0
# Edition: ${edition}
# ADR-021: No-Domain Phase 1 Strategy (HTTP-only ALB)
# =============================================================================

global:
  # Edition (ce or ee)
  edition: ${edition}

  # Hosts configuration (ADR-021 Fase 1: no custom domain)
  hosts:
    domain: example.com  # Placeholder, will use ALB DNS
    https: ${enable_tls}

  # Ingress configuration
  ingress:
    enabled: true
    class: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/healthcheck-path: /-/health
      alb.ingress.kubernetes.io/healthcheck-protocol: HTTP
      alb.ingress.kubernetes.io/success-codes: "200"
      alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=300
      %{ if enable_tls }
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
      alb.ingress.kubernetes.io/certificate-arn: ""  # To be configured in Phase 2
      %{ else }
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
      %{ endif }

  # ServiceAccount (IRSA)
  serviceAccount:
    enabled: true
    create: false
    name: ${service_account_name}

  # PostgreSQL (external - CloudNativePG)
  psql:
    host: ${postgresql_host}
    port: ${postgresql_port}
    database: ${postgresql_database}
    username: ${postgresql_username}
    password:
      useSecret: true
      secret: ${postgresql_password_secret}
      key: password

  # Redis (external - Spotahome Redis Operator)
  redis:
    host: ${redis_host}
    port: ${redis_port}
    password:
      enabled: true
      secret: ${redis_password_secret}
      key: password

  # Object Storage (S3 with IRSA)
  appConfig:
    object_store:
      enabled: true
      proxy_download: true
      storage_options: {}
      connection:
        secret: ""  # Empty, using IRSA
        key: ""

    # LFS (Large File Storage)
    lfs:
      enabled: true
      proxy_download: true
      bucket: ${s3_uploads_bucket}
      connection:
        secret: ""
        key: ""

    # Artifacts
    artifacts:
      enabled: true
      proxy_download: true
      bucket: ${s3_artifacts_bucket}
      connection:
        secret: ""
        key: ""

    # Uploads
    uploads:
      enabled: true
      proxy_download: true
      bucket: ${s3_uploads_bucket}
      connection:
        secret: ""
        key: ""

    # Packages
    packages:
      enabled: true
      proxy_download: true
      bucket: ${s3_uploads_bucket}
      connection:
        secret: ""
        key: ""

    # External Diffs
    externalDiffs:
      enabled: false

    # Terraform State
    terraformState:
      enabled: true
      bucket: ${s3_artifacts_bucket}
      connection:
        secret: ""
        key: ""

    # CI Secure Files
    ciSecureFiles:
      enabled: true
      bucket: ${s3_artifacts_bucket}
      connection:
        secret: ""
        key: ""

    # Dependency Proxy
    dependencyProxy:
      enabled: true
      proxy_download: true
      bucket: ${s3_artifacts_bucket}
      connection:
        secret: ""
        key: ""

  # Disable internal charts (using external services)
  minio:
    enabled: false

# =============================================================================
# GitLab Components
# =============================================================================

# Disable internal PostgreSQL
postgresql:
  install: false

# Disable internal Redis
redis:
  install: false

# GitLab Shell (SSH for Git over SSH)
gitlab-shell:
  enabled: true
  service:
    type: LoadBalancer
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
      service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing

# GitLab Webservice (main application)
gitlab:
  webservice:
    enabled: true
    replicaCount: ${replicas}

    resources:
      requests:
        cpu: 500m
        memory: 2Gi
      limits:
        cpu: 2000m
        memory: 4Gi

    workhorse:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 256Mi

    # Metrics
    metrics:
      enabled: ${enable_monitoring}
      port: 8083

  # GitLab Sidekiq (background jobs)
  sidekiq:
    enabled: true
    replicaCount: 1

    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: 1500m
        memory: 2Gi

    metrics:
      enabled: ${enable_monitoring}

  # Gitaly (Git repository storage)
  gitaly:
    enabled: true
    replicaCount: 1

    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 1000m
        memory: 1Gi

    persistence:
      enabled: true
      storageClass: gp3
      size: 50Gi

# GitLab Runner (CI/CD)
gitlab-runner:
  install: true
  replicas: ${runner_replicas}

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

  runners:
    config: |
      [[runners]]
        [runners.kubernetes]
          namespace = "gitlab"
          image = "ubuntu:22.04"
          privileged = false
          cpu_request = "100m"
          memory_request = "256Mi"
          service_cpu_request = "50m"
          service_memory_request = "128Mi"
          helper_cpu_request = "50m"
          helper_memory_request = "128Mi"
        [runners.cache]
          Type = "s3"
          Shared = true
          [runners.cache.s3]
            BucketName = "${s3_artifacts_bucket}"
            BucketLocation = "${s3_region}"

# NGINX Ingress (disabled, using ALB)
nginx-ingress:
  enabled: false

# Prometheus (metrics)
prometheus:
  install: false  # Using existing kube-prometheus-stack

# Grafana (dashboards)
grafana:
  enabled: false  # Using existing Grafana instance

# =============================================================================
# Certmanager (ADR-021 Fase 1: disabled)
# =============================================================================
certmanager:
  install: false

# =============================================================================
# Shared Secrets (root password)
# =============================================================================
shared-secrets:
  enabled: true
  rbac:
    create: true

  selfsign:
    enabled: false  # ADR-021 Fase 1: no TLS

  env: production

  # Root password secret (pre-created by Terraform)
  secret:
    initialRootPassword:
      secret: ${root_password_secret}
      key: password

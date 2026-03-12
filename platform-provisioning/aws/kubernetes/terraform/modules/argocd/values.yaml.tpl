# ArgoCD Helm Chart Values
# Terraform-managed configuration
# Secrets: ESO ExternalSecrets (Vault KV v2) — V-002 remediation

global:
  domain: ${domain}

  # ADR-048: Corporate labels obrigatórias — compliance Kyverno ENFORCE mode
  # Fix: 2026-03-04 — labels propagadas para todos os pods via podLabels
  podLabels:
    app.kubernetes.io/part-of: k8s-platform
    domain: platform
    environment: staging
    owner: platform-team

# External PostgreSQL Configuration
configs:
  secret:
    # Database password from ESO-managed K8s secret (argocd-postgresql-credentials)
    postgresPassword: $${argocd-postgresql-credentials:password}

  params:
    # Use external PostgreSQL
    "server.insecure": "true"  # For internal cluster access

    # -------------------------------------------------------------------------
    # Repo-server timeout tuning — fixes "authentication handshake failed:
    # context deadline exceeded" on GitLab when the default 60s is too short.
    # Root cause: TLS handshake + Git clone on large repos exceeds default timeout.
    # ADR: increased to 300s (5 min) to cover slow GitLab responses under load.
    # -------------------------------------------------------------------------
    "server.repo.server.timeout.seconds": "300"
    "reposerver.parallelism.limit": "10"

  cm:
    # Increase timeout for repo operations (Git fetch/clone/diff)
    # Default: 60s — insufficient when GitLab is under load or repo is large.
    timeout.reconciliation: 300s
    exec.timeout: 300s

server:
  replicas: ${replicas}

  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

  # External Database Configuration (ESO-managed secret: argocd-postgresql-credentials)
  envFrom:
    - secretRef:
        name: argocd-postgresql-credentials

  env:
    - name: ARGOCD_SERVER_POSTGRESQL_HOST
      valueFrom:
        secretKeyRef:
          name: argocd-postgresql-credentials
          key: host
    - name: ARGOCD_SERVER_POSTGRESQL_DATABASE
      valueFrom:
        secretKeyRef:
          name: argocd-postgresql-credentials
          key: database
    - name: ARGOCD_SERVER_POSTGRESQL_USERNAME
      valueFrom:
        secretKeyRef:
          name: argocd-postgresql-credentials
          key: username
    - name: ARGOCD_SERVER_POSTGRESQL_PASSWORD
      valueFrom:
        secretKeyRef:
          name: argocd-postgresql-credentials
          key: password

  config:
    url: http://${domain}

    # Keycloak OIDC — client_secret via ESO (Vault: secret/argocd/oidc)
    # ArgoCD syntax: $<secret-name>:<key> resolves from K8s Secret in argocd namespace
    oidc.config: |
      name: Keycloak
      issuer: ${keycloak_url}/realms/platform
      clientID: ${keycloak_client}
      clientSecret: $argocd-oidc-credentials:client_secret
      requestedScopes: ["openid", "profile", "email"]

  rbacConfig:
    policy.default: role:readonly
    policy.csv: |
      # Admin group from Keycloak
      g, argocd-admins, role:admin

      # No secret enumeration (security)
      p, role:readonly, repositories, get, */*, deny
      p, role:readonly, certificates, get, *, deny
      p, role:readonly, accounts, get, *, deny

  metrics:
    enabled: ${enable_monitoring}
    serviceMonitor:
      enabled: ${enable_monitoring}

  ingress:
    enabled: ${ingress_enabled}
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
      %{ if ingress_group_name != "" }alb.ingress.kubernetes.io/group.name: ${ingress_group_name}%{ endif }
    hosts:
      - ${domain}

repoServer:
  replicas: ${replicas}

  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

  # -------------------------------------------------------------------------
  # Repo-server env vars — fix "authentication handshake failed: context
  # deadline exceeded" for backstage + staging-platform-new-service apps.
  # Root cause: default Git timeout (60s) exceeded when GitLab is under load
  # or SSH/TLS handshake is slow. These env vars override ArgoCD defaults.
  # -------------------------------------------------------------------------
  env:
    - name: ARGOCD_GIT_ATTEMPTS_COUNT
      value: "5"
    - name: ARGOCD_GIT_REQUEST_TIMEOUT
      value: "300"

  metrics:
    enabled: ${enable_monitoring}
    serviceMonitor:
      enabled: ${enable_monitoring}

controller:
  replicas: 1  # Single controller (leader election)

  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

  metrics:
    enabled: ${enable_monitoring}
    serviceMonitor:
      enabled: ${enable_monitoring}

dex:
  enabled: false  # Using Keycloak OIDC instead

redis:
  enabled: true

  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

applicationSet:
  enabled: true
  replicas: ${replicas}

  tolerations:
    - key: node-type
      operator: Equal
      value: system
      effect: NoSchedule
    - key: workload
      operator: Equal
      value: critical
      effect: NoSchedule

notifications:
  enabled: false  # TODO: Enable with Slack/email

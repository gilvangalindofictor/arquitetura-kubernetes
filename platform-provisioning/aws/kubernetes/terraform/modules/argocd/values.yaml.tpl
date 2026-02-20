# ArgoCD Helm Chart Values
# Terraform-managed configuration
# Secrets: ESO ExternalSecrets (Vault KV v2) — V-002 remediation

global:
  domain: ${domain}

# External PostgreSQL Configuration
configs:
  secret:
    # Database password from ESO-managed K8s secret (argocd-postgresql-credentials)
    postgresPassword: $${argocd-postgresql-credentials:password}

  params:
    # Use external PostgreSQL
    "server.insecure": "true"  # For internal cluster access

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

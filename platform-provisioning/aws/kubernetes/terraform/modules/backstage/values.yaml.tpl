# =============================================================================
# Backstage IDP Helm values — gerado pelo módulo Terraform
# Chart: backstage/backstage v${backstage_chart_version}
# Cluster: ${cluster_name}
# Namespace: ${namespace}
# ADR: ADR-055
# =============================================================================

backstage:
  image:
    registry: ${image_registry}
    repository: platform/backstage
    tag: "${image_tag}"
    pullPolicy: IfNotPresent

  # ---------------------------------------------------------------------------
  # app-config.yaml injetado via Helm
  # ---------------------------------------------------------------------------
  appConfig:
    app:
      baseUrl: https://backstage.staging.internal

    backend:
      baseUrl: https://backstage.staging.internal
      listen:
        port: 7007
      cors:
        origin: https://backstage.staging.internal
      database:
        client: pg
        connection:
          host: $${POSTGRES_HOST}
          port: 5432
          user: $${POSTGRES_USER}
          password: $${POSTGRES_PASSWORD}
          database: backstage
          ssl:
            require: true
            rejectUnauthorized: false

    # -------------------------------------------------------------------------
    # Autenticação — Keycloak OIDC (ADR-046)
    # CRITICO (ALTO-3): Validar metadataUrl ANTES do deploy
    # CRITICO: PKCE S256 deve estar habilitado no client Keycloak
    # -------------------------------------------------------------------------
    auth:
      session:
        secret: $${AUTH_SESSION_SECRET}
      providers:
        keycloak:
          production:
            metadataUrl: https://${keycloak_host}/realms/platform/.well-known/openid-configuration
            clientId: $${KEYCLOAK_CLIENT_ID}
            clientSecret: $${KEYCLOAK_CLIENT_SECRET}
            prompt: auto

    # -------------------------------------------------------------------------
    # Integrações de Source Control
    # CRITICO (ALTO-2): Usar Group Access Token — NÃO OAuth token (issue #30650)
    # -------------------------------------------------------------------------
    integrations:
      gitlab:
        - host: ${gitlab_host}
          token: $${GITLAB_TOKEN}

    # -------------------------------------------------------------------------
    # Catálogo — Discovery automático GitLab
    # Schedule mínimo 30min — rate limit GitLab 18.6+ (BAIXO-1)
    # -------------------------------------------------------------------------
    catalog:
      providers:
        gitlab:
          selfHosted:
            host: ${gitlab_host}
            schedule:
              frequency:
                minutes: 30
              timeout:
                minutes: 3

    # -------------------------------------------------------------------------
    # Kubernetes Plugin
    # -------------------------------------------------------------------------
    kubernetes:
      serviceLocatorMethod:
        type: multiTenant
      clusterLocatorMethods:
        - type: config
          clusters:
            - name: staging-eks
              url: $${EKS_CLUSTER_URL}
              authProvider: aws

    # -------------------------------------------------------------------------
    # Vault Plugin — read-only via Kubernetes Auth Method
    # -------------------------------------------------------------------------
    vault:
      baseUrl: $${VAULT_ADDR}
      secretEngine: secret
      kvVersion: 2

    # -------------------------------------------------------------------------
    # ArgoCD Plugin
    # -------------------------------------------------------------------------
    argocd:
      appLocatorMethods:
        - type: config
          instances:
            - name: staging
              url: $${ARGOCD_URL}
              token: $${ARGOCD_TOKEN}

    # -------------------------------------------------------------------------
    # SonarQube Plugin
    # ATENCAO: plugin @backstage-community/plugin-sonarqube (nao @backstage — DEPRECATED)
    # -------------------------------------------------------------------------
    sonarqube:
      baseUrl: $${SONARQUBE_URL}
      apiKey: $${SONARQUBE_TOKEN}

  # ---------------------------------------------------------------------------
  # Recursos do pod
  # ---------------------------------------------------------------------------
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 1536Mi

  # ---------------------------------------------------------------------------
  # Anotações do pod
  # CRITICO (ALTO-1): skip-outbound-ports 443 para Harbor + Linkerd mTLS workaround
  # Harbor pode não ter sidecar Linkerd — sem o skip, conexão falha.
  # ---------------------------------------------------------------------------
  podAnnotations:
    linkerd.io/inject: "enabled"
    config.linkerd.io/proxy-await: "enabled"
    config.linkerd.io/skip-outbound-ports: "443"

  # ---------------------------------------------------------------------------
  # Variáveis de ambiente lidas do Secret backstage-secrets (ESO → Vault)
  # ---------------------------------------------------------------------------
  extraEnvVars:
    - name: POSTGRES_HOST
      valueFrom:
        secretKeyRef:
          name: backstage-secrets
          key: postgres-host
    - name: POSTGRES_USER
      valueFrom:
        secretKeyRef:
          name: backstage-secrets
          key: postgres-user
    - name: POSTGRES_PASSWORD
      valueFrom:
        secretKeyRef:
          name: backstage-secrets
          key: postgres-password
    - name: KEYCLOAK_CLIENT_ID
      valueFrom:
        secretKeyRef:
          name: backstage-secrets
          key: keycloak-client-id
    - name: KEYCLOAK_CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: backstage-secrets
          key: keycloak-client-secret
    - name: GITLAB_TOKEN
      valueFrom:
        secretKeyRef:
          name: backstage-secrets
          key: gitlab-token
    - name: VAULT_ADDR
      valueFrom:
        secretKeyRef:
          name: backstage-secrets
          key: vault-addr
    - name: ARGOCD_URL
      valueFrom:
        secretKeyRef:
          name: backstage-secrets
          key: argocd-url
    - name: ARGOCD_TOKEN
      valueFrom:
        secretKeyRef:
          name: backstage-secrets
          key: argocd-token
    - name: SONARQUBE_URL
      valueFrom:
        secretKeyRef:
          name: backstage-secrets
          key: sonarqube-url
    - name: SONARQUBE_TOKEN
      valueFrom:
        secretKeyRef:
          name: backstage-secrets
          key: sonarqube-token
    - name: EKS_CLUSTER_URL
      valueFrom:
        secretKeyRef:
          name: backstage-secrets
          key: eks-cluster-url
    - name: AUTH_SESSION_SECRET
      valueFrom:
        secretKeyRef:
          name: backstage-secrets
          key: auth-session-secret

  # ---------------------------------------------------------------------------
  # Service Account com IRSA (AWS EKS IAM Roles for Service Accounts)
  # ---------------------------------------------------------------------------
  serviceAccount:
    create: true
    name: backstage
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::${aws_account_id}:role/backstage-irsa-role

# =============================================================================
# Ingress — ALB interno
# =============================================================================
ingress:
  enabled: true
  className: alb
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internal
    alb.ingress.kubernetes.io/target-type: ip
  host: backstage.staging.internal

# =============================================================================
# PostgreSQL — DESABILITADO (usa RDS externo existente)
# =============================================================================
postgresql:
  enabled: false

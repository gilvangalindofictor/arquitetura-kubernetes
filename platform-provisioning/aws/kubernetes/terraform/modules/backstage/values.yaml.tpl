# =============================================================================
# Backstage IDP Helm values — gerado pelo módulo Terraform
# Chart: backstage/backstage v${backstage_chart_version}
# Cluster: ${cluster_name}
# Namespace: ${namespace}
# ADR: ADR-055, ADR-102
# =============================================================================

# =============================================================================
# Labels comuns aplicados a TODOS os recursos gerados pelo Helm (ADR-048)
# Kyverno policy require-corporate-labels exige: domain, owner, environment,
# app.kubernetes.io/name, app.kubernetes.io/part-of
# =============================================================================
commonLabels:
  domain: platform
  owner: platform-team
  environment: staging
  app.kubernetes.io/name: backstage
  app.kubernetes.io/part-of: platform-core

backstage:
  # GAP-S6A-01: replicas=1 → 2 para PDB minAvailable=1 permitir disruption
  # NOTA: chart 2.6.3+ renomeou replicaCount → replicas
  replicas: 2

  # GAP-SCHED-001: route to workload nodes (t3.large) — free system nodes (t3.medium)
  # Label eks.amazonaws.com/nodegroup=workloads confirmed on workloads node group (2026-03-23)
  nodeSelector:
    eks.amazonaws.com/nodegroup: workloads

  image:
    registry: ${image_registry}
    repository: platform/backstage
    tag: "${image_tag}"
    pullPolicy: IfNotPresent

  # ---------------------------------------------------------------------------
  # Labels do pod — obrigatorias Kyverno ADR-048
  # GAP-S6A-15: app.kubernetes.io/name obrigatório pela policy require-corporate-labels
  # ---------------------------------------------------------------------------
  podLabels:
    domain: platform
    environment: staging
    owner: platform-team
    app.kubernetes.io/name: backstage
    app.kubernetes.io/part-of: platform-core

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
        methods: [GET, HEAD, PATCH, POST, PUT, DELETE]
        credentials: true
      # -----------------------------------------------------------------------
      # GAP-S6A-05: reading.allow obrigatório para GitLab self-hosted
      # Sem esta seção, o catalog reader recusa URLs do GitLab interno.
      # Inclui DNS do serviço GitLab dentro do cluster.
      # -----------------------------------------------------------------------
      reading:
        allow:
          - host: "${gitlab_host}"
          - host: "*.${gitlab_host}"
          - host: "gitlab-webservice-default.staging-platform-gitlab.svc.cluster.local"
          - host: "*.staging-platform-gitlab.svc.cluster.local"
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
        # GAP-SEC-S6-06: cookie config ausente — sem maxAge, cookie persiste indefinidamente
        # maxAge: 86400000ms = 24h (expira sessão após inatividade de 1 dia)
        # secure: true — cookie enviado APENAS em HTTPS (evita interceptação em HTTP)
        # sameSite: lax — mitiga CSRF mantendo UX de navegação entre abas
        cookie:
          maxAge: 86400000
          secure: true
          sameSite: lax
      providers:
        oidc:
          production:
            # OIDC discovery via service DNS interno (HTTP/80 funcional). Issuer externo via KC_HOSTNAME no Keycloak.
            metadataUrl: http://keycloak-keycloakx-http.staging-platform-keycloak.svc.cluster.local/auth/realms/platform/.well-known/openid-configuration
            clientId: $${KEYCLOAK_CLIENT_ID}
            clientSecret: $${KEYCLOAK_CLIENT_SECRET}
            prompt: auto
            callbackUrl: https://backstage.staging.internal/api/auth/oidc/handler/frame
            # GAP-S6A-02: 'scope' removido em Backstage 1.34+ → additionalScopes
            # 'openid' é adicionado automaticamente pelo provider
            additionalScopes: 'profile email'
            signIn:
              resolvers:
                - resolver: emailMatchingUserEntityProfileEmail

    # -------------------------------------------------------------------------
    # Integrações de Source Control
    # CRITICO (ALTO-2): Usar Group Access Token — NÃO OAuth token (issue #30650)
    # GAP-S6A-08: apiBaseUrl e baseUrl obrigatórios para hosts self-hosted (chart 2.6.3+)
    # Sem apiBaseUrl, o plugin-scaffolder-module-gitlab falha com 'undefined'
    # NOTA: ALB só serve HTTP:80 internamente — usar http:// para API calls
    # -------------------------------------------------------------------------
    integrations:
      gitlab:
        - host: ${gitlab_host}
          # GAP-S6A-08: baseUrl e apiBaseUrl obrigatórios (chart 2.6.3+)
          baseUrl: http://${gitlab_host}
          apiBaseUrl: http://${gitlab_host}/api/v4
          token: $${GITLAB_TOKEN}

    # -------------------------------------------------------------------------
    # Catálogo — Discovery automático GitLab
    # Schedule mínimo 30min — rate limit GitLab 18.6+ (BAIXO-1)
    # GAP-S6A-03: URL de catalog location usa /-/raw/main/ (não /blob/)
    # GAP-S6A-04: 'Resource' adicionado na lista de allow
    # -------------------------------------------------------------------------
    catalog:
      rules:
        - allow: [Component, System, API, Group, User, Domain, Location, Template, Resource]
      locations:
        - type: url
          # GAP-S6A-03: /-/raw/main/ entrega YAML bruto (não HTML da UI /blob/)
          target: http://${gitlab_host}/platform/backstage-catalog/-/raw/main/catalog-info.yaml
          rules:
            - allow: [Location, Domain, System, Component, API, Group, User, Template, Resource]
      providers:
        # GitLab EntityProvider — discovery automático de catalog-info.yaml
        gitlab:
          selfHosted:
            host: ${gitlab_host}
            schedule:
              frequency:
                minutes: 30
              timeout:
                minutes: 3
        # Keycloak EntityProvider — sync de Users e Groups
        # GAP-S6A-16: plugin-catalog-backend-module-keycloak
        keycloakOrg:
          default:
            baseUrl: http://${keycloak_host}/auth
            loginRealm: platform
            realm: platform
            clientId: $${KEYCLOAK_CLIENT_ID}
            clientSecret: $${KEYCLOAK_CLIENT_SECRET}
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
              skipTLSVerify: false
              skipMetricsLookup: false

    # -------------------------------------------------------------------------
    # Vault Plugin — read-only via Kubernetes Auth Method
    # -------------------------------------------------------------------------
    vault:
      baseUrl: $${VAULT_ADDR}
      secretEngine: secret
      kvVersion: 2

    # -------------------------------------------------------------------------
    # ArgoCD Plugin
    # GAP-S6A-07: waitCycles ausente — timeout em clusters com muitas apps
    # -------------------------------------------------------------------------
    argocd:
      waitCycles: 20
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

    # -------------------------------------------------------------------------
    # TechDocs — external builder (GitLab CI gera, Backstage lê do S3)
    # GAP-S6A-11: ausente no values original — sem config, usa 'local' por padrão
    # GAP-011: NUNCA usar runIn: 'local' em produção (consome recursos do pod)
    # Builder 'external' = GitLab CI gera os docs; Backstage lê do S3
    # -------------------------------------------------------------------------
    techdocs:
      builder: 'external'
      generator:
        runIn: 'external'
      publisher:
        type: 'awsS3'
        awsS3:
          bucketName: 'backstage-techdocs-${aws_account_id}-${aws_region}'
          region: '${aws_region}'
          # IRSA assume role via ServiceAccount annotations (sem credenciais estáticas)
          credentials:
            roleArn: 'arn:aws:iam::${aws_account_id}:role/backstage-irsa-role'

    # -------------------------------------------------------------------------
    # Harbor Plugin (M2 Scaffolder)
    # -------------------------------------------------------------------------
    harbor:
      baseUrl: $${HARBOR_URL}
      username: $${HARBOR_ROBOT_TOKEN}
      password: $${HARBOR_ROBOT_TOKEN}

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
  # GAP-S6A-14: inclui 5432 (RDS direto, não via mesh)
  # ---------------------------------------------------------------------------
  podAnnotations:
    linkerd.io/inject: "enabled"
    config.linkerd.io/proxy-await: "enabled"
    config.linkerd.io/skip-outbound-ports: "443,5432"

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
    - name: HARBOR_URL
      valueFrom:
        secretKeyRef:
          name: backstage-secrets
          key: harbor-url
    - name: HARBOR_ROBOT_TOKEN
      valueFrom:
        secretKeyRef:
          name: backstage-secrets
          key: harbor-robot-token
    # GAP-S6A-12: NODE_OPTIONS — sem heap limit, pod sofre OOMKill com 1536Mi
    # Com limits.memory=1536Mi, heap max = 75% = ~1100Mi
    - name: NODE_OPTIONS
      value: "--max-old-space-size=1100"
    # GAP-S6A-13: CA certificate para TLS de hosts *.staging.internal
    - name: NODE_EXTRA_CA_CERTS
      value: /etc/ssl/certs/staging-internal-ca.crt

  extraVolumes:
    - name: staging-internal-ca
      configMap:
        name: staging-internal-ca

  extraVolumeMounts:
    - name: staging-internal-ca
      mountPath: /etc/ssl/certs/staging-internal-ca.crt
      subPath: ca.crt
      readOnly: true

# =============================================================================
# Service Account com IRSA (AWS EKS IAM Roles for Service Accounts)
# NOTA: chart 2.6.3+ moveu serviceAccount para o nível raiz (fora de backstage:)
# =============================================================================
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
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
    alb.ingress.kubernetes.io/group.name: backstage-staging
    alb.ingress.kubernetes.io/healthcheck-path: /healthcheck
    alb.ingress.kubernetes.io/success-codes: "200,301,302"
  host: backstage.staging.internal
  path: /

# =============================================================================
# PostgreSQL — DESABILITADO (usa RDS externo existente)
# =============================================================================
postgresql:
  enabled: false

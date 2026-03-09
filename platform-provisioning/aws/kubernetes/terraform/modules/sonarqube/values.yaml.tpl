# SonarQube Helm Chart Values
# Terraform-managed configuration

replicaCount: ${replicas}  # Community Edition: 1 only

image:
  repository: sonarqube
  tag: 10.3.0-community
  pullPolicy: IfNotPresent

# PostgreSQL Configuration (external RDS)
postgresql:
  enabled: false  # Using external PostgreSQL

jdbcOverwrite:
  enabled: true  # Fixed: 'enable' was deprecated, chart uses 'enabled' (2026-03-09)
  jdbcUrl: "jdbc:postgresql://${postgresql_host}:${postgresql_port}/${postgresql_database}"
  jdbcUsername: sonarqube_user
  jdbcSecretName: sonarqube-postgresql
  jdbcSecretPasswordKey: postgresql-password

# Persistence
persistence:
  enabled: true
  storageClass: ${storage_class}
  size: ${pvc_size}
  accessMode: ReadWriteOnce

# Resources
# staging-rightsize 2026-03-05: reduced requests for staging scheduling (limits unchanged)
resources:
  requests:
    cpu: 200m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi

# Probes
# SRE-FIX 2026-03-09: SonarQube JVM boot on staging t3.medium takes 3-5min under load.
# Root cause: 600 restarts during cluster recovery (2026-03-07) — startupProbe window (270s)
# was insufficient. Increased failureThreshold 24→36 (total window: 30 + 36*10 = 390s = 6.5min).
# readinessProbe/livenessProbe: added explicit failureThreshold=10 (300s tolerance post-startup).
startupProbe:
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 36

livenessProbe:
  initialDelaySeconds: 120
  periodSeconds: 30
  failureThreshold: 10

readinessProbe:
  initialDelaySeconds: 120
  periodSeconds: 30
  failureThreshold: 10

# Ingress
ingress:
  enabled: ${ingress_enabled}
  ingressClassName: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP":80}]'
    alb.ingress.kubernetes.io/healthcheck-path: /api/system/status
    %{ if ingress_group_name != "" }alb.ingress.kubernetes.io/group.name: ${ingress_group_name}%{ endif }
  hosts:
    - name: ${domain}
      path: /

# Prometheus JMX Exporter
# DISABLED by default: sonarqube:10.3.0-community curl has SSL timeout (exit code 28)
# TODO: Re-enable with custom downloadURL or pre-cached image
prometheusExporter:
  enabled: ${enable_prometheus_exporter}
  config:
    rules:
      - pattern: ".*"

# ServiceMonitor (scrapes SonarQube built-in metrics — independent of JMX exporter)
serviceMonitor:
  enabled: ${enable_monitoring}

# Plugins (optional)
plugins:
  install: []
  # - https://github.com/mc1arke/sonarqube-community-branch-plugin/releases/download/1.14.0/sonarqube-community-branch-plugin-1.14.0.jar

%{ if saml_enabled || gitlab_oauth_enabled ~}
sonarProperties:
  # Server base URL (MUST be external hostname — browser redirect pattern, ADR-grafana-sso)
  sonar.core.serverBaseURL: "http://sonarqube.staging.internal"
%{ if saml_enabled ~}
  # SAML 2.0 Authentication (Keycloak)
  # https://docs.sonarsource.com/sonarqube-community-build/instance-administration/authentication/saml/overview
  sonar.auth.saml.enabled: "true"
  sonar.auth.saml.applicationId: "${saml_application_id}"
  sonar.auth.saml.providerId: "${saml_provider_id}"
  sonar.auth.saml.loginUrl: "${saml_login_url}"
  sonar.auth.saml.certificate.secured: "${saml_certificate}"
  sonar.auth.saml.user.login: "${saml_user_login_attribute}"
  sonar.auth.saml.user.email: "${saml_user_email_attribute}"
  sonar.auth.saml.user.name: "${saml_user_name_attribute}"
  sonar.auth.saml.group.name: "${saml_group_attribute}"
  sonar.auth.saml.groupsSync: "true"
  # SP certificate (public) — private key via sonarSecretProperties (K8s Secret)
  sonar.auth.saml.sp.certificate.secured: "${saml_sp_certificate}"
  # Signature: SP signs AuthnRequests + validates IdP assertions
  sonar.auth.saml.signature.enabled: "true"
%{ endif ~}
%{ if gitlab_oauth_enabled ~}
  # GitLab OAuth2 Authentication
  # https://docs.sonarsource.com/sonarqube-community-build/instance-administration/authentication/gitlab/
  # applicationId + secret injected via sonarSecretProperties (K8s Secret — ESO from Vault secret/sonarqube/gitlab)
  sonar.auth.gitlab.enabled: "true"
  sonar.auth.gitlab.url: "${gitlab_url}"
  sonar.auth.gitlab.allowUsersToSignUp: "${gitlab_allow_signup}"
  sonar.auth.gitlab.groupsSyncEnabled: "${gitlab_groups_sync}"
%{ endif ~}

# K8s Secret with additional sonar.properties injected by concat-properties init container
# Keys merged: SAML SP cert+key (secret/sonarqube/saml) + GitLab applicationId+secret (secret/sonarqube/gitlab)
# ESO ExternalSecret: sonarqube-sp-saml (ns: sonarqube)
sonarSecretProperties: "${saml_sp_secret_name}"
%{ else ~}
# Authentication: using default local users
# To enable SAML SSO: set saml_enabled = true
# To enable GitLab OAuth: set gitlab_oauth_enabled = true
%{ endif ~}

# Quality Gates
# TODO: Configure via API after deployment
# Default: "Sonar way" (built-in)

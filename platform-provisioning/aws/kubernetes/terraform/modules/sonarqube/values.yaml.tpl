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
  enable: true
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
resources:
  requests:
    cpu: 500m
    memory: 2Gi
  limits:
    cpu: 2000m
    memory: 4Gi

# Probes
startupProbe:
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 24

livenessProbe:
  initialDelaySeconds: 60
  periodSeconds: 30

readinessProbe:
  initialDelaySeconds: 60
  periodSeconds: 30

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

%{ if saml_enabled ~}
# SAML 2.0 Authentication (Keycloak)
# https://docs.sonarsource.com/sonarqube-community-build/instance-administration/authentication/saml/overview
sonarProperties:
  sonar.auth.saml.enabled: "true"
  sonar.auth.saml.applicationId: "${saml_application_id}"
  sonar.auth.saml.providerId: "${saml_provider_id}"
  sonar.auth.saml.loginUrl: "${saml_login_url}"
  sonar.auth.saml.certificate.secured: "${saml_certificate}"
  sonar.auth.saml.user.login: "${saml_user_login_attribute}"
  sonar.auth.saml.user.email: "${saml_user_email_attribute}"
  sonar.auth.saml.user.name: "${saml_user_name_attribute}"
  sonar.auth.saml.group.name: "${saml_group_attribute}"
  # Group synchronization
  sonar.auth.saml.groupsSync: "true"
  # Signature validation
  sonar.auth.saml.signature.enabled: "true"
%{ else ~}
# Authentication: using default local users
# To enable SAML SSO, set saml_enabled = true in Terraform
%{ endif ~}

# Quality Gates
# TODO: Configure via API after deployment
# Default: "Sonar way" (built-in)

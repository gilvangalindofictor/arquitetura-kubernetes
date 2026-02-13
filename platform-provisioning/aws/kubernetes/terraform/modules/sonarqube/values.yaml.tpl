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

# Monitoring
prometheusExporter:
  enabled: ${enable_monitoring}
  config:
    rules:
      - pattern: ".*"

serviceMonitor:
  enabled: ${enable_monitoring}

# Plugins (optional)
plugins:
  install: []
  # - https://github.com/mc1arke/sonarqube-community-branch-plugin/releases/download/1.14.0/sonarqube-community-branch-plugin-1.14.0.jar

# OIDC Authentication (Keycloak)
env:
  - name: SONAR_AUTH_OIDC_ENABLED
    value: "true"
  - name: SONAR_AUTH_OIDC_ISSUERURI
    value: "http://keycloak-http.keycloak.svc.cluster.local/auth/realms/platform"
  - name: SONAR_AUTH_OIDC_CLIENTID_SECURED
    value: "sonarqube"
  - name: SONAR_AUTH_OIDC_CLIENTSECRET_SECURED
    valueFrom:
      secretKeyRef:
        name: sonarqube-oidc
        key: client-secret
  - name: SONAR_AUTH_OIDC_GROUPSSYNC
    value: "true"
  - name: SONAR_AUTH_OIDC_GROUPSSYNC_CLAIMNAME
    value: "groups"

# Quality Gates
# TODO: Configure via API after deployment
# Default: "Sonar way" (built-in)

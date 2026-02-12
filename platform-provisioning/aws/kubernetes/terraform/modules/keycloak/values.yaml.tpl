# -----------------------------------------------------------------------------
# Keycloak Helm Chart Values (KeycloakX 7.1.7 - Keycloak 26.5.1 Quarkus)
# Migration: WildFly 17.x → Quarkus 26.x
# Chart: codecentric/keycloakx (avoid Bitnami $72k/yr Tanzu license)
# -----------------------------------------------------------------------------

# Replica count (HA enabled)
replicas: ${replicas}

# Quarkus runtime arguments
command:
  - "/opt/keycloak/bin/kc.sh"
  - "start"
  - "--http-relative-path=/auth"  # Backward compatibility OIDC clients

# Keycloak admin credentials (Quarkus format)
extraEnv: |
  - name: KEYCLOAK_ADMIN
    value: admin
  - name: KEYCLOAK_ADMIN_PASSWORD
    value: "${admin_password}"
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

# HTTP configuration
http:
  relativePath: "/auth"  # Chart-level backward compatibility

# Disable internal PostgreSQL
postgresql:
  enabled: false

# Startup probe (Quarkus health endpoints + DB migration margin)
# Health endpoints exposed on HTTP port 8080 (KC_HTTP_MANAGEMENT_HEALTH_ENABLED=false)
# Paths: /auth/health/ready, /auth/health/live (inherit http-relative-path prefix)
startupProbe:
  httpGet:
    path: /auth/health/ready
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 5
  timeoutSeconds: 5
  failureThreshold: 30  # 150s total (DB migration 17→26)

# Liveness probe
livenessProbe:
  httpGet:
    path: /auth/health/live
    port: 8080
  initialDelaySeconds: 60
  periodSeconds: 30
  timeoutSeconds: 5
  failureThreshold: 5

# Readiness probe
readinessProbe:
  httpGet:
    path: /auth/health/ready
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 5

# Resources (unchanged from 17.x)
resources:
  requests:
    cpu: 1000m
    memory: 2Gi
  limits:
    cpu: 2000m
    memory: 4Gi

# Service configuration
service:
  type: ClusterIP

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
  namespace: monitoring
  labels:
    release: prometheus
%{ endif ~}

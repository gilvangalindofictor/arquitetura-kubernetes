# -----------------------------------------------------------------------------
# Keycloak Helm Chart Values Template (Minimal Configuration)
# Chart: codecentric/keycloak 18.4.0
# Pattern: External PostgreSQL + Essential config only
# -----------------------------------------------------------------------------

# Replica count
replicas: ${replicas}

# Keycloak admin credentials (Keycloak 17.x format)
extraEnv: |
  - name: KEYCLOAK_USER
    value: admin
  - name: KEYCLOAK_PASSWORD
    value: "${admin_password}"
  - name: DB_VENDOR
    value: postgres
  - name: DB_ADDR
    valueFrom:
      secretKeyRef:
        name: keycloak-postgresql-credentials
        key: host
  - name: DB_PORT
    valueFrom:
      secretKeyRef:
        name: keycloak-postgresql-credentials
        key: port
  - name: DB_DATABASE
    valueFrom:
      secretKeyRef:
        name: keycloak-postgresql-credentials
        key: database
  - name: DB_USER
    valueFrom:
      secretKeyRef:
        name: keycloak-postgresql-credentials
        key: username
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: keycloak-postgresql-credentials
        key: password
  - name: PROXY_ADDRESS_FORWARDING
    value: "true"

# Disable internal PostgreSQL
postgresql:
  enabled: false

# Startup probe configuration (Keycloak slow startup ~40s)
startupProbe:
  httpGet:
    path: /auth/
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 12  # 30s + (12 * 10s) = 150s total

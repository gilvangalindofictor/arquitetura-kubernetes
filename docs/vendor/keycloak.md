# Keycloak — trechos pinados

version: 26.5.1 (Quarkus 3.27.1)
chart: codecentric/keycloakx 7.1.7
source: https://www.keycloak.org/
link: https://www.keycloak.org/docs/latest/
release_notes: https://www.keycloak.org/docs/latest/release_notes/
health_docs: https://www.keycloak.org/observability/health
mgmt_docs: https://www.keycloak.org/server/management-interface

## Trechos Críticos

### Startup Commands
- Start: `kc.sh start` (quarkus-based distributions)
- Start optimized: `kc.sh start --optimized` (skip build, 2-3x faster)
- Show config: `kc.sh show-config`
- Build: `kc.sh build` (pre-optimize configuration)

### Health Endpoints (CRÍTICO - Lição 2026-02-11)

**Behavior com `--http-relative-path`:**
- Quando `--http-relative-path=/auth` configurado, **TODOS** endpoints herdam o prefixo
- Health endpoints são **AFETADOS** por relative path (não documentado claramente)
- Exemplo: `/health/ready` torna-se `/auth/health/ready`

**Management Interface (porta 9000):**
- Auto-desabilitado quando nada exposto (KC_HEALTH_ENABLED + KC_METRICS_ENABLED ambos false)
- Para expor health na porta HTTP principal (8080), usar `KC_HTTP_MANAGEMENT_HEALTH_ENABLED=false`

**Configuração Correta (Kubernetes probes):**
```yaml
# Environment variables
KC_HTTP_MANAGEMENT_HEALTH_ENABLED: "false"  # Force health on HTTP port
KC_HTTP_RELATIVE_PATH: "/auth"              # Backward compatibility

# Probes
startupProbe:
  httpGet:
    path: /auth/health/ready  # COM prefixo /auth
    port: 8080

livenessProbe:
  httpGet:
    path: /auth/health/live   # COM prefixo /auth
    port: 8080

readinessProbe:
  httpGet:
    path: /auth/health/ready  # COM prefixo /auth
    port: 8080
```

**Validation:**
```bash
# Test health endpoint
curl http://keycloak:8080/auth/health/ready
# Expected: {"status":"UP","checks":[...]}

# Common mistakes (return 404):
curl http://keycloak:8080/health/ready        # WRONG - missing /auth
curl http://keycloak:9000/health/ready        # WRONG - port 9000 disabled
curl http://keycloak:8080/auth/health         # WRONG - missing /ready
```

### Database Configuration (PostgreSQL)

**SSL/TLS Required:**
```yaml
KC_DB: postgres
KC_DB_URL_HOST: <hostname>
KC_DB_URL_PORT: 5432
KC_DB_URL_DATABASE: keycloak
KC_DB_USERNAME: keycloak_user
KC_DB_PASSWORD: <secret>
KC_DB_URL_PROPERTIES: "?sslmode=require"  # CRITICAL for RDS
```

### Migration Path (WildFly → Quarkus)

**Breaking Changes 17.x → 26.x:**
- Runtime: WildFly application server → Quarkus native
- Startup command: `standalone.sh` → `kc.sh start`
- Env vars: `KEYCLOAK_USER` → `KEYCLOAK_ADMIN`
- Env vars: `DB_VENDOR` → `KC_DB`, `DB_ADDR` → `KC_DB_URL_HOST`
- Health paths: `/auth/` → `/auth/health/ready` (readiness)
- Liquibase: 3.5.5 → 4.6.2 (auto-migration ~200 changesets, irreversível)
- Startup time: 60-80s → 27s (65% faster)

**Chart Migration:**
```hcl
# Old (WildFly)
chart: codecentric/keycloak
version: 18.4.0

# New (Quarkus)
chart: codecentric/keycloakx
version: 7.1.7
```

### Performance

**Startup Time (26.5.1 Quarkus):**
- First boot: 43s Quarkus build + 16s init = 59s total
- Subsequent boots (--optimized): ~20-27s
- WildFly 17.x baseline: 60-80s

**Resource Recommendations:**
```yaml
# STAGING (1-2 replicas, <100 users)
requests:
  cpu: 500m
  memory: 1Gi
limits:
  cpu: 1000m
  memory: 2Gi

# PRODUCTION (2-3 replicas, 1000+ users)
requests:
  cpu: 1000m
  memory: 2Gi
limits:
  cpu: 2000m
  memory: 4Gi
```

## Referências Locais

### Terraform
- Module: `platform-provisioning/aws/kubernetes/terraform/modules/keycloak/`
- Values: `modules/keycloak/values.yaml.tpl`
- Bootstrap: `scripts/keycloak/bootstrap-database.sh`

### Documentação
- ADR: `docs/adr/adr-046-keycloak-sso-strategy.md`
- Quick Ref: `docs/KEYCLOAK-SONARQUBE-QUICK-REFERENCE.md`
- Audit: `docs/KEYCLOAK-SONARQUBE-AUDIT.md`
- Logbook: `docs/logbook/2026-02-11-keycloak-26-deployment-final.md`

## OIDC Integration

### Service Alias (CRITICAL - 2026-02-11)

**Problema:**
- Chart codecentric/keycloakx cria service `keycloak-keycloakx-http`
- OIDC clients (ArgoCD, GitLab, Grafana, SonarQube) esperam `keycloak-http.keycloak.svc.cluster.local`
- Resultado: OIDC discovery fail, login quebrado

**Solução:**
```yaml
# Service alias para backward compatibility
apiVersion: v1
kind: Service
metadata:
  name: keycloak-http
  namespace: keycloak
spec:
  type: ClusterIP
  ports:
    - name: http
      port: 80
      targetPort: 8080
  selector:
    app.kubernetes.io/instance: keycloak
    app.kubernetes.io/name: keycloakx
```

**Validation:**
```bash
kubectl get endpoints -n keycloak keycloak-http
# Output: 10.0.137.158:8080 (keycloak-keycloakx-0)

curl http://keycloak-http.keycloak/auth/realms/platform/.well-known/openid-configuration
# Output: {"issuer":"http://keycloak-http.keycloak/auth/realms/platform",...}
```

### OIDC Clients Configuration

**ArgoCD:**
```yaml
# argocd-cm ConfigMap
oidc.config: |
  name: Keycloak
  issuer: http://keycloak-http.keycloak.svc.cluster.local/auth/realms/platform
  clientID: argocd
  requestedScopes: [openid, profile, email, groups]
```

**Ingress (External Access):**
```yaml
# Keycloak Ingress
host: keycloak.staging.internal
service: keycloak-keycloakx-http:80

# ArgoCD Ingress
host: argocd.staging.internal
service: argocd-server:80
```

## Issues Conhecidos

### GitHub Issues Relevantes
- [#16002](https://github.com/keycloak/keycloak/issues/16002) - Health check failure when KC_HTTP_RELATIVE_PATH set
  - Solução: Sempre incluir `/` no início do path

### Bitnami Licensing
- ❌ NÃO usar charts Bitnami (require $72k/ano Tanzu Standard license)
- ✅ Usar codecentric/keycloakx (sem licensing restrictions)
- Ref: `docs/finops/BITNAMI-LICENSING-IMPACT-ANALYSIS.md`

---

**Last Updated:** 2026-02-11 18:00 UTC
**Validated Against:** Keycloak 26.5.1 (Quarkus 3.27.1) em STAGING
**Deployment Status:** ✅ 1/1 Running (HA pending cluster capacity)
**OIDC Status:** ✅ Discovery validated, service alias deployed, backend integration OK

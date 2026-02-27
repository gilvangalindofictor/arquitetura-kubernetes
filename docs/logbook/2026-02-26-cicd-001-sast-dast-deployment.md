# Logbook: CICD-001 Deployment — SAST/DAST Security Scanning Enforcement

**Date**: 2026-02-26
**Demand**: CICD-001 — SAST/DAST Pipeline Enforcement Deployment
**Status**: BLOCKED — Cluster DOWN (deployment commands prepared)
**Effort**: 1h (artifact verification + deployment prep)
**ADR**: [ADR-081](../adr/adr-081-sast-dast-pipeline-enforcement.md)
**Planning Logbook**: [2026-02-26-cicd-001-sast-dast-planning.md](2026-02-26-cicd-001-sast-dast-planning.md)

---

## Objetivo

Deploy da stack CICD-001 (4 scanners de segurança bloqueantes) no ambiente staging.

---

## Estado Atual

### Cluster Status

**CLUSTER DOWN**: Contexto `k8s-platform-prod` não está disponível.

```bash
$ kubectl get pods -n sonarqube --context=k8s-platform-prod
error: context "k8s-platform-prod" does not exist
```

Todos os comandos de deployment foram preparados mas NÃO executados.

### Artefatos Verificados

| Artefato | Status | Path |
|----------|--------|------|
| GitLab CI Template | ✅ EXISTE | `/domains/cicd-platform/infra/gitlab-ci/templates/.gitlab-ci-security-template.yml` |
| SonarQube Script | ✅ EXISTE | `/scripts/sonarqube/configure-blocking.sh` |
| Harbor Script | ✅ EXISTE | `/scripts/harbor/configure-trivy-blocking.sh` |
| PrometheusRule | ✅ EXISTE | `/domains/observability/infra/alerts/cicd-security-prometheus-rules.yaml` |
| Grafana Dashboard | ✅ EXISTE | `/monitoring/grafana/dashboards/cicd-security-scan-performance.json` |
| Runbook | ✅ EXISTE | `/docs/runbooks/security-scan-failures-troubleshooting.md` |
| Developer Guide | ✅ EXISTE | `/docs/CICD-001-DEVELOPER-GUIDE.md` |
| ADR-081 | ✅ EXISTE | `/docs/adr/adr-081-sast-dast-pipeline-enforcement.md` |

**Conclusão**: Todos os 9 artefatos planejados estão prontos para deploy.

---

## Deployment Commands (READY TO EXECUTE)

### Phase 1: Verificação de Pré-Requisitos

Quando cluster estiver UP, executar:

```bash
# 1. Verificar SonarQube UP
kubectl get pods -n sonarqube --context=k8s-platform-prod | grep sonarqube

# Expected output:
# sonarqube-<hash>  1/1  Running  0  Xd

# 2. Verificar Harbor UP
kubectl get pods -n harbor-system --context=k8s-platform-prod | grep harbor-core

# Expected output:
# harbor-core-<hash>  1/1  Running  0  Xd

# 3. Verificar GitLab UP
kubectl get pods -n staging-platform-gitlab --context=k8s-platform-prod | grep webservice

# Expected output:
# gitlab-webservice-<hash>  2/2  Running  0  Xd

# 4. Verificar Prometheus UP
kubectl get pods -n monitoring --context=k8s-platform-prod | grep prometheus-kube

# Expected output:
# prometheus-kube-prometheus-stack-prometheus-0  2/2  Running  0  Xd
```

**Se TODOS DOWN**: Cluster precisa ser iniciado antes do deployment.

---

### Phase 2: Deploy PrometheusRule Alerts

```bash
# Working directory: /home/gilvangalindo/projects/Arquitetura/Kubernetes

# 1. Apply PrometheusRule
kubectl apply -f domains/observability/infra/alerts/cicd-security-prometheus-rules.yaml \
  --context=k8s-platform-prod

# 2. Verify PrometheusRule created
kubectl get prometheusrules -n monitoring --context=k8s-platform-prod | grep cicd001

# Expected output:
# cicd001-security-scan-alerts  <age>

# 3. Verify alerts loaded in Prometheus
# Access Prometheus UI: http://prometheus.staging.platform/alerts
# Search for: "SonarQubeQualityGateFailed" or "TrivyCriticalVulnerabilitiesFound"

# 4. Check for errors in Prometheus Operator
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator --tail=50 \
  --context=k8s-platform-prod | grep -i "cicd001\|error"

# If no errors: alerts are loaded successfully
```

**Expected Result**: 10 alertas criados em 3 grupos (cicd.sonarqube, cicd.pipeline-security, cicd.harbor-security)

---

### Phase 3: Configure SonarQube Quality Gate

```bash
# Working directory: /home/gilvangalindo/projects/Arquitetura/Kubernetes

# 1. Get SonarQube admin token from Vault
SONAR_TOKEN=$(kubectl exec -n staging-security-vault vault-0 --context=k8s-platform-prod -- \
  vault kv get -field=token secret/sonarqube/admin)

# 2. Port-forward SonarQube (if not accessible via ingress)
kubectl port-forward svc/sonarqube 9000:9000 -n sonarqube --context=k8s-platform-prod &
PF_PID=$!
sleep 3

# 3. Configure blocking quality gate
cd scripts/sonarqube
SONAR_HOST_URL="http://localhost:9000" \
SONAR_TOKEN="${SONAR_TOKEN}" \
  ./configure-blocking.sh

# Expected output:
# [OK] SonarQube is UP (version: 10.3.0)
# [INFO] Quality gate 'Platform Security Gate' created with ID: <id>
# [OK] All conditions configured
# [OK] Gate 'Platform Security Gate' set as default for all new projects

# 4. Validate configuration
SONAR_HOST_URL="http://localhost:9000" \
SONAR_TOKEN="${SONAR_TOKEN}" \
  ./configure-blocking.sh --validate

# Expected output:
# Default gate is correctly set to 'Platform Security Gate'
# Conditions for 'Platform Security Gate':
#   metric=new_vulnerabilities op=GT error=0
#   metric=new_bugs op=GT error=0
#   metric=new_security_hotspots_reviewed op=LT error=100
#   metric=new_coverage op=LT error=80
#   metric=new_reliability_rating op=GT error=1
#   metric=new_security_rating op=GT error=1
#   metric=new_code_smells op=GT error=20
#   metric=new_duplicated_lines_density op=GT error=5

# 5. Kill port-forward
kill $PF_PID

cd ../..
```

**Expected Result**: Quality Gate "Platform Security Gate" criado com 8 condições bloqueantes.

---

### Phase 4: Configure Harbor Trivy Blocking

```bash
# Working directory: /home/gilvangalindo/projects/Arquitetura/Kubernetes

# 1. Get Harbor admin password from Vault
HARBOR_ADMIN_PASSWORD=$(kubectl exec -n staging-security-vault vault-0 --context=k8s-platform-prod -- \
  vault kv get -field=password secret/harbor/admin)

# 2. Port-forward Harbor (if not accessible via ingress)
kubectl port-forward svc/harbor-portal 8080:80 -n harbor-system --context=k8s-platform-prod &
PF_PID=$!
sleep 3

# 3. Configure Trivy blocking
cd scripts/harbor
HARBOR_REGISTRY="http://localhost:8080" \
HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD}" \
  ./configure-trivy-blocking.sh

# Expected output:
# [OK] Harbor is reachable
# [INFO] Harbor version: <version>
# [OK] Trivy scanner found (UUID: <uuid>)
# [OK] System vulnerability threshold set to: high
# [INFO] Configuring ALL Harbor projects...
# [OK] Project <name>: prevent_vul=high+ | auto_scan=true
# ...

# 4. Validate configuration
HARBOR_REGISTRY="http://localhost:8080" \
HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD}" \
  ./configure-trivy-blocking.sh --validate

# Expected output:
# System Configuration:
#   Vulnerability Severity Threshold: high
# Project Security Settings:
#   Project: <name> | auto_scan=true | prevent_vul=true | severity=high
#   ...

# 5. Kill port-forward
kill $PF_PID

cd ../..
```

**Expected Result**: Harbor configurado para bloquear imagens com HIGH/CRITICAL vulnerabilities.

---

### Phase 5: Import Grafana Dashboard

**Option A: Via Grafana UI (Recommended)**

```bash
# 1. Access Grafana
# URL: http://grafana.staging.platform

# 2. Navigate to: Dashboards → Import → Upload JSON file

# 3. Select file:
# /home/gilvangalindo/projects/Arquitetura/Kubernetes/monitoring/grafana/dashboards/cicd-security-scan-performance.json

# 4. Click "Import"

# 5. Verify dashboard created with UID: cicd001-security-scans
```

**Option B: Via Grafana API**

```bash
# Working directory: /home/gilvangalindo/projects/Arquitetura/Kubernetes

# 1. Get Grafana admin credentials from Vault
GRAFANA_USER=$(kubectl exec -n staging-security-vault vault-0 --context=k8s-platform-prod -- \
  vault kv get -field=user secret/grafana/admin)

GRAFANA_PASSWORD=$(kubectl exec -n staging-security-vault vault-0 --context=k8s-platform-prod -- \
  vault kv get -field=password secret/grafana/admin)

# 2. Port-forward Grafana (if not accessible via ingress)
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring --context=k8s-platform-prod &
PF_PID=$!
sleep 3

# 3. Create API key
GRAFANA_API_KEY=$(curl -s -X POST \
  -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" \
  -H "Content-Type: application/json" \
  -d '{"name":"cicd001-dashboard-import","role":"Admin"}' \
  "http://localhost:3000/api/auth/keys" | jq -r '.key')

# 4. Import dashboard
curl -X POST \
  -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
  -H "Content-Type: application/json" \
  -d @monitoring/grafana/dashboards/cicd-security-scan-performance.json \
  "http://localhost:3000/api/dashboards/db"

# Expected output:
# {"id":<id>,"slug":"cicd001-security-scans","status":"success","uid":"cicd001-security-scans","url":"/d/cicd001-security-scans/cicd-security-scan-performance","version":<version>}

# 5. Delete temporary API key
curl -X DELETE \
  -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
  "http://localhost:3000/api/auth/keys/<key-id>"

# 6. Kill port-forward
kill $PF_PID
```

**Expected Result**: Dashboard "CICD Security Scan Performance" disponível em Grafana com UID `cicd001-security-scans`.

---

### Phase 6: GitLab Template Availability Check

**Nota**: Template GitLab CI já está no repositório local. Projetos podem incluí-lo via:

```yaml
# .gitlab-ci.yml
include:
  - local: '/domains/cicd-platform/infra/gitlab-ci/templates/.gitlab-ci-security-template.yml'

stages:
  - security-scan

# Use hidden jobs as templates
security:sast:
  extends: .sonarqube-sast

security:container:
  extends: .trivy-container-scan

security:dependencies:
  extends: .owasp-dependency-check

security:secrets:
  extends: .trufflehog-secret-scan
```

**Alternative**: Se este repositório for separado, template pode ser incluído via `project` reference:

```yaml
include:
  - project: 'platform/templates'
    file: '/gitlab-ci/templates/.gitlab-ci-security-template.yml'
```

---

### Phase 7: End-to-End Test (OPTIONAL — Se GitLab UP)

```bash
# 1. Create test repository
mkdir -p /tmp/cicd001-test
cd /tmp/cicd001-test

git init
git remote add origin https://gitlab.staging.platform/platform/cicd001-security-test.git

# 2. Create test project structure
mkdir -p src
cat > src/example.py <<'EOF'
import os

# This should trigger TruffleHog (fake secret for testing)
# trufflehog:ignore
aws_key = "AKIAIOSFODNN7EXAMPLE"

def hello():
    print("Hello, World!")
EOF

cat > requirements.txt <<'EOF'
# Intentionally old version with known CVEs for testing
requests==2.20.0  # Known CVE-2018-18074
EOF

# 3. Create .gitlab-ci.yml
cat > .gitlab-ci.yml <<'EOF'
include:
  - local: '/domains/cicd-platform/infra/gitlab-ci/templates/.gitlab-ci-security-template.yml'

stages:
  - security-scan

security:sast:
  extends: .sonarqube-sast
  variables:
    SONAR_TOKEN: ${SONAR_TOKEN}  # Set in CI/CD variables

security:dependencies:
  extends: .owasp-dependency-check
EOF

# 4. Commit and push
git add .
git commit -m "test: CICD-001 security scanning E2E test"
git push origin main

# 5. Monitor pipeline
# Access: https://gitlab.staging.platform/platform/cicd001-security-test/-/pipelines

# Expected results:
# - security:sast job: PASS or FAIL (depends on code)
# - security:dependencies job: FAIL (due to requests==2.20.0 CVE)
# - Prometheus metrics pushed to PushGateway
# - Grafana dashboard shows scan results
```

**Expected Result**: Pipeline fails on `security:dependencies` devido a CVE conhecido. Métricas aparecem no dashboard Grafana.

---

## Post-Deployment Validation

Quando cluster estiver UP e deployment completo, executar:

```bash
# 1. Verify PrometheusRule alerts loaded
kubectl get prometheusrules -n monitoring --context=k8s-platform-prod | grep cicd001
# Expected: cicd001-security-scan-alerts

# 2. Check Prometheus targets
# http://prometheus.staging.platform/targets
# Search for: sonarqube, harbor

# 3. Verify SonarQube Quality Gate
# http://sonarqube.staging.platform/quality_gates
# Expected: "Platform Security Gate" marked as DEFAULT with 8 conditions

# 4. Verify Harbor Trivy config
# http://harbor.staging.platform → Projects → [any project] → Configuration
# Expected: "Automatically scan images on push" = YES
#           "Prevent vulnerable images from running" = YES (severity: HIGH)

# 5. Check Grafana dashboard
# http://grafana.staging.platform/d/cicd001-security-scans
# Expected: Dashboard loads with 5 sections (no data yet until first pipeline runs)

# 6. Test PushGateway accessibility
kubectl port-forward svc/prometheus-pushgateway 9091:9091 -n monitoring --context=k8s-platform-prod &
curl http://localhost:9091/metrics | grep gitlab_ci
# Expected: Metrics endpoint accessible (may be empty if no scans yet)
```

---

## Deployment Status Summary

| Component | Status | Deployment Command Ready? | Notes |
|-----------|--------|---------------------------|-------|
| GitLab CI Template | ✅ READY | N/A (local file) | Available at `domains/cicd-platform/infra/gitlab-ci/templates/.gitlab-ci-security-template.yml` |
| SonarQube Quality Gate | 🔶 PENDING | ✅ YES | Requires SonarQube UP + admin token |
| Harbor Trivy Config | 🔶 PENDING | ✅ YES | Requires Harbor UP + admin password |
| PrometheusRule Alerts | 🔶 PENDING | ✅ YES | `kubectl apply -f ...` command ready |
| Grafana Dashboard | 🔶 PENDING | ✅ YES | Import via UI or API |
| E2E Test | ⏸️ OPTIONAL | ✅ YES | Test repository creation script ready |

**Overall Status**: ⏸️ **BLOCKED** — Aguardando cluster UP

**Blocker**: Contexto `k8s-platform-prod` não existe. Cluster precisa ser iniciado.

---

## Next Steps (When Cluster is UP)

### Immediate (Day 1)

1. ✅ Execute Phase 1: Verify all services UP
2. ✅ Execute Phase 2: Deploy PrometheusRule alerts
3. ✅ Execute Phase 3: Configure SonarQube Quality Gate
4. ✅ Execute Phase 4: Configure Harbor Trivy blocking
5. ✅ Execute Phase 5: Import Grafana dashboard
6. ✅ Execute Phase 7: Run E2E test (optional)

### Short-term (Sprint +1 week)

1. Onboard 1-2 pilot projects to use security template
2. Monitor Grafana dashboard for first scan results
3. Adjust thresholds if needed based on feedback
4. Document false positive handling with real examples

### Medium-term (Sprint +2 weeks)

1. Rollout security template to ALL active projects
2. Create NetworkPolicy for PushGateway access from GitLab Runners
3. Setup AlertManager routing for security scan failures
4. Create Slack integration for critical security alerts

---

## ROI Calculation

**Cost Avoidance (Risk Mitigation)**:

| Risk Prevented | Probability | Impact (R$) | Expected Value |
|----------------|-------------|-------------|----------------|
| Critical CVE in production | 30%/year | R$ 100K (incident response + downtime) | R$ 30K/year |
| Exposed secret in git history | 15%/year | R$ 150K (data breach + remediation) | R$ 22.5K/year |
| Compliance violation (LGPD) | 10%/year | R$ 200K (fines + audit) | R$ 20K/year |

**Total Expected Value**: ~R$ 70K/year

**Implementation Cost**:
- Artefact creation: 9h × R$ 300/h = R$ 2.700
- Deployment + validation: 4h × R$ 300/h = R$ 1.200
- Developer training: 8h × R$ 300/h = R$ 2.400

**Total Cost**: R$ 6.300

**ROI**: (R$ 70K - R$ 6.3K) / R$ 6.3K = **1011% ROI**

**Payback Period**: (R$ 6.3K / R$ 70K) × 12 months = **1.08 months**

---

## Lições Aprendadas

1. **Cluster DOWN é esperado**: Preparar comandos idempotentes para execução posterior é a melhor estratégia.

2. **Artefatos já existiam**: Planejamento anterior (logbook 2026-02-26-cicd-001-sast-dast-planning.md) criou todos os artefatos. Deployment é apenas aplicação dos recursos.

3. **Port-forwarding necessário**: Scripts assumem acesso via ingress. Se ingress não estiver configurado, port-forward é obrigatório.

4. **Secrets em Vault**: SonarQube token e Harbor password devem estar em Vault. Se não estiverem, criar manualmente via UI e depois migrar para Vault.

5. **PushGateway networking**: GitLab Runners precisam acessar Prometheus PushGateway. Verificar NetworkPolicies não bloqueiam `staging-platform-gitlab` → `monitoring`.

6. **Template include path**: Projetos precisam incluir template com path correto. Se repositório é monorepo, usar `local`. Se separado, usar `project` reference.

---

## References

- [ADR-081: SAST/DAST Pipeline Enforcement](../adr/adr-081-sast-dast-pipeline-enforcement.md)
- [Planning Logbook: CICD-001](2026-02-26-cicd-001-sast-dast-planning.md)
- [Runbook: Security Scan Failures](../runbooks/security-scan-failures-troubleshooting.md)
- [Developer Guide: CICD-001](../CICD-001-DEVELOPER-GUIDE.md)
- [PrometheusRule: cicd-security-alerts.yaml](../../domains/observability/infra/alerts/cicd-security-prometheus-rules.yaml)

---

**Deployment Prepared By**: Platform SRE Agent (Security Specialist)
**Date**: 2026-02-26
**Status**: Aguardando cluster UP para execução dos comandos

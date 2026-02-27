# CICD-001: SAST/DAST Security Scanning Enforcement — DEPLOYMENT SUMMARY

**Date**: 2026-02-26
**Status**: ⏸️ **BLOCKED** — Aguardando cluster UP
**Demand**: CICD-001 — SAST/DAST Pipeline Enforcement
**ADR**: [ADR-081](docs/adr/adr-081-sast-dast-pipeline-enforcement.md)

---

## Executive Summary

A demanda CICD-001 implementa **4 scanners de segurança bloqueantes** no pipeline GitLab CI/CD:

1. **SonarQube SAST** — Zero tolerance para vulnerabilidades e bugs
2. **Trivy Container Scan** — Bloqueia imagens com CVEs HIGH/CRITICAL
3. **OWASP Dependency-Check** — Detecta CVEs em dependências (npm, maven, pip)
4. **TruffleHog Secret Detection** — Detecta secrets expostos em git history

**ROI**: R$ 70K/ano (risk mitigation) | **Payback**: 1 mês | **Effort**: 9h artefatos + 4h deployment

---

## Deployment Status

### Artefatos (9/9 COMPLETOS)

| # | Artefato | Status | Path |
|---|----------|--------|------|
| 1 | GitLab CI Template | ✅ | `domains/cicd-platform/infra/gitlab-ci/templates/.gitlab-ci-security-template.yml` |
| 2 | SonarQube Script | ✅ | `scripts/sonarqube/configure-blocking.sh` |
| 3 | Harbor Script | ✅ | `scripts/harbor/configure-trivy-blocking.sh` |
| 4 | PrometheusRule | ✅ | `domains/observability/infra/alerts/cicd-security-prometheus-rules.yaml` |
| 5 | Grafana Dashboard | ✅ | `monitoring/grafana/dashboards/cicd-security-scan-performance.json` |
| 6 | ADR-081 | ✅ | `docs/adr/adr-081-sast-dast-pipeline-enforcement.md` |
| 7 | Runbook | ✅ | `docs/runbooks/security-scan-failures-troubleshooting.md` |
| 8 | Developer Guide | ✅ | `docs/CICD-001-DEVELOPER-GUIDE.md` |
| 9 | Deployment Logbook | ✅ | `docs/logbook/2026-02-26-cicd-001-sast-dast-deployment.md` |

### Deployment Commands

| # | Phase | Status | Command Ready? |
|---|-------|--------|----------------|
| 1 | Prerequisites Check | 🔶 PENDING | ✅ YES |
| 2 | Deploy PrometheusRule | 🔶 PENDING | ✅ YES |
| 3 | Configure SonarQube | 🔶 PENDING | ✅ YES |
| 4 | Configure Harbor | 🔶 PENDING | ✅ YES |
| 5 | Import Grafana Dashboard | 🔶 PENDING | ✅ YES |
| 6 | Post-Deployment Validation | 🔶 PENDING | ✅ YES |

**Blocker**: Kubernetes context `k8s-platform-prod` não existe. Cluster precisa ser iniciado.

---

## Quick Start (When Cluster is UP)

### Option A: Automated Deployment Script

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes

# Execute deployment script (interactive)
./CICD-001-DEPLOYMENT-COMMANDS.sh

# Or non-interactive (answer 'y' to all prompts)
yes | ./CICD-001-DEPLOYMENT-COMMANDS.sh
```

### Option B: Manual Phase-by-Phase

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes

# Phase 1: Check prerequisites
kubectl get pods -n sonarqube --context=k8s-platform-prod
kubectl get pods -n harbor-system --context=k8s-platform-prod
kubectl get pods -n monitoring --context=k8s-platform-prod

# Phase 2: Deploy PrometheusRule
kubectl apply -f domains/observability/infra/alerts/cicd-security-prometheus-rules.yaml --context=k8s-platform-prod

# Phase 3: Configure SonarQube
cd scripts/sonarqube
kubectl port-forward svc/sonarqube 9000:9000 -n sonarqube --context=k8s-platform-prod &
SONAR_TOKEN=$(kubectl exec -n staging-security-vault vault-0 --context=k8s-platform-prod -- vault kv get -field=token secret/sonarqube/admin)
SONAR_HOST_URL="http://localhost:9000" SONAR_TOKEN="${SONAR_TOKEN}" ./configure-blocking.sh
cd ../..

# Phase 4: Configure Harbor
cd scripts/harbor
kubectl port-forward svc/harbor-portal 8080:80 -n harbor-system --context=k8s-platform-prod &
HARBOR_ADMIN_PASSWORD=$(kubectl exec -n staging-security-vault vault-0 --context=k8s-platform-prod -- vault kv get -field=password secret/harbor/admin)
HARBOR_REGISTRY="http://localhost:8080" HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD}" ./configure-trivy-blocking.sh
cd ../..

# Phase 5: Import Grafana Dashboard
# Manual: http://grafana.staging.platform → Dashboards → Import → Upload JSON
# File: monitoring/grafana/dashboards/cicd-security-scan-performance.json
```

---

## Post-Deployment Checklist

- [ ] PrometheusRule alerts loaded (10 alertas em 3 grupos)
- [ ] SonarQube Quality Gate "Platform Security Gate" criado e default
- [ ] Harbor Trivy blocking configurado (severity: HIGH)
- [ ] Grafana dashboard importado (UID: cicd001-security-scans)
- [ ] PushGateway acessível de GitLab Runners
- [ ] Pilot project onboarded (1-2 projetos de teste)
- [ ] E2E test executado e pipeline bloqueado por segurança

---

## Key Components

### 1. GitLab CI Template

**Path**: `domains/cicd-platform/infra/gitlab-ci/templates/.gitlab-ci-security-template.yml`

**Usage** (em .gitlab-ci.yml de projetos):

```yaml
include:
  - local: '/domains/cicd-platform/infra/gitlab-ci/templates/.gitlab-ci-security-template.yml'

stages:
  - security-scan

security:sast:
  extends: .sonarqube-sast

security:container:
  extends: .trivy-container-scan

security:dependencies:
  extends: .owasp-dependency-check

security:secrets:
  extends: .trufflehog-secret-scan
```

### 2. SonarQube Quality Gate

**Condições bloqueantes** (8 condições):

| Métrica | Threshold | Severity |
|---------|-----------|----------|
| New Vulnerabilities | > 0 | BLOCKING |
| New Bugs | > 0 | BLOCKING |
| Security Hotspots Reviewed | < 100% | BLOCKING |
| New Coverage | < 80% | BLOCKING |
| New Reliability Rating | > A | BLOCKING |
| New Security Rating | > A | BLOCKING |
| New Code Smells | > 20 | WARNING |
| New Duplicated Lines | > 5% | WARNING |

### 3. Harbor Trivy Config

- **Severity Threshold**: HIGH, CRITICAL
- **Auto-scan on push**: ENABLED
- **Block vulnerable pull**: ENABLED

### 4. PrometheusRule Alerts

**10 alertas** em 3 grupos:

| Alert | Severity | Description |
|-------|----------|-------------|
| SonarQubeQualityGateFailed | critical | Quality Gate falhou |
| TrivyCriticalVulnerabilitiesFound | critical | CVEs CRITICAL em imagem |
| TruffleHogSecretDetected | critical | Secret detectado em git |
| PipelineSecurityScanFailed | warning | Qualquer scan falhou |
| OWASPDependencyCheckFailed | warning | CVE em dependências |
| SecurityScanDurationAnomaly | warning | Scan > 10 minutos |
| SonarQubeDown | warning | SonarQube indisponível |
| SonarQubeNewVulnerabilitiesHigh | warning | Novas vulnerabilidades |
| SecurityScanJobMissing | warning | Projeto sem scan |
| HarborScannerDown | warning | Harbor indisponível |

### 5. Grafana Dashboard

**UID**: `cicd001-security-scans`

**5 seções**:
1. Overview — Quality Gate Status
2. Quality Gate Pass/Fail Ratio
3. Scan Duration Trends
4. SonarQube Metrics
5. Recent Scan History

---

## Scanner Configuration

| Scanner | Image | Version | Output | Cache |
|---------|-------|---------|--------|-------|
| SonarQube SAST | sonarsource/sonar-scanner-cli | 5.0 | Quality Gate | .sonar/cache |
| Trivy Container | aquasec/trivy | 0.50.0 | SARIF + Table | .trivy-cache/ |
| OWASP Dependency-Check | owasp/dependency-check | latest | HTML + JSON | .owasp-cache/data/ |
| TruffleHog Secret Scan | trufflesecurity/trufflehog | latest | JSON | N/A |

**Pipeline Duration**: +3-8 minutos (após cache warm)

---

## False Positive Handling

### SonarQube
```
Mark as "Won't Fix" in UI with justification comment
```

### Trivy
```bash
# .trivyignore
CVE-2023-12345  # Justification: vulnerable code path not reachable. Reviewed by <name> on <date>.
```

### OWASP Dependency-Check
```xml
<!-- dependency-check-suppression.xml -->
<suppress until="2026-05-01">
  <notes>CVE-XXXX: Reviewed by <name>. Not exploitable because...</notes>
  <cve>CVE-XXXX-XXXXX</cve>
</suppress>
```

### TruffleHog
```python
# Inline comment
secret = "fake_secret_for_testing"  # trufflehog:ignore
```

---

## Emergency Bypass Process

**NEVER use `allow_failure: true` as permanent workaround!**

**Required approvals**:
1. Platform SRE or Tech Lead approval via GitLab MR review
2. Create tracking issue with SLA (max 5 business days)
3. Set CI/CD variable: `SECURITY_SCAN_BYPASS_REASON="<justification>"`
4. Commit message: `[SECURITY-BYPASS] Reason: <justification>`

---

## Observability

### Prometheus Metrics

```promql
# Scan status (1=pass, 0=fail)
gitlab_ci_pipeline_security_scan_status{scanner="sonarqube|trivy|owasp-dependency-check|trufflehog"}

# Scan duration (seconds)
gitlab_ci_pipeline_security_scan_duration_seconds{scanner="...", status="pass|fail"}
```

### Grafana Dashboards

- **CICD-001 Security Scans**: http://grafana.staging.platform/d/cicd001-security-scans

### Prometheus Alerts

- **Prometheus UI**: http://prometheus.staging.platform/alerts
- **Filter**: `CICD-001` or `cicd.sonarqube`, `cicd.pipeline-security`, `cicd.harbor-security`

---

## Documentation

| Document | Path |
|----------|------|
| ADR-081 | `docs/adr/adr-081-sast-dast-pipeline-enforcement.md` |
| Planning Logbook | `docs/logbook/2026-02-26-cicd-001-sast-dast-planning.md` |
| Deployment Logbook | `docs/logbook/2026-02-26-cicd-001-sast-dast-deployment.md` |
| Runbook | `docs/runbooks/security-scan-failures-troubleshooting.md` |
| Developer Guide | `docs/CICD-001-DEVELOPER-GUIDE.md` |

---

## ROI & Impact

### Cost Avoidance (Risk Mitigation)

| Risk | Probability | Impact | Expected Value |
|------|-------------|--------|----------------|
| Critical CVE in production | 30%/year | R$ 100K | R$ 30K/year |
| Exposed secret | 15%/year | R$ 150K | R$ 22.5K/year |
| Compliance violation | 10%/year | R$ 200K | R$ 20K/year |
| **Total** | - | - | **R$ 70K/year** |

### Implementation Cost

- Artefatos: 9h × R$ 300/h = R$ 2.700
- Deployment: 4h × R$ 300/h = R$ 1.200
- Training: 8h × R$ 300/h = R$ 2.400
- **Total**: R$ 6.300

**ROI**: 1011% | **Payback**: 1 mês

---

## Next Steps

### Immediate (When Cluster UP)

1. Execute deployment script: `./CICD-001-DEPLOYMENT-COMMANDS.sh`
2. Verify all components deployed successfully
3. Access Grafana dashboard: http://grafana.staging.platform/d/cicd001-security-scans

### Short-term (Week 1-2)

1. Onboard 1-2 pilot projects
2. Monitor scan results and adjust thresholds if needed
3. Document real false positive examples
4. Setup AlertManager Slack integration

### Medium-term (Sprint +1)

1. Rollout to ALL active projects
2. Create NetworkPolicy for PushGateway access
3. Setup pre-commit hooks for developers
4. Review security posture after 30 days

---

## Support & Troubleshooting

- **Runbook**: `docs/runbooks/security-scan-failures-troubleshooting.md`
- **Developer Guide**: `docs/CICD-001-DEVELOPER-GUIDE.md`
- **Deployment Logbook**: `docs/logbook/2026-02-26-cicd-001-sast-dast-deployment.md`
- **Team**: Platform SRE Team
- **Slack**: #platform-sre (when available)

---

**Prepared by**: Platform SRE Agent (Security Specialist)
**Date**: 2026-02-26
**Status**: Ready for deployment when cluster is UP

# CICD-001: SAST/DAST Security Scanning — Deployment Guide

**Demand**: CICD-001
**ADR**: [ADR-081](../../docs/adr/adr-081-sast-dast-pipeline-enforcement.md)
**Status**: Ready to deploy (cluster must be UP)
**Date**: 2026-02-26

---

## Overview of Artifacts

This document describes all CICD-001 artifacts and how to deploy them.

```
domains/cicd-platform/infra/gitlab-ci/templates/
  security.gitlab-ci-security-template.yml    ← GitLab CI template (main artifact)

scripts/sonarqube/
  configure-blocking.sh                       ← SonarQube Quality Gate API automation

scripts/harbor/
  configure-trivy-blocking.sh                 ← Harbor Trivy severity threshold

domains/observability/infra/alerts/
  cicd-security-prometheus-rules.yaml         ← PrometheusRule (8 alerts)

monitoring/grafana/dashboards/
  cicd-security-scan-performance.json         ← Grafana dashboard

docs/adr/
  adr-081-sast-dast-pipeline-enforcement.md   ← Architecture Decision Record

docs/runbooks/
  security-scan-failures-troubleshooting.md   ← Troubleshooting for all 4 scanners

docs/
  CICD-001-DEVELOPER-GUIDE.md                ← Developer onboarding guide

docs/logbook/
  2026-02-26-cicd-001-sast-dast-planning.md  ← Implementation log
```

---

## Pre-deployment Checklist

Before deploying, verify these are all green:

```
[ ] Cluster is running (kubectl get nodes)
[ ] SonarQube is UP (kubectl get pods -n sonarqube)
[ ] Harbor is UP (kubectl get pods -n harbor-system)
[ ] Prometheus PushGateway is running (kubectl get pods -n monitoring -l app=prometheus-pushgateway)
[ ] PrometheusRule CRD is available (kubectl get crd prometheusrules.monitoring.coreos.com)
[ ] You have SonarQube admin token (generate if not: SonarQube UI → Administration → Security)
[ ] You have Harbor admin password (retrieve: vault kv get secret/harbor/admin)
[ ] kubectl context is pointing to staging cluster
```

---

## Deployment Steps

### Step 1 — Deploy PrometheusRule

```bash
# Apply the security scan alerting rules
kubectl apply -f /home/gilvangalindo/projects/Arquitetura/Kubernetes/domains/observability/infra/alerts/cicd-security-prometheus-rules.yaml

# Verify
kubectl get prometheusrule cicd001-security-scan-alerts -n monitoring
kubectl describe prometheusrule cicd001-security-scan-alerts -n monitoring | grep -A5 "Group:"
```

Expected output:
```
prometheusrule.monitoring.coreos.com/cicd001-security-scan-alerts created
```

Verify rules are loaded by Prometheus:
```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
# Open: http://localhost:9090/rules → search for "cicd"
```

### Step 2 — Configure SonarQube Quality Gate

```bash
# Retrieve SonarQube admin token from Vault or use existing SONAR_TOKEN
# Generate new token: SonarQube UI → Administration → Security → Users → Tokens

# Dry run first (verify what will happen)
SONAR_TOKEN=<your-token> \
  /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/sonarqube/configure-blocking.sh \
  --url http://sonarqube.staging.internal \
  --dry-run

# Execute
SONAR_TOKEN=<your-token> \
  /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/sonarqube/configure-blocking.sh \
  --url http://sonarqube.staging.internal

# Validate
SONAR_TOKEN=<your-token> \
  /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/sonarqube/configure-blocking.sh \
  --url http://sonarqube.staging.internal \
  --validate
```

If SonarQube is not externally reachable, port-forward first:
```bash
kubectl port-forward svc/sonarqube 9000:9000 -n sonarqube

# Then use localhost
SONAR_TOKEN=<token> \
  ./scripts/sonarqube/configure-blocking.sh \
  --url http://localhost:9000
```

Expected output:
```
[OK]      Quality gate 'Platform Security Gate' set as default for all new projects
[OK]      SonarQube blocking Quality Gate configuration complete
```

### Step 3 — Configure Harbor Trivy

```bash
# Retrieve Harbor admin password from Vault
HARBOR_ADMIN_PASSWORD=$(vault kv get -field=password secret/harbor/admin)

# Dry run
HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD}" \
  /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/harbor/configure-trivy-blocking.sh \
  --url https://harbor.staging.internal \
  --dry-run

# Execute
HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD}" \
  /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/harbor/configure-trivy-blocking.sh \
  --url https://harbor.staging.internal

# Validate
HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD}" \
  /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/harbor/configure-trivy-blocking.sh \
  --url https://harbor.staging.internal \
  --validate
```

Expected output:
```
[OK]      System vulnerability threshold set to: high
[OK]      Harbor Trivy blocking configuration complete
  Severity threshold:    HIGH and above
  Block vulnerable pull: ENABLED
  Auto-scan on push:     true
```

### Step 4 — Import Grafana Dashboard

**Option A: Via Grafana UI** (recommended for first deployment):
1. Open `https://grafana.internal`
2. Navigate to: Dashboards → Import
3. Click "Upload JSON file"
4. Select: `monitoring/grafana/dashboards/cicd-security-scan-performance.json`
5. Select datasource: `kube-prometheus-stack-prometheus`
6. Click Import

**Option B: Via Grafana API**:
```bash
GRAFANA_URL="https://grafana.internal"
GRAFANA_TOKEN="<api-key>"  # Create: Grafana → Administration → API Keys

curl -X POST "${GRAFANA_URL}/api/dashboards/import" \
  -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  -H "Content-Type: application/json" \
  -d @monitoring/grafana/dashboards/cicd-security-scan-performance.json
```

**Option C: Via Grafana ConfigMap** (GitOps, for future):
```bash
kubectl create configmap cicd001-grafana-dashboard \
  --from-file=cicd-security-scan-performance.json=monitoring/grafana/dashboards/cicd-security-scan-performance.json \
  -n monitoring \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl label configmap cicd001-grafana-dashboard \
  grafana_dashboard=1 \
  -n monitoring
```

### Step 5 — Add Template to GitLab Projects

For each project that should have security scanning enforced:

1. Copy the template include section to the project's `.gitlab-ci.yml`
2. Add `security-scan` to the stages list

**Minimum change (2 lines)**:
```yaml
include:
  - project: 'platform/templates'
    file: '/gitlab-ci/templates/security.gitlab-ci-security-template.yml'

stages:
  - build
  - test
  - security-scan   # ← ADD THIS
  - deploy
```

**For pilot deployment**: Start with a low-risk internal tool project.

---

## Validation Checklist

After deployment, validate each component:

### PrometheusRule
```bash
# Check rule is loaded
kubectl get prometheusrule cicd001-security-scan-alerts -n monitoring -o yaml | grep -c "alert:"
# Expected: >= 8

# Check Prometheus picked up rules (port-forward first)
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[] | select(.name | startswith("cicd")) | .name'
# Expected: "cicd.sonarqube", "cicd.pipeline-security", "cicd.harbor-security"
```

### SonarQube Quality Gate
```bash
# Via API
curl -s -u "${SONAR_TOKEN}:" "http://sonarqube.staging.internal/api/qualitygates/list" | \
  jq '.qualitygates[] | select(.name == "Platform Security Gate") | {name: .name, isDefault: .isDefault}'
# Expected: {"name": "Platform Security Gate", "isDefault": true}
```

### Harbor Trivy
```bash
# Via API
curl -s -u "admin:${HARBOR_ADMIN_PASSWORD}" --insecure \
  "https://harbor.staging.internal/api/v2.0/projects?page_size=5" | \
  jq '.[].metadata | {auto_scan, prevent_vul, severity}'
# Expected: {"auto_scan": "true", "prevent_vul": "true", "severity": "high"}
```

### GitLab CI Template
```bash
# Trigger a test pipeline in a pilot project
# Navigate to: GitLab project → CI/CD → Pipelines → Run pipeline
# Verify all 4 security-scan jobs appear and run
```

### Grafana Dashboard
```bash
# Open dashboard
# https://grafana.internal/d/cicd001-security-scans

# Verify panels load (may show "No data" initially — metrics arrive after first pipeline run)
```

### PushGateway Metrics (after first pipeline run)
```bash
kubectl port-forward svc/prometheus-pushgateway 9091:9091 -n monitoring

curl -s http://localhost:9091/metrics | grep gitlab_ci_pipeline_security_scan
# Expected: metrics with scanner, project, branch labels
```

---

## Rollback Procedure

If issues arise, roll back in reverse order:

### Rollback PrometheusRule
```bash
kubectl delete prometheusrule cicd001-security-scan-alerts -n monitoring
# No service impact — only removes alerts
```

### Rollback SonarQube Quality Gate
```bash
# Set back to "Sonar way" as default
SONAR_TOKEN=<token> curl -X POST \
  "http://sonarqube.staging.internal/api/qualitygates/set_as_default" \
  -u "${SONAR_TOKEN}:" \
  --data "name=Sonar%20way"
# Or via UI: Quality Gates → "Sonar way" → Set as Default
```

### Rollback Harbor Trivy
```bash
# Disable prevent_vul for each project via API or:
# Harbor UI → Projects → [project] → Configuration → Vulnerability scanning → Disable
```

### Rollback GitLab CI Template
```bash
# Remove from project .gitlab-ci.yml:
# - The include section
# - security-scan from stages list
# - Any security-scan job overrides
git revert <commit>
git push
```

---

## Known Limitations (to address in future iterations)

1. **OWASP DC NVD API rate limiting**: Without an NVD API key, downloads may be throttled.
   Get a free key at https://nvd.nist.gov/developers/request-an-api-key and set
   `DEPENDENCY_CHECK_OPTS: "--nvdApiKey ${NVD_API_KEY}"` in CI variables.

2. **TruffleHog in air-gapped environments**: `--only-verified` requires internet access to
   verify credentials against external APIs. In air-gapped mode, remove `--only-verified`
   and accept higher false positive rate.

3. **GitLab Security tab**: SARIF output from Trivy is generated but not yet uploaded as
   a GitLab security report (requires `reports.container_scanning` in artifacts, which
   needs GitLab Ultimate). Currently saved as artifact for manual review.

4. **SonarQube PR decoration**: Inline comments on MR diffs require SonarQube PR decoration
   configuration (GitLab integration in SonarQube settings). Not configured yet.

5. **PushGateway staleness**: Metrics from completed/deleted jobs remain in PushGateway
   until manually cleaned or TTL expires. Configure PushGateway with `--push.disable-consistency-check`
   to handle job-level metrics properly.

---

## Support

- **Slack**: `#platform-engineering`
- **Runbook**: `docs/runbooks/security-scan-failures-troubleshooting.md`
- **Developer Guide**: `docs/CICD-001-DEVELOPER-GUIDE.md`
- **ADR**: `docs/adr/adr-081-sast-dast-pipeline-enforcement.md`

# Runbook: Security Scan Failures Troubleshooting

**Demand**: CICD-001 — SAST/DAST Pipeline Enforcement
**ADR**: [ADR-081](../adr/adr-081-sast-dast-pipeline-enforcement.md)
**Audience**: Developers, Platform SRE
**Last Updated**: 2026-02-26

---

## Overview

This runbook covers how to diagnose and resolve failures in the four security scanners
enforced by CICD-001:

1. **SonarQube** — SAST (Static Application Security Testing)
2. **Trivy** — Container vulnerability scanning
3. **OWASP Dependency-Check** — Dependency CVE scanning
4. **TruffleHog** — Secret detection in git history

All four scanners run with `allow_failure: false`. A failure in ANY scanner blocks the
merge/pipeline.

**Policy**: Fix the underlying issue first. Suppression is the last resort.

---

## Quick Diagnosis

When a pipeline fails at the `security-scan` stage, first check which job failed:

```
GitLab CI Pipeline → [security-scan stage]
  ├── sonarqube-sast         → FAILED?  See section: SonarQube
  ├── trivy-container-scan   → FAILED?  See section: Trivy
  ├── owasp-dependency-check → FAILED?  See section: OWASP
  └── trufflehog-secret-scan → FAILED?  See section: TruffleHog
```

**Step 1**: Click the failed job in GitLab CI → Read the job output log
**Step 2**: Download artifacts from the job (reports are exported even on failure)
**Step 3**: Follow the section below for the specific scanner

---

## 1. SonarQube SAST

### 1.1 Quality Gate FAILED

**Symptom**: Job output contains `Quality Gate status: ERROR`

**Step 1 — View details in SonarQube**:
```
http://sonarqube.staging.internal/dashboard?id=<project-key>
```
Project key = `CI_PROJECT_PATH_SLUG` (e.g., `mygroup-myproject`)

**Step 2 — Identify failing conditions**:
Click "Quality Gate" in SonarQube → See which conditions are failing:
- New Vulnerabilities
- New Bugs
- Security Hotspots not reviewed
- New Coverage
- Reliability/Security Rating

**Step 3 — Fix the code**:
For each failing condition:
- **Vulnerabilities/Bugs**: Click the issue → Review → Fix the code
- **Security Hotspots**: Review if the hotspot is real. Mark as "Safe" or fix
- **Coverage**: Add unit tests for the new code
- **Rating**: Fix reliability or security issues shown in the Issues tab

**Step 4 — Re-trigger pipeline**:
```bash
git push   # triggers new scan automatically
```

### 1.2 SonarQube Connection Error

**Symptom**: `ERROR: SonarQube server [http://sonarqube.staging.internal] can not be reached`

**Diagnosis**:
```bash
# Check if SonarQube pod is running
kubectl get pods -n sonarqube

# Check pod logs
kubectl logs -n sonarqube -l app=sonarqube --tail=100

# Check PVC status
kubectl get pvc -n sonarqube

# Port-forward for testing
kubectl port-forward svc/sonarqube 9000:9000 -n sonarqube
curl http://localhost:9000/api/system/status
```

**Common causes**:
- SonarQube pod crashlooping → Check PostgreSQL connectivity
- PVC full → Check disk usage: `kubectl exec -n sonarqube <pod> -- df -h /opt/sonarqube/data`
- PostgreSQL down → Check `kubectl get pods -n sonarqube` for db pod

### 1.3 False Positive Suppression (SonarQube)

**Policy**: Suppression requires peer review comment in SonarQube.

**Process**:
1. Open the issue in SonarQube
2. Click the issue → "Mark as" → "Won't Fix" or "False Positive"
3. Add mandatory comment: `Why this is a false positive: <explanation>`
4. Tag the issue with `false-positive-reviewed-<YYYY-MM>`
5. The next pipeline run will see the issue as resolved and pass the gate

**Acceptable reasons for Won't Fix**:
- Code is unreachable in production context
- Vulnerability is in test-only code
- Compensating control exists elsewhere (document it)

**Unacceptable reasons**:
- "We'll fix it later" (open a tracked issue instead)
- No explanation provided

---

## 2. Trivy Container Scan

### 2.1 HIGH or CRITICAL Vulnerability Found

**Symptom**: Job output shows `FAIL` with CVE table listing HIGH or CRITICAL entries

**Step 1 — Download and read the report**:
```bash
# From GitLab CI: Pipeline → trivy-container-scan job → Artifacts → Download
# Or from job output, scan the CVE table
```

The report shows:
```
Library          Vulnerability    Severity    Installed Version  Fixed Version
libssl           CVE-2024-XXXXX   CRITICAL    1.1.1k             1.1.1n
python3-urllib   CVE-2024-YYYYY   HIGH        3.9.7              3.9.11
```

**Step 2 — Fix the vulnerability**:

**Option A: Update base image (preferred)**:
```dockerfile
# Before: outdated base
FROM python:3.9-slim

# After: patched version
FROM python:3.11-slim  # or 3.9.18-slim if pinning minor
```

**Option B: Install patched package**:
```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl1.1=1.1.1n-0+deb11u6 \
    && rm -rf /var/lib/apt/lists/*
```

**Option C: Multi-stage build to exclude dev dependencies**:
```dockerfile
FROM maven:3.9 AS builder
RUN mvn package

FROM eclipse-temurin:17-jre-alpine
COPY --from=builder /app/target/app.jar /app.jar
# Alpine JRE has fewer OS packages = smaller attack surface
```

**Step 3 — Verify fix locally**:
```bash
# Install Trivy locally
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh

# Build and scan locally before pushing
docker build -t myapp:test .
trivy image --severity HIGH,CRITICAL myapp:test
```

### 2.2 False Positive Suppression (Trivy)

**When is suppression acceptable?**
- CVE exists in a library but the vulnerable code path is NOT called by your application
- CVE is in test tooling only (not in production image)
- CVE has been assessed as not exploitable in your specific deployment context

**Process**:
1. Verify the CVE at https://nvd.nist.gov/vuln/detail/CVE-XXXX-XXXXX
2. Confirm the vulnerable function is not called (code review or static analysis)
3. Create or update `.trivyignore` in project root:
   ```
   # CVE-2024-XXXXX
   # Library: libssl 1.1.1k (OpenSSL)
   # Status: False positive — SSL context not used in this service (HTTP only internally)
   # Reviewed by: <name> on 2026-02-26
   # Re-review date: 2026-05-26
   # Reference: https://nvd.nist.gov/vuln/detail/CVE-2024-XXXXX
   CVE-2024-XXXXX
   ```
4. Get peer review on the `.trivyignore` change (at least 1 reviewer)
5. Add a tracking issue: "Re-evaluate CVE-2024-XXXXX suppression by 2026-05-26"

**Mandatory fields in suppression comment**:
- CVE ID
- Affected library/version
- Why it's a false positive
- Reviewer name and date
- Re-review date (max 90 days)

### 2.3 Trivy Cannot Pull Image

**Symptom**: `FATAL unauthorized: access to the requested resource is not authorized`

**Cause**: Harbor credentials not available in runner environment

**Diagnosis**:
```bash
# Check if runner has Harbor credentials
kubectl get secret gitlab-ci-credentials -n staging-platform-gitlab -o yaml

# Verify the ExternalSecret is synced
kubectl get externalsecret gitlab-ci-credentials -n staging-platform-gitlab
```

**Fix**: Ensure the runner `envFrom` is configured correctly in the Helm values:
```yaml
# gitlab-runner values
runners:
  envFrom:
    - secretRef:
        name: gitlab-ci-credentials
```

---

## 3. OWASP Dependency-Check

### 3.1 HIGH/CRITICAL CVE Found in Dependencies

**Symptom**: Job fails with `One or more dependencies were identified with known vulnerabilities`

**Step 1 — Read the HTML report**:
```bash
# Download from GitLab CI: Pipeline → owasp-dependency-check job → Artifacts
# Open: dependency-check-report/dependency-check-report.html
```

The report shows:
- Vulnerable dependency name and version
- CVE ID and CVSS score
- Fix version (if available)
- Evidence that matched the dependency

**Step 2 — Update the dependency**:

For Java/Maven:
```xml
<!-- pom.xml -->
<dependency>
  <groupId>com.example</groupId>
  <artifactId>vulnerable-lib</artifactId>
  <version>2.0.1</version>  <!-- updated from 1.9.0 -->
</dependency>
```

For Node.js:
```bash
npm update vulnerable-package
# or for specific version:
npm install vulnerable-package@3.2.1
npm audit fix  # automated fix for some CVEs
```

For Python:
```bash
pip install --upgrade vulnerable-package
# Update requirements.txt
pip freeze > requirements.txt
```

**Step 3 — Check transitive dependencies**:
Sometimes the vulnerable dep is transitive (not directly in your pom/package.json):
```bash
# Maven: find who depends on vulnerable-lib
mvn dependency:tree | grep vulnerable-lib

# Node: find dependency chain
npm ls vulnerable-package

# Python
pip show vulnerable-package | grep Requires
```

### 3.2 False Positive Suppression (OWASP DC)

**Common false positives**:
- OWASP DC matched the wrong CPE (Common Platform Enumeration)
- CVE is in a different product with similar name
- Dependency is test-only (not in production classpath)

**Process**:
1. Verify the CVE matches your actual dependency (same artifact, same version range)
2. Create or update `dependency-check-suppression.xml` in project root:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <suppressions xmlns="https://jeremylong.github.io/DependencyCheck/dependency-suppression.1.3.xsd">
     <!--
       Suppression: CVE-XXXX-XXXXX
       Library: com.example:mylib:1.9.0
       Reason: False positive — OWASP DC matched wrong CPE. This is mylib not other-lib.
                CVE affects other-lib which has different groupId.
       Reviewed by: <name> on 2026-02-26
       Expiration: 2026-05-26 (mandatory — will re-fail after this date)
     -->
     <suppress until="2026-05-26">
       <notes>
         CVE-XXXX-XXXXX: False positive. This is com.example:mylib, not com.other:mylib.
         OWASP DC matched wrong artifact. NVD link: https://nvd.nist.gov/vuln/detail/CVE-XXXX-XXXXX
         Reviewed by: <name> on 2026-02-26
       </notes>
       <packageUrl regex="true">^pkg:maven/com\.example/mylib@.*$</packageUrl>
       <cve>CVE-XXXX-XXXXX</cve>
     </suppress>
   </suppressions>
   ```
3. The CI template automatically includes this file if it exists:
   ```
   $([ -f dependency-check-suppression.xml ] && echo "--suppression dependency-check-suppression.xml" || echo "")
   ```

### 3.3 Slow First Run (NVD Database Download)

**Symptom**: Job takes 15-20 minutes on first run

**Cause**: OWASP DC downloads the National Vulnerability Database (~200MB) on first run

**Fix**: The GitLab cache is configured to cache `.owasp-cache/data/` between runs.
If cache miss occurs (first run per branch), expect 15-20 min.

**Verify cache is working**:
Check job output for:
```
Restoring cache for key: owasp-nvd-db-<MONTH>
```

If cache is consistently missing:
1. Check GitLab runner cache configuration
2. Ensure GitLab Runner has S3/GCS/Minio cache storage configured

---

## 4. TruffleHog Secret Detection

### 4.1 Verified Secret Found (CRITICAL)

**Symptom**: Job fails with `Found verified result` in output

**IMMEDIATE ACTIONS (within 15 minutes)**:

**Step 1 — Identify the secret**:
```bash
# Download trufflehog-report.json from CI artifacts
cat trufflehog-report.json | jq '.'

# Key fields:
# .DetectorName — type of secret (GitHubToken, AWSKeyID, Slack, etc.)
# .RawV2        — the actual secret value (HANDLE WITH CARE)
# .SourceMetadata.Data.Git.commit — which commit introduced it
# .SourceMetadata.Data.Git.file   — which file
```

**Step 2 — Rotate the secret IMMEDIATELY**:

| Secret Type | Rotation Method |
|---|---|
| AWS Access Key | AWS Console → IAM → Users → Delete key + create new → Update Vault |
| GitHub Token | GitHub → Settings → Developer Settings → Personal Access Tokens → Revoke |
| Slack Token | Slack API → Your Apps → Revoke and regenerate |
| Database Password | Change in DB + update Vault: `vault kv put secret/<path> password=<new>` |
| API Key (SaaS) | Use the SaaS platform's key management to revoke and regenerate |

**Step 3 — Update Vault**:
```bash
# Example: rotating an AWS key found in git
vault kv put secret/myservice/aws \
  access_key_id="NEWKEYID" \
  secret_access_key="NEWSECRET"

# ESO will sync automatically within ~30 seconds
kubectl get externalsecret -A | grep myservice
```

**Step 4 — Clean git history**:
```bash
# Install BFG Repo Cleaner
# https://rtyley.github.io/bfg-repo-cleaner/
java -jar bfg.jar --replace-text passwords.txt <repo.git>

# OR using git-filter-repo (modern alternative)
git filter-repo --path <file-with-secret> --invert-paths

# Clean refs and GC
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# Force-push (coordinate with team — rewrites history)
git push --force-with-lease
```

**Step 5 — Notify security team**:
- Create incident in ticketing system
- Document: what secret, where found, when rotated, what impact assessment

**Step 6 — Prevention**:
- Verify this secret is now managed via Vault + ESO
- Add pre-commit hook to project:
  ```bash
  # .git/hooks/pre-commit
  trufflehog git file://. --since-commit HEAD --only-verified --fail
  ```

### 4.2 False Positive (TruffleHog)

TruffleHog with `--only-verified` has very low false positive rate. If you believe a
finding is false positive:

1. Verify: Can TruffleHog actually authenticate with the reported credential?
2. If yes: The credential IS real. Rotate it (see 4.1).
3. If the value only LOOKS like a secret (test data, placeholder, example):

**Option A: Inline suppression**:
```python
# Example: test fixture that looks like an API key
TEST_API_KEY = "sk_test_abcdefghijklmnopqrstuvwxyz"  # trufflehog:ignore
```

**Option B: `.trufflehogignore` file**:
```
# Regex patterns to ignore (one per line)
# Be specific — don't ignore entire files
sk_test_.*  # Test Stripe keys (non-production prefixed with sk_test_)
```

### 4.3 TruffleHog Scan Depth

By default, TruffleHog scans the last 50 commits (`TRUFFLEHOG_SCAN_DEPTH=50`).
For initial onboarding of legacy projects, scan full history:

```yaml
# In your project .gitlab-ci.yml
trufflehog-secret-scan:
  extends: .trufflehog-secret-scan
  variables:
    TRUFFLEHOG_SCAN_DEPTH: "1000"  # or a very large number for full history
```

---

## 5. Scanner Infrastructure Issues

### 5.1 PushGateway Not Receiving Metrics

**Symptom**: Grafana dashboard shows no data; alerts about metrics missing

**Diagnosis**:
```bash
# Check PushGateway is running
kubectl get pods -n monitoring -l app=prometheus-pushgateway

# Check metrics via port-forward
kubectl port-forward svc/prometheus-pushgateway 9091:9091 -n monitoring
curl http://localhost:9091/metrics | grep gitlab_ci_pipeline_security_scan
```

**Check PUSHGATEWAY_URL in runner**:
The runner must have network access to `prometheus-pushgateway.monitoring.svc:9091`.

```bash
# Test from within the runner namespace
kubectl run -n staging-platform-gitlab --rm -it test-curl \
  --image=curlimages/curl:latest \
  --restart=Never \
  -- curl -s http://prometheus-pushgateway.monitoring.svc:9091/metrics
```

### 5.2 Harbor Network Policy Blocking Scanner

**Symptom**: Trivy can't pull image — connection refused or timeout

**Diagnosis**:
```bash
# Check Network Policies in harbor-system
kubectl get networkpolicies -n harbor-system

# Check if gitlab runner egress to harbor is allowed
kubectl get networkpolicies -n staging-platform-gitlab -o yaml | grep -A5 harbor
```

**Fix**: Ensure the NetworkPolicy in `staging-platform-gitlab` allows egress to `harbor-system`:
```yaml
# The existing GAP-007 NetworkPolicy should cover this
# If not, add egress rule for harbor registry port 443
```

---

## 6. Emergency Bypass Process

**This process is for genuine emergencies only** — e.g., security fix release blocked by
an unrelated false positive in a different part of the codebase.

**Criteria for bypass**:
1. The security finding is confirmed false positive OR in code unrelated to this release
2. A critical security fix or production incident response is blocked
3. Time to fix exceeds incident SLA

**Process**:
1. Platform SRE or Engineering Manager approves in writing (Slack/Jira)
2. Create tracking issue: `[SECURITY-BYPASS] <description>` with SLA: max 5 business days
3. In `.gitlab-ci.yml` override, document the bypass:
   ```yaml
   # Temporary bypass — approved by <name> on <date>
   # Tracking issue: <link>
   # SLA for resolution: <date>
   sonarqube-sast:
     extends: .sonarqube-sast
     allow_failure: true  # TEMPORARY — must not be permanent
   ```
4. The tracking issue must be resolved before the next sprint ends

**This override MUST be reverted before the tracking issue closes.**

---

## Contacts

| Issue | Contact |
|---|---|
| SonarQube access/config | Platform SRE Team |
| Harbor admin | Platform SRE Team |
| Security policy questions | Tech Lead + Platform SRE |
| Secret rotation emergency | On-call SRE (PagerDuty) |
| OWASP suppression approval | Tech Lead |

---

## Related Documentation

- [ADR-081: SAST/DAST Pipeline Enforcement Strategy](../adr/adr-081-sast-dast-pipeline-enforcement.md)
- [Developer Guide: Security Scan Stage](../CICD-001-DEVELOPER-GUIDE.md)
- [SonarQube Quality Gates Documentation](https://docs.sonarqube.org/latest/user-guide/quality-gates/)
- [Trivy Documentation](https://aquasecurity.github.io/trivy/v0.50.0/)
- [BFG Repo Cleaner](https://rtyley.github.io/bfg-repo-cleaner/)
- [OWASP Dependency-Check Suppression](https://jeremylong.github.io/DependencyCheck/general/suppression.html)
- [NVD CVE Database](https://nvd.nist.gov/vuln)

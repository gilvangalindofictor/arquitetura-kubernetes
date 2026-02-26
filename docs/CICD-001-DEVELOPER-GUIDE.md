# Developer Guide: Security Scan Stage (CICD-001)

**Demand**: CICD-001 — SAST/DAST Pipeline Enforcement
**ADR**: [ADR-081](adr/adr-081-sast-dast-pipeline-enforcement.md)
**Runbook**: [Security Scan Failures Troubleshooting](runbooks/security-scan-failures-troubleshooting.md)
**Updated**: 2026-02-26

---

## TL;DR — Minimum Setup

Add these two things to your project's `.gitlab-ci.yml`:

```yaml
# 1. Add the security template include
include:
  - project: 'platform/templates'
    file: '/gitlab-ci/templates/security.gitlab-ci-security-template.yml'

# 2. Add security-scan to your stages list
stages:
  - build
  - test
  - security-scan   # ← ADD THIS
  - deploy
```

That's it. The template handles the rest.

---

## What is CICD-001?

CICD-001 enforces four security scanners that run on every merge request and main branch push.
All four must pass before a pipeline can proceed to `deploy`.

| Scanner | What it checks | Blocks on |
|---|---|---|
| **SonarQube** | Code quality + security (SAST) | Quality Gate ERROR: new bugs, vulnerabilities, low coverage |
| **Trivy** | Container image CVEs | HIGH or CRITICAL vulnerability in image layers |
| **OWASP Dependency-Check** | Library/dependency CVEs | CVSS >= 7.0 in any dependency |
| **TruffleHog** | Secrets in git history | Any verified secret (API key, password, token) |

**Important**: `allow_failure: false` on all scanners. There is no bypass without explicit
approval from Platform SRE or Engineering Manager.

---

## Full Setup Guide

### Step 1 — Update your `.gitlab-ci.yml`

```yaml
# Complete example with security-scan stage
include:
  - project: 'platform/templates'
    file: '/gitlab-ci/templates/security.gitlab-ci-security-template.yml'

stages:
  - build
  - test
  - security-scan
  - deploy

variables:
  DOCKER_IMAGE: "${HARBOR_REGISTRY}/${CI_PROJECT_PATH}:${CI_COMMIT_SHORT_SHA}"
  DOCKER_IMAGE_LATEST: "${HARBOR_REGISTRY}/${CI_PROJECT_PATH}:latest"
  DOCKER_DRIVER: overlay2
  DOCKER_TLS_CERTDIR: ""

default:
  tags:
    - kubernetes

# ── Your existing build/test/deploy jobs ──────────────────────────────────────
build:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
  before_script:
    - docker login "${HARBOR_REGISTRY}" -u "${HARBOR_USER}" -p "${HARBOR_PASSWORD}"
  script:
    - docker build -t "${DOCKER_IMAGE}" -t "${DOCKER_IMAGE_LATEST}" .
    - docker push "${DOCKER_IMAGE}"
    - docker push "${DOCKER_IMAGE_LATEST}"
  after_script:
    - docker logout "${HARBOR_REGISTRY}"

test:
  stage: test
  image: "${DOCKER_IMAGE}"
  script:
    - echo "Run your tests here"

deploy:
  stage: deploy
  image: argoproj/argocd:v2.10.0
  variables:
    ARGOCD_SERVER: "argocd.staging.internal"
    ARGOCD_OPTS: "--grpc-web --insecure"
  script:
    - argocd app sync "${CI_PROJECT_NAME}" --auth-token "${ARGOCD_TOKEN}" --server "${ARGOCD_SERVER}" ${ARGOCD_OPTS}
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
      when: on_success
    - when: never

# ── Security scan stage is provided by the template ───────────────────────────
# The include above automatically adds:
#   - sonarqube-sast
#   - trivy-container-scan
#   - owasp-dependency-check
#   - trufflehog-secret-scan
```

### Step 2 — Create `sonar-project.properties` (Optional but recommended)

```properties
# sonar-project.properties
# Place in project root for fine-grained SonarQube configuration

sonar.projectKey=mygroup-myproject
sonar.projectName=My Project
sonar.sources=src
sonar.tests=test,src/test
sonar.exclusions=**/node_modules/**,**/vendor/**,**/*.test.js,**/migrations/**
sonar.test.inclusions=**/*.test.js,**/*.spec.ts,**/test/**
sonar.coverage.exclusions=**/migrations/**,**/seeds/**

# For Java/Maven: specify compiled classes
# sonar.java.binaries=target/classes
# sonar.java.test.binaries=target/test-classes

# For Python
# sonar.python.coverage.reportPaths=coverage.xml
```

### Step 3 — Configure Scanner Variables (Optional)

Override default scanner behavior per project via GitLab CI/CD Variables
(Settings → CI/CD → Variables):

| Variable | Default | Description |
|---|---|---|
| `TRIVY_SEVERITY` | `HIGH,CRITICAL` | Change to `CRITICAL` to only block on critical CVEs |
| `TRIVY_EXIT_CODE` | `1` | Set to `0` to report but not block (not recommended) |
| `TRUFFLEHOG_SCAN_DEPTH` | `50` | Number of commits to scan back |
| `DEPENDENCY_CHECK_OPTS` | `` | Extra OWASP DC flags (e.g., `--suppression file.xml`) |
| `PUSHGATEWAY_URL` | `http://prometheus-pushgateway.monitoring.svc:9091` | Metrics endpoint |

### Step 4 — Add Suppression Files (if needed)

For initial onboarding, you may have pre-existing issues that need suppression.
Use the scanner-specific suppression mechanism:

**Trivy** — create `.trivyignore` in project root:
```
# CVE-2023-XXXXX: In libssl, but code doesn't use SSL (HTTP only)
# Reviewed: <name>, 2026-02-26. Re-review: 2026-05-26
CVE-2023-XXXXX
```

**OWASP Dependency-Check** — create `dependency-check-suppression.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<suppressions xmlns="https://jeremylong.github.io/DependencyCheck/dependency-suppression.1.3.xsd">
  <suppress until="2026-05-26">
    <notes>False positive: OWASP matched wrong artifact. Reviewed by <name>.</notes>
    <cve>CVE-XXXX-XXXXX</cve>
  </suppress>
</suppressions>
```

**SonarQube** — mark issues in the SonarQube UI (not via files).

**TruffleHog** — add `# trufflehog:ignore` inline comment on the flagged line.

---

## Understanding the Pipeline Flow

```
Push / MR Created
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ build                                                    │
│   docker build → harbor push                            │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ test                                                     │
│   unit tests, integration tests                         │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ security-scan  (ALL must pass — parallel execution)      │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │ sonarqube-sast       → Quality Gate check (SAST)   │ │
│  │ trivy-container-scan → CVE scan on Docker image    │ │
│  │ owasp-dependency-check → Library CVE scan          │ │
│  │ trufflehog-secret-scan → Git secret detection      │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  All 4 must have status=PASSED                          │
│  Metrics → PushGateway → Grafana dashboard              │
└─────────────────────────────────────────────────────────┘
      │
      ▼ (only if branch == main)
┌─────────────────────────────────────────────────────────┐
│ deploy                                                   │
│   ArgoCD sync                                           │
└─────────────────────────────────────────────────────────┘
```

The four security scan jobs run in **parallel** — the stage completes when ALL pass.
This typically adds 3-8 minutes to your pipeline (after the NVD database is cached).

---

## Interpreting Scan Results

### SonarQube

**Where to look**: Job output contains a URL to the SonarQube project dashboard.

```
INFO: Analysis report uploaded in 2,345ms, id=AXxxxxxxxxxxxxxx
INFO: QUALITY GATE STATUS: FAILED
INFO: Quality gate failure: New Vulnerabilities is greater than 0
```

Click the SonarQube link from the job output, or:
`http://sonarqube.staging.internal/dashboard?id=<CI_PROJECT_PATH_SLUG>`

**Reading the quality gate**:
- Green circle = condition passed
- Red circle = condition failed (blocks pipeline)
- Click any condition for details and code links

### Trivy

**Where to look**: `trivy-report.txt` in pipeline artifacts.

```
╔══════════╤══════════════╤══════════╤═══════════╤════════════════╗
║ Library  │ Vulnerability│ Severity │ Installed │ Fixed Version  ║
╠══════════╪══════════════╪══════════╪═══════════╪════════════════╣
║ libssl   │ CVE-2024-... │ CRITICAL │ 1.1.1k   │ 1.1.1n        ║
╚══════════╧══════════════╧══════════╧═══════════╧════════════════╝
```

**Action**: Update your base image to get the fixed version.

### OWASP Dependency-Check

**Where to look**: `dependency-check-report/dependency-check-report.html` in pipeline artifacts.
Open this file in a browser — it's a rich HTML report.

The report shows:
- Vulnerable dependency (name, version, ecosystem)
- CVE ID, CVSS score, description
- Evidence (what in your code matched)
- Suggested action (update to version X)

### TruffleHog

**Where to look**: `trufflehog-report.json` in pipeline artifacts and job output.

```json
{
  "DetectorName": "AWSKeyID",
  "Raw": "AKIAIOSFODNN7EXAMPLE",
  "RawV2": "AKIAIOSFODNN7EXAMPLE:wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
  "SourceMetadata": {
    "Data": {
      "Git": {
        "commit": "abc1234",
        "file": "src/config/settings.py",
        "line": 42
      }
    }
  }
}
```

**If you see this**: This is a CRITICAL finding. Rotate the secret IMMEDIATELY.
See runbook: [Secret Detected](runbooks/security-scan-failures-troubleshooting.md#41-verified-secret-found-critical)

---

## Frequently Asked Questions

**Q: My pipeline was green before CICD-001 adoption. Now it fails. What do I do?**

A: The existing codebase may have pre-existing issues that the scanners now surface.
This is expected. Follow these steps:
1. Run the scanners and get the full report
2. Fix what can be fixed quickly (dependency updates, base image bumps)
3. For pre-existing issues that can't be fixed immediately: use suppression mechanisms
   with a tracking issue for resolution
4. Contact Platform SRE for help prioritizing

**Q: SonarQube says my code coverage is below 80%. How do I fix this?**

A: The 80% threshold applies to NEW code only (code changed in this PR), not existing code.
- Write unit tests for the new functions/classes you added
- SonarQube shows exactly which lines are uncovered: see "Coverage" tab in project

**Q: The OWASP scan takes 20 minutes on first run. This is too slow.**

A: First run downloads the NVD database (~200MB). Subsequent runs use the GitLab cache
and take ~30 seconds. Ensure cache is configured:
```yaml
cache:
  key: "owasp-nvd-db-${CI_COMMIT_MONTH}"
  paths:
    - .owasp-cache/data/
```

**Q: TruffleHog flagged a test API key in our test fixtures. How do I suppress it?**

A: Add `# trufflehog:ignore` to the line, OR use a `.trufflehogignore` pattern:
```
# .trufflehogignore
sk_test_.*    # Stripe test keys (non-production prefix)
EXAMPLE.*     # Example/placeholder values in documentation
```

**Q: Can I skip the security-scan stage for a hotfix?**

A: Only with explicit Platform SRE or Engineering Manager approval. See
[Emergency Bypass Process](runbooks/security-scan-failures-troubleshooting.md#6-emergency-bypass-process).
Even then, there is a 5-business-day SLA to resolve the bypass.

**Q: Can I run scans locally before pushing?**

A: Yes! Install the scanners locally:

```bash
# Trivy (macOS)
brew install trivy
trivy image --severity HIGH,CRITICAL myapp:local

# TruffleHog
curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh
trufflehog git file://. --since-commit HEAD --only-verified

# OWASP (requires Java)
curl -L -o dc.sh https://jeremylong.github.io/DependencyCheck/install.sh
bash dc.sh --install
dependency-check.sh --scan . --failOnCVSS 7

# SonarQube
# Download sonar-scanner-cli and run:
sonar-scanner \
  -Dsonar.host.url=http://sonarqube.staging.internal \
  -Dsonar.token=<your-token> \
  -Dsonar.projectKey=<project-key>
```

**Q: How do I see scan results for all my projects in one place?**

A: Use the Grafana dashboard:
`https://grafana.internal/d/cicd001-security-scans`

Filter by project, scanner, or time range to see trends, duration, and pass/fail history.

---

## Advanced Configuration

### Override a scanner's behavior

```yaml
# In your project .gitlab-ci.yml
# Example: extend Trivy to only block on CRITICAL (not HIGH)
trivy-container-scan:
  extends: .trivy-container-scan
  variables:
    TRIVY_SEVERITY: "CRITICAL"  # Override: only CRITICAL blocks

# Example: extend OWASP to use a custom NVD API key (faster updates)
owasp-dependency-check:
  extends: .owasp-dependency-check
  variables:
    DEPENDENCY_CHECK_OPTS: "--nvdApiKey ${NVD_API_KEY}"
```

### Add language-specific SonarQube configuration

```yaml
# Example: Maven project with compiled sources
sonarqube-sast:
  extends: .sonarqube-sast
  before_script:
    - SCAN_START_TS=$(date +%s%N)
    - SCANNER_NAME="sonarqube"
    - apk add --no-cache bc curl openjdk17 maven
    - mvn compile test   # generate .class files and coverage report
  variables:
    SONAR_EXTRA_PROPS: >-
      -Dsonar.java.binaries=target/classes
      -Dsonar.java.test.binaries=target/test-classes
      -Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml
```

### Scan only on specific branches

The default template scans on:
- Merge request events
- `main` branch
- `master`, `release/*`, `hotfix/*` branches

To add more branches or restrict:
```yaml
sonarqube-sast:
  extends: .sonarqube-sast
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      when: always
    - if: '$CI_COMMIT_BRANCH == "main"'
      when: always
    - if: '$CI_COMMIT_BRANCH =~ /^develop$/'
      when: always
    - when: never
```

---

## Metrics and Observability

After each pipeline, scan metrics are pushed to Prometheus PushGateway and visible in:

**Grafana Dashboard**: `https://grafana.internal/d/cicd001-security-scans`

Available metrics per scanner and project:
- `gitlab_ci_pipeline_security_scan_duration_seconds` — how long each scan took
- `gitlab_ci_pipeline_security_scan_status` — 1=pass, 0=fail

These feed the platform-level alerts:
- SonarQubeQualityGateFailed (critical → PagerDuty)
- TruffleHogSecretDetected (critical → PagerDuty)
- PipelineSecurityScanFailed (warning → Slack)

---

## Getting Help

| Need | Contact |
|---|---|
| Understanding a scanner finding | #platform-engineering Slack |
| Suppression approval | Platform SRE Team |
| Emergency bypass | Platform SRE + Engineering Manager |
| SonarQube access issues | Platform SRE Team |
| Scanner configuration help | Platform SRE Team |

**Slack channel**: `#platform-engineering`
**Runbook**: [Security Scan Failures Troubleshooting](runbooks/security-scan-failures-troubleshooting.md)

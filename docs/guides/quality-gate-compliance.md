# Quality Gate Compliance Guide

**Demand**: CICD-002 — SonarQube Quality Gate Enforcement Policy
**ADR**: [ADR-082](../adr/adr-082-sonarqube-quality-gate-policy.md)
**Date**: 2026-02-26

---

## Quick Summary

Every merge request on the platform must pass the **Production quality gate** in SonarQube.
If your pipeline fails at the `sonarqube-quality-gate` job, this guide explains:

1. What the gate requires
2. How to read the failure message
3. How to fix each type of failure
4. How to handle false positives
5. How to request a temporary exemption

---

## Quality Gate Requirements

The "Production" gate checks **new code only** (code you added in your MR). Your MR must pass:

| Condition | Threshold | What it means |
|-----------|-----------|----------------|
| New Code Coverage | >= 80% | At least 80% of your new code must be covered by tests |
| New Bugs | = 0 | No logic errors in your new code |
| New Vulnerabilities | = 0 | No security vulnerabilities in your new code |
| New Code Smells | <= 10 | No more than 10 maintainability issues in your new code |
| Security Hotspots Reviewed | >= 80% | At least 80% of security-sensitive code patterns reviewed |

**All conditions are blocking**: a single failing condition blocks the merge.

---

## How to Find the Failure Reason

### Option 1: GitLab CI job output

In your pipeline, click the `sonarqube-quality-gate` job. The output includes:

```
[QUALITY-GATE] BLOCKED: Quality Gate 'ERROR'

  The 'Production' quality gate has FAILED for this MR.
  Merge is BLOCKED until all gate conditions pass.

  SonarQube Dashboard:
  http://sonarqube.staging.internal/dashboard?id=<your-project>
```

### Option 2: SonarQube dashboard

Access: `http://sonarqube.staging.internal/dashboard?id=<your-project-key>`

- Click the **"Overall Code"** tab to see total metrics
- Click the **"New Code"** tab to see metrics for your MR specifically
- The **Quality Gate** widget shows which conditions are red

### Option 3: Artifact

Download the `SonarQube Quality Gate Results` artifact from the pipeline job.
The file `quality-gate-results/quality-gate-status.json` contains the full status.

---

## Fixing Each Failure Type

### 1. Coverage < 80%

**Symptom**: `sonarqube_project_code_coverage_percent < 80`

**What it means**: Your new code has less than 80% test coverage. SonarQube measures line and
branch coverage. If you added 100 lines of code, at least 80 lines must be executed by tests.

**How to fix**:

```bash
# Step 1: Run your tests with coverage enabled

# Python (pytest + pytest-cov)
pytest --cov=src --cov-report=xml --cov-report=term-missing
# Coverage XML: coverage/coverage.xml

# Node.js / TypeScript (jest)
jest --coverage --coverageReporters=lcov,text
# Coverage: coverage/lcov.info

# Java (Maven + JaCoCo)
mvn test jacoco:report
# Coverage: target/site/jacoco/jacoco.xml

# Go
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out  # open in browser
# Coverage: coverage.out
```

```bash
# Step 2: Identify uncovered lines
# In SonarQube UI: New Code tab → Coverage → click on the percentage
# Uncovered lines are highlighted in red on the source view
```

```bash
# Step 3: Add missing tests
# Focus on:
# - New functions/methods you added
# - Error handling branches (catch blocks, error returns)
# - Edge cases (empty list, null input, boundary values)
```

```bash
# Step 4: Upload coverage to SonarQube
# In your .gitlab-ci.yml, set:
variables:
  SONAR_COVERAGE_REPORT: "coverage/coverage.xml"  # adjust to your path
```

**Common mistakes**:
- Not running tests before pushing: run `pytest` or `npm test` locally first
- Coverage report path wrong: check `SONAR_COVERAGE_REPORT` variable points to existing file
- Mocking everything: mocked code doesn't count as tested — test the real code path

---

### 2. New Bugs > 0

**Symptom**: `sonarqube_project_bugs_total > 0`

**What it means**: SonarQube detected a logic error in your new code. Bugs are reliability issues
with high confidence — SonarQube only flags bugs when it can prove a code path is incorrect.

**How to find**:

```
SonarQube → Your Project → Issues → Filter: Type=Bug, Status=Open, Scope=New Code
```

**Common bug types and fixes**:

```python
# BUG: NullPointerException risk
user = get_user(id)
print(user.name)  # user can be None!

# FIX: Check for None
user = get_user(id)
if user is not None:
    print(user.name)
```

```java
// BUG: Resource not closed
FileReader fr = new FileReader(file);
String content = fr.read(); // FileReader never closed if exception occurs

// FIX: Use try-with-resources
try (FileReader fr = new FileReader(file)) {
    String content = fr.read();
}
```

```javascript
// BUG: equals() vs == confusion (Java)
// SonarQube detects language-specific patterns

// BUG: Using Math.random() for security
const token = Math.random().toString(36);  // Not cryptographically secure

// FIX: Use crypto
const token = require('crypto').randomBytes(32).toString('hex');
```

**For genuine false positives** (SonarQube is wrong about a bug):

1. Click on the issue in SonarQube
2. Click "Won't Fix"
3. Add a comment: `False Positive: This cannot be null because [reason]. Reviewed by [name] on [date].`
4. Get a peer to agree before marking as FP

---

### 3. New Vulnerabilities > 0

**Symptom**: `sonarqube_project_vulnerabilities_total > 0`

**Severity**: CRITICAL — vulnerabilities may be exploitable by attackers.

**How to find**:

```
SonarQube → Your Project → Issues → Filter: Type=Vulnerability, Status=Open, Scope=New Code
```

**Common vulnerability types**:

```python
# VULNERABILITY: SQL Injection
query = f"SELECT * FROM users WHERE name = '{user_input}'"
cursor.execute(query)

# FIX: Parameterized queries
query = "SELECT * FROM users WHERE name = %s"
cursor.execute(query, (user_input,))
```

```javascript
// VULNERABILITY: XSS - rendering untrusted input as HTML
element.innerHTML = userInput;

// FIX: Use textContent for text, or sanitize HTML
element.textContent = userInput;
// OR for rich text: import DOMPurify; element.innerHTML = DOMPurify.sanitize(userInput);
```

```python
# VULNERABILITY: Hardcoded credential
DB_PASSWORD = "admin123"  # Never hardcode passwords!

# FIX: Use environment variable or Vault
import os
DB_PASSWORD = os.environ.get('DB_PASSWORD')
```

```python
# VULNERABILITY: Weak cryptography
import hashlib
password_hash = hashlib.md5(password.encode()).hexdigest()  # MD5 is broken!

# FIX: Use bcrypt, argon2, or scrypt
import bcrypt
password_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt())
```

**For false positives on vulnerabilities**:

- Before marking as FP, you must be **certain** the code is not exploitable
- Add a detailed explanation in the SonarQube comment
- Get Platform SRE review (`#platform-sre` Slack channel)
- SonarQube FP must include: why the vulnerable code path is not reachable or not exploitable

---

### 4. Code Smells > 10

**Symptom**: `sonarqube_project_code_smells_total > 10`

**What it means**: Your MR introduced more than 10 maintainability issues. Code smells don't cause
bugs immediately, but make the code harder to understand, modify, and test over time.

**How to find**:

```
SonarQube → Your Project → Issues → Filter: Type=Code Smell, Status=Open, Scope=New Code
```

**Common code smells and fixes**:

```python
# SMELL: Method too long (>100 lines)
def process_order(order):
    # ... 150 lines of code ...
    pass

# FIX: Extract sub-functions
def process_order(order):
    validate_order(order)
    calculate_totals(order)
    apply_discounts(order)
    send_confirmation(order)
```

```python
# SMELL: Magic numbers
if retries > 3:
    time.sleep(5)

# FIX: Named constants
MAX_RETRIES = 3
RETRY_DELAY_SECONDS = 5
if retries > MAX_RETRIES:
    time.sleep(RETRY_DELAY_SECONDS)
```

```python
# SMELL: Duplicate code block
# Same logic in process_payment() and process_refund()

# FIX: Extract shared function
def _calculate_amount(order, multiplier=1):
    return order.subtotal * multiplier
```

```python
# SMELL: Cognitive complexity too high
def check_user(user):
    if user:
        if user.active:
            if user.email:
                if user.email.verified:
                    return True
    return False

# FIX: Early returns (guard clauses)
def check_user(user):
    if not user or not user.active:
        return False
    if not user.email or not user.email.verified:
        return False
    return True
```

**Strategy if you have too many smells**:

- Sort by "Debt" in SonarQube (shows estimated fix time)
- Fix the highest-effort ones first (they're usually the most impactful)
- Break large PRs into smaller ones — each PR has a fresh smell count
- If touching legacy code with many smells: only fix smells in lines **you changed**

---

### 5. Security Hotspots Reviewed < 80%

**Symptom**: `new_security_hotspots_reviewed < 80`

**What it means**: Your code contains security-sensitive patterns that need human review.
Hotspots are NOT necessarily vulnerabilities — they require human judgment to determine if
they're safe in context.

**How to review hotspots**:

1. Go to: `SonarQube → Your Project → Security Hotspots`
2. Click "Review" on each hotspot
3. Read the "What's the risk?" and "Are you protected?" sections
4. If the code is safe: click "Safe" with a comment explaining why
5. If it's a real risk: click "Acknowledged" and fix it

**Common hotspot categories**:

```python
# HOTSPOT: Use of pseudorandom number generator
import random
session_id = random.randint(10000, 99999)
# SonarQube flags this: random is predictable for security contexts

# Review: Is this for security? YES → VULNERABILITY, use secrets.randbelow()
# Review: Is this for non-security use (e.g., load balancing)? → SAFE, comment why
```

```python
# HOTSPOT: Command execution
subprocess.run(cmd, shell=True)
# SonarQube flags this: shell=True can lead to injection

# Review: Is cmd from user input? YES → FIX (use shell=False with list)
# Review: Is cmd hardcoded/controlled? → SAFE, comment why
```

```python
# HOTSPOT: Hardcoded IP address
server = "192.168.1.100"
# SonarQube flags this: may be a hardcoded production address

# Review: Is this a test/local IP? → SAFE, add comment
# Review: Is this a real production IP? → VULNERABILITY, use config
```

**Marking a hotspot as "Safe"**:

```
Comment format:
Safe: This uses [context]. Not a security risk because [reason].
The input is [controlled/validated/hardcoded] and cannot be influenced by external parties.
Reviewed by: [your name], [date].
```

---

## Handling False Positives

### What is a false positive?

SonarQube raised an issue that, after careful review, is determined to NOT be a real problem
in your specific context.

### Process for false positives

**DO NOT just mark as FP to unblock your pipeline.** False positives require:

1. **Understand the issue**: Read SonarQube's "Why is this an issue?" section carefully
2. **Verify it's not a real issue**: Trace the code path — is the vulnerability actually reachable?
3. **Document your reasoning**: Click "Won't Fix" or "False Positive"
4. **Add a detailed comment**:
   ```
   False Positive: [Concise explanation]

   Reason: [Specific technical reason why this is not a real issue in our context]
   Evidence: [Code path analysis or test case that proves it's safe]
   Reviewed by: [Your name] on [date]
   Peer review: [Colleague name] confirmed on [date]
   ```
5. **Get peer review**: Another developer should agree with your assessment
6. **For vulnerabilities**: Get Platform SRE review before marking as FP

### Fast-track false positive cases

Some patterns are known false positives in our stack:

| Pattern | Reason | Action |
|---------|--------|--------|
| `Math.random()` in test code | Not security-sensitive context | Mark as FP with comment "Test code only" |
| `subprocess.run(cmd)` with hardcoded cmd | Controlled input | Mark as FP with "cmd is hardcoded, not user-controlled" |
| SQL with ORM-generated queries | ORM handles parameterization | Mark as FP with "Generated by SQLAlchemy ORM" |

---

## Requesting a Temporary Exemption

### When is an exemption appropriate?

- **Large legacy codebase** with < 80% coverage that cannot be fixed in one sprint
- **Critical hotfix** that must be deployed immediately (5-day max)
- **Third-party code** being integrated with known smells that cannot be modified

### When is exemption NOT appropriate?

- You don't want to write tests
- The fix is difficult but not impossible
- You want to merge before the end of sprint to "clean up later"

### Exemption process

1. **Open an issue** in the project:
   ```
   Title: [QUALITY-GATE-EXEMPTION] Project X needs coverage exemption

   Body:
   - Current coverage: XX%
   - Gate requirement: 80%
   - Reason: [Technical reason why coverage cannot be increased now]
   - Plan to fix: [Concrete plan with tasks and timeline]
   - SLA: [Date by which coverage will reach 80%]
   - Approved by: [Tech Lead name]
   ```

2. **Get approval** from Tech Lead (coverage/smells) or Platform SRE (bugs/vulnerabilities)

3. **Set CI/CD variables** in GitLab project settings (Settings → CI/CD → Variables):
   ```
   SONAR_QUALITY_GATE_BYPASS = true
   SONAR_BYPASS_REASON = "Issue #123: Legacy coverage <80%, plan to fix by 2026-03-15"
   ```

4. **Track resolution**: Issue must be resolved by the SLA date
   - Reviewer will follow up on issue progress
   - Variable will be removed after SLA

### Exemption SLAs

| Issue type | Max duration |
|-----------|-------------|
| Coverage exemption | 30 days |
| Code smell exemption | 30 days |
| Bug exemption | 5 business days |
| Vulnerability exemption | Not allowed (must fix) |

---

## Local SonarQube Scanning

Run SonarQube analysis locally to catch issues before pushing:

### Prerequisites

```bash
# Install sonar-scanner
# macOS
brew install sonar-scanner

# Linux
wget https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-5.0.1.3006-linux.zip
unzip sonar-scanner-cli-*.zip -d ~/.local
export PATH="$PATH:$HOME/.local/sonar-scanner-*/bin"
```

### Run local scan

```bash
# Port-forward to SonarQube (cluster must be UP)
kubectl port-forward svc/sonarqube 9000:9000 -n sonarqube &

# Set your token (generate in SonarQube UI → My Account → Security → Tokens)
export SONAR_TOKEN="squ_..."

# Run scan
sonar-scanner \
  -Dsonar.host.url=http://localhost:9000 \
  -Dsonar.token="${SONAR_TOKEN}" \
  -Dsonar.projectKey=my-project-key \
  -Dsonar.projectName="My Project" \
  -Dsonar.sources=. \
  -Dsonar.qualitygate.wait=true \
  -Dsonar.qualitygate.timeout=120
```

### sonar-project.properties (recommended)

Create `sonar-project.properties` in your project root to avoid repeating flags:

```properties
# sonar-project.properties
sonar.projectKey=platform-my-service
sonar.projectName=Platform My Service
sonar.sources=src
sonar.tests=tests
sonar.exclusions=**/__pycache__/**,**/node_modules/**,**/vendor/**

# Python
sonar.python.coverage.reportPaths=coverage/coverage.xml

# Node/TypeScript
# sonar.javascript.lcov.reportPaths=coverage/lcov.info

# Java
# sonar.java.binaries=target/classes
# sonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml
```

Then run:
```bash
sonar-scanner -Dsonar.host.url=http://localhost:9000 -Dsonar.token="${SONAR_TOKEN}"
```

---

## Including the Template in Your Project

### Minimal setup (2 lines)

Add to your `.gitlab-ci.yml`:

```yaml
include:
  - project: 'platform/templates'
    file: '/gitlab-ci/templates/sonarqube-quality-gate.gitlab-ci.yml'

stages:
  - build
  - test
  - quality-gate   # template adds job here
  - deploy
```

### Full setup with coverage

```yaml
include:
  - project: 'platform/templates'
    file: '/gitlab-ci/templates/sonarqube-quality-gate.gitlab-ci.yml'

stages:
  - build
  - test
  - quality-gate
  - deploy

# Override the template to add coverage report
sonarqube-quality-gate:
  extends: .sonarqube-quality-gate
  variables:
    SONAR_COVERAGE_REPORT: "coverage/coverage.xml"
    SONAR_EXTRA_PROPS: "-Dsonar.exclusions=**/migrations/**,**/vendor/**"
  # Make it depend on your test job so coverage report exists
  needs:
    - job: test
      artifacts: true
```

### Running tests and generating coverage in your test job

```yaml
# Python example
test:
  stage: test
  image: python:3.11
  script:
    - pip install -r requirements-dev.txt
    - pytest --cov=src --cov-report=xml:coverage/coverage.xml --cov-report=term-missing
  artifacts:
    paths:
      - coverage/
    expire_in: 1 day
```

---

## Frequently Asked Questions

**Q: My pipeline worked last week but now the quality gate fails. What changed?**

A: New code you added in this PR failed the gate. The gate only evaluates **new code** since your
branch diverged from main. Check the "New Code" tab in SonarQube.

**Q: I only changed a README file. Why is the quality gate running?**

A: The template runs on all MRs, main, and release branches. For documentation-only changes,
you can add a rule to skip:
```yaml
sonarqube-quality-gate:
  extends: .sonarqube-quality-gate
  rules:
    - changes:
        - "**/*.py"
        - "**/*.ts"
        - "**/*.java"
      when: always
    - when: never
```

**Q: My coverage report is generated but SonarQube still shows 0% coverage. Why?**

A: The coverage report path is wrong. Check:
1. Does the file exist? Run `ls coverage/coverage.xml` in your CI job
2. Is the path correct in `SONAR_COVERAGE_REPORT`?
3. Is the format correct? SonarQube accepts XML (JaCoCo, Cobertura), lcov, and Go coverage

**Q: SonarQube flagged a bug in code I didn't touch. Why?**

A: The gate measures **New Code** which is code added since the branch was created from main.
If someone added that code in a previous commit on your branch, it's "new code" for this MR.
Fix or mark as FP.

**Q: My tech lead approved the false positive but I can't find the "Won't Fix" button.**

A: You need at least "Browse" permission on the project. Ask your project admin to grant access.

**Q: The scan is taking > 10 minutes. Is something wrong?**

A: Increase the timeout:
```yaml
sonarqube-quality-gate:
  extends: .sonarqube-quality-gate
  variables:
    SONAR_TIMEOUT: "600"  # 10 minutes
```

If it consistently takes > 5 minutes, open a ticket with Platform SRE — it may indicate
SonarQube is under-resourced.

**Q: I need to deploy a critical hotfix RIGHT NOW. Can I bypass the gate?**

A: Yes, with approval. Contact Platform SRE (`#platform-sre`). They will set the bypass variable.
You MUST create a follow-up issue with SLA <= 5 business days.

**Q: Can I set different thresholds for my project (e.g., 60% coverage)?**

A: Not unilaterally. You need to go through the formal exemption process (see above).
Permanent per-project thresholds are not supported in the current implementation.
If your project genuinely requires different thresholds, raise a request to Platform SRE
with business justification.

---

## Reference

| Resource | Location |
|----------|----------|
| SonarQube Dashboard | http://sonarqube.staging.internal |
| Quality Gate API Script | scripts/sonarqube/configure-quality-gate.sh |
| GitLab CI Template | domains/cicd-platform/infra/gitlab-ci/templates/sonarqube-quality-gate.gitlab-ci.yml |
| PrometheusRules | domains/observability/infra/alerts/sonarqube-quality-gate-prometheus-rules.yaml |
| Grafana Dashboard | monitoring/grafana/dashboards/cicd-quality-gate-trends.json |
| ADR-082 | docs/adr/adr-082-sonarqube-quality-gate-policy.md |
| ADR-081 (CICD-001) | docs/adr/adr-081-sast-dast-pipeline-enforcement.md |
| Security Scan Troubleshooting | docs/runbooks/security-scan-failures-troubleshooting.md |

**Contact**: Platform SRE Team — `#platform-sre` (Slack) or via GitLab issue

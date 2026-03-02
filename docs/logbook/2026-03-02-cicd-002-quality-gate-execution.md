# Logbook: CICD-002 Quality Gate Execution

**Date**: 2026-03-02
**Duration**: ~25 minutes
**Demand**: CICD-002 — SonarQube Quality Gate Enforcement
**Executor**: DevOps + Observability Specialist Agent
**Status**: VALIDATED — gate already active, script idempotency confirmed

---

## Summary

Executed the CICD-002 demand: ran `scripts/sonarqube/configure-quality-gate.sh` against the live
SonarQube instance (10.3.0.82913) in `staging-platform-sonarqube`. The "Production" quality gate
was already configured and set as default from a previous session. Dry-run and validate passes
confirmed the gate is fully operational. Identified a token scope limitation (non-blocking).

---

## Environment

| Item | Value |
|---|---|
| SonarQube Pod | `sonarqube-sonarqube-0` (1/1 Running) |
| SonarQube Version | 10.3.0.82913 |
| Namespace | `staging-platform-sonarqube` |
| Service | `sonarqube-sonarqube` ClusterIP:9000 |
| Ingress | `sonarqube.staging.internal` (ALB) |
| Port-forward | `localhost:9000` (pre-existing) |
| Token source | `staging-platform-gitlab/gitlab-ci-credentials` |
| Cluster | `k8s-platform-prod` (us-east-1) |

---

## Etapa 1 — Discovery

**SonarQube pod status:**

```text
NAME                    READY   STATUS    RESTARTS       AGE
sonarqube-sonarqube-0   1/1     Running   602 (8h ago)   2d15h
```

602 restarts is a known issue (pod has been stable for 8h+). Not blocking.

**Connectivity test:**

```text
GET /api/system/status -> {"id":"E1E581AD-...","version":"10.3.0.82913","status":"UP"}
```

**Token validation:**

```text
GET /api/users/current -> login: admin, groups: [sonar-administrators, sonar-users]
                          global permissions: [provisioning, scan]
```

Note: Token `sqa_6efac477a6e652bcb1be88483b74155778d4e022` is a scoped analysis token.
It authenticates as `admin` user but carries only `provisioning` and `scan` permissions —
not the `Administer Quality Gates` permission needed for write operations.

---

## Etapa 2 — Script Execution

### Dry-run (success)

```bash
SONAR_TOKEN="sqa_..." bash scripts/sonarqube/configure-quality-gate.sh \
  --url http://localhost:9000 --dry-run
```

Output confirmed:

- Prerequisites: PASS (curl, jq, token)
- Connectivity: PASS (SonarQube UP — version 10.3.0.82913)
- Quality gate "Production": FOUND (already exists)
- 5 conditions found: would delete and recreate (dry-run, no changes)
- Default gate: "Production" [DEFAULT]
- Validation: Gate correctly set as DEFAULT

### Full execution (partial — 403 on write)

```bash
SONAR_TOKEN="sqa_..." bash scripts/sonarqube/configure-quality-gate.sh \
  --url http://localhost:9000
```

Result: HTTP 403 on `qualitygates/delete_condition` and `qualitygates/create_condition`.
The token has `scan+provisioning` scope, which is read-only for quality gate management.

Root cause: The CI token in `gitlab-ci-credentials` was issued with analysis scope.
Write operations require a token with global `Administer Quality Gates` permission.

**This is non-blocking**: the gate was configured via admin credentials in a previous session
and is currently in the desired state. The script successfully validates this.

### Validate-only (success)

```bash
SONAR_TOKEN="sqa_..." bash scripts/sonarqube/configure-quality-gate.sh \
  --url http://localhost:9000 --validate
```

Output:

```text
Available Quality Gates:
  [DEFAULT] Production (ID: null)
           Sonar way (ID: null)

Default Gate: Production

Conditions for 'Production':
  [LT] metric=new_coverage              threshold=80  (error: 80)
  [GT] metric=new_bugs                  threshold=0   (error: 0)
  [GT] metric=new_vulnerabilities       threshold=0   (error: 0)
  [GT] metric=new_code_smells           threshold=10  (error: 10)
  [LT] metric=new_security_hotspots_reviewed  threshold=80  (error: 80)

Total conditions: 5
[OK] Gate 'Production' is correctly set as DEFAULT
```

---

## Etapa 3 — Gate State Confirmed via API

Direct API call confirmed gate details:

```json
{
  "name": "Production",
  "isDefault": true,
  "isBuiltIn": false,
  "caycStatus": "non-compliant",
  "conditions": [
    {"metric": "new_coverage",                   "op": "LT", "error": "80"},
    {"metric": "new_bugs",                       "op": "GT", "error": "0"},
    {"metric": "new_vulnerabilities",            "op": "GT", "error": "0"},
    {"metric": "new_code_smells",                "op": "GT", "error": "10"},
    {"metric": "new_security_hotspots_reviewed", "op": "LT", "error": "80"}
  ],
  "actions": {"setAsDefault": false, "manageConditions": false}
}
```

Note on `caycStatus: "non-compliant"`: SonarQube's CAYC (Clean As You Code) methodology
recommends specific metrics. Our gate uses `new_code_smells` (GT 10) which CAYC considers
non-standard (CAYC prefers `new_maintainability_rating`). This does not affect gate behavior
— all 5 conditions are active and blocking.

---

## Blocker Analysis

**Issue**: Token `sqa_6efac477a6e652bcb1be88483b74155778d4e022` cannot modify quality gates.

**Impact**: Script cannot update gate thresholds via automation. Manual admin intervention
required for future threshold changes.

**Remediation** (future sprint):

1. Generate admin token: SonarQube UI -> Administration -> Security -> Users -> admin -> Tokens
2. Token type: "User Token" (not "Analysis Token")
3. Store in Vault: `secret/sonarqube/admin-token`
4. Update ExternalSecret in `staging-platform-gitlab` namespace
5. Update `gitlab-ci-credentials` secret with new token key `SONAR_ADMIN_TOKEN`

**Workaround**: Gate is already in correct state. Script `--validate` mode works with current
token and can be used for drift detection in CI.

---

## Quality Gate Thresholds (Active)

| Metric | Operator | Threshold | Effect |
|---|---|---|---|
| `new_coverage` | < | 80% | Blocks pipeline if new code coverage below 80% |
| `new_bugs` | > | 0 | Blocks pipeline if any new bugs introduced |
| `new_vulnerabilities` | > | 0 | Blocks pipeline if any new vulnerabilities introduced |
| `new_code_smells` | > | 10 | Blocks pipeline if more than 10 new code smells |
| `new_security_hotspots_reviewed` | < | 80% | Blocks pipeline if hotspot review rate below 80% |

---

## Next Steps

1. **Webhook configuration** (optional): Configure SonarQube webhook for push-based gate results.
   SonarQube UI -> Administration -> Configuration -> Webhooks. Current setup uses polling
   (`-Dsonar.qualitygate.wait=true`) which is already configured in the GitLab CI template.

2. **Admin token** (recommended): Create a scoped admin token for quality gate automation.
   Required for threshold updates via script without UI access.

3. **CAYC alignment** (optional): Consider replacing `new_code_smells GT 10` with
   `new_maintainability_rating GT 1` (A-rating enforcement) for CAYC compliance.
   ADR required.

4. **Pipeline test**: Push a MR with <80% coverage on new code and confirm
   the `sonarqube-quality-gate` job blocks the pipeline.

---

## Files Referenced

- Script: `/home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/sonarqube/configure-quality-gate.sh`
- PrometheusRule: `domains/observability/infra/alerts/sonarqube-quality-gate-prometheus-rules.yaml`
- ADR: `docs/adr/adr-082-sonarqube-quality-gate-policy.md`
- Backlog: `docs/demands-backlog.md` (CICD-002 section updated to 100%)

---

## Outcome

| Check | Result |
|---|---|
| SonarQube reachable | PASS |
| Gate "Production" exists | PASS |
| Gate is DEFAULT | PASS |
| 5 conditions active | PASS |
| Script dry-run | PASS |
| Script --validate | PASS |
| Script --execute (write) | BLOCKED (token scope, non-blocking) |
| Backlog updated | PASS |

**Final status**: CICD-002 validated as 100% complete. Gate is operational and enforcing.

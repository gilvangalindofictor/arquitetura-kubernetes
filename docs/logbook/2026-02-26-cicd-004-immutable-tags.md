# Logbook: CICD-004 Immutable Image Tags Enforcement

**Date**: 2026-02-26
**Type**: Security + CI/CD Enhancement
**Status**: READY FOR DEPLOYMENT (environment offline)
**Duration**: Preparation phase (artifacts created, deployment pending cluster startup)
**Demand**: CICD-004
**Related**: ADR-084, ADR-070 (Network Policies), ADR-077 (ApplicationSets GitOps)

---

## Summary

Prepared all artifacts for immutable image tag enforcement across the K8s Platform Harbor registry. The change introduces a three-tier tagging strategy (`sha-*` immutable, `v*` immutable, `env` mutable) and configures Harbor API rules to enforce immutability at the registry layer.

**Deliverables**:
- Harbor API automation script with dry-run mode
- GitLab CI template implementing three-tier tagging strategy
- Complete pipeline example with dev/staging/release flows
- ADR-084 documenting architecture decisions and trade-offs
- Developer guide with good/bad examples and FAQ
- Updated `build.gitlab-ci.yml` with deprecation notice

---

## Context

### Problem Statement

The existing CI/CD pipeline (GAP-002/005) uses two image tags:
- `${CI_COMMIT_SHORT_SHA}` — short SHA but MUTABLE (Harbor allows overwrites)
- `latest` — always mutable

This creates a supply chain risk: any pipeline run for the same commit would overwrite the previously pushed image. ArgoCD rollbacks reference tags that could have been silently replaced.

### Why Now (Post-Marco-4)

Marco 4 is 100% complete (all 8 GAPs done). The CI/CD pipeline is fully operational. Implementing immutability now:

1. Adds a security layer before production readiness
2. Establishes the tagging pattern that Production will inherit
3. Requires no downtime (Harbor rules are additive — existing images are unaffected)
4. Aligns with the security remediation sprint (V-001 through V-008 complete)

---

## Implementation

### Architecture Decision (ADR-084)

Three-tier tagging model chosen over alternatives:

| Alternative | Why Rejected |
|-------------|-------------|
| OCI Cosign signing | Higher complexity, key management overhead; can be added as Phase 2 |
| Registry proxy webhook | Harbor native immutability is simpler and already available |
| Digest-only deployments | ArgoCD integration simpler with human-readable sha-* tags |

The three-tier model balances security (immutable production references) with developer ergonomics (mutable dev/staging shortcuts).

### Harbor Script (`scripts/harbor/configure-immutability.sh`)

**Design decisions**:
- Dry-run mode (`--dry-run`) as default safety: run in offline environments for preview
- Idempotent: checks for existing rules before creating (safe to re-run)
- Per-project targeting: `--project platform-apps` for surgical application
- Full error handling with colored output and exit codes
- Retention policy: weekly schedule, last-10 for dev/staging, last-5 for feature branches

**Harbor API endpoints used**:
```
GET  /api/v2.0/projects?name=<project>
POST /api/v2.0/projects (create if missing)
GET  /api/v2.0/projects/{id}/immutabletagrules
POST /api/v2.0/projects/{id}/immutabletagrules
POST /api/v2.0/retentions
GET  /api/v2.0/systeminfo
```

**Immutability rules per project** (platform-apps, microservices, infrastructure):
- `sha-*` → IMMUTABLE
- `v*` → IMMUTABLE
- `release-*` → IMMUTABLE
- `latest` → IMMUTABLE

**Retention policy** (weekly, Sunday):
- `dev*` → keep last 10
- `staging*` → keep last 10
- `feature-*` → keep last 5

### GitLab CI Template (`build-immutable.gitlab-ci.yml`)

**Key design decisions**:
- Single build with multiple `docker tag` calls (avoids rebuilding identical image)
- CI-side production guard: pipeline fails if `CI_ENVIRONMENT_NAME=production` is set
- Harbor-side enforcement: independent of CI, registry rejects immutability violations
- `build.env` artifact: passes `IMAGE_SHA_TAG`, `IMAGE_DIGEST`, `GIT_COMMIT` to deploy stage
- OCI labels on every image: `git.commit`, `git.ref`, `build.pipeline`, `build.job`, `build.timestamp`

**Three hidden jobs provided**:
- `.build-immutable` — base job, full strategy
- `.build-release` — convenience for semver-only pipelines
- `.build-dev` / `.build-staging` — convenience for branch-specific pipelines

### Tag Lifecycle

```
Feature branch push:
  CI creates: sha-a1b2c3d + dev-feature-auth
  Harbor allows: both (new sha-*, mutable dev tag)

Main branch push:
  CI creates: sha-b2c3d4e + staging
  Harbor allows: both (new sha-*, mutable staging tag)

git tag v1.2.3:
  CI creates: sha-b2c3d4e + v1.2.3
  Harbor allows: both (new sha-*, new v* tag)

Re-run same commit pipeline:
  CI attempts: sha-b2c3d4e (already exists)
  Harbor blocks: HTTP 412 (immutable tag violation)
  CI behavior: build.env artifact with existing tag still usable
```

---

## Files Created

| File | Type | Purpose |
|------|------|---------|
| `scripts/harbor/configure-immutability.sh` | Shell script | Apply Harbor immutability rules via API |
| `domains/cicd-platform/infra/gitlab-ci/templates/build-immutable.gitlab-ci.yml` | GitLab CI | Three-tier tagging CI template |
| `domains/cicd-platform/infra/gitlab-ci/examples/immutable-tags.gitlab-ci.yml` | GitLab CI | Complete pipeline example |
| `docs/adr/adr-084-immutable-image-tags-enforcement.md` | ADR | Architecture decision record |
| `docs/guides/image-tagging-best-practices.md` | Guide | Developer onboarding + FAQ |
| `docs/logbook/2026-02-26-cicd-004-immutable-tags.md` | Logbook | This file |

## Files Modified

| File | Change |
|------|--------|
| `domains/cicd-platform/infra/gitlab-ci/templates/build.gitlab-ci.yml` | Added deprecation notice pointing to build-immutable template |

---

## Deployment Instructions

### Prerequisites

```bash
# 1. Start cluster (environment offline — startup required)
./scripts/finops/startup-marco2.sh

# 2. Authenticate
aws sso login --profile k8s-platform-staging
kubectl cluster-info

# 3. Retrieve Harbor admin credentials (V-004 complete — ESO-managed)
export HARBOR_PASS=$(kubectl get secret harbor-admin-credentials \
  -n harbor-system \
  -o jsonpath='{.data.password}' | base64 -d)

# 4. Verify Harbor is accessible
curl -s -u "admin:${HARBOR_PASS}" \
  https://harbor.staging.internal/api/v2.0/systeminfo | jq '.harbor_version'
```

### Step 1: Dry-Run Verification

```bash
# Preview all changes without applying
./scripts/harbor/configure-immutability.sh --dry-run

# Expected output:
# [DRY] Would create project: platform-apps (private, auto-scan enabled)
# [DRY] Would POST /projects/1/immutabletagrules — tag: sha-*
# [DRY] Would POST /projects/1/immutabletagrules — tag: v*
# [DRY] Would POST /projects/1/immutabletagrules — tag: release-*
# [DRY] Would POST /projects/1/immutabletagrules — tag: latest
# [DRY] Would configure retention policy for: platform-apps
# ...
# Status: SUCCESS
```

### Step 2: Apply Rules

```bash
# Apply to all projects
HARBOR_PASS="${HARBOR_PASS}" \
./scripts/harbor/configure-immutability.sh

# Expected: Rules created for platform-apps, microservices, infrastructure
# Expected: Retention policies configured (weekly Sunday cleanup)
```

### Step 3: Verify in Harbor UI

```bash
# Open Harbor UI
# Navigate: https://harbor.staging.internal
# Login: admin (Keycloak SSO)
# Go to: microservices project > Configuration > Tag Immutability
# Verify: sha-*, v*, release-*, latest rules are listed and enabled
```

### Step 4: Test Enforcement

```bash
# Test immutable tag (should succeed first time, fail second time)
docker login harbor.staging.internal -u admin -p "${HARBOR_PASS}"

docker pull alpine:latest
docker tag alpine:latest harbor.staging.internal/microservices/test:sha-test001

# First push — expect 201 OK
docker push harbor.staging.internal/microservices/test:sha-test001

# Second push — expect 412 Precondition Failed (immutable)
docker push harbor.staging.internal/microservices/test:sha-test001

# Mutable tag — expect both pushes to succeed
docker tag alpine:latest harbor.staging.internal/microservices/test:staging
docker push harbor.staging.internal/microservices/test:staging
docker push harbor.staging.internal/microservices/test:staging  # should succeed
```

### Step 5: Migrate Existing Pipelines (Week 1 — Team Action)

```yaml
# BEFORE (build.gitlab-ci.yml — DEPRECATED)
build:
  extends: .build

# AFTER (build-immutable.gitlab-ci.yml)
build-staging:
  extends: .build-immutable
  variables:
    HARBOR_PROJECT: "microservices"
    CI_ENVIRONMENT_NAME: "staging"
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
```

---

## Validation Checklist

### Day 1

- [ ] Cluster started and healthy
- [ ] `configure-immutability.sh --dry-run` exits 0
- [ ] `configure-immutability.sh` applies rules (3 projects × 4 rules = 12 rules)
- [ ] Harbor UI shows rules in all 3 projects
- [ ] Test: second push of sha-* tag → HTTP 412
- [ ] Test: second push of staging tag → HTTP 201

### Week 1

- [ ] At least one project pipeline migrated to `build-immutable.gitlab-ci.yml`
- [ ] `build.env` artifact produced with correct `IMAGE_SHA_TAG`
- [ ] ArgoCD deploy stage consumes `IMAGE_SHA_TAG` from artifact
- [ ] Developer guide reviewed by at least one dev team member

### Month 1

- [ ] All platform projects on immutable template
- [ ] Harbor retention policy executed once (Sunday)
- [ ] Zero immutability violation incidents
- [ ] ADR-084 CTO review completed

---

## Known Issues and Mitigations

### Issue 1: Pipeline Re-run Fails on sha-* Push

**Symptom**: Re-running a CI pipeline for the same commit fails with "The tag is immutable".

**Cause**: Expected behavior. The sha-* tag was created on the first run and is now protected.

**Mitigation**: The CI template creates `build.env` before failing on the push attempt. A future improvement would be to detect the existing tag and skip the push gracefully (treating the existing tag as success).

**Workaround**: Use the `IMAGE_SHA_TAG` from the first run's artifact. Re-run only the deploy stage using `needs` with the first run's artifacts.

### Issue 2: Harbor API Not Accessible During Dry-Run

**Symptom**: `--dry-run` flag is useful precisely when the cluster is offline.

**Design**: The script intentionally skips connectivity checks in dry-run mode. All Harbor API calls are replaced with `[DRY] Would...` log messages.

### Issue 3: Retention Policy API Endpoint

**Note**: The retention policy endpoint (`/api/v2.0/retentions`) requires Harbor admin permissions. The script uses the same `HARBOR_PASS` credential as other operations. If the API returns 403, verify that the user has admin role in Harbor.

---

## Cost Impact

**Zero additional infrastructure cost.** All changes are:
- Configuration-only (Harbor immutability rules)
- Template updates (GitLab CI YAML)
- Documentation

**Security value**: Prevents supply chain attacks via tag overwrite. Estimated incident cost avoided: $400+ per incident (6-8 hour investigation + remediation).

---

## Next Steps

| Action | Owner | Timeline |
|--------|-------|----------|
| Deploy script to staging cluster | Platform Team | 2026-02-27 (cluster restart) |
| Migrate 1st project pipeline | Dev Team (platform-apps) | 2026-03-03 |
| Migrate all project pipelines | All teams | 2026-03-10 |
| CTO ADR-084 review | CTO | 2026-02-27 |
| Phase 2: Cosign image signing | Platform Team | Q2 2026 |

---

## References

- **ADR-084**: `docs/adr/adr-084-immutable-image-tags-enforcement.md`
- **Script**: `scripts/harbor/configure-immutability.sh`
- **CI Template**: `domains/cicd-platform/infra/gitlab-ci/templates/build-immutable.gitlab-ci.yml`
- **CI Example**: `domains/cicd-platform/infra/gitlab-ci/examples/immutable-tags.gitlab-ci.yml`
- **Developer Guide**: `docs/guides/image-tagging-best-practices.md`
- **Harbor Immutability Docs**: https://goharbor.io/docs/2.0.0/working-with-projects/project-configuration/configure-tag-immutability/

---

**Status**: READY FOR DEPLOYMENT
**Estimated Deployment Time**: 20 minutes (post cluster startup)
**Risk Level**: LOW (additive configuration, no existing resources modified)
**Rollback Plan**: Delete immutability rules via Harbor UI or API (takes effect immediately)

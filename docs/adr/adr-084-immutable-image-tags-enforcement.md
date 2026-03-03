# ADR-084: Immutable Image Tags Enforcement Policy

**Date**: 2026-02-26
**Status**: ACCEPTED & DEPLOYED (2026-03-02)
**Decision Maker**: Platform Architecture + CTO
**Related ADRs**: ADR-004 (Terraform vs Helm), ADR-070 (Network Policies), ADR-077 (ApplicationSets GitOps)
**Demand**: CICD-004
**Deploy Date**: 2026-03-02 — 12 immutability rules + 3 retention policies active in Harbor v2.10.0

---

## Context

### Background

The K8s Platform CI/CD stack (Marco 4) is operational with GitLab CI/CD, Harbor registry, and ArgoCD GitOps fully integrated. As of 2026-02-25, all 8 GAPs are complete and the pipeline is end-to-end functional.

The current build template (`build.gitlab-ci.yml`) uses two tags:
- `${CI_COMMIT_SHORT_SHA}` — short SHA (mutable, can be overwritten)
- `latest` — always mutable

This creates two critical risks:

**Risk 1: Supply Chain Attack Vector**
An attacker (or misconfigured pipeline) can overwrite an existing image tag. If ArgoCD references `latest` or even a specific short SHA that was overwritten, the deployed image is no longer verifiable.

**Risk 2: Audit Gap**
When an incident occurs, there is no guarantee that the image tag referenced in a K8s Deployment matches the image that was originally pushed. Overwritten tags destroy the audit chain.

**Risk 3: Rollback Unreliability**
Rolling back to a previous deployment (e.g., ArgoCD rollback to sha-abc123) is unsafe if that tag was already overwritten by a subsequent build.

### Current State (Pre-CICD-004)

| Tag | Mutability | Risk |
|-----|-----------|------|
| `${CI_COMMIT_SHORT_SHA}` | Mutable (no Harbor rule) | Medium |
| `latest` | Always mutable | High |
| Release tags (`v1.2.3`) | Mutable (no Harbor rule) | High |

### Harbor Capability

Harbor 2.x provides native immutability rules via the `/api/v2.0/projects/{project}/immutabletagrules` endpoint. When a rule is active, Harbor returns HTTP 412 (Precondition Failed) if a client attempts to push an image with a tag that already exists in the registry.

This enforcement happens at the registry layer — independent of CI/CD pipeline configuration — providing defense in depth.

---

## Decision

**ACCEPT: Implement Immutable Image Tag Enforcement (CICD-004)**

Enforce immutable image tags in Harbor registry for all platform projects, combined with a standardized three-tier tagging strategy in GitLab CI pipelines.

---

## Tagging Strategy

### Three-Tier Model

```
PRIMARY   sha-$CI_COMMIT_SHORT_SHA   IMMUTABLE  Always created
SECONDARY v$CI_COMMIT_TAG            IMMUTABLE  Created on git tags only
ENVIRONMENT $CI_ENVIRONMENT_NAME     MUTABLE    dev/staging only
```

### Tier 1: Primary Tag — `sha-$CI_COMMIT_SHORT_SHA`

**Format**: `sha-a1b2c3d`
**When created**: Every pipeline run, every branch
**Mutability**: IMMUTABLE (Harbor rule enforces)
**Use**: GitOps deployments via ArgoCD ApplicationSets

This tag is the source of truth for deployments. ArgoCD ApplicationSets reference this tag to ensure the deployed image is exactly what CI built for a specific commit.

**Example**:
```
harbor.staging.internal/microservices/my-app:sha-a1b2c3d
```

The `sha-` prefix is intentional: it prevents Harbor from confusing SHA tags with other tag patterns and makes the immutability rule selector unambiguous (`sha-*`).

### Tier 2: Secondary Tag — `v$CI_COMMIT_TAG`

**Format**: `v1.2.3`, `v1.2.3-rc1`
**When created**: Only when pipeline is triggered by a git tag matching semver
**Mutability**: IMMUTABLE (Harbor rule enforces)
**Use**: Production releases, changelog references, rollback targets

This tag provides a human-readable, semantically versioned alias for a specific SHA. It is always a re-tag of the primary SHA image — never a separate build.

**Example**:
```
harbor.staging.internal/microservices/my-app:v1.2.3
  → same digest as sha-a1b2c3d
```

### Tier 3: Environment Tag — `$CI_ENVIRONMENT_NAME`

**Format**: `dev`, `staging`, `dev-feature-auth`, `staging-hotfix-123`
**When created**: Only when `CI_ENVIRONMENT_NAME` is set
**Mutability**: MUTABLE for dev/* and staging/* (Harbor exception rule)
**Blocked**: Harbor BLOCKS environment tags in production projects

This tag provides a human-readable shortcut for the current state of an environment. It is intentionally mutable — teams expect `staging` to always point to the latest main branch image.

**IMPORTANT**: ArgoCD deployments MUST NOT reference environment tags. They are for human inspection only (e.g., `docker pull harbor.staging.internal/microservices/my-app:staging`).

---

## Harbor Immutability Rules

### Rule Configuration Per Project

Applied to projects: `platform-apps`, `microservices`, `infrastructure`

| Tag Pattern | Harbor Rule | Effect |
|-------------|-------------|--------|
| `sha-*` | IMMUTABLE | Cannot overwrite any SHA tag after first push |
| `v*` | IMMUTABLE | Cannot overwrite any semver release tag |
| `release-*` | IMMUTABLE | Cannot overwrite any release candidate tag |
| `latest` | IMMUTABLE | `latest` is blocked entirely (exception: first push) |

### Exception Patterns (Mutable)

Tags matching these patterns are allowed to be overwritten:

| Tag Pattern | Mutable | Purpose |
|-------------|---------|---------|
| `dev*` | YES | Development environment shortcut |
| `staging*` | YES | Staging environment shortcut |
| `feature-*` | YES | Feature branch shortcut (cleanup via retention) |
| `hotfix-*` | YES | Hotfix branch shortcut |

### Harbor API Enforcement

When a CI pipeline attempts to overwrite an immutable tag, Harbor returns:

```
HTTP/1.1 412 Precondition Failed
{
  "errors": [{
    "code": "PRECONDITION_FAILED",
    "message": "The tag is immutable."
  }]
}
```

The pipeline fails with a clear error message, preventing the overwrite.

---

## Tag Retention Policy

Development and staging tags accumulate over time. To prevent registry bloat:

| Tag Pattern | Retention | Schedule |
|-------------|-----------|----------|
| `dev*` | Last 10 pushed | Weekly (Sunday) |
| `staging*` | Last 10 pushed | Weekly (Sunday) |
| `feature-*` | Last 5 pushed | Weekly (Sunday) |

**Note**: Immutable tags (`sha-*`, `v*`) are NOT subject to retention policies — they are permanent references. Teams should manually delete old SHA tags if storage becomes a concern.

---

## Implementation

### Artifacts

| Artifact | Path | Purpose |
|---------|------|---------|
| Harbor API script | `scripts/harbor/configure-immutability.sh` | Apply rules to all projects |
| CI template | `domains/cicd-platform/infra/gitlab-ci/templates/build-immutable.gitlab-ci.yml` | Three-tier tagging strategy |
| Complete example | `domains/cicd-platform/infra/gitlab-ci/examples/immutable-tags.gitlab-ci.yml` | Full pipeline reference |
| Developer guide | `docs/guides/image-tagging-best-practices.md` | Team onboarding |

### Deployment Sequence

```
1. Apply Harbor rules (offline prep — done)
   scripts/harbor/configure-immutability.sh --dry-run
   scripts/harbor/configure-immutability.sh

2. Migrate existing pipelines (gradual)
   Replace .build extends with .build-immutable

3. Verify enforcement
   Push same sha-* tag twice → expect HTTP 412
   Push dev tag twice → should succeed (mutable)

4. Update ArgoCD ApplicationSets
   Reference sha-${CI_COMMIT_SHORT_SHA} in image.tag parameter
```

### Credentials

The script requires Harbor admin credentials stored in Vault (already available from V-004):

```bash
# Retrieve from ESO-managed secret (harbor-admin-credentials)
HARBOR_PASS=$(kubectl get secret harbor-admin-credentials \
  -n harbor-system \
  -o jsonpath='{.data.password}' | base64 -d)

# Apply rules
HARBOR_PASS="${HARBOR_PASS}" \
./scripts/harbor/configure-immutability.sh
```

Vault path: `secret/harbor/admin` (existing, V-004 compliant)

---

## Consequences

### Positive

**Security**:
- Prevents supply chain attacks via tag overwrite
- Ensures deployed images are cryptographically verifiable via digest
- Audit trail: every deployment maps 1:1 to a specific git commit

**Reliability**:
- ArgoCD rollbacks are guaranteed to restore the exact previous image
- No risk of "same tag, different image" incidents in production
- Retention policies prevent registry storage bloat

**Operational**:
- `sha-*` tags enable precise incident attribution (git blame equivalent for images)
- `v*` tags provide human-readable release history in Harbor UI
- Environment tags (`staging`) remain convenient for manual inspection

### Negative / Trade-offs

**Build complexity increased**:
- Three tag variants per build (vs two previously)
- Pipelines must handle `CI_COMMIT_TAG` conditional logic
- Mitigation: `.build-immutable` hidden job abstracts complexity

**First-push constraint**:
- If a SHA tag already exists (rare, but possible if pipeline is re-triggered for same commit), the push will fail with HTTP 412
- Mitigation: CI template should use `--force` equivalent only for `latest` in dev environments; SHA tags must never be forced

**Migration effort**:
- Existing projects using `build.gitlab-ci.yml` must migrate to `build-immutable.gitlab-ci.yml`
- Mitigation: Old template is marked deprecated with migration note; backward compatible

### Risk Acceptance

| Risk | Mitigation |
|------|-----------|
| Team confusion about mutable vs immutable tags | Developer guide + clear CI output messages |
| Pipeline failure when re-running job for same commit | Document expected behavior; SHA tags are designed to be write-once |
| Harbor API downtime blocking pushes | Harbor HA (2 replicas) mitigates; immutability rules are cached by Harbor |
| Accidental `latest` push blocked by Harbor | Update all pipelines before enabling `latest` immutability |

---

## Alternatives Considered

### A: OCI Image Signing (Cosign/Notary)

**Description**: Sign images with Cosign and verify signatures at deploy time (Kyverno policy).

**Rejected because**:
- Higher implementation complexity (key management, Kyverno ClusterPolicy)
- Does not prevent overwrite — only detects unsigned images
- ADR-084 + Cosign could be combined in a future iteration (Phase 2)
- Current maturity level does not require signing

### B: Registry Proxy with Admission Controller

**Description**: Intercept registry pushes via a webhook, reject overwrites.

**Rejected because**:
- Harbor native immutability achieves the same goal without additional components
- Lower operational overhead using Harbor's built-in feature

### C: Digest-only Deployments (No Tags)

**Description**: Remove tags entirely; all deployments reference image digest (`@sha256:...`).

**Rejected because**:
- ArgoCD ApplicationSets and GitLab CI integration is simpler with human-readable tags
- Digest-only references cannot be scanned for CVEs by Harbor without tag context
- Hybrid approach (sha-* tags with digest in artifacts) achieves security goals

---

## Validation Criteria

### Day 1 (After Harbor Rules Applied) — 2026-03-02 COMPLETO

- [x] `scripts/harbor/configure-immutability.sh --dry-run` exits 0
- [x] Rules applied to all 3 projects (via Bearer token OIDC — script basic auth incompatible with OIDC mode)
- [x] Harbor API confirmed 12 immutability rules active (4 per project x 3 projects)
- [ ] Test: `docker push sha-abc1234` (first push) — HTTP 201 (pending e2e)
- [ ] Test: `docker push sha-abc1234` (second push) — HTTP 412 (pending e2e)
- [ ] Test: `docker push staging` (second push) — HTTP 201 (pending e2e)

**Blockers resolved during execution (4)**:

1. CoreDNS namespace drift: keycloak rewrite pointed to wrong namespace
2. Harbor OIDC token missing `sub` claim: added `basic` scope to harbor KC client
3. Harbor OIDC token missing `aud=harbor`: added oidc-audience-mapper to harbor KC client
4. Harbor admin without OIDC user record: inserted testadmin mapping in Harbor DB

### Week 1 (After Pipeline Migration) — PENDING

- [ ] At least one project migrated to `build-immutable.gitlab-ci.yml`
- [ ] Artifacts `build.env` produced with `IMAGE_SHA_TAG` and `IMAGE_DIGEST`
- [ ] ArgoCD deploy stage consumes `IMAGE_SHA_TAG` from artifact
- [ ] No pipeline failures due to accidental immutability violations

### Month 1 (Full Adoption) — PENDING

- [ ] All platform projects using `build-immutable.gitlab-ci.yml`
- [ ] Retention policy executed at least once (Harbor weekly schedule)
- [ ] Zero immutability violation incidents reported
- [ ] Developer guide reviewed and approved by team

---

## Metrics

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Pipelines using immutable tags | 100% | GitLab CI template usage audit |
| Immutability violations blocked | 0 (violations occur, blocked = good) | Harbor audit log |
| Registry storage growth | <5% monthly | Harbor project quota monitoring |
| Deployment traceability | 100% of deployments have sha-* reference | ArgoCD application history |

---

## Related Documentation

- **Script**: `scripts/harbor/configure-immutability.sh`
- **CI Template**: `domains/cicd-platform/infra/gitlab-ci/templates/build-immutable.gitlab-ci.yml`
- **CI Example**: `domains/cicd-platform/infra/gitlab-ci/examples/immutable-tags.gitlab-ci.yml`
- **Developer Guide**: `docs/guides/image-tagging-best-practices.md`
- **Logbook**: `docs/logbook/2026-02-26-cicd-004-immutable-tags.md`
- **Harbor API Docs**: https://harbor.io/docs/2.0.0/working-with-projects/project-configuration/configure-tag-immutability/

---

## Approval Status

- ACCEPTED: Platform Architecture (2026-02-26)
- ACCEPTED: CTO Review (2026-03-02)
- DEPLOYED: 2026-03-02 — 12 rules + 3 retention policies active

---

## OIDC Auth Chain (Resolved 2026-03-02)

Harbor runs in `oidc_auth` mode with Keycloak as identity provider.
The CICD-004 execution required resolving the full OIDC chain:

```text
Keycloak (staging-platform-keycloak)
  └── Realm: platform
      └── Client: harbor
          ├── Scope: basic (sub claim)
          ├── Mapper: oidc-audience-mapper (aud=harbor)
          └── Token endpoint: /auth/realms/platform/protocol/openid-connect/token
              └── Bearer token → Harbor API v2.0
                  └── testadmin (sysadmin=true, oidc_user mapped)
                      └── 12 immutability rules + 3 retention policies
```

**Key discovery**: `configure-immutability.sh` uses basic auth which is incompatible with
Harbor OIDC mode. All write operations executed via Bearer token directly. Script needs
update to support OIDC auth (non-blocking, tracked in pendentes).

---

**Decision Finalized**: 2026-02-26
**Deployed**: 2026-03-02 — 3 projects, 12 immutability rules, 3 retention policies
**Migration Deadline**: 2026-03-10 (all pipelines migrated to immutable template)
**Logbook**: `docs/logbook/2026-03-02-cicd-004-immutable-tags-execution.md`

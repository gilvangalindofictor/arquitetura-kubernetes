# Image Tagging Best Practices — K8s Platform

**Version**: 1.0
**Date**: 2026-02-26
**Audience**: Development Teams, Platform Engineers
**Status**: Active (enforced by Harbor immutability rules — CICD-004)

---

## Quick Reference

```
GOOD  sha-a1b2c3d    Primary tag — immutable, always use for deployments
GOOD  v1.2.3         Semver release — immutable, production-ready
GOOD  staging        Environment shortcut — mutable, development only
BAD   latest         Never use in production (blocked by Harbor)
BAD   mybranch       Unstructured tags are blocked in production projects
```

---

## Overview

The K8s Platform enforces immutable image tags through Harbor registry rules (CICD-004). This guide explains the tagging strategy, what is allowed and blocked, and how to use the CI/CD templates correctly.

Immutable tags ensure that:
1. Every deployed image can be traced to a specific git commit
2. Images cannot be silently replaced after deployment
3. ArgoCD rollbacks restore the exact previous image state
4. Supply chain integrity is preserved end-to-end

---

## The Three-Tier Tagging Strategy

### Tier 1: Primary Tag — `sha-<short-commit>` (IMMUTABLE)

**Format**: `sha-` prefix followed by the 8-character git short SHA.

```
harbor.staging.internal/microservices/payment-api:sha-a1b2c3d
```

**Rules**:
- Created by CI on every pipeline run, for every branch
- IMMUTABLE: Harbor blocks any second push of the same tag
- This is the ONLY tag that ArgoCD should reference for deployments
- Never push this tag manually — always let CI create it

**Why `sha-` prefix?**
Without the prefix, Harbor cannot distinguish a SHA tag from a branch name. The prefix also makes the immutability rule selector unambiguous: `sha-*` in Harbor's pattern language.

**Usage in ArgoCD**:
```yaml
# ApplicationSet image parameter
- name: image.tag
  value: "sha-{{ .Values.gitCommitShortSha }}"
```

```yaml
# Kustomize overlay
images:
  - name: my-app
    newName: harbor.staging.internal/microservices/my-app
    newTag: sha-a1b2c3d
```

---

### Tier 2: Secondary Tag — `v<semver>` (IMMUTABLE)

**Format**: `v` prefix followed by semantic version.

```
harbor.staging.internal/microservices/payment-api:v1.2.3
harbor.staging.internal/microservices/payment-api:v1.2.3-rc1
harbor.staging.internal/microservices/payment-api:v2.0.0-beta.1
```

**Rules**:
- Created by CI ONLY when the pipeline is triggered by a git tag
- IMMUTABLE: Harbor blocks re-pushing the same version tag
- Must follow semver format: `vMAJOR.MINOR.PATCH[-prerelease]`
- This tag points to the same image digest as the corresponding `sha-*` tag

**When to use**:
- Production releases
- Release notes and changelog references
- Docker pull commands in runbooks (human-readable)

**How to create a release**:
```bash
# Tag the commit
git tag v1.2.3
git push origin v1.2.3

# CI automatically creates:
#   sha-a1b2c3d  (primary, always present)
#   v1.2.3       (secondary, release)
```

---

### Tier 3: Environment Tag — `dev` / `staging` / `feature-*` (MUTABLE)

**Format**: Environment name, optionally with branch suffix.

```
harbor.staging.internal/microservices/payment-api:dev
harbor.staging.internal/microservices/payment-api:staging
harbor.staging.internal/microservices/payment-api:dev-main
harbor.staging.internal/microservices/payment-api:staging-feature-auth
harbor.staging.internal/microservices/payment-api:feature-checkout
```

**Rules**:
- MUTABLE: CI overwrites this tag on every push to the branch (intentional)
- Allowed patterns: `dev*`, `staging*`, `feature-*`, `hotfix-*`
- Harbor BLOCKS environment tags in production repositories
- DO NOT reference environment tags in ArgoCD or Kubernetes manifests

**Purpose**:
These tags are shortcuts for humans — they answer "what is currently deployed to staging?". They are NOT for automation. Use `sha-*` tags in all automated tooling.

```bash
# OK: Inspect the current staging image
docker pull harbor.staging.internal/microservices/payment-api:staging

# WRONG: Reference staging tag in a Kubernetes deployment
image: harbor.staging.internal/microservices/payment-api:staging  # NEVER DO THIS
```

---

## Good vs Bad Examples

### GOOD: Immutable Production Reference

```yaml
# Kubernetes Deployment
spec:
  containers:
    - name: payment-api
      image: harbor.staging.internal/microservices/payment-api:sha-a1b2c3d
```

```bash
# Docker pull for debugging
docker pull harbor.staging.internal/microservices/payment-api:sha-a1b2c3d
docker pull harbor.staging.internal/microservices/payment-api:v1.2.3
```

```yaml
# ArgoCD sync with immutable tag
argocd app sync payment-api --force
# ArgoCD reads the image tag from Git (sha-a1b2c3d) — immutable in Harbor
```

---

### ACCEPTABLE: Mutable Development Tags

```bash
# Local development: use environment tag to pull "current staging"
docker pull harbor.staging.internal/microservices/payment-api:staging

# Feature branch testing: use dev tag
docker pull harbor.staging.internal/microservices/payment-api:dev-feature-auth
```

```yaml
# CI job for integration testing (ephemeral, not a deployment)
test:
  image: harbor.staging.internal/microservices/payment-api:staging
  script:
    - run-integration-tests.sh
```

---

### BAD: Never Use These Patterns

```yaml
# BLOCKED by Harbor in production:
image: harbor.staging.internal/microservices/payment-api:latest

# BLOCKED by CI template (production environment guard):
CI_ENVIRONMENT_NAME: "production"  # → pipeline fails before push

# BLOCKED by Harbor (immutability violation after first push):
# docker push sha-a1b2c3d (second push of same tag) → HTTP 412

# WRONG: Mutable tag in production Deployment:
image: harbor.staging.internal/microservices/payment-api:staging  # NEVER IN PROD
image: harbor.staging.internal/microservices/payment-api:dev      # NEVER IN PROD
```

---

## Using the CI Templates

### Standard Build (All Projects)

Add to your `.gitlab-ci.yml`:

```yaml
include:
  - project: 'platform/templates'
    file: '/gitlab-ci/templates/build-immutable.gitlab-ci.yml'

stages:
  - build
  - test
  - deploy

# Feature branch build (creates sha-* and dev tag)
build-dev:
  extends: .build-immutable
  variables:
    HARBOR_PROJECT: "microservices"
    CI_ENVIRONMENT_NAME: "dev"
  rules:
    - if: '$CI_COMMIT_BRANCH && $CI_COMMIT_BRANCH != "main"'

# Main branch build (creates sha-* and staging tag)
build-staging:
  extends: .build-immutable
  variables:
    HARBOR_PROJECT: "microservices"
    CI_ENVIRONMENT_NAME: "staging"
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'

# Git tag build (creates sha-* and v* tag)
build-release:
  extends: .build-immutable
  variables:
    HARBOR_PROJECT: "microservices"
  rules:
    - if: '$CI_COMMIT_TAG =~ /^v[0-9]+\.[0-9]+\.[0-9]+.*$/'
```

### Accessing the Image Reference in Downstream Jobs

The build job creates a `build.env` artifact with:

```bash
IMAGE_SHA_TAG=harbor.staging.internal/microservices/my-app:sha-a1b2c3d
IMAGE_DIGEST=harbor.staging.internal/microservices/my-app@sha256:abc...
GIT_COMMIT=a1b2c3d4e5f6...
GIT_SHORT_SHA=a1b2c3d
```

Use it in the deploy stage:

```yaml
deploy:
  stage: deploy
  needs:
    - job: build-staging
      artifacts: true
  script:
    # IMAGE_SHA_TAG is available from build.env artifact
    - echo "Deploying ${IMAGE_SHA_TAG}"
    - argocd app set my-app -p image.tag="sha-${CI_COMMIT_SHORT_SHA}"
```

---

## Harbor Projects and Access

| Harbor Project | Purpose | Immutability | Mutable Exception |
|----------------|---------|-------------|-------------------|
| `platform-apps` | Platform services (Harbor, Keycloak, ArgoCD) | sha-*, v*, release-*, latest | dev*, staging*, feature-* |
| `microservices` | Application workloads | sha-*, v*, release-*, latest | dev*, staging*, feature-* |
| `infrastructure` | Base images, tooling | sha-*, v*, release-*, latest | dev*, staging*, feature-* |

### Harbor UI Navigation

1. Login: `https://harbor.staging.internal` (Keycloak SSO)
2. Project: Select `microservices` (or your project)
3. Immutability Rules: Project > Configuration > Tag Immutability
4. Retention Policy: Project > Configuration > Tag Retention

---

## Verifying Immutability

### Test: Push Blocked by Harbor

```bash
# Setup
HARBOR_URL="https://harbor.staging.internal"
IMAGE="${HARBOR_URL}/microservices/test-app"

# First push — should succeed (HTTP 201)
docker tag nginx:latest "${IMAGE}:sha-test001"
docker push "${IMAGE}:sha-test001"
# Expected: Successfully pushed

# Second push — should fail (HTTP 412)
docker push "${IMAGE}:sha-test001"
# Expected: Error: The tag is immutable.
```

### Test: Mutable Tag Allowed

```bash
# First push — succeed
docker tag nginx:latest "${IMAGE}:staging"
docker push "${IMAGE}:staging"

# Second push — also succeed (mutable)
docker tag nginx:alpine "${IMAGE}:staging"
docker push "${IMAGE}:staging"
# Expected: Successfully pushed (overwrites previous)
```

---

## FAQ

**Q: My pipeline failed with "The tag is immutable" on a re-run. What do I do?**

This is expected behavior. The `sha-*` tag for your commit was already pushed in the first run. You have two options:
1. If the image needs to be rebuilt (dependency update, base image fix): create a new commit. The new commit SHA generates a new tag.
2. If the build failed after the push: the image is already in Harbor. Skip the build job and proceed with the existing tag.

**Q: Can I delete an immutable tag to re-push it?**

Technically yes, via the Harbor UI (requires admin access) or API. However, you should never delete a `sha-*` tag that has been deployed or referenced in ArgoCD — this breaks rollback capability.

**Q: Why is `latest` blocked?**

`latest` is ambiguous by definition — it does not tell you which commit or version it represents. In production, `latest` is a security antipattern because it can be silently updated to a different image. Use `sha-*` or `v*` tags instead.

**Q: I need to test a hotfix urgently. Can I bypass immutability?**

No. The security model requires all images to be traceable. For a hotfix:
1. Create a `hotfix/*` branch (mutable, fast iteration)
2. Use the `sha-*` tag when promoting to production
3. Create a `v*` tag for the official release

**Q: What happens to old sha-* tags from 6 months ago?**

SHA tags are not subject to retention policies (only dev/staging/feature tags are cleaned up). Old SHA tags accumulate but the storage impact is minimal since Harbor shares layers between images.

**Q: Can I use `docker pull harbor.../my-app:staging` in my Dockerfile FROM?**

For base images in production Dockerfiles, NO. Use an immutable reference:
```dockerfile
# BAD (mutable — FROM can change between builds)
FROM harbor.staging.internal/infrastructure/node-base:staging

# GOOD (immutable — guaranteed reproducible)
FROM harbor.staging.internal/infrastructure/node-base:sha-a1b2c3d
# or
FROM harbor.staging.internal/infrastructure/node-base:v18.3.1
```

---

## Troubleshooting

### Harbor Returns HTTP 412

```
denied: The tag is immutable.
```

**Cause**: Attempting to push a tag that already exists and is protected by an immutability rule.

**Solution**:
- For `sha-*` tags: create a new commit (new SHA = new tag allowed)
- For `v*` tags: bump the version number
- For `latest`: not allowed — switch to sha-* tags

### Harbor Returns HTTP 401

```
unauthorized: authentication required
```

**Cause**: Runner credentials expired or ESO ExternalSecret not synced.

**Solution**:
```bash
# Check ESO secret status
kubectl get externalsecret gitlab-ci-credentials -n staging-platform-gitlab

# Check Harbor credentials in runner
kubectl get secret harbor-admin-credentials -n harbor-system
```

### Pipeline Creates Wrong Tag Format

Ensure `CI_COMMIT_SHORT_SHA` is not empty:
```yaml
# Debug: print all CI variables
script:
  - env | grep CI_COMMIT
```

If `CI_COMMIT_SHORT_SHA` is empty, check that the pipeline is triggered from a commit (not from a schedule with detached HEAD).

---

## References

- ADR: `docs/adr/adr-084-immutable-image-tags-enforcement.md`
- Harbor API Script: `scripts/harbor/configure-immutability.sh`
- CI Template: `domains/cicd-platform/infra/gitlab-ci/templates/build-immutable.gitlab-ci.yml`
- CI Example: `domains/cicd-platform/infra/gitlab-ci/examples/immutable-tags.gitlab-ci.yml`
- Harbor Docs: https://goharbor.io/docs/2.0.0/working-with-projects/project-configuration/configure-tag-immutability/
- OCI Image Spec: https://specs.opencontainers.org/image-spec/

---

**Owner**: Platform Team
**Review Cycle**: Quarterly
**Next Review**: 2026-05-26

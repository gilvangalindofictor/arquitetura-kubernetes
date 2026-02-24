# Migration: test-governance → staging-governance-test

**Data:** 2026-02-24
**Wave:** 1
**Agent:** Wave1-A4
**Pattern:** A (Test namespace with nginx deployment)
**Duration:** 8 minutes
**Status:** SUCCESS

## Summary
Migrated test namespace used for Kyverno policy validation (GAP-009). The namespace contained a single nginx test deployment used for policy testing.

## Resources Migrated
- **Original namespace:** test-governance
- **New namespace:** staging-governance-test
- **Workload:** nginx-test deployment (1 replica, nginx:latest)
  - Resources: 10m CPU / 64Mi RAM (requests), 100m CPU / 128Mi RAM (limits)

## Execution Steps

### 1. Pre-Migration Assessment
```bash
kubectl get all -n test-governance
# Found: nginx-test deployment (1 pod, 4h24m age)
```

### 2. Backup
```bash
mkdir -p /tmp/migration-test-governance-backup
kubectl get all -n test-governance -o yaml > /tmp/migration-test-governance-backup/resources.yaml
kubectl get deployment nginx-test -n test-governance -o yaml > /tmp/migration-test-governance-backup/nginx-deployment.yaml
```

### 3. Create New Namespace
```bash
kubectl create namespace staging-governance-test
kubectl label namespace staging-governance-test environment=staging domain=governance product=test
```

### 4. Migrate Workload
```bash
# Cleaned manifest (removed namespace-specific metadata)
kubectl apply -f nginx-deployment-clean.yaml
# Result: nginx-test deployment created in staging-governance-test
```

### 5. Validation & Cleanup
```bash
kubectl get pods -n staging-governance-test  # 1/1 Running
kubectl delete deployment nginx-test -n test-governance
kubectl get all -n test-governance  # No resources found
```

## Validation Results

### New Namespace
- **Name:** staging-governance-test
- **Labels:**
  - environment=staging
  - domain=governance
  - product=test
  - kubernetes.io/metadata.name=staging-governance-test
- **Status:** Active

### Migrated Workload
- **Deployment:** nginx-test (1/1 ready)
- **Pod:** nginx-test-79fc6c7498-hs2nq (Running)
- **Node:** ip-10-0-157-56.ec2.internal
- **Age:** Fresh deployment (< 1min)
- **Zero restarts:** Healthy startup

### Old Namespace
- **Status:** Empty (all resources removed)
- **Next step:** Can be safely deleted or kept as empty namespace

## Migration Pattern
**Pattern A Applied:** Stateless test workload
- No persistent volumes
- No ConfigMaps/Secrets (uses defaults)
- No Services/Ingress (internal testing only)
- Simple deployment recreation

## Next Steps
1. Update Kyverno policy tests to use `staging-governance-test` namespace
2. Delete old `test-governance` namespace after confirming no dependencies
3. Document new namespace in governance testing procedures

## Backup Location
- `/tmp/migration-test-governance-backup/resources.yaml` (full backup)
- `/tmp/migration-test-governance-backup/nginx-deployment.yaml` (original manifest)
- `/tmp/migration-test-governance-backup/nginx-deployment-clean.yaml` (migration manifest)

## Success Criteria
- [x] Namespace created with correct labels
- [x] Workload migrated successfully (1/1 Running)
- [x] Zero downtime (test namespace, recreate strategy acceptable)
- [x] Old namespace cleaned up
- [x] Migration completed in < 10min
- [x] Full backup created

## Notes
- Migration was trivial as expected (single test deployment, no dependencies)
- Used deployment recreation instead of live migration (acceptable for test workloads)
- Namespace labeled following DEC-074 standard: environment=staging, domain=governance, product=test
- Old namespace kept empty temporarily for rollback safety (can delete after 24h validation)

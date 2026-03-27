# Health Audit Report — 2026-03-26

**Auditor**: Claude Code (Health Auditor Agent)
**Cluster**: k8s-platform-prod (EKS v1.34.2-eks-ecaa3a6)
**Account**: 891377105802 (us-east-1)
**Date**: 2026-03-26 ~19:00 UTC
**Total Pods**: 305
**Total Nodes**: 14 (all Ready)

---

## Executive Summary

| Metric | Value |
|--------|-------|
| Nodes | 14/14 Ready (3 system t3.medium, 2 critical t3.xlarge, 9 workloads t3.large) |
| Pods Running | 305 (0 in error state) |
| ArgoCD Staging Apps | 19 (18 Synced, 1 OutOfSync — Hatch ETL expected) |
| ArgoCD Prod Apps | 0 (confirmed GAP-ARGOCD-PROD-ZERO-APPS) |
| ExternalSecrets | 54/54 SecretSynced |
| ClusterSecretStores | 2/2 Valid (vault-backend + vault-backend-prod) |
| Velero | Schedules active, backups running on schedule |
| Certificates | 6/6 Ready |
| CronJobs | 7 total, 1 suspended (etl-extraction — expected) |

**Overall Health**: GOOD with P1/P2 issues requiring attention.

---

## Phase 1: Cluster Infrastructure

### 1.1 Nodes

All 14 nodes Ready, no MemoryPressure/DiskPressure/PIDPressure conditions.

| Node | Type | Group | CPU% | MEM% | Obs |
|------|------|-------|------|------|-----|
| ip-10-0-129-91 | t3.medium | system | 18% | 72% | OK |
| ip-10-0-130-144 | t3.xlarge | critical | 18% | 37% | OK |
| ip-10-0-130-41 | t3.large | workloads | 24% | 82% | HIGH MEM (overcommitted 199% limits) |
| **ip-10-0-132-116** | **t3.medium** | **system** | **30%** | **99%** | **CRITICAL MEM — 229% limits overcommit** |
| ip-10-0-133-154 | t3.large | workloads | 13% | 21% | OK |
| ip-10-0-138-21 | t3.large | workloads | 13% | 27% | OK |
| ip-10-0-138-53 | t3.large | workloads | 15% | 32% | OK |
| ip-10-0-142-36 | t3.large | workloads | 15% | 35% | OK |
| ip-10-0-144-5 | t3.medium | system | 12% | 43% | OK |
| ip-10-0-147-54 | t3.large | workloads | 13% | 21% | OK |
| ip-10-0-148-135 | t3.large | workloads | 18% | 54% | OK |
| ip-10-0-148-9 | t3.large | workloads | 18% | 24% | OK |
| ip-10-0-155-239 | t3.xlarge | critical | 15% | 24% | OK |
| ip-10-0-157-60 | t3.large | workloads | 15% | 30% | OK |

**Node Groups**:
- system: 3x t3.medium (taint: node-type=NoSchedule)
- critical: 2x t3.xlarge (taint: workload=NoSchedule)
- workloads: 9x t3.large (no taints)

### 1.2 DaemonSets (all healthy)

| DaemonSet | Namespace | Desired | Ready |
|-----------|-----------|---------|-------|
| aws-node | kube-system | 14 | 14 |
| calico-node | kube-system | 14 | 14 |
| ebs-csi-node | kube-system | 14 | 14 |
| harbor-registry-config | kube-system | 14 | 14 |
| kube-proxy | kube-system | 14 | 14 |
| linkerd-cni | linkerd-cni | 14 | 14 |
| node-exporter | staging-obs | 14 | 14 |
| loki-canary (staging) | staging-obs | 9 | 9 |
| loki-canary (prod) | prod-obs | 9 | 9 |
| promtail | staging-obs | 14 | 14 |
| node-agent (velero) | velero | 14 | 14 |

---

## Phase 2: Issues Found

### P1 Issues

#### GAP-HEALTH-001: Node ip-10-0-132-116 at 99% Memory (system node)

- **Severity**: P1
- **Type**: GAP-HEALTH
- **Node**: ip-10-0-132-116.ec2.internal (t3.medium, system group)
- **Actual Memory**: 3272Mi / 3296Mi (99%)
- **Memory Limits**: 7568Mi (229% overcommit)
- **CPU Limits**: 1710m (88%)
- **Pods on node**: prometheus-kube-prometheus-stack-prometheus-0, plus daemonset pods
- **Root Cause**: Prometheus staging is running on a t3.medium system node (3.7GB total). It alone uses 2716Mi. The system nodes are too small for Prometheus workloads.
- **Impact**: OOM risk, kubelet evictions possible
- **Fix Proposal**: Move Prometheus to workloads node group via nodeSelector/affinity, or increase system node size. The `prometheus-kube-prometheus-stack-prometheus-0` pod (2716Mi actual usage) should NOT be on a t3.medium system node.

#### GAP-HEALTH-002: Prod Keycloak Ingress Certificate Missing

- **Severity**: P1
- **Type**: GAP-CONFIG
- **Resource**: Ingress `keycloak-keycloakx` in `prod-platform-keycloak`
- **Error**: `Failed build model due to ingress: prod-platform-keycloak/keycloak-keycloakx: no certificate found for host: keycloak.keycloak.example.com`
- **Root Cause**: Ingress host is `keycloak.keycloak.example.com` (a placeholder, not real). Certificate ARN annotation is empty. TLS SNI routes `access.prod.alvocard.com.br` but host rule uses example.com.
- **Impact**: All ingresses in the `platform-prod` ALB group are affected (harbor-prod, argocd-prod, keycloak-prod). The ALB controller cannot build the model because of this invalid ingress.
- **Fix Proposal**: Fix the Keycloak prod ingress host to match the actual domain (e.g., `keycloak.prod.alvocard.com.br` or `access.prod.alvocard.com.br`) and set the correct ACM certificate ARN. This is a Helm values change in the Keycloak prod deployment.

#### GAP-HEALTH-003: Prod ALB Group Poisoned by Keycloak Ingress

- **Severity**: P1 (cascade from GAP-HEALTH-002)
- **Type**: GAP-CONFIG
- **Resources affected**:
  - `prod-platform-argocd/argocd-prod-server` — FailedBuildModel
  - `prod-platform-harbor/harbor-prod-ingress` — FailedBuildModel
  - `prod-platform-keycloak/keycloak-keycloakx` — FailedBuildModel
- **Root Cause**: All three ingresses share the `platform-prod` ALB group. The invalid keycloak ingress with missing certificate blocks the entire ALB model build.
- **Impact**: No HTTPS routing working for any production service on the platform-prod ALB.

#### GAP-HEALTH-004: OTel HPA Target Mismatch (Orphaned HPA)

- **Severity**: P1
- **Type**: GAP-CONFIG
- **Resource**: HPA `opentelemetry-collector` in `staging-observability-monitoring`
- **Error**: `deployments.apps "opentelemetry-collector-opentelemetry-collector" not found` (6359 events in 26h)
- **Root Cause**: HPA targets deployment `opentelemetry-collector-opentelemetry-collector` but actual deployment is named `opentelemetry-collector`. Name mismatch, likely from a helm chart upgrade that changed the deployment name.
- **Impact**: OTel collector cannot autoscale. HPA shows `cpu: <unknown>/70%` and `0 current / 0 desired` replicas.
- **Fix Proposal**: Update the HPA scaleTargetRef.name to `opentelemetry-collector`. However, since the OTel deployment has 2 replicas running via its own spec, there is no immediate service impact. The HPA is just non-functional.

#### GAP-HEALTH-005: Prod Keycloak Backup CronJob Never Executed

- **Severity**: P1
- **Type**: GAP-HEALTH
- **Resource**: CronJob `keycloak-backup` in `prod-platform-keycloak`
- **Schedule**: `30 11 * * *` (daily), suspend=false
- **Last Schedule Time**: `<unset>` (never ran)
- **Jobs created**: 0
- **Age**: 5h30m
- **Root Cause**: CronJob was recently created (~5.5h ago) and the schedule `30 11 * * *` means 11:30 UTC. Current time is ~19:00 UTC, so it should have triggered at 11:30 UTC today if it existed at that time. Since it was created only 5.5h ago (~13:30 UTC), it missed today's window.
- **Impact**: No Keycloak realm backup in production. Staging backup works (last ran 6d17h ago).
- **Fix Proposal**: Monitor next day's execution. If it still doesn't run, investigate ConfigMap `keycloak-backup-script` and credentials. Consider running a manual job to validate: `kubectl create job --from=cronjob/keycloak-backup keycloak-backup-manual-test -n prod-platform-keycloak`.

#### GAP-HEALTH-006: No Promtail in Production

- **Severity**: P1
- **Type**: GAP-MISSING
- **Resource**: No promtail DaemonSet in `prod-observability-monitoring`
- **Current State**: Promtail only exists in `staging-observability-monitoring` (14/14 pods). Production has Loki running but no log collector.
- **Impact**: No log collection from production pods. Loki prod has no data to query.
- **Fix Proposal**: Deploy promtail DaemonSet to `prod-observability-monitoring` namespace with the same configuration as staging, pointing to the prod Loki gateway.

### P2 Issues

#### GAP-HEALTH-007: Harbor Staging JobService 138 Restarts (Stable)

- **Severity**: P2 (stable — no new restarts in 8h)
- **Type**: GAP-HEALTH
- **Resource**: `harbor-jobservice-77d48b4bc4-27vx8` in `harbor-system`
- **Restarts**: 138 (last restart 8h ago)
- **Current State**: Running, stable, processing jobs normally
- **Root Cause**: Previously documented as GAP-HARBOR-JOBSERVICE-LOOP (harbor-core unavailable during rolling update, auto-recovered)
- **Status**: STABLE — matches MEMORY.md entry. No action needed unless restarts resume.

#### GAP-HEALTH-008: Harbor Prod Core/JobService Restarts

- **Severity**: P2
- **Type**: GAP-HEALTH
- **Resources**:
  - `harbor-prod-core` (2 pods): 3 restarts each — Last State: Error, Exit Code 1
  - `harbor-prod-jobservice`: 4 restarts — Last State: Terminated, Exit Code 137 (OOMKilled)
- **Current State**: All Running now
- **Root Cause**: Core errors during startup (likely dependency on other services). JobService killed with signal 137 (OOM or SIGKILL from kubelet).
- **Fix Proposal**: Monitor. Consider increasing memory limits for harbor-prod-jobservice if OOM recurs.

#### GAP-HEALTH-009: Node ip-10-0-130-41 Overcommitted (82% MEM)

- **Severity**: P2
- **Type**: GAP-HEALTH
- **Node**: ip-10-0-130-41.ec2.internal (t3.large, workloads)
- **Memory**: 5866Mi / 7168Mi (82%)
- **Memory Limits**: 14096Mi (199% overcommit)
- **CPU Limits**: 7510m (389% overcommit)
- **Pod Count**: 23 pods including GitLab webservice (2273Mi), SonarQube (1546Mi), loki-chunks-cache
- **Impact**: At risk if multiple pods spike simultaneously
- **Fix Proposal**: Spread heavy workloads across more nodes. Consider pod anti-affinity rules for GitLab/SonarQube.

#### GAP-HEALTH-010: GitLab Ingress SSLRedirect Errors

- **Severity**: P2
- **Type**: GAP-CONFIG
- **Resources**:
  - `staging-platform-gitlab/gitlab-webservice-default`
  - `staging-platform-gitlab/gitlab-minio`
  - `staging-platform-gitlab/gitlab-kas`
  - `staging-observability-monitoring/kube-prometheus-stack-grafana`
- **Error**: `Failed build model due to listener does not exist for SSLRedirect port: 443`
- **Root Cause**: These ingresses have `ssl-redirect: 443` annotation but the ALB group `gitlab-staging` only has HTTP listener (no HTTPS/443 configured). Missing certificate or listen-ports config.
- **Impact**: No SSL redirect for GitLab and Grafana staging ingresses. Services accessible via HTTP but not auto-redirecting to HTTPS.

#### GAP-HEALTH-011: Prod ArgoCD Has Zero Applications

- **Severity**: P2
- **Type**: GAP-MISSING
- **Resource**: Namespace `prod-platform-argocd`
- **Current State**: ArgoCD is running (5 pods healthy) but manages 0 Applications
- **Impact**: No GitOps management in production. All prod workloads are manually deployed.
- **Status**: Matches MEMORY.md entry `GAP-ARGOCD-PROD-ZERO-APPS`

#### GAP-HEALTH-012: Empty Production Namespaces

- **Severity**: P2
- **Type**: GAP-MISSING
- **Namespaces with 0 pods, 0 deployments, 0 statefulsets**:
  - `prod-data-hatch-etl` — Expected: Hatch ETL in HOLD mode
  - `prod-data-ipaas` — Expected: iPaaS components (GAP-IPAAS-STAGING-001)
  - `prod-data-services` — Expected: application services
  - `prod-data-vemsoft-etl` — Expected: VemSoft ETL
  - `prod-platform-backstage` — Expected: Backstage IDP (GAP-BACKSTAGE-PROD-EMPTY)
  - `prod-data-redis-operator` — Expected: Redis operator
- **Impact**: Production namespaces created but no workloads deployed.
- **Status**: Partially matches MEMORY.md entries. These are planned deployments not yet executed.

#### GAP-HEALTH-013: Kyverno Policy Violation Spam

- **Severity**: P2 (noise)
- **Type**: GAP-CONFIG
- **Resources**: 80+ Warning events from Kyverno policies
- **Policies triggering**:
  - `validate-service-naming/check-service-name` — flagging all helm-generated service names
  - `require-corporate-labels/check-corporate-labels` — flagging cert-manager, sonarqube, keycloak
  - `validate-label-values/check-label-domain|owner|environment` — flagging cert-manager, sonarqube
- **Root Cause**: Kyverno policies are in audit/warn mode and flagging Helm chart-generated names that don't follow corporate naming conventions.
- **Impact**: Event log pollution. Obscures real warnings.
- **Status**: Matches MEMORY.md `GAP-KYVERNO-POLICY-SPAM`
- **Fix Proposal**: Add exclusion rules for known helm charts (cert-manager, sonarqube, keycloak, loki, tempo, argocd, vault, external-secrets, external-dns) in the Kyverno policies.

### P3 Issues

#### GAP-HEALTH-014: Empty Legacy Namespaces

- **Severity**: P3
- **Type**: GAP-CONFIG
- **Namespaces**: `cert-manager`, `cicd-argocd`, `vault-system` — empty, no pods
- **Impact**: None — just namespace clutter
- **Fix Proposal**: Evaluate for cleanup after confirming no references exist

#### GAP-HEALTH-015: Loki Canary NodeSelector Limited

- **Severity**: P3
- **Type**: GAP-CONFIG
- **Resource**: Loki-canary DaemonSets (both staging and prod)
- **Current**: nodeSelector `eks.amazonaws.com/nodegroup=workloads` — only 9/14 nodes
- **Impact**: Loki canary does not validate log pipeline on system (3) and critical (2) nodes
- **Fix Proposal**: Low priority, acceptable design choice

#### GAP-HEALTH-016: Staging Vault PDB maxUnavailable=0

- **Severity**: P3
- **Type**: GAP-CONFIG
- **Resource**: PDB `vault` in `staging-security-vault` — maxUnavailable=0
- **Impact**: Vault pod cannot be evicted during node drain. Node drains will hang.
- **Fix Proposal**: Change to maxUnavailable=1 since staging Vault has only 1 replica

---

## Phase 3: Fix Proposals

### Safe Fixes (Can Execute Now)

None required at this time — no pods are in error state. All services are Running.

### Terraform/IaC Fixes Needed

#### FIX-AUDIT-001: Prometheus NodeAffinity to Workloads Nodes

**Problem**: Prometheus staging (2716Mi) running on t3.medium system node (3.3GB total).

**Proposed Change**: Add nodeSelector to Prometheus to run on workloads or critical nodes.

**File**: Likely in `modules/monitoring/main.tf` or kube-prometheus-stack Helm values.

```yaml
# In kube-prometheus-stack values
prometheus:
  prometheusSpec:
    nodeSelector:
      node-type: workloads
    tolerations: []
```

**Status**: Needs terraform plan/apply.

#### FIX-AUDIT-002: Prod Keycloak Ingress Host + Certificate

**Problem**: Ingress host is `keycloak.keycloak.example.com` (placeholder), certificate ARN empty.

**Proposed Change**: Set correct host and ACM certificate ARN.

**File**: Keycloak prod Helm values in the appropriate module.

```yaml
ingress:
  rules:
    - host: access.prod.alvocard.com.br  # or keycloak.prod.alvocard.com.br
  tls:
    - hosts:
        - access.prod.alvocard.com.br
  annotations:
    alb.ingress.kubernetes.io/certificate-arn: <ACM_CERT_ARN_FOR_PROD>
```

**Status**: Needs correct domain decision + terraform plan/apply.

#### FIX-AUDIT-003: OTel HPA ScaleTargetRef Name Fix

**Problem**: HPA targets non-existent deployment name.

**Proposed Change**: Fix HPA target from `opentelemetry-collector-opentelemetry-collector` to `opentelemetry-collector`.

**File**: OTel collector Helm values or HPA definition in the monitoring module.

**Status**: Needs terraform plan/apply or Helm values update.

#### FIX-AUDIT-004: Prod Promtail Deployment

**Problem**: No log collection in production.

**Proposed Change**: Deploy promtail DaemonSet to `prod-observability-monitoring`.

**Status**: Needs IaC module creation or extension of existing promtail module to prod.

#### FIX-AUDIT-005: GitLab/Grafana Staging SSL Redirect

**Problem**: ALB listener 443 not configured for gitlab-staging group.

**Proposed Change**: Add HTTPS listener with appropriate certificate ARN.

**Status**: Needs terraform plan/apply.

---

## Phase 4: Cross-Reference with MEMORY.md GAPs

| MEMORY.md GAP | Audit Finding | Status |
|---------------|---------------|--------|
| GAP-TOLERATION-001 (Linkerd tolerations) | Linkerd control plane NOW has system node tolerations | **IMPROVED** — tolerations present in cluster |
| GAP-IMAGE-001 (linkerd-cni-token-renewal) | CronJob exists, linkerd-cni 14/14 Running | **STABLE** |
| GAP-SHARED-RDS | Not validated (requires RDS audit) | **PENDING** |
| GAP-VAULT-ADMIN-WILDCARD | Not validated (requires Vault policy audit) | **PENDING** |
| GAP-HARBOR-JOBSERVICE-LOOP | 138 restarts frozen, 0 new in 8h | **STABLE** (confirmed) |
| GAP-KYVERNO-POLICY-SPAM | 80+ Warning events confirmed | **OPEN** (GAP-HEALTH-013) |
| GAP-BACKSTAGE-PROD-EMPTY | Confirmed: 0 pods in prod-platform-backstage | **OPEN** (GAP-HEALTH-012) |
| GAP-ARGOCD-PROD-ZERO-APPS | Confirmed: 0 Applications in prod ArgoCD | **OPEN** (GAP-HEALTH-011) |
| GAP-IPAAS-STAGING-001 | prod-data-ipaas also empty | **OPEN** |
| GAP-FIXTEMP-003 (Linkerd tolerations IaC) | Tolerations present in cluster, need IaC codification | **PENDING IaC** |
| GAP-HARBOR-HELM-DRIFT | Harbor prod running with manual patches | **PENDING** |
| GAP-LAMBDA-003 (cold start) | Not validated (requires Lambda audit) | **PENDING** |

---

## Summary of Actions

### Immediate (P1)

| ID | Action | Type | Effort |
|----|--------|------|--------|
| FIX-AUDIT-001 | Move Prometheus off system node | IaC | 1h |
| FIX-AUDIT-002 | Fix prod Keycloak ingress (host + cert) | IaC | 2h |
| FIX-AUDIT-004 | Deploy promtail to production | IaC | 2h |
| Monitor | Keycloak prod backup CronJob next execution | Observe | 0h |

### Short-term (P2)

| ID | Action | Type | Effort |
|----|--------|------|--------|
| FIX-AUDIT-003 | Fix OTel HPA target name | IaC | 30m |
| FIX-AUDIT-005 | Fix GitLab/Grafana HTTPS redirect | IaC | 1h |
| GAP-HEALTH-013 | Add Kyverno policy exclusions | IaC | 2h |

### Planned (P2-P3)

| ID | Action | Type | Effort |
|----|--------|------|--------|
| GAP-HEALTH-012 | Deploy prod workloads (Hatch, iPaaS, VemSoft, Backstage) | IaC | Sprint |
| GAP-HEALTH-011 | Configure ArgoCD prod Applications | IaC | 4h |
| GAP-HEALTH-014 | Cleanup empty legacy namespaces | Manual | 30m |

---

## Cluster Health Score

| Category | Score | Notes |
|----------|-------|-------|
| Node Health | 9/10 | All Ready, 1 node at 99% mem |
| Pod Health | 10/10 | 0 errors, 0 CrashLoopBackOff |
| Networking/Ingress | 6/10 | Prod ALB group broken, GitLab SSL redirect missing |
| Observability | 7/10 | No promtail in prod, HPA broken |
| Backup/DR | 8/10 | Velero healthy, prod Keycloak backup untested |
| GitOps | 6/10 | Staging OK, prod has 0 ArgoCD apps |
| Secrets | 10/10 | 54/54 ExternalSecrets synced |
| **Overall** | **8/10** | Good baseline, P1 issues need attention |

---

*Report generated by Claude Code Health Auditor Agent*
*Audit duration: ~15 minutes*
*Next recommended audit: 2026-03-27*

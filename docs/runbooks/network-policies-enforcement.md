# Runbook: Network Policies Enforcement (GAP-007)

**Gap:** GAP-007 (Network Segmentation)
**ADR:** ADR-070
**Status:** Scheduled for 2026-03-03 (after 7-day audit period)
**Deployment Date:** 2026-02-25
**Audit Duration:** 7 days (until 2026-03-03)

---

## Overview

This runbook provides step-by-step procedures to enforce Network Policies deployed on 2026-02-25 after successful 7-day audit validation period. All 22 Network Policies are currently in **audit mode** (`policy.cilium.io/audit-mode: "true"`), which logs policy violations but does NOT block traffic.

**Enforcement Goal:** Remove audit-mode annotation from all policies on 2026-03-03, enabling active traffic blocking.

### Policy Inventory Summary

| Namespace | Policies | Status | Validation Status |
|-----------|----------|--------|-------------------|
| argocd | 6 | Audit | Pending 2026-03-03 |
| sonarqube | 2 | Audit | Pending 2026-03-03 |
| keycloak | 3 | Audit | Pending 2026-03-03 |
| staging-platform-gitlab | 8 | Audit | Pending 2026-03-03 |
| staging-security-vault | 3 | Audit | Pending 2026-03-03 |
| **TOTAL** | **22** | **Audit** | **All pending** |

---

## Section 1: Pre-Requisites (2026-02-25 to 2026-03-03)

### 1.1 Validation Environment Requirements

Before attempting enforcement, verify:

- **Kubernetes Cluster**: EKS 1.34+ running
- **CNI Plugin**: Calico with Network Policy support enabled
- **Access**: kubectl configured with cluster-admin permissions
- **Scripts**: All 4 validation scripts in `/scripts/security/` directory

**Validation Command:**

```bash
# Check cluster version
kubectl version --short

# Check Calico deployment
kubectl get pods -n kube-system -l k8s-app=calico-node

# Check kubectl access
kubectl auth can-i create networkpolicies --all-namespaces
```

### 1.2 Pre-Enforcement Checklist (Week of 2026-02-25)

Complete these tasks before enforcement date (2026-03-03):

- [ ] **Day 1 (2026-02-25):** Deploy all policies, verify they appear in audit mode
- [ ] **Day 2-6 (2026-02-26 to 2026-03-02):** Run daily validation script to check for denies
- [ ] **Day 6 (2026-03-02):** Final comprehensive connectivity test
- [ ] **Day 6 (2026-03-02 EOD):** Team review and sign-off on enforcement
- [ ] **Day 7 (2026-03-03):** Execute enforcement procedure

### 1.3 Communication Plan

**7 days before (2026-02-25 EOD):**
- Send "Network Policies Audit Period Started" notification
- Document audit period in wiki/status page
- Set calendar reminder for 2026-03-03 enforcement

**1 day before (2026-03-02):**
- Send "Network Policies Enforcement Scheduled for Tomorrow" notification
- Include: Estimated duration (15 min), rollback procedures, contact info

**During enforcement (2026-03-03):**
- Announce start time
- Real-time status updates in Slack
- Post-enforcement validation results

---

## Section 2: Audit Validation Checklist (2026-02-25 to 2026-03-02)

### 2.1 Deployment Verification (2026-02-25)

Verify all 22 policies deployed successfully in audit mode:

```bash
# List all GAP-007 policies
kubectl get networkpolicies -A -o custom-columns=\
NAME:.metadata.name,NAMESPACE:.metadata.namespace,\
AUDIT:.metadata.annotations['policy\.cilium\.io/audit-mode'],\
GAP:.metadata.annotations['gap'],\
AGE:.metadata.creationTimestamp

# Expected output: 22 policies, all with audit-mode=true, all with gap=GAP-007
```

**Success Criteria:**
- All 22 policies listed
- All show `audit-mode: true`
- All show `gap: GAP-007`
- All creation timestamps recent (within last hour)

### 2.2 Daily Audit Log Analysis (2026-02-26 to 2026-03-02)

Run audit log analysis daily to check for unexpected denies:

```bash
# Daily validation script (run once per day)
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-audit-analysis.sh

# Expected output:
#   - Summary of policy denies in last 24 hours
#   - Grouped by namespace and policy
#   - Any unexpected blocks reported
#   - Overall status: "SAFE_TO_ENFORCE" or "INVESTIGATE_REQUIRED"
```

**What to expect:**
- DNS denies (expected, normal Calico audit logging)
- Few to zero application denies
- No "connection refused" errors in app logs

**If you see:**
- High deny count (>100/hour) → Investigate with netpol-audit-analysis.sh
- Specific policy blocking legitimate traffic → Add rule and re-test
- Services unable to connect → Extend audit period, investigate root cause

### 2.3 Connectivity Validation (Daily)

Run connectivity tests daily to confirm critical paths are working:

```bash
# Run connectivity tests (should all pass)
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-connectivity-tests.sh

# Expected output:
#   Test 1: ArgoCD → Keycloak (OIDC)  [PASS]
#   Test 2: GitLab → Keycloak (OIDC)  [PASS]
#   Test 3: SonarQube → Keycloak (SAML) [PASS]
#   Test 4: Harbor → PostgreSQL RDS  [PASS]
#   Test 5: Vault → KMS              [PASS]
#
#   Overall Status: ALL TESTS PASSED ✓
```

### 2.4 Application Health Checks (Daily)

Verify core services remain healthy during audit period:

```bash
# Check ArgoCD
kubectl get application -n argocd 2>/dev/null | grep -v OutOfSync

# Check GitLab
kubectl get pods -n staging-platform-gitlab -l app=webservice | grep Running

# Check SonarQube
kubectl logs -n sonarqube deployment/sonarqube --tail=20 | grep -i error

# Check Keycloak
kubectl get pods -n keycloak -l app.kubernetes.io/name=keycloak | grep Running

# Check Vault
kubectl get pods -n staging-security-vault -l app.kubernetes.io/name=vault | grep Running
```

**Success Criteria:**
- All core pods Running
- No recent restart loops
- No connection timeout errors in logs

### 2.5 Performance Baseline (2026-02-25)

Capture performance metrics before enforcement as baseline:

```bash
# Capture baseline CPU/memory for all Marco 4 services
kubectl top pods -n argocd
kubectl top pods -n sonarqube
kubectl top pods -n keycloak
kubectl top pods -n staging-platform-gitlab
kubectl top pods -n staging-security-vault

# Note these values for comparison post-enforcement
# Network Policy enforcement should have minimal performance impact
```

---

## Section 3: Enforcement Procedure (2026-03-03)

### 3.1 Pre-Enforcement Checklist (Morning of 2026-03-03)

Before starting enforcement, complete these final checks:

```bash
# 1. Verify audit logs show no critical denies
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-audit-analysis.sh

# 2. Run connectivity tests (should all pass)
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-connectivity-tests.sh

# 3. Check all policies still in audit mode
kubectl get networkpolicies -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\t"}{.metadata.annotations.policy\.cilium\.io/audit-mode}{"\n"}{end}' | grep -v "true$" | wc -l

# Expected: 0 (all should be in audit mode)
```

**If any check fails:** STOP enforcement and investigate before proceeding.

### 3.2 Enforcement Execution

#### Step 1: Backup Current State (30 seconds)

```bash
# Export all GAP-007 policies before enforcement
mkdir -p /tmp/netpol-backup-20260303
kubectl get networkpolicies -A -o yaml > /tmp/netpol-backup-20260303/all-policies.yaml

# Backup each namespace separately
for ns in argocd sonarqube keycloak staging-platform-gitlab staging-security-vault; do
  kubectl get networkpolicies -n $ns -o yaml > /tmp/netpol-backup-20260303/${ns}-policies.yaml
done

echo "✓ Backup complete: /tmp/netpol-backup-20260303/"
```

#### Step 2: Announce Start (1 minute)

Post to team communication channel:

```
🚀 STARTING NETWORK POLICIES ENFORCEMENT (2026-03-03)

Timeline:
- 00:00 - Enforcement starts
- 00:05 - All policies updated (audit mode removed)
- 00:10 - Connectivity validation
- 00:15 - Completion + status report

If critical errors occur: Rollback will be instant
Contact: [Platform Engineering on-call]
```

#### Step 3: Enable Enforcement (3 minutes)

Run the enforcement script:

```bash
# Execute enforcement (removes audit-mode annotation)
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-enable-enforcement.sh

# Expected output:
#   Enforcing namespace: argocd
#   ✓ argocd-server-ingress (enforced)
#   ✓ argocd-server-egress (enforced)
#   ... (20 more policies)
#
#   Summary:
#   - Total policies enforced: 22
#   - Success rate: 100%
#   - Time taken: ~180 seconds
```

**Monitor during execution:**
- Watch for any errors in script output
- Check kubectl for policy updates: `watch kubectl get networkpolicies -A`

#### Step 4: Validate Enforcement (2 minutes)

```bash
# Confirm all policies are now enforcing (audit-mode should be removed)
kubectl get networkpolicies -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\t"}{.metadata.annotations.policy\.cilium\.io/audit-mode}{"\n"}{end}' | grep "true" | wc -l

# Expected: 0 (no policies should be in audit mode)

# View enforcement status
kubectl get networkpolicies -A -o custom-columns=\
NAME:.metadata.name,NAMESPACE:.metadata.namespace,\
AUDIT:.metadata.annotations['policy\.cilium\.io/audit-mode'],\
POLICYTYPE:.spec.policyTypes[*]
```

#### Step 5: Connectivity Validation (5 minutes)

```bash
# Run full connectivity test suite
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-connectivity-tests.sh

# Expected: ALL TESTS PASSED
```

**If any connectivity test fails:**
- IMMEDIATELY execute rollback procedure (Section 5)
- Investigate failed connection path
- Update policy rules if necessary
- Re-enforce after validation

#### Step 6: Post-Enforcement Monitoring (30 minutes)

Monitor for issues for 30 minutes after enforcement:

```bash
# Monitor 1: Check for pod restart loops
watch -n 5 'kubectl get pods -A --sort-by=.metadata.creationTimestamp | tail -20'

# Monitor 2: Watch application logs
kubectl logs -n keycloak deployment/keycloak -f --tail=50
kubectl logs -n argocd deployment/argocd-server -f --tail=50

# Monitor 3: Check metrics
kubectl top pods -n argocd
kubectl top pods -n sonarqube
```

**Look for:**
- ✓ No unexpected pod restarts
- ✓ No spike in error logs
- ✓ Performance metrics stable vs baseline

#### Step 7: Completion Announcement

```bash
# Post final status
echo "✅ NETWORK POLICIES ENFORCEMENT COMPLETE (2026-03-03)

Status: SUCCESS
- 22/22 policies enforced
- All connectivity tests passed
- No pod restarts detected
- Performance metrics stable

Policy enforcement is now ACTIVE. All unauthorized traffic is BLOCKED.
"
```

---

## Section 4: Post-Enforcement Validation (2026-03-03+)

### 4.1 Day-1 Validation (2026-03-03 EOD)

End-of-day checklist:

```bash
# 1. All policies enforcing?
kubectl get networkpolicies -A | wc -l  # Should show 22 + header

# 2. All critical services Running?
for ns in argocd sonarqube keycloak staging-platform-gitlab staging-security-vault; do
  echo "=== $ns ==="
  kubectl get pods -n $ns | grep -v Running | grep -v NAME
done

# 3. No unusual pod restarts?
for ns in argocd sonarqube keycloak staging-platform-gitlab staging-security-vault; do
  echo "=== $ns restarts ==="
  kubectl get pods -n $ns -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}'
done

# 4. Applications healthy?
kubectl get applications -n argocd 2>/dev/null | tail -5
kubectl get statefulsets -n keycloak
kubectl logs -n sonarqube deployment/sonarqube --tail=20 | grep -i "error\|fail" || echo "No errors"
```

### 4.2 Week-1 Validation (Week of 2026-03-03)

Run daily for one week post-enforcement:

```bash
# Daily health check
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-connectivity-tests.sh

# Weekly audit log review
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-audit-analysis.sh
```

**Expected behavior (Week 1):**
- 0 connection errors (audit-mode logging is disabled now)
- All connectivity tests pass
- No cascading failures or unexpected outages
- Performance metrics stable

### 4.3 Performance Impact Assessment (Day 7 Post-Enforcement)

Compare post-enforcement metrics to baseline (captured on 2026-02-25):

```bash
# Capture current metrics
kubectl top pods -n argocd > /tmp/metrics-argocd.txt
kubectl top pods -n sonarqube > /tmp/metrics-sonarqube.txt
kubectl top pods -n keycloak > /tmp/metrics-keycloak.txt
kubectl top pods -n staging-platform-gitlab > /tmp/metrics-gitlab.txt
kubectl top pods -n staging-security-vault > /tmp/metrics-vault.txt

# Expected: <5% CPU/memory increase (minimal impact)
```

### 4.4 Team Sign-Off (Day 7 Post-Enforcement)

Document enforcement completion:

```bash
# Update ADR-070 with enforcement date
# Update MEMORY.md memory file
# Create logbook entry: 2026-03-03-gap007-enforcement.md
```

---

## Section 5: Rollback Plan (Emergency Only)

If any critical connectivity issue occurs during/after enforcement, rollback immediately:

### 5.1 Quick Rollback (Option A: Return to Audit Mode) - **Recommended**

Use this if policies are blocking legitimate traffic:

```bash
# Re-enable audit mode on all GAP-007 policies
for ns in argocd sonarqube keycloak staging-platform-gitlab staging-security-vault; do
  kubectl annotate networkpolicy -n $ns \
    policy.cilium.io/audit-mode=true --overwrite \
    -l gap=GAP-007 --overwrite
done

# Verify audit mode restored
kubectl get networkpolicies -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\t"}{.metadata.annotations.policy\.cilium\.io/audit-mode}{"\n"}{end}' | grep "true" | wc -l

# Expected: 22 (all policies back in audit mode)

# Validate connectivity
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-connectivity-tests.sh
```

### 5.2 Full Rollback (Option B: Delete All Policies) - **Last Resort**

Use this only if audit mode doesn't resolve issues:

```bash
# DELETE ALL GAP-007 policies (this is destructive!)
# ⚠️  ONLY USE IF ABSOLUTELY NECESSARY ⚠️

for ns in argocd sonarqube keycloak staging-platform-gitlab staging-security-vault; do
  kubectl delete networkpolicies -n $ns -l gap=GAP-007
done

# Verify deletion
kubectl get networkpolicies -A | grep GAP-007 | wc -l  # Should output 0

# Connectivity should restore immediately
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-connectivity-tests.sh
```

### 5.3 Selective Rollback (Option C: Delete Single Policy) - **Surgical**

Use this to rollback only the policy blocking a specific service:

```bash
# Example: Keycloak policy is blocking authentication
kubectl delete networkpolicy keycloak-ingress -n keycloak

# Test affected service
kubectl run test -n argocd --image=busybox:1.35 --restart=Never -- sleep 60
kubectl exec -n argocd test -- wget -O- http://keycloak:8080/health/ready
kubectl delete pod test -n argocd

# If successful, investigate and re-apply policy with corrected rules
```

### 5.4 Recovery After Rollback

1. **Announce rollback** to team
2. **Document** what failed (policy name, source, destination)
3. **Investigate** audit logs: `netpol-audit-analysis.sh --all`
4. **Update** policy YAML with corrected rules
5. **Re-validate** in audit mode for 1-2 days
6. **Retry** enforcement

---

## Troubleshooting Guide

### Issue: "Connection refused" from ArgoCD → Keycloak

**Diagnosis:**

```bash
# 1. Check policy exists
kubectl get networkpolicy argocd-server-egress -n argocd

# 2. Check ArgoCD pod labels
kubectl get pod -l app.kubernetes.io/name=argocd-server -n argocd --show-labels

# 3. Check if policy selects pod
kubectl describe networkpolicy argocd-server-egress -n argocd | grep podSelector -A 2

# 4. Temporarily disable policy to confirm
kubectl annotate networkpolicy argocd-server-egress -n argocd \
  policy.cilium.io/audit-mode=true --overwrite

# 5. Test connectivity
kubectl run test -n argocd --image=busybox:1.35 --restart=Never -- sleep 60
kubectl exec -n argocd test -- wget -O- http://keycloak:8080
```

**Common causes:**
- Pod labels don't match `podSelector` in policy
- Keycloak port mismatch (8080 vs 8443)
- RDS CIDR block missing from egress rule

### Issue: DNS Resolution Fails

**Diagnosis:**

```bash
# Test DNS from affected pod
kubectl exec -n <NS> <POD> -- nslookup kubernetes.default

# Check kube-dns running
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check DNS egress rule in policy
kubectl get networkpolicy <POLICY> -n <NS> -o yaml | grep -A 5 "port: 53"
```

**Fix:**
- Ensure all policies include DNS egress rule (kube-dns:53 UDP)
- Re-create policy with DNS rule if missing

### Issue: High CPU/Memory Usage Post-Enforcement

**Diagnosis:**

```bash
# Compare to baseline
kubectl top pods -n <NS> | grep <POD>

# Check if policy is missing and causing retries
kubectl describe pod <POD> -n <NS> | grep -i restart

# Check Calico performance
kubectl top pods -n kube-system -l k8s-app=calico-node
```

**Fix:**
- Network Policies should NOT increase resource usage
- If they do, it's a sign of misconfigured policies causing retries
- Return to audit mode and investigate
- Calico node pods may see small increase in CPU (normal)

---

## Monitoring & Alerting

### Metrics to Monitor (Post-Enforcement)

```promql
# 1. Connection timeout errors
increase(log_errors_total{error=~".*timeout.*"}[5m]) > 0

# 2. Policy evaluation time (should be <1ms per packet)
rate(calico_policy_evaluation_time_ms_sum[1m]) / rate(calico_policy_evaluation_time_ms_count[1m])

# 3. Pod restart spike
rate(kube_pod_container_status_restarts_total[5m]) > 0

# 4. Application error spike
rate(app_errors_total[5m]) > baseline + 10%
```

### Alert Configuration

Add these Prometheus alerts to your monitoring:

```yaml
groups:
- name: network-policies
  rules:
  - alert: NetworkPolicyConnectionErrors
    expr: increase(log_errors_total{error=~".*connection.*"}[5m]) > 5
    for: 2m
    annotations:
      summary: "High rate of connection errors post-enforcement"
      runbook: "network-policies-enforcement.md"

  - alert: NetworkPolicyPodRestarts
    expr: rate(kube_pod_container_status_restarts_total{namespace=~"(argocd|sonarqube|keycloak|staging-platform-gitlab|staging-security-vault)"}[5m]) > 0
    for: 1m
    annotations:
      summary: "Unexpected pod restarts in policy-enforced namespace"
      runbook: "network-policies-enforcement.md"
```

---

## Appendix A: Quick Reference Commands

### View all GAP-007 policies

```bash
kubectl get networkpolicies -A -l gap=GAP-007
```

### Check if policy is in audit mode

```bash
kubectl get networkpolicy <NAME> -n <NS> -o jsonpath='{.metadata.annotations.policy\.cilium\.io/audit-mode}'
```

### View policy rules

```bash
kubectl get networkpolicy <NAME> -n <NS> -o yaml
```

### Enable audit mode on specific policy

```bash
kubectl annotate networkpolicy <NAME> -n <NS> policy.cilium.io/audit-mode=true --overwrite
```

### Remove audit mode from specific policy

```bash
kubectl annotate networkpolicy <NAME> -n <NS> policy.cilium.io/audit-mode- --overwrite
```

### Count policies in enforcement status

```bash
# Count enforcing policies
kubectl get networkpolicies -A -o json | jq '.items[] | select(.metadata.annotations["policy.cilium.io/audit-mode"] != "true") | .metadata.name' | wc -l

# Count audit mode policies
kubectl get networkpolicies -A -o json | jq '.items[] | select(.metadata.annotations["policy.cilium.io/audit-mode"] == "true") | .metadata.name' | wc -l
```

---

## Appendix B: Key Pod Labels (Label Reference)

| Service | Namespace | Label | Purpose |
|---------|-----------|-------|---------|
| ArgoCD Server | argocd | `app.kubernetes.io/name: argocd-server` | Ingress from ALB, OIDC from users |
| ArgoCD Repo Server | argocd | `app.kubernetes.io/name: argocd-repo-server` | Git repo fetches |
| ArgoCD App Controller | argocd | `app.kubernetes.io/name: argocd-application-controller` | K8s API access |
| Keycloak Server | keycloak | `app.kubernetes.io/name: keycloakx` | SSO for all services |
| SonarQube | sonarqube | `app: sonarqube` | Code quality service |
| GitLab Webservice | staging-platform-gitlab | `app: webservice` | Main GitLab API/UI |
| GitLab Sidekiq | staging-platform-gitlab | `app: sidekiq` | Background jobs |
| GitLab Gitaly | staging-platform-gitlab | `app: gitaly` | Git storage |
| GitLab Runner | staging-platform-gitlab | `app: gitlab-gitlab-runner` | CI/CD executor |
| Vault Server | staging-security-vault | `app.kubernetes.io/name: vault, component: server` | Secrets storage |
| ESO | staging-security-externalsecrets | `app.kubernetes.io/name: external-secrets` | Secret syncing |

---

## References

- **ADR-070**: `/docs/adr/adr-070-network-policies-marco4-least-privilege.md`
- **Policy Files**: `/domains/security/network-policies/marco4/`
- **Troubleshooting Guide**: `/docs/runbooks/network-policy-troubleshooting.md`
- **Kubernetes Network Policies**: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- **Calico Documentation**: https://docs.tigera.io/calico/latest/network-policy/

---

**Document Version:** 1.0
**Last Updated:** 2026-02-25
**Status:** Ready for 2026-03-03 Enforcement

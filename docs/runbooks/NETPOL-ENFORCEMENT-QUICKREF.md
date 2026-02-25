# Network Policy Enforcement - Quick Reference Guide

**Created:** 2026-02-25
**Enforcement Date:** 2026-03-03
**Gap:** GAP-007 (Network Segmentation)
**ADR:** ADR-070

---

## Timeline

- **2026-02-25**: All 22 Network Policies deployed in AUDIT MODE
- **2026-02-26 to 2026-03-02**: Daily validation (7-day audit period)
- **2026-03-03**: ENFORCEMENT DAY (remove audit-mode annotations)

---

## Quick Command Reference

### Daily Validation (2026-02-26 to 2026-03-02)

Run once per day to check for issues:

```bash
# Daily audit analysis
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-audit-analysis.sh

# Daily connectivity test
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-connectivity-tests.sh
```

**Expected Output:**
- Audit analysis: "SAFE_TO_ENFORCE"
- Connectivity tests: "ALL TESTS PASSED ✓"

---

## Enforcement Day (2026-03-03) - 15 Minutes Total

### Pre-Enforcement (5 min)

```bash
# 1. Check audit logs (should show minimal denies)
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-audit-analysis.sh

# 2. Final connectivity validation
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-connectivity-tests.sh

# 3. Verify all policies still in audit mode
kubectl get networkpolicies -A -o jsonpath='{range .items[*]}{.metadata.annotations.policy\.cilium\.io/audit-mode}{"\n"}{end}' | grep -c "true"
# Expected: 22
```

**If any check fails: STOP and investigate before proceeding**

### Enable Enforcement (3 min)

```bash
# Remove audit-mode annotations (enable enforcement)
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-enable-enforcement.sh --confirm
```

### Post-Enforcement Validation (5 min)

```bash
# Verify enforcement enabled
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-connectivity-tests.sh

# Check for pod restart loops
watch -n 5 'kubectl get pods -A --sort-by=.metadata.creationTimestamp | tail -20'

# Monitor for 30 minutes (look for errors, restarts, timeouts)
```

---

## Emergency Rollback

### Option 1: Return to Audit Mode (Recommended)

Use if policies are blocking legitimate traffic:

```bash
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-disable-enforcement.sh --confirm
```

**Effect:** Policies log violations but don't block (no traffic disruption)

### Option 2: Delete All Policies (Last Resort)

Use only if audit mode doesn't resolve issues:

```bash
bash /home/gilvangalindo/projects/Arquitetura/Kubernetes/scripts/security/netpol-disable-enforcement.sh --mode delete --confirm
```

**Effect:** All traffic restrictions removed immediately

---

## Troubleshooting

### Issue: "Connection refused" after enforcement

**Quick fix:**
1. Check which policy is blocking: `kubectl describe networkpolicies -n <NS>`
2. Verify pod labels match: `kubectl get pod <POD> -n <NS> --show-labels`
3. Return to audit mode: `bash netpol-disable-enforcement.sh --confirm`
4. Investigate and fix policy rules
5. Re-validate and re-enforce

### Issue: Pod can't reach database

**Quick check:**
```bash
# Verify RDS CIDR in egress rules
kubectl get networkpolicy <NAME> -n <NS> -o yaml | grep -A 5 "ipBlock"

# Expected: RDS CIDR (e.g., 10.0.0.0/16) is whitelisted
```

### Issue: DNS resolution fails

**Quick fix:**
- All policies should include DNS egress rule (kube-dns:53)
- If missing, re-apply policy with DNS rule

---

## Policy Inventory

| Namespace | Count | Status (2026-02-25) |
|-----------|-------|---------------------|
| argocd | 6 | Audit |
| sonarqube | 2 | Audit |
| keycloak | 3 | Audit |
| staging-platform-gitlab | 8 | Audit |
| staging-security-vault | 3 | Audit |
| **TOTAL** | **22** | **All Audit** |

---

## Useful Commands

### View all GAP-007 policies in audit mode
```bash
kubectl get networkpolicies -A -l gap=GAP-007 -o jsonpath='{range .items[?(@.metadata.annotations.policy\.cilium\.io/audit-mode=="true")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'
```

### View specific policy rules
```bash
kubectl get networkpolicy <NAME> -n <NS> -o yaml
```

### Check pod labels
```bash
kubectl get pod <POD> -n <NS> --show-labels
```

### List all namespaces with GAP-007 policies
```bash
kubectl get networkpolicies -A -l gap=GAP-007 | grep -E "^[a-z]" | awk '{print $1}' | sort -u
```

---

## Key Contacts

- **Platform Engineering On-Call**: [Contact info]
- **Security Team**: [Contact info]
- **Documentation**: `/docs/adr/adr-070-network-policies-marco4-least-privilege.md`

---

## References

- **Full Runbook**: `/docs/runbooks/network-policies-enforcement.md`
- **Troubleshooting**: `/docs/runbooks/network-policy-troubleshooting.md`
- **Scripts Location**: `/scripts/security/`
- **Policy Files**: `/domains/security/network-policies/marco4/`

---

**Status**: Ready for 2026-03-03 enforcement

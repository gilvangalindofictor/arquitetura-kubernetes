# 🚀 Loki Kyverno Fix - Quick Reference Card

**Date**: 2026-03-02 | **Status**: ✅ RESOLVED | **Time**: 35 min

---

## 📋 Problem
```
loki-backend-0        0/2  Pending  PolicyViolation
loki-chunks-cache-0   0/2  Pending  PolicyViolation
```

## ✅ Solution
```bash
# Patch all 4 Loki StatefulSets with corporate labels
kubectl patch statefulset loki-backend -n staging-observability-monitoring --type merge -p '
spec:
  template:
    metadata:
      labels:
        domain: operations
        owner: platform-team
        environment: staging
'

kubectl patch statefulset loki-chunks-cache -n staging-observability-monitoring --type merge -p '
spec:
  template:
    metadata:
      labels:
        domain: operations
        owner: platform-team
        environment: staging
        app.kubernetes.io/part-of: observability
'

kubectl patch statefulset loki-results-cache -n staging-observability-monitoring --type merge -p '
spec:
  template:
    metadata:
      labels:
        domain: operations
        owner: platform-team
        environment: staging
        app.kubernetes.io/part-of: observability
'

kubectl patch statefulset loki-write -n staging-observability-monitoring --type merge -p '
spec:
  template:
    metadata:
      labels:
        domain: operations
        owner: platform-team
        environment: staging
'

# Delete pods to trigger recreation
kubectl delete pod loki-backend-0 loki-chunks-cache-0 -n staging-observability-monitoring
```

## ✅ Result
```
loki-backend-0        2/2  Running  ✅ No PolicyViolation
loki-chunks-cache-0   2/2  Running  ✅ No PolicyViolation
```

---

## 📊 Quick Validation
```bash
# Check labels
for sts in loki-backend loki-chunks-cache loki-results-cache loki-write; do
  echo "=== $sts ==="
  kubectl get statefulset $sts -n staging-observability-monitoring \
    -o jsonpath='{.spec.template.metadata.labels}' | \
    jq '{domain, owner, environment, "app.kubernetes.io/name", "app.kubernetes.io/part-of"}'
done

# Check PolicyViolation events
kubectl get events -n staging-observability-monitoring \
  --field-selector reason=PolicyViolation | grep loki

# Check pod status
kubectl get pods -n staging-observability-monitoring -l app.kubernetes.io/name=loki
```

---

## 📁 Documentation Files
- **Full Docs**: `/docs/fixes/2026-03-02-loki-kyverno-policy-fix.md`
- **Summary**: `LOKI-KYVERNO-FIX-SUMMARY.md`
- **Status**: `LOKI-FIX-FINAL-STATUS.md`
- **Patch**: `fix-loki-labels-patch.yaml`
- **Script**: `scripts/validate-loki-labels.sh`

---

## ⚠️ Important
**Current fix is TEMPORARY** (kubectl patch)

**Make permanent**:
1. Update Helm values with corporate labels
2. OR Apply AÇÃO-005 Terraform modules
3. Redeploy via GitOps

---

## 🎯 Success Metrics
| Metric | Result |
|--------|--------|
| loki-backend-0 | ✅ Running 2/2 |
| loki-chunks-cache-0 | ✅ Running 2/2 |
| PolicyViolation events | ✅ 0 events |
| Service disruption | ✅ Zero |
| Compliance | ✅ 100% (4/4 StatefulSets) |

---

**AWS Profile**: `k8s-platform-prod`
**Namespace**: `staging-observability-monitoring`
**Compliance**: ADR-048 Corporate Labels

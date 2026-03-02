# ⚡ Loki Fix — Quick Reference Card

```
┌─────────────────────────────────────────────────────────────────┐
│                     LOKI FIX QUICK REFERENCE                    │
│                         2026-02-27                              │
└─────────────────────────────────────────────────────────────────┘
```

## 🔴 Problem
```
Loki read pods: CrashLoopBackOff
Error: field shared_store not found in type compactor.Config
Impact: Log ingestion stopped, correlation blocked
```

## ✅ Solution (ONE COMMAND)
```bash
helm upgrade loki grafana/loki \
  -n staging-observability-monitoring \
  -f /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/migrations/wave5-monitoring/loki-values-updated.yaml \
  --version 6.53.0 --wait --timeout 5m
```

## ⏱️ Timeline
- **Fix:** 5 minutes (Helm upgrade)
- **Validation:** 2 minutes (pods + logs + API)
- **Soak test:** 10 minutes (optional stability check)
- **Total:** 12 minutes (fast path) | 23 minutes (full)

## 🧪 Validation (Copy-Paste)
```bash
# Check pods (expect: all Running)
kubectl get pods -n staging-observability-monitoring -l app.kubernetes.io/name=loki

# Check logs (expect: no errors)
kubectl logs -n staging-observability-monitoring \
  $(kubectl get pod -n staging-observability-monitoring -l app.kubernetes.io/component=read -o jsonpath='{.items[0].metadata.name}') \
  --tail=10 | grep -i error

# Test API (expect: returns data)
kubectl exec -n staging-observability-monitoring \
  $(kubectl get pod -n staging-observability-monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}') \
  -c grafana -- \
  curl -s 'http://loki-gateway.staging-observability-monitoring.svc.cluster.local/loki/api/v1/query?query={namespace="staging-observability-monitoring"}&limit=1' | jq .
```

## 🔄 Rollback (If Needed)
```bash
helm rollback loki -n staging-observability-monitoring --wait --timeout 3m
```

## 📊 Success Criteria
- [ ] 0 pods in CrashLoopBackOff
- [ ] 0 "shared_store" errors in logs
- [ ] Loki API returns log data
- [ ] Grafana Loki datasource: Status OK
- [ ] No pod restarts for 10 minutes

## 🎯 What Changed
```yaml
# BEFORE (deprecated)
compactor:
  shared_store: s3  # ❌ Removed in Loki 3.6.5

# AFTER (correct)
compactor:
  delete_request_store: s3  # ✅ New field name
```

## 📁 Files
| File | Purpose |
|------|---------|
| `LOKI-FIX-EXECUTIVE-SUMMARY.md` | TL;DR with one-command fix |
| `LOKI-FIX-QUICKSTART.sh` | Automated script with prompts |
| `docs/operations/loki-fix-execution-plan.md` | 23-step detailed procedure |
| `docs/operations/loki-fix-mesa-tecnica-analysis.md` | Multi-agent analysis |
| `docs/migrations/wave5-monitoring/loki-values-updated.yaml` | Corrected values file |

## 🚀 Quick Start Options

### Option 1: Automated (Recommended)
```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes
./LOKI-FIX-QUICKSTART.sh
```

### Option 2: Manual
```bash
# 1. Upgrade (5 min)
helm upgrade loki grafana/loki \
  -n staging-observability-monitoring \
  -f /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/migrations/wave5-monitoring/loki-values-updated.yaml \
  --version 6.53.0 --wait --timeout 5m

# 2. Validate (2 min)
kubectl get pods -n staging-observability-monitoring -l app.kubernetes.io/name=loki

# 3. Commit (1 min)
cp docs/migrations/wave5-monitoring/loki-values-updated.yaml \
   domains/observability/infra/helm/loki/values.yaml
git add domains/observability/infra/helm/loki/values.yaml
git commit -m "fix(loki): Replace deprecated compactor.shared_store"
```

## ⚠️ Risk Assessment
- **Overall:** LOW
- **Rollback time:** 2 minutes
- **Data loss risk:** VERY LOW (S3-backed)
- **Downtime:** ~30 seconds (pod restarts)

## 🎓 Why This Fix?

**Mesa Técnica Decision (3 agents):**
- ✅ Historian: Fix documented but never applied
- ✅ K8s Expert: Helm values need update
- ✅ Solution Architect: Option A (Helm Upgrade) scores 9.4/10

**Rejected Alternatives:**
- ❌ Option B (ConfigMap patch): Not GitOps compliant
- ❌ Option C (Rollback): No stable version to rollback to

## 📞 Troubleshooting

### If Helm upgrade fails:
```bash
# Check Helm history
helm history loki -n staging-observability-monitoring

# Rollback
helm rollback loki -n staging-observability-monitoring --wait
```

### If pods still crash:
```bash
# Check events
kubectl describe pod -n staging-observability-monitoring loki-read-XXX

# Check previous logs
kubectl logs -n staging-observability-monitoring loki-read-XXX --previous

# Check resources
kubectl top pod -n staging-observability-monitoring loki-read-XXX
```

### If capacity blocks pods:
```bash
# Check node capacity
kubectl get nodes -l node-type=system

# Scale system nodes (if needed)
aws eks update-nodegroup-config \
  --cluster-name k8s-platform-prod \
  --nodegroup-name system-nodes \
  --scaling-config minSize=4,maxSize=6,desiredSize=5 \
  --region us-east-1 --profile k8s-platform-prod
```

## 📈 Expected Impact

**Immediate:**
- ✅ Log ingestion restored
- ✅ Grafana Loki datasource: OK
- ✅ 0 CrashLoops

**Short-term:**
- ✅ Loki-Tempo correlation working
- ✅ Sprint 3 Priority 3: 100% complete
- ✅ Platform health: 95%+

**Long-term:**
- ✅ Observability maturity improved
- ✅ MTTR reduced (one-click trace navigation)
- ✅ GitOps compliance restored

---

```
┌─────────────────────────────────────────────────────────────────┐
│  STATUS: ✅ READY FOR EXECUTION                                 │
│  APPROVAL: Solution Architect — Mesa Técnica Virtual           │
│  RISK: LOW | ETA: 12 minutes | ROLLBACK: 2 minutes             │
└─────────────────────────────────────────────────────────────────┘
```

**Ready to fix?** Run `./LOKI-FIX-QUICKSTART.sh` or copy-paste manual commands above.

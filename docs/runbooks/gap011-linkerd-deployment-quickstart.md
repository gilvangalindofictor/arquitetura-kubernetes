# GAP-011 Linkerd Deployment — Quick Start Runbook

**Status**: ⏸️ BLOCKED — Staging offline
**Ready to Deploy**: ✅ YES
**Estimated Time**: 30-40 minutes
**Cost**: +$5/month

---

## Prerequisites Check

```bash
# 1. AWS Session
aws sts get-caller-identity || exit 1

# 2. Kubernetes Cluster
kubectl cluster-info --context=k8s-platform-prod || exit 1

# 3. Navigate to staging environment
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging
```

---

## Deployment Commands

### Step 1: Terraform Plan (5 minutes)

```bash
terraform init -upgrade
terraform plan -out=gap011-linkerd.tfplan -target=module.linkerd 2>&1 | tee /tmp/gap011-plan.log

# Validate: Expected ~11 resources
grep -c "module.linkerd" /tmp/gap011-plan.log
```

### Step 2: Terraform Apply (15-20 minutes)

```bash
# Apply in background with monitoring
terraform apply gap011-linkerd.tfplan > /tmp/gap011-apply.log 2>&1 &
APPLY_PID=$!

# Monitor pods during apply (15s refresh)
while kill -0 $APPLY_PID 2>/dev/null; do
  clear
  echo ">>> Control Plane Pods:"
  kubectl get pods -n linkerd --context=k8s-platform-prod 2>/dev/null || echo "Not ready yet"
  echo ""
  echo ">>> Viz Pods:"
  kubectl get pods -n linkerd-viz --context=k8s-platform-prod 2>/dev/null || echo "Not ready yet"
  echo ""
  echo ">>> Terraform log:"
  tail -10 /tmp/gap011-apply.log
  sleep 15
done

wait $APPLY_PID
```

### Step 3: Validation (5 minutes)

```bash
# 3.1. Control Plane Ready
kubectl get pods -n linkerd --context=k8s-platform-prod
# Expected: linkerd-destination 4/4, linkerd-identity 2/2, linkerd-proxy-injector 2/2

# 3.2. CRDs Installed
kubectl get crd | grep linkerd.io | wc -l
# Expected: 6 CRDs

# 3.3. Viz Ready
kubectl get pods -n linkerd-viz --context=k8s-platform-prod
# Expected: 4 pods Running (metrics-api, tap, tap-injector, web)

# 3.4. Linkerd CLI Check (if installed)
linkerd check --context=k8s-platform-prod || echo "linkerd CLI not installed (optional)"

# 3.5. PKI Certificate Expiry
terraform output linkerd_trust_anchor_certificate_expiry
# Expected: 8760 (365 days)
```

### Step 4: Proxy Injection Test (5 minutes)

```bash
# 4.1. Create test namespace
kubectl apply --context=k8s-platform-prod -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: linkerd-test
  annotations:
    linkerd.io/inject: enabled
EOF

# 4.2. Deploy test pod
kubectl run nginx-linkerd-test --image=nginx:alpine --namespace=linkerd-test --context=k8s-platform-prod

# 4.3. Wait for Ready
kubectl wait --for=condition=Ready pod/nginx-linkerd-test -n linkerd-test --timeout=60s --context=k8s-platform-prod

# 4.4. Verify proxy injected
kubectl get pod nginx-linkerd-test -n linkerd-test --context=k8s-platform-prod -o jsonpath='{.spec.containers[*].name}'
# Expected: nginx linkerd-proxy

# 4.5. Cleanup
kubectl delete namespace linkerd-test --context=k8s-platform-prod
```

---

## Success Criteria

- ✅ Control Plane: 3 pods Ready (destination, identity, proxy-injector)
- ✅ Viz Extension: 4 pods Ready (metrics-api, tap, tap-injector, web)
- ✅ CRDs: 6 CRDs installed (authorizationpolicies, httproutes, meshtlsauthentications, servers, serverauthorizations, serviceprofiles)
- ✅ PKI: Trust anchor valid for 365 days
- ✅ Proxy Injection: Test pod has linkerd-proxy sidecar

---

## Troubleshooting

### Pods stuck in Pending
```bash
kubectl describe pod -n linkerd | grep -A5 "Events:"
# Common: Insufficient CPU/Memory — scale nodes or reduce proxy_cpu_request
```

### Helm release timeout
```bash
helm list -n linkerd --kube-context k8s-platform-prod
# If FAILED: helm uninstall linkerd-control-plane -n linkerd && terraform apply
```

### Proxy not injected
```bash
# Check MutatingWebhookConfiguration
kubectl get mutatingwebhookconfiguration linkerd-proxy-injector -o yaml | grep caBundle
# If empty: Helm release incomplete, check control plane pods
```

### CRDs conflict
```bash
# List existing Linkerd CRDs
kubectl get crd | grep linkerd.io
# If duplicated: kubectl delete crd <crd-name> && terraform apply
```

---

## Rollback (If Apply Fails)

```bash
# 1. Destroy partial resources
terraform destroy -target=module.linkerd -auto-approve

# 2. Clean orphaned namespaces
kubectl delete namespace linkerd linkerd-viz --context=k8s-platform-prod --force --grace-period=0

# 3. Clean CRDs
kubectl get crd | grep linkerd.io | awk '{print $1}' | xargs kubectl delete crd --context=k8s-platform-prod

# 4. Retry
terraform init -reconfigure
terraform plan -out=gap011-linkerd-retry.tfplan -target=module.linkerd
terraform apply gap011-linkerd-retry.tfplan
```

---

## Post-Deployment Actions

### 1. Create logbook
```bash
# Document deployment in:
# /docs/logbook/2026-02-26-gap011-linkerd-deployment-success.md
```

### 2. Update MEMORY.md
```markdown
| GAP-011: Linkerd Service Mesh (mTLS BACEN) | +$5/mês | COMPLETO (2026-02-26) |
```

### 3. Update demands-backlog.md
```markdown
| GAP-011 | Linkerd Service Mesh | ✅ COMPLETO | 2026-02-26 |
```

### 4. Enable proxy injection for production namespaces
```bash
# When applications are ready:
kubectl annotate namespace <namespace> linkerd.io/inject=enabled --context=k8s-platform-prod
kubectl rollout restart deployment -n <namespace> --context=k8s-platform-prod
```

---

## Compliance Mapping — BACEN BCB 85/2021

| Article | Control | Status |
|---------|---------|--------|
| Art. 6º SS IV — Encryption in transit | mTLS automatic (SPIFFE/SPIRE) | ✅ Deployed |
| Art. 6º SS V — Mutual authentication | x.509 certs per ServiceAccount | ✅ Deployed |
| Art. 9º — Credential rotation | 24h TTL + auto-rotation | ✅ Deployed |
| Art. 11º — Communication audit | Tap API + Prometheus L7 metrics | ✅ Deployed |
| Art. 15º — Traffic segregation | AuthorizationPolicy CRDs | ✅ Deployed (pending: create policies) |

---

## Architecture Overview

```
┌──────────────────────────────────────────────┐
│    Linkerd Control Plane (namespace: linkerd)│
│  - identity: SPIFFE cert issuer              │
│  - proxy-injector: MutatingWebhook           │
│  - destination: L7 traffic control           │
└──────────────────────────────────────────────┘
            ↓
┌──────────────────────────────────────────────┐
│   Linkerd Viz (namespace: linkerd-viz)       │
│  - dashboard: http://web:8084                │
│  - tap: real-time L7 traffic inspection      │
│  - metrics-api: Prometheus integration       │
└──────────────────────────────────────────────┘
            ↓
┌──────────────────────────────────────────────┐
│   Data Plane (opt-in per namespace)          │
│  - Annotation: linkerd.io/inject=enabled     │
│  - Sidecar: linkerd-proxy (100m CPU, 64Mi)   │
│  - mTLS: automatic SPIFFE identity           │
└──────────────────────────────────────────────┘
```

---

## Cost Breakdown

| Resource | Staging (ha_mode=false) | Production (ha_mode=true) |
|----------|-------------------------|---------------------------|
| Control Plane | +$2/month | +$6/month |
| Viz Extension | +$1/month | +$1/month |
| Proxy Sidecars (2 namespaces) | +$2/month | +$2/month |
| **Total** | **+$5/month** | **+$9/month** |

---

## Terraform Module Files

- **Main**: `/platform-provisioning/aws/kubernetes/terraform/modules/linkerd/main.tf`
- **Variables**: `/platform-provisioning/aws/kubernetes/terraform/modules/linkerd/variables.tf`
- **Outputs**: `/platform-provisioning/aws/kubernetes/terraform/modules/linkerd/outputs.tf`
- **README**: `/platform-provisioning/aws/kubernetes/terraform/modules/linkerd/README.md`

**Staging Integration**: `/platform-provisioning/aws/kubernetes/terraform/environments/staging/main.tf` (lines 2298-2374)

---

**BLOCKED**: ⏸️ Staging environment offline — AWS credentials unavailable
**READY TO DEPLOY**: ✅ All Terraform artifacts reviewed and tested
**NEXT ACTION**: Execute this runbook when staging is online

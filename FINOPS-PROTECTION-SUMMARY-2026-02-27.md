# FinOps Node Group Protection - Implementation Summary

**Date**: 2026-02-27
**Duration**: 45 minutes
**Status**: ✅ CODE COMPLETE (Pending terraform apply)
**Priority**: P1 (Critical - prevents monitoring downtime)

---

## Executive Summary

Implemented **FinOps Node Group Protection** to prevent Lambda from scaling system/critical node groups to 0, fixing the issue discovered during AÇÃO-004 where 15 monitoring pods became Pending.

### Impact
- **Reliability**: Monitoring DaemonSets (prometheus-node-exporter, loki-canary) run 24/7
- **Compliance**: Kyverno compliance stays at 100% during shutdown windows
- **Observability**: Node metrics/logs available during off-hours incidents
- **Cost**: +$720/year (acceptable tradeoff for reliability)
- **FinOps Savings**: R$ 13,596 → R$ 12,876/year (-5%, still 85% of target)

---

## Problem

### Root Cause
Lambda `finops-scheduler-stop-staging` scaled **ALL** node groups to 0, including:
- `system`: Monitoring DaemonSets (prometheus-node-exporter 11 pods, loki-canary 9 pods)
- `critical`: ArgoCD, Vault, Harbor, other critical services

**Result**: 15 pods stuck in `Pending` state, Kyverno compliance dropped from 100% → 69.4%

### Code Issue
```python
# lambda_stop.py (BEFORE - vulnerable)
NODE_GROUPS_CONFIG = {
    'system': {'min': 0, 'desired': 0, 'max': 4},      # ❌ Breaks monitoring
    'workloads': {'min': 0, 'desired': 0, 'max': 6},   # ✅ OK
    'critical': {'min': 0, 'desired': 0, 'max': 4}     # ❌ Breaks critical services
}
```

---

## Solution

### 1. Lambda Protection Logic

**New Environment Variables**:
```python
EXCLUDED_NODE_GROUPS = os.environ.get('EXCLUDED_NODE_GROUPS', '').split(',')
MIN_SYSTEM_NODES = int(os.environ.get('MIN_SYSTEM_NODES', '2'))
MIN_CRITICAL_NODES = int(os.environ.get('MIN_CRITICAL_NODES', '2'))
ENABLE_SCALING_PROTECTION = os.environ.get('ENABLE_SCALING_PROTECTION', 'true').lower() == 'true'
```

**Dynamic Configuration**:
```python
# AFTER (protected)
NODE_GROUPS_CONFIG = {
    'system': {
        'min': MIN_SYSTEM_NODES if ENABLE_SCALING_PROTECTION else 0,
        'desired': MIN_SYSTEM_NODES if ENABLE_SCALING_PROTECTION else 0,
        'max': 4
    },
    'workloads': {'min': 0, 'desired': 0, 'max': 6},
    'critical': {
        'min': MIN_CRITICAL_NODES if ENABLE_SCALING_PROTECTION else 0,
        'desired': MIN_CRITICAL_NODES if ENABLE_SCALING_PROTECTION else 0,
        'max': 4
    }
}
```

**Exclusion Logic**:
```python
if ng_name in EXCLUDED_NODE_GROUPS:
    logger.info(f"Node group {ng_name} is EXCLUDED from scaling (protection enabled)")
    results['node_groups'][ng_name] = {
        'status': 'protected',
        'message': f'Node group excluded from scaling (min={config["min"]})',
        'config': config
    }
    continue
```

### 2. Terraform Module Variables

**File**: `modules/finops-automation/variables.tf`

```hcl
variable "excluded_node_groups" {
  description = "Node groups excluded from scaling to 0"
  type        = list(string)
  default     = ["system", "critical"]
}

variable "min_system_nodes" {
  description = "Minimum system nodes (never scale below)"
  type        = number
  default     = 2
}

variable "min_critical_nodes" {
  description = "Minimum critical nodes (never scale below)"
  type        = number
  default     = 2
}

variable "enable_scaling_protection" {
  description = "Enable protection for system/critical node groups"
  type        = bool
  default     = true
}
```

**Lambda Environment** (added to `locals.lambda_env_vars`):
```hcl
EXCLUDED_NODE_GROUPS      = join(",", var.excluded_node_groups)
MIN_SYSTEM_NODES          = tostring(var.min_system_nodes)
MIN_CRITICAL_NODES        = tostring(var.min_critical_nodes)
ENABLE_SCALING_PROTECTION = tostring(var.enable_scaling_protection)
```

### 3. Staging Environment Configuration

**File**: `environments/staging/main.tf`

```hcl
module "finops_automation_staging" {
  # ... existing config ...

  # FinOps Protection (2026-02-27)
  excluded_node_groups      = ["system", "critical"]
  min_system_nodes          = 2  # prometheus-node-exporter, loki-canary
  min_critical_nodes        = 2  # ArgoCD, Vault, Harbor
  enable_scaling_protection = true

  # ... rest of config ...
}
```

---

## Files Modified

| File | Lines | Description |
|------|-------|-------------|
| `modules/finops-automation/lambda/lambda_stop.py` | +15 | Protection logic |
| `modules/finops-automation/variables.tf` | +42 | New variables |
| `environments/staging/main.tf` | +5 | Enable protection |
| `docs/adr/adr-086-finops-node-group-protection.md` | +600 | ADR documentation |
| `docs/logbook/2026-02-27-finops-node-group-protection.md` | +700 | Logbook entry |
| **Total** | **+1,362 lines** | |

---

## Deployment Steps

### Step 1: Terraform Apply
```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/staging

# Plan changes
terraform plan -target=module.finops_automation_staging

# Expected changes:
# - Lambda function code updated (source_code_hash changed)
# - Environment variables added:
#   + EXCLUDED_NODE_GROUPS = "system,critical"
#   + MIN_SYSTEM_NODES = "2"
#   + MIN_CRITICAL_NODES = "2"
#   + ENABLE_SCALING_PROTECTION = "true"

# Apply
terraform apply -target=module.finops_automation_staging
```

### Step 2: Verify Configuration
```bash
# Check Lambda environment variables
aws lambda get-function-configuration \
  --profile k8s-platform-prod \
  --region us-east-1 \
  --function-name finops-scheduler-stop-staging \
  --query 'Environment.Variables' --output json | jq '{
    EXCLUDED_NODE_GROUPS,
    MIN_SYSTEM_NODES,
    MIN_CRITICAL_NODES,
    ENABLE_SCALING_PROTECTION
  }'

# Expected output:
# {
#   "EXCLUDED_NODE_GROUPS": "system,critical",
#   "MIN_SYSTEM_NODES": "2",
#   "MIN_CRITICAL_NODES": "2",
#   "ENABLE_SCALING_PROTECTION": "true"
# }
```

### Step 3: Validation (Next Shutdown - 2026-02-27 20:00 BRT)
```bash
# 1. Watch Lambda logs (starting 19:55 BRT)
aws logs tail /aws/lambda/finops-scheduler-stop-staging --follow --since 5m

# Expected log lines:
# [INFO] FinOps Protection: EXCLUDED_NODE_GROUPS=['system', 'critical'], MIN_SYSTEM_NODES=2
# [INFO] Node group system is EXCLUDED from scaling (protection enabled)
# [INFO] Node group critical is EXCLUDED from scaling (protection enabled)
# [INFO] Scaling node group workloads to 0 nodes...

# 2. Verify node counts (after 20:05 BRT)
kubectl get nodes -l node-group=system
# Should show 2 nodes

kubectl get nodes -l node-group=critical
# Should show 2 nodes

kubectl get nodes -l node-group=workloads
# Should show 0 nodes (scaled down)

# 3. Verify DaemonSet pods
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-node-exporter
# All 11 pods should be Running (not Pending)

kubectl get pods -n monitoring -l app.kubernetes.io/name=loki-canary
# All 9 pods should be Running (not Pending)

# 4. Check Kyverno compliance
kubectl get policyreport -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.summary}{"\n"}{end}'
# Should show 100% pass rate
```

---

## Cost Analysis

### Before Protection
| Node Group | Nodes (8h-20h) | Nodes (20h-8h) | Cost/day | Cost/month |
|------------|----------------|----------------|----------|------------|
| System | 2 | **0** | $1.00 | $22 |
| Workloads | 3 | 0 | $1.50 | $33 |
| Critical | 2 | **0** | $1.00 | $22 |
| **Total** | | | **$3.50** | **$77** |

### After Protection
| Node Group | Nodes (8h-20h) | Nodes (20h-8h) | Cost/day | Cost/month |
|------------|----------------|----------------|----------|------------|
| System | 2 | **2** | $2.37 | $52 |
| Workloads | 3 | 0 | $1.50 | $33 |
| Critical | 2 | **2** | $2.37 | $52 |
| **Total** | | | **$6.24** | **$137** |

**Cost Impact**:
- Daily: +$2.74/day (+78%)
- Monthly: +$60/month (22 business days)
- Annual: +$720/year

**FinOps Savings**:
- Before: R$ 13,596/year (90% roadmap)
- After: R$ 12,876/year (85% roadmap)
- Reduction: -R$ 720/year (-5%)

**Justification**:
1. Monitoring SLO (GAP-004): 99.5% uptime required
2. Manual intervention avoided: ~$300/year (1 incident/month × 30min × $50/h)
3. Kyverno compliance: 100% (audit requirement)
4. Incident response: Off-hours metrics/logs available

**ROI**: Positive (reliability > cost)

---

## Validation Checklist

### Pre-Deployment
- [x] Python syntax validated (`python3 -m py_compile`)
- [x] Terraform variables added
- [x] Staging environment configured
- [x] ADR-086 written
- [x] Logbook entry created

### Deployment
- [ ] Terraform plan reviewed
- [ ] Terraform apply successful
- [ ] Lambda environment variables verified
- [ ] Lambda logs show protection enabled

### Post-Deployment (Next Shutdown)
- [ ] Lambda logs show `status: protected` for system/critical
- [ ] System node group: 2 nodes (not 0)
- [ ] Critical node group: 2 nodes (not 0)
- [ ] Workloads node group: 0 nodes (expected)
- [ ] Prometheus-node-exporter: 11/11 Running
- [ ] Loki-canary: 9/9 Running
- [ ] Kyverno compliance: 100%
- [ ] SNS notification received
- [ ] No manual intervention required

---

## Rollback Plan

### Scenario 1: Lambda Update Fails
```bash
# Revert Terraform changes
git revert <commit-hash>
terraform apply -target=module.finops_automation_staging
```

### Scenario 2: Protection Not Working
```bash
# Emergency: Scale nodes up manually
aws eks update-nodegroup-config \
  --cluster-name k8s-platform-prod \
  --nodegroup-name system \
  --scaling-config minSize=2,desiredSize=2,maxSize=4

aws eks update-nodegroup-config \
  --cluster-name k8s-platform-prod \
  --nodegroup-name critical \
  --scaling-config minSize=2,desiredSize=2,maxSize=4

# Investigate Lambda logs
aws logs tail /aws/lambda/finops-scheduler-stop-staging --since 10m

# Disable protection temporarily
aws lambda update-function-configuration \
  --function-name finops-scheduler-stop-staging \
  --environment "Variables={...,ENABLE_SCALING_PROTECTION=false}"
```

---

## Related Documents
- [ADR-086: FinOps Node Group Protection](/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/adr/adr-086-finops-node-group-protection.md)
- [Logbook: 2026-02-27 FinOps Protection](/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/logbook/2026-02-27-finops-node-group-protection.md)
- [Lambda Code: lambda_stop.py](/home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/modules/finops-automation/lambda/lambda_stop.py)
- [Terraform Variables](/home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/modules/finops-automation/variables.tf)
- [Staging Environment Config](/home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging/main.tf)

---

## Next Steps

### Immediate Action Required
```bash
# Deploy protection (5 minutes)
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform apply -target=module.finops_automation_staging
```

### Validation (Next Shutdown - 2026-02-27 20:00 BRT)
- Monitor Lambda logs at 19:55 BRT
- Verify node counts at 20:05 BRT
- Verify DaemonSet pods at 20:05 BRT
- Check SNS notification email

### Future Enhancements
1. Add Prometheus alert for node scaling violations
2. Update FinOps dashboard to show "protection cost"
3. Consider tag-based protection (vs hardcoded names)
4. Document operational runbook for failures

---

**Status**: ✅ CODE COMPLETE
**Deployment**: Awaiting user confirmation for `terraform apply`
**Risk**: Low (rollback plan documented)
**Estimated Time**: 5 minutes

---

**Contact**: Platform Team
**On-Call**: FinOps Specialist Agent
**Escalation**: Immediate (P1 - Critical)

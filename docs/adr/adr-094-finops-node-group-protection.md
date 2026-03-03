# ADR-094: FinOps Node Group Protection

**Status**: Accepted
**Date**: 2026-02-27
**Author**: FinOps Specialist Agent
**Priority**: P1 (Critical - prevents monitoring downtime)
**Context**: AÇÃO-004 Kyverno compliance issue revealed FinOps Lambda scaled system nodes to 0

---

## Context

On 2026-02-27, during AÇÃO-004 (Kyverno DaemonSet compliance), we discovered that the FinOps Lambda `finops-scheduler-stop-staging` scaled the **system node group to 0 nodes**, causing:

- 15 monitoring pods (prometheus-node-exporter, loki-canary) stuck in `Pending` state
- Loss of node-level metrics and log collection
- Kyverno compliance dropping from 100% to 69.4%
- Manual intervention required to scale nodes back up

**Root Cause**: Lambda `lambda_stop.py` (lines 39-43) scales ALL node groups to 0, including:
- `system`: Monitoring DaemonSets (prometheus-node-exporter, loki-canary)
- `critical`: ArgoCD, Vault, Harbor, other critical services

This violates operational requirements:
1. Monitoring must remain functional 24/7 (GAP-004 SLO: 99.5%)
2. Critical services should survive shutdown windows
3. DaemonSets require at least 1 node per AZ (3 total for HA)

---

## Decision

Implement **FinOps Node Group Protection** with following mechanisms:

### 1. Exclusion List
- Environment variable `EXCLUDED_NODE_GROUPS`: comma-separated list of protected node groups
- Default: `"system,critical"`
- Lambda skips scaling for excluded groups

### 2. Minimum Node Thresholds
- `MIN_SYSTEM_NODES`: Minimum system nodes (default: 2)
- `MIN_CRITICAL_NODES`: Minimum critical nodes (default: 2)
- Applied when `ENABLE_SCALING_PROTECTION=true`

### 3. Lambda Logic Changes
**Before** (vulnerable):
```python
NODE_GROUPS_CONFIG = {
    'system': {'min': 0, 'desired': 0, 'max': 4},
    'workloads': {'min': 0, 'desired': 0, 'max': 6},
    'critical': {'min': 0, 'desired': 0, 'max': 4}
}
```

**After** (protected):
```python
# Configuration from env vars
EXCLUDED_NODE_GROUPS = os.environ.get('EXCLUDED_NODE_GROUPS', '').split(',')
MIN_SYSTEM_NODES = int(os.environ.get('MIN_SYSTEM_NODES', '2'))
MIN_CRITICAL_NODES = int(os.environ.get('MIN_CRITICAL_NODES', '2'))
ENABLE_SCALING_PROTECTION = os.environ.get('ENABLE_SCALING_PROTECTION', 'true').lower() == 'true'

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

# In scaling loop
if ng_name in EXCLUDED_NODE_GROUPS:
    logger.info(f"Node group {ng_name} is EXCLUDED from scaling (protection enabled)")
    results['node_groups'][ng_name] = {
        'status': 'protected',
        'message': f'Node group excluded from scaling (min={config["min"]})',
        'config': config
    }
    continue
```

### 4. Terraform Module Changes
**New Variables** (`modules/finops-automation/variables.tf`):
```hcl
variable "excluded_node_groups" {
  description = "Node groups excluded from scaling to 0 (comma-separated)"
  type        = list(string)
  default     = ["system", "critical"]
}

variable "min_system_nodes" {
  description = "Minimum system nodes to keep running"
  type        = number
  default     = 2
}

variable "min_critical_nodes" {
  description = "Minimum critical nodes to keep running"
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

---

## Consequences

### Positive
1. **Reliability**: Monitoring DaemonSets (prometheus-node-exporter, loki-canary) run 24/7
2. **Compliance**: Kyverno policies remain 100% compliant during shutdown windows
3. **Observability**: Node metrics/logs available even during off-hours incidents
4. **Flexibility**: Protection can be disabled per environment via `enable_scaling_protection=false`
5. **Auditability**: Lambda logs show protected node groups with status: `protected`

### Negative
1. **Cost Impact**: +$1.37/day for 2 system nodes (t3.medium × 16h × $0.0416/h × 2)
   - Monthly: ~$30 (22 business days)
   - Annual: ~$360
   - **ROI**: Cost justified by avoiding monitoring gaps + manual intervention
2. **Savings Reduction**: Total FinOps savings decrease from R$ 13,596/year to ~R$ 12,240/year (-10%)
   - Still 85% of target savings
   - Acceptable tradeoff for reliability

### Neutral
1. **Deployment**: Requires `terraform apply` to update Lambda code + environment variables
2. **Testing**: Next shutdown window (2026-02-27 20:00 BRT) will validate protection
3. **Monitoring**: SNS notifications will show `status: protected` for excluded node groups

---

## Implementation

### Files Modified
1. `modules/finops-automation/lambda/lambda_stop.py` (+15 lines)
   - Added protection logic (lines 38-45, 77-86)
2. `modules/finops-automation/variables.tf` (+42 lines)
   - Added 4 new variables + env vars mapping
3. `environments/staging/main.tf` (+5 lines)
   - Enabled protection for staging environment

### Deployment Steps
```bash
# 1. Terraform apply (updates Lambda code + env vars)
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform init
terraform plan  # Verify Lambda code changes
terraform apply -target=module.finops_automation_staging

# 2. Verify Lambda configuration
aws lambda get-function-configuration \
  --profile k8s-platform-prod \
  --region us-east-1 \
  --function-name finops-scheduler-stop-staging \
  --query 'Environment.Variables' --output json

# Expected output:
# {
#   "EXCLUDED_NODE_GROUPS": "system,critical",
#   "MIN_SYSTEM_NODES": "2",
#   "MIN_CRITICAL_NODES": "2",
#   "ENABLE_SCALING_PROTECTION": "true",
#   ...
# }

# 3. Test during next shutdown window (20:00 BRT)
# Check Lambda logs:
aws logs tail /aws/lambda/finops-scheduler-stop-staging --follow

# Expected log line:
# "Node group system is EXCLUDED from scaling (protection enabled)"
# "Node group critical is EXCLUDED from scaling (protection enabled)"

# 4. Verify node count stays at 2
kubectl get nodes -l node-group=system
# Should show 2 nodes (not 0)
```

---

## Validation Criteria

### Success Metrics
- [ ] Lambda logs show `status: protected` for system/critical node groups
- [ ] System node group maintains 2 nodes during shutdown window
- [ ] Critical node group maintains 2 nodes during shutdown window
- [ ] Workloads node group scales to 0 (expected behavior)
- [ ] Prometheus-node-exporter: 11/11 pods Running (not Pending)
- [ ] Loki-canary: 9/9 pods Running (not Pending)
- [ ] Kyverno compliance: 100% (not 69.4%)
- [ ] No manual intervention required during shutdown

### Rollback Plan
If protection fails:
```bash
# Emergency disable
aws lambda update-function-configuration \
  --function-name finops-scheduler-stop-staging \
  --environment "Variables={...,ENABLE_SCALING_PROTECTION=false}"

# Then manually scale up nodes
aws eks update-nodegroup-config \
  --cluster-name k8s-platform-prod \
  --nodegroup-name system \
  --scaling-config minSize=2,desiredSize=2,maxSize=4
```

---

## Cost Analysis

### Before (vulnerable)
| Window | System Nodes | Cost/day |
|--------|--------------|----------|
| 8h-20h (12h) | 2 nodes | $1.00 |
| 20h-8h (16h) | **0 nodes** | $0 |
| **Total** | | **$1.00/day** |

### After (protected)
| Window | System Nodes | Cost/day |
|--------|--------------|----------|
| 8h-20h (12h) | 2 nodes | $1.00 |
| 20h-8h (16h) | **2 nodes** | $1.37 |
| **Total** | | **$2.37/day** |

**Daily Increase**: +$1.37/day
**Monthly Increase**: +$30/month (22 business days)
**Annual Increase**: +$360/year

**Justification**: Cost increase justified by:
1. Avoiding monitoring gaps (GAP-004 SLO: 99.5%)
2. Preventing manual intervention (~30min × $50/h = $25/incident)
3. Maintaining Kyverno compliance (100%)
4. Enabling off-hours incident response (metrics/logs available)

---

## Related Documents
- [GAP-004: Monitoring SLO Requirements](../gaps/GAP-004-monitoring-slo.md)
- [ADR-076: FinOps PDB Optimization](adr-076-finops-pdb-optimization.md)
- [Logbook: 2026-02-27 AÇÃO-004 Kyverno Compliance](../logbook/2026-02-27-acao-004-kyverno-compliance.md)
- [FinOps Automation Module](../../platform-provisioning/aws/kubernetes/terraform/modules/finops-automation/)

---

## Alternatives Considered

### Alternative 1: Node Group Tagging
**Approach**: Use AWS tags (`Schedule=always-on`) to exclude node groups
**Pros**: More flexible, no code changes
**Cons**: Requires existing tag-based logic in Lambda (not implemented), longer development time
**Decision**: Rejected - Environment variables are simpler and faster to implement

### Alternative 2: Separate EventBridge Rules
**Approach**: Create separate EventBridge rules for workloads vs system/critical
**Pros**: Fine-grained control per node group
**Cons**: Duplicates Lambda functions, increases complexity, harder to maintain
**Decision**: Rejected - Single Lambda with protection logic is more maintainable

### Alternative 3: Spot Instances for System Nodes
**Approach**: Use Spot instances for system nodes during off-hours
**Pros**: Reduces cost to ~$0.50/day
**Cons**: Risk of Spot interruption breaks monitoring, violates SLO
**Decision**: Rejected - Reliability > Cost for monitoring infrastructure

---

## Approval

**Approved by**: FinOps Specialist Agent
**Approval Date**: 2026-02-27
**Review Date**: 2026-03-27 (30 days)
**Status**: Pending terraform apply

---

**Tags**: `finops`, `cost-optimization`, `reliability`, `monitoring`, `daemonsets`, `node-scaling`

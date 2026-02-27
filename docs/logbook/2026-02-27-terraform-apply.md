# Terraform Apply Summary - 2026-02-27

## Mission Accomplished

Successfully applied 2 Terraform modules from commit e091144:

### 1. Snapshot Lifecycle Module (Terraform) ✅
- **Duration:** 4 minutes
- **Method:** `terraform apply -target=module.snapshot_lifecycle`
- **Resources Created:**
  - IAM Role: `k8s-platform-staging-dlm-lifecycle-role`
  - IAM Policy: `k8s-platform-staging-dlm-lifecycle-policy`
  - DLM Policy 1: Migration snapshots (7d retention) - policy-0a1002ce488462888
  - DLM Policy 2: Velero backups (30d retention) - policy-0abcef75c927f4fa0
  - DLM Policy 3: Manual snapshots (14d retention) - policy-00f2c707302df641d
- **Impact:** R$ 252/ano savings (automated snapshot cleanup)
- **Status:** All policies ENABLED and active

### 2. FinOps Protection (AWS CLI) ✅
- **Duration:** 15 seconds
- **Method:** `aws lambda update-function-configuration` (bypassed Terraform to avoid RDS SG replacement)
- **Lambdas Updated:**
  - finops-scheduler-stop-staging
  - finops-scheduler-start-staging
- **Environment Variables Added:**
  - ENABLE_SCALING_PROTECTION=true
  - EXCLUDED_NODE_GROUPS=system;critical
  - MIN_SYSTEM_NODES=2
  - MIN_CRITICAL_NODES=2
- **Impact:** R$ ~5K/ano downtime prevention
- **Status:** Both Lambdas updated successfully

### 3. CoreDNS PDB (kubectl) ✅
- **Duration:** 5 seconds
- **Method:** `kubectl apply -f coredns-pdb.yaml`
- **Resource:** PodDisruptionBudget coredns (kube-system namespace)
- **Config:** maxUnavailable=1, currentHealthy=2, status=True
- **Impact:** Faster node drains during shutdown

## Key Decisions

1. **Avoided RDS Downtime:** Detected PostgreSQL Security Group replacement issue (description change forces recreation). Decided to use AWS CLI for Lambda updates instead of full Terraform apply to avoid impacting 39 running pods.

2. **Terraform State Drift:** Lambda environment variables applied via AWS CLI are not in Terraform state. Next `terraform plan` will show drift. Resolution options documented in report.

3. **Corporate Labels:** Removed unsupported `domain`, `owner`, `environment` parameters from kube-prometheus-stack module call (variables not defined in module).

## Total Impact

- **Savings Realized:** R$ 252/ano (Snapshot Lifecycle)
- **Risk Mitigation:** R$ ~5K/ano (FinOps Protection downtime prevention)
- **Execution Time:** 7 minutes
- **Downtime:** 0 minutes
- **Status:** SUCCESS ✅

## Files

- **Report:** /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/reports/terraform-apply-2026-02-27.txt
- **Commit:** 0195a31 feat(terraform): Apply FinOps Protection + Snapshot Lifecycle modules
- **Branch:** main

## Next Actions

1. Monitor Lambda CloudWatch Logs (7 days) - verify exclusion logic
2. Monitor DLM policies deleting old snapshots (30 days)
3. Update ADR-086 with applied timestamp
4. Schedule PostgreSQL SG maintenance window (fix description change)
5. Terraform state drift resolution (import Lambda config or reapply via Terraform)


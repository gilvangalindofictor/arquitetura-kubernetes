# VPA Module Validation Checklist

## Pre-Migration Validation

### Current State Verification
- [ ] VPA helm release deployed: `helm list -n kube-system | grep vpa`
  - Expected: `vpa  kube-system  2  deployed  vpa-4.4.6  1.0.0`
- [ ] VPA recommender running: `kubectl get deploy -n kube-system vpa-recommender`
  - Expected: `1/1 Ready`
- [ ] VPA objects count: `kubectl get vpa -A | wc -l`
  - Expected: 13 (12 workload VPAs + 1 header)
- [ ] VPA recommendations available: `kubectl describe vpa -A | grep -A 5 "Recommendation:"`
  - Expected: At least 8/12 workloads with recommendations (30d metrics)

### Module Structure Validation
- [ ] Module files present:
  ```bash
  ls -1 modules/vpa/{main,variables,outputs}.tf values.yaml.tpl README.md MIGRATION.md
  ```
- [ ] Terraform syntax: `cd modules/vpa && terraform validate`
  - Expected: "Success! The configuration is valid."
- [ ] Formatting: `cd modules/vpa && terraform fmt -check`
  - Expected: No output (already formatted)

## Post-Migration Validation

### Terraform State
- [ ] Old resource removed: `terraform state list | grep -v module | grep vpa`
  - Expected: No output (only kubectl_manifest.vpa_* remaining)
- [ ] Module imported: `terraform state list | grep "module.vpa_staging"`
  - Expected: `module.vpa_staging.helm_release.vpa`

### Terraform Plan
- [ ] No changes: `terraform plan`
  - Expected: "No changes. Your infrastructure matches the configuration."
- [ ] Module outputs work: `terraform output -module=vpa_staging`
  - Expected: release_name, namespace, chart_version, status

### Cluster Verification
- [ ] VPA components unchanged:
  ```bash
  kubectl get deploy -n kube-system vpa-recommender -o jsonpath='{.status.replicas}/{.status.readyReplicas}'
  ```
  - Expected: `1/1`
- [ ] VPA recommender logs healthy:
  ```bash
  kubectl logs -n kube-system deployment/vpa-recommender --tail=20 | grep -i error
  ```
  - Expected: No errors
- [ ] VPA objects unchanged:
  ```bash
  kubectl get vpa -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' | wc -l
  ```
  - Expected: 12 (unchanged from pre-migration)

### Integration Tests
- [ ] Prometheus metrics scraped:
  ```bash
  kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -- \
    wget -qO- 'http://localhost:9090/api/v1/query?query=up{job="vpa-recommender"}' | \
    jq -r '.data.result[0].value[1]'
  ```
  - Expected: "1" (vpa-recommender up)
- [ ] VPA recommendations updated (wait 5min after apply):
  ```bash
  kubectl get vpa vault -n vault-system -o jsonpath='{.status.recommendation.containerRecommendations[0].target.cpu}'
  ```
  - Expected: Non-empty value (e.g., "150m")

## Rollback Validation (If Needed)

- [ ] State restored: `terraform state pull | jq '.resources[] | select(.type=="helm_release" and .name=="vpa")'`
  - Expected: Non-empty JSON object
- [ ] Configuration reverted: `git diff environments/staging/main.tf`
  - Expected: No diff (reverted to pre-migration state)
- [ ] Plan clean: `terraform plan`
  - Expected: "No changes"

## Sign-Off

**Date:** _____________
**Validated by:** _____________
**Terraform Version:** `terraform version`
**Cluster Version:** `kubectl version --short`
**Notes:**

---

**Migration Status:**
- [ ] Pre-migration checks passed
- [ ] Migration completed successfully
- [ ] Post-migration validation passed
- [ ] Rollback procedure tested (optional)
- [ ] Documentation updated
- [ ] Changes committed to version control

**Approval:**
- [ ] FinOps Specialist: _____________
- [ ] Platform Engineer: _____________
- [ ] Security Review: _____________ (N/A for this change)

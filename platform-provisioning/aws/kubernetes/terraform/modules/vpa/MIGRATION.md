# VPA Module Migration Guide

## Current State (Inline Implementation)

VPA is currently deployed via inline `helm_release` resource in `environments/staging/main.tf` (lines 1533-1557).

## Migration Steps

### 1. State Backup

```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/staging
terraform state pull > /tmp/staging-state-backup-$(date +%Y%m%d).json
```

### 2. Remove Inline Helm Release from Configuration

**File:** `environments/staging/main.tf`

**DELETE lines 1533-1557:**
```hcl
resource "helm_release" "vpa" {
  name       = "vpa"
  repository = "https://charts.fairwinds.com/stable"
  chart      = "vpa"
  version    = "4.4.6"
  namespace  = "kube-system"
  timeout    = 300

  values = [<<-YAML
    recommender:
      enabled: true
      extraArgs:
        storage: prometheus
        prometheus-address: "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"
    updater:
      enabled: false
    admissionController:
      enabled: false
  YAML
  ]

  lifecycle {
    ignore_changes = [metadata]
  }
}
```

### 3. Add Module Call

**File:** `environments/staging/main.tf` (insert after VPC Endpoints section, before VPA Objects)

```hcl
#------------------------------------------------------------------------------
# VPA — Vertical Pod Autoscaler (FinOps P1.5)
# Module: ../../modules/vpa (refactored 2026-02-20)
# Purpose: Recommendation mode — collect 30d metrics → enable rightsizing
# Savings: Habilita R$ 8.712/ano via rightsizing (após 30d metrics)
#------------------------------------------------------------------------------

module "vpa_staging" {
  source = "../../modules/vpa"

  release_name  = "vpa"
  chart_version = "4.4.6"
  namespace     = "kube-system"

  # Recommendation mode only (no auto-apply)
  recommender_enabled          = true
  updater_enabled              = false
  admission_controller_enabled = false

  # Prometheus integration
  prometheus_address = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"

  common_tags = local.common_tags
}
```

### 4. Update VPA Object Dependencies

**File:** `environments/staging/main.tf` (lines 1564-1922)

**REPLACE** all `depends_on = [helm_release.vpa]` with `depends_on = [module.vpa_staging]`

```bash
# Automated replacement (run from staging directory)
sed -i 's/depends_on = \[helm_release\.vpa\]/depends_on = [module.vpa_staging]/g' main.tf
```

### 5. Import Existing Helm Release into Module State

```bash
cd environments/staging

# Remove old resource from state
terraform state rm helm_release.vpa

# Import into module
terraform import 'module.vpa_staging.helm_release.vpa' kube-system/vpa

# Verify state
terraform state list | grep vpa
```

Expected output:
```
module.vpa_staging.helm_release.vpa
kubectl_manifest.vpa_argocd
kubectl_manifest.vpa_grafana
kubectl_manifest.vpa_harbor_core
kubectl_manifest.vpa_keycloak
kubectl_manifest.vpa_loki
kubectl_manifest.vpa_prometheus
kubectl_manifest.vpa_rabbitmq
kubectl_manifest.vpa_redis
kubectl_manifest.vpa_tempo
kubectl_manifest.vpa_vault
kubectl_manifest.vpa_gitlab_sidekiq
kubectl_manifest.vpa_gitlab_webservice
```

### 6. Validate Plan (Should be No-Op)

```bash
# WSL workaround: export credentials + no profile
eval $(aws configure export-credentials --profile k8s-platform-staging --format env)
unset AWS_PROFILE
export AWS_DEFAULT_REGION=us-east-1

# Plan
terraform init -plugin-dir=.terraform/providers
terraform plan -out=/tmp/vpa-migration.tfplan

# Expected: 0 to add, 0 to change, 0 to destroy
```

### 7. Apply (If Plan Shows Changes)

```bash
terraform apply /tmp/vpa-migration.tfplan
```

## Rollback Procedure

If migration fails:

```bash
# Restore state from backup
terraform state push /tmp/staging-state-backup-YYYYMMDD.json

# Restore main.tf from git
git checkout environments/staging/main.tf

# Re-run plan
terraform plan
```

## Validation

```bash
# Verify VPA components running
kubectl get deployment -n kube-system | grep vpa

# Expected output:
# vpa-recommender   1/1     1            1           2d7h

# Verify VPA objects unchanged
kubectl get vpa -A | wc -l
# Expected: 13 (12 workload VPAs + 1 header line)

# Check module outputs
terraform output -module=vpa_staging
```

## Benefits of Module Migration

1. **Reusability:** Same module can be used for prod environment
2. **Versioning:** Module version can be pinned independently
3. **Consistency:** Follows project pattern (all services as modules)
4. **Maintainability:** Centralized VPA logic, easier updates
5. **Testing:** Module can be tested in isolation

## Notes

- VPA objects (12 kubectl_manifest resources) remain in `main.tf` — NOT moved to module
- Module only manages Helm chart deployment, not VPA object definitions
- Zero downtime: Terraform import preserves existing resources
- No cluster impact: VPA recommender continues running during migration

# 🔧 Multi-Marco Infrastructure Guide

**Last Updated:** 2026-02-13
**Version:** 1.0.0
**Status:** Operational Runbook
**Owner:** Platform Team

---

## 📋 Overview

Este guia operacional documenta como trabalhar com a **Multi-Marco Infrastructure Split Strategy** formalizada em [ADR-059](../adr/adr-059-multi-marco-infrastructure-split.md).

**Arquitetura:**
- **Marco 0:** VPC Foundation (Legacy) - Rede base compartilhada
- **Marco 1:** EKS Cluster Foundation - Cluster compartilhado (prod + staging)
- **Marco 3 Staging:** Workloads & Data Services - Aplicações staging

**Padrão Chave:** Shared Cluster Strategy
- 1 cluster para prod + staging
- Isolamento via namespaces + RBAC + NetworkPolicies
- Savings: R$ 1.002/ano (-$139/mês)

---

## 🎯 Quick Reference

### Terraform State Locations

```bash
# Marco 0: VPC Foundation (Legacy)
MARCO0_STATE="s3://terraform-state-marco0-891377105802/marco0/terraform.tfstate"

# Marco 1: EKS Cluster Foundation
MARCO1_STATE="s3://terraform-state-marco0-891377105802/marco1/terraform.tfstate"

# Marco 3 Staging: Workloads
MARCO3_STATE="s3://terraform-state-marco0-891377105802/environments/staging/terraform.tfstate"
```

### Resource Ownership Quick Lookup

| Resource Type | Owner Marco | Terraform Path |
|--------------|-------------|----------------|
| VPC, Subnets, NAT | Marco 0 | N/A (legacy) |
| EKS Cluster, Node Groups | Marco 1 | `marco1/` |
| EKS Addons | Marco 1 | `marco1/` |
| VPC Endpoints (STS/EC2/ELB/KMS) | Marco 1 | `marco1/` |
| PostgreSQL RDS | Marco 3 | `environments/staging/` |
| Vault, Harbor, GitLab | Marco 3 | `environments/staging/` |

**Full Matrix:** [ARCHITECTURE.md - Resource Ownership](../context/architecture.md#-resource-ownership-matrix)

---

## 🔄 Common Operations

### 1. Validate All Marcos (Drift Detection)

```bash
#!/bin/bash
# validate-all-marcos.sh

PROFILE="k8s-platform-prod"
REGION="us-east-1"

echo "=== Multi-Marco Validation ==="
echo ""

# Marco 0: Skip (legacy, não gerenciado via TF ativo)
echo "Marco 0: VPC Foundation"
echo "  Status: LEGACY (skip validation)"
echo ""

# Marco 1: EKS Cluster Foundation
echo "Marco 1: EKS Cluster Foundation"
cd platform-provisioning/aws/kubernetes/terraform/marco1/ || exit 1
terraform init -backend-config="profile=$PROFILE"
terraform plan -detailed-exitcode

MARCO1_EXIT=$?
if [[ $MARCO1_EXIT -eq 0 ]]; then
  echo "  ✅ No changes"
elif [[ $MARCO1_EXIT -eq 2 ]]; then
  echo "  ⚠️  Drift detected (review plan above)"
else
  echo "  ❌ Error"
  exit 1
fi
echo ""

# Marco 3 Staging: Workloads
echo "Marco 3 Staging: Workloads & Data Services"
cd ../environments/staging/ || exit 1
terraform init -backend-config="profile=$PROFILE"
terraform plan -detailed-exitcode

MARCO3_EXIT=$?
if [[ $MARCO3_EXIT -eq 0 ]]; then
  echo "  ✅ No changes"
elif [[ $MARCO3_EXIT -eq 2 ]]; then
  echo "  ⚠️  Drift detected (review plan above)"
else
  echo "  ❌ Error"
  exit 1
fi
echo ""

# Summary
if [[ $MARCO1_EXIT -eq 0 && $MARCO3_EXIT -eq 0 ]]; then
  echo "✅ All Marcos in sync"
  exit 0
else
  echo "⚠️  Drift detected in one or more Marcos"
  exit 2
fi
```

**Usage:**
```bash
./scripts/validate-all-marcos.sh
```

---

### 2. EKS Cluster Upgrade (Marco 1)

**⚠️ CRITICAL:** EKS upgrade afeta **TODOS** os workloads (prod + staging).

**Pre-requisites:**
- [ ] Backup Vault snapshots (S3)
- [ ] Backup GitLab databases (RDS snapshot)
- [ ] Communication: notify stakeholders (30min downtime expected)
- [ ] Validation window: staging testing before prod rollout

**Procedure:**

```bash
# 1. Upgrade Control Plane (Marco 1)
cd platform-provisioning/aws/kubernetes/terraform/marco1/

# Update cluster_version in terraform.tfvars
# Example: 1.31 → 1.32
vim terraform.tfvars

# Plan and review
terraform plan -out=upgrade.tfplan

# Apply (control plane only, 10-15min)
terraform apply upgrade.tfplan

# 2. Upgrade Addons (Marco 1)
# Update addon versions in main.tf to match EKS version
# Example: coredns v1.31.x → v1.32.x
vim main.tf

terraform plan -out=addons.tfplan
terraform apply addons.tfplan

# 3. Upgrade Node Groups (Marco 1)
# Option A: Rolling update (zero downtime, 30min)
# Option B: Blue-green (create new, migrate, delete old, 1h)

# Rolling update (default):
terraform plan -out=nodes.tfplan
terraform apply nodes.tfplan

# 4. Validate Staging Workloads (Marco 3)
cd ../environments/staging/

# Verify pods health
kubectl get pods -A | grep -v Running | grep -v Completed

# Check critical workloads
kubectl get pods -n vault-system
kubectl get pods -n gitlab-staging
kubectl get pods -n keycloak

# Run smoke tests
kubectl run test-pod --image=nicolaka/netshoot --rm -it -- curl -I https://keycloak.staging.internal

# 5. Update Marco 3 if needed
# If workload configs reference EKS version, update
terraform plan
terraform apply

# 6. Post-upgrade validation
./scripts/validate-all-marcos.sh
```

**Rollback Procedure:**

```bash
# CRITICAL: Only rollback control plane within 1 hour of upgrade
# After 1h, rollback requires cluster recreation

cd marco1/
terraform plan -destroy -target=aws_eks_cluster.main
# DON'T ACTUALLY DESTROY - just to see impact

# Instead: restore from RDS snapshots + Vault S3 snapshots
# Document: docs/operations/disaster-recovery.md
```

---

### 3. Add New Workload (Marco 3)

**Scenario:** Deploy new application to staging environment.

```bash
cd platform-provisioning/aws/kubernetes/terraform/environments/staging/

# 1. Create new module call
vim main.tf

# Example: Add SonarQube
module "sonarqube" {
  source = "../../modules/sonarqube"

  cluster_name = data.aws_eks_cluster.cluster.name
  cluster_endpoint = data.aws_eks_cluster.cluster.endpoint

  # Consume Marco 1 resources via data sources
  oidc_provider_arn = data.aws_iam_openid_connect_provider.eks.arn

  postgresql_host = module.postgresql.endpoint
  postgresql_database = "sonarqube"
  postgresql_username = "sonarqube_user"

  # Workload-specific configs
  replicas = 1
  namespace = "sonarqube"
  storage_class = "gp3"
}

# 2. Plan and review
terraform plan -out=new-workload.tfplan

# 3. Apply
terraform apply new-workload.tfplan

# 4. Validate
kubectl get pods -n sonarqube
kubectl logs -n sonarqube -l app=sonarqube

# 5. Update ARCHITECTURE.md
# Add to Resource Ownership Matrix (Marco 3 section)
```

---

### 4. Troubleshoot Drift (Marco 1 vs Marco 3)

**Symptom:** `terraform plan` mostra changes não esperados.

**Root Cause Checklist:**

#### A. Marco 3 tentando criar recurso de Marco 1

```bash
# Error example:
# Error: creating Security Group: AlreadyExists

# Validation:
cd marco1/
terraform state list | grep security_group

cd ../environments/staging/
terraform state list | grep security_group

# Fix: Import to correct Marco OR use data source
terraform import aws_security_group.cluster sg-0f8978f3835a9bb55
# OR
# Use data source instead of resource
```

#### B. Data Source não encontra recurso

```bash
# Error example:
# Error: no matching EKS cluster found

# Validation:
aws eks describe-cluster --name k8s-platform-prod --profile k8s-platform-prod

# Fix: Verify cluster exists in Marco 1
cd marco1/
terraform state list | grep aws_eks_cluster

# If missing: Import to Marco 1
terraform import aws_eks_cluster.main k8s-platform-prod
```

#### C. Recurso duplicado (Marco 1 E Marco 3)

```bash
# Symptom: Both marcos show resource in state

# Validation:
cd marco1/ && terraform state list | grep vpc_endpoint
cd ../environments/staging/ && terraform state list | grep vpc_endpoint

# Fix: Remove from Marco 3 (consumer)
cd environments/staging/
terraform state rm aws_vpc_endpoint.sts

# Convert to data source
data "aws_vpc_endpoint" "sts" {
  vpc_id = data.aws_vpc.main.id
  service_name = "com.amazonaws.us-east-1.sts"
}
```

---

## 🚨 Troubleshooting Guide

### Issue: Marco 3 plan fails with "cluster not found"

**Symptom:**
```
Error: no matching EKS cluster found
│
│   with data.aws_eks_cluster.cluster,
│   on data.tf line 10
```

**Diagnosis:**
```bash
# Check Marco 1 state
cd marco1/
terraform state show aws_eks_cluster.main | grep cluster_name

# Check AWS
aws eks describe-cluster --name k8s-platform-prod
```

**Resolution:**
- If cluster exists in AWS but not in Marco 1 state → Import to Marco 1
- If cluster doesn't exist → Deploy Marco 1 first
- If cluster name mismatch → Update data source filter

---

### Issue: Security Group dependency violation

**Symptom:**
```
Error: DependencyViolation: resource sg-XXX has a dependent object
```

**Diagnosis:**
```bash
# Check what references this SG
aws ec2 describe-security-groups --group-ids sg-XXX --query 'SecurityGroups[0].{IpPermissions:IpPermissions,IpPermissionsEgress:IpPermissionsEgress}'

# Check ENI attachments
aws ec2 describe-network-interfaces --filters "Name=group-id,Values=sg-XXX"
```

**Resolution:**
1. Remove SG rules that reference the target SG
2. Wait for ENI detachment (if any)
3. Retry delete

**Reference:** [2026-02-13 Security Groups Cleanup](../logbook/2026-02-13-security-groups-cleanup-completion.md)

---

### Issue: IRSA authentication fails after Marco 1 change

**Symptom:**
```
Error: AssumeRoleWithWebIdentity failed: InvalidIdentityToken
```

**Diagnosis:**
```bash
# Verify OIDC provider exists
aws iam list-open-id-connect-providers

# Verify issuer URL matches cluster
kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}'
aws eks describe-cluster --name k8s-platform-prod --query 'cluster.identity.oidc.issuer'
```

**Resolution:**
1. Verify OIDC provider in Marco 1: `terraform state show aws_iam_openid_connect_provider.eks`
2. Recreate service account annotations: `kubectl annotate sa -n <namespace> <sa-name> eks.amazonaws.com/role-arn=<role-arn>`
3. Restart pods: `kubectl rollout restart deployment -n <namespace> <deployment>`

---

## 📊 Drift Detection Patterns

### Pattern 1: Marco 3 shows "no changes" but workload fails

**Scenario:** Terraform plan clean, but pods CrashLoop.

**Root Cause:** Marco 1 resource changed (e.g., OIDC issuer URL), Marco 3 doesn't track.

**Detection:**
```bash
# Compare Marco 1 outputs vs Marco 3 data sources
cd marco1/
terraform output oidc_provider_arn

cd ../environments/staging/
terraform console
> data.aws_iam_openid_connect_provider.eks.arn
```

**Fix:** Run Marco 3 refresh to update data sources:
```bash
terraform apply -refresh-only
```

---

### Pattern 2: Marco 1 upgrade breaks Marco 3 workloads

**Scenario:** EKS 1.31 → 1.32 upgrade in Marco 1, GitLab pods fail.

**Root Cause:** Kubernetes API deprecations (e.g., Ingress v1beta1 removed).

**Prevention:**
```bash
# Before Marco 1 upgrade:
kubectl get all -A -o yaml | grep "apiVersion: extensions/v1beta1"

# Upgrade Helm charts FIRST (Marco 3)
cd environments/staging/
terraform plan -target=module.gitlab
terraform apply -target=module.gitlab

# THEN upgrade Marco 1
cd ../../marco1/
terraform apply
```

---

## 🔐 Security Considerations

### RBAC Separation

```yaml
# Marco 1: Cluster-admin access required
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: platform-team-cluster-admin
subjects:
- kind: User
  name: platform-team
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
```

```yaml
# Marco 3: Namespace-scoped access
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: staging-team-admin
  namespace: gitlab-staging
subjects:
- kind: User
  name: staging-team
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: admin
  apiGroup: rbac.authorization.k8s.io
```

**Principle:** Marco 1 = Platform Team only. Marco 3 = Application Teams.

---

### Network Policies

```yaml
# Isolate prod from staging at network level
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-cross-environment
  namespace: gitlab-staging
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          environment: staging
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          environment: staging
```

---

## 📈 Cost Optimization

### Shared Cluster Savings

| Resource | Without Shared Cluster | With Shared Cluster | Savings |
|----------|----------------------|---------------------|---------|
| EKS Control Plane | $146/mês (2 clusters) | $73/mês (1 cluster) | $73/mês |
| NAT Gateways | $132/mês (4 NGW) | $66/mês (2 NGW) | $66/mês |
| **Total** | **$278/mês** | **$139/mês** | **$139/mês** |

**Annual Savings:** R$ 1.002/ano (assuming BRL 6.0 exchange rate)

### Resource Quotas per Environment

```yaml
# Prevent staging from consuming all resources
apiVersion: v1
kind: ResourceQuota
metadata:
  name: staging-quota
  namespace: gitlab-staging
spec:
  hard:
    requests.cpu: "20"
    requests.memory: 40Gi
    persistentvolumeclaims: "50"
    services.loadbalancers: "3"
```

---

## 🔄 State Management

### Remote State Dependencies

```hcl
# Marco 3 staging/data.tf
data "terraform_remote_state" "marco1" {
  backend = "s3"
  config = {
    bucket = "terraform-state-marco0-891377105802"
    key    = "marco1/terraform.tfstate"
    region = "us-east-1"
    profile = "k8s-platform-prod"
  }
}

# Consume Marco 1 outputs
locals {
  cluster_name = data.terraform_remote_state.marco1.outputs.cluster_name
  oidc_provider_arn = data.terraform_remote_state.marco1.outputs.oidc_provider_arn
}
```

**⚠️ Dependency:** If Marco 1 state corrupted → Marco 3 blocked.

**Mitigation:**
- S3 versioning enabled (restore previous version)
- DynamoDB locking prevents concurrent modifications
- Daily backups: `aws s3 sync s3://terraform-state-marco0-891377105802 /backup/terraform-state/$(date +%Y-%m-%d)`

---

## 📚 Reference Documentation

- **Architecture:** [ARCHITECTURE.md](../context/architecture.md)
- **ADR-059:** [Multi-Marco Infrastructure Split](../adr/adr-059-multi-marco-infrastructure-split.md)
- **Logbooks:**
  - [2026-02-12 Terraform Conformance](../logbook/2026-02-12-terraform-conformance-implementation.md)
  - [2026-02-13 Security Groups Cleanup](../logbook/2026-02-13-security-groups-cleanup-completion.md)

---

## 🚀 Future Enhancements

### Planned

1. **Automated Drift Detection** (Q1 2026)
   - GitHub Actions workflow
   - Daily `terraform plan` across all Marcos
   - Slack notifications on drift

2. **Multi-Environment Expansion** (Q2 2026)
   - Marco 4 Production: Prod workloads
   - Same shared cluster, different namespaces
   - RBAC + NetworkPolicies enforcement

3. **Cost Allocation Tags** (Q1 2026)
   - Tag all resources: `Environment=staging|prod`
   - AWS Cost Explorer breakdown
   - Chargeback reports per team

### Considered but Deferred

- **Separate Prod Cluster:** Cost analysis showed +$139/mês, not justified for current scale
- **Multi-Region:** Not required (single region compliance sufficient)

---

**Maintainer:** Platform Team
**Last Review:** 2026-02-13
**Next Review:** 2026-03-13 (monthly)

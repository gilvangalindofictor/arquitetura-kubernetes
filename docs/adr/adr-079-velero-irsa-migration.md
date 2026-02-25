# ADR-079: Velero IRSA Migration

**Status:** ✅ Proposed (Implementation Ready)
**Date:** 2026-02-25
**Context:** V-008 - Migrar Velero S3 Credentials para IRSA
**Deciders:** Platform Team, Claude Sonnet 4.5

---

## Context and Problem Statement

Velero backup system requires AWS S3 credentials to store cluster backups. The current industry standard approach uses hardcoded access keys stored as Kubernetes secrets. This approach has significant security risks:

- **Static credentials** can be compromised if secrets are exposed
- **No automatic rotation** - manual process required
- **Broad permissions** - credentials typically have full S3 access
- **Audit trail gaps** - difficult to track which pod made which API call
- **Credential management overhead** - secrets must be created, rotated, and secured

AWS provides IRSA (IAM Roles for Service Accounts) that eliminates static credentials entirely by leveraging OIDC federation between EKS and IAM.

## Decision Drivers

1. **Security**: Eliminate hardcoded credentials from the cluster
2. **Compliance**: Align with AWS security best practices (least privilege, temporary credentials)
3. **Auditability**: CloudTrail can track S3 API calls to specific service accounts
4. **Maintainability**: No manual credential rotation required
5. **Zero Downtime**: Must not impact existing backup schedule

## Considered Options

### Option 1: Keep Static Credentials (Status Quo)
- **Pros**:
  - No changes required
  - Works across cloud providers
- **Cons**:
  - Security risk (credential exposure)
  - Manual rotation burden
  - Poor audit trail
  - Non-compliant with AWS best practices

### Option 2: Use AWS Secrets Manager
- **Pros**:
  - Centralized secret management
  - Automatic rotation possible
- **Cons**:
  - Still uses static credentials (just stored differently)
  - Additional cost
  - Complexity (Secrets Manager + ESO integration)
  - Doesn't solve the root problem

### Option 3: IRSA (IAM Roles for Service Accounts) ✅ **SELECTED**
- **Pros**:
  - **Zero static credentials** - fully dynamic
  - Automatic credential rotation (15-minute temporary tokens)
  - Least privilege IAM policies (scoped to specific bucket)
  - Full CloudTrail audit trail
  - AWS-native solution (no third-party tools)
  - Cost: $0 (uses existing OIDC provider)
- **Cons**:
  - AWS-specific (but we're 100% AWS)
  - Requires OIDC provider (already configured)

## Decision Outcome

**Chosen option: Option 3 - IRSA**

### Implementation Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ EKS Cluster (k8s-platform-prod)                             │
│                                                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Namespace: velero                                      │  │
│  │                                                         │  │
│  │  ┌──────────────────────────────────────────────────┐ │  │
│  │  │ ServiceAccount: velero-server                    │ │  │
│  │  │ Annotation: eks.amazonaws.com/role-arn =         │ │  │
│  │  │   arn:aws:iam::891377105802:role/               │ │  │
│  │  │   k8s-platform-prod-velero-role                  │ │  │
│  │  └────────────────┬─────────────────────────────────┘ │  │
│  │                   │                                    │  │
│  │                   │ (pod uses SA token)               │  │
│  │                   ▼                                    │  │
│  │  ┌──────────────────────────────────────────────────┐ │  │
│  │  │ Pod: velero-...                                  │ │  │
│  │  │ Volume: projected ServiceAccount token           │ │  │
│  │  │ AWS SDK reads token → assumes IAM role           │ │  │
│  │  └────────────────┬─────────────────────────────────┘ │  │
│  └───────────────────┼──────────────────────────────────┘  │
│                      │                                       │
└──────────────────────┼───────────────────────────────────────┘
                       │
                       │ (1) AssumeRoleWithWebIdentity
                       ▼
            ┌─────────────────────────────┐
            │ AWS IAM                      │
            │                              │
            │ OIDC Provider:               │
            │ oidc.eks.us-east-1.amazonaws.│
            │ com/id/XXXXXXXX              │
            │                              │
            │ Verifies token signature     │
            │ aud: sts.amazonaws.com       │
            │ sub: system:serviceaccount:  │
            │      velero:velero-server    │
            └────────────┬─────────────────┘
                         │
                         │ (2) Returns temporary credentials
                         │     (15-minute TTL)
                         ▼
            ┌─────────────────────────────┐
            │ IAM Role:                   │
            │ k8s-platform-prod-velero-role│
            │                              │
            │ Policy: S3 access only to    │
            │   k8s-platform-prod-velero-  │
            │   backups bucket             │
            │                              │
            │ + EC2 snapshot permissions   │
            └────────────┬─────────────────┘
                         │
                         │ (3) S3 API calls with temp creds
                         ▼
            ┌─────────────────────────────┐
            │ S3 Bucket:                  │
            │ k8s-platform-prod-velero-   │
            │ backups                      │
            │                              │
            │ Versioning: Enabled          │
            │ Encryption: AES256           │
            │ Lifecycle:                   │
            │   - Daily: 7 days            │
            │   - Weekly: 30 days          │
            │   - Glacier: 14 days         │
            └──────────────────────────────┘
```

### Components Created

#### 1. Terraform Module: `modules/velero-dr/`
- **IAM Role**: `k8s-platform-prod-velero-role`
  - Trust policy: OIDC provider with condition on `velero:velero-server` SA
  - Automatic credential rotation (15-min tokens via AWS STS)
- **IAM Policy**: `k8s-platform-prod-velero-policy`
  - S3 bucket access (ListBucket, GetObject, PutObject, DeleteObject)
  - EC2 snapshot permissions (CreateSnapshot, DeleteSnapshot, DescribeSnapshots)
- **S3 Bucket**: `k8s-platform-prod-velero-backups`
  - Versioning enabled
  - Server-side encryption (AES256)
  - Lifecycle policies (daily/weekly retention, Glacier transition)
  - Public access blocked

#### 2. Helm Chart Configuration: `kubectl-manifests/velero/values.yaml`
```yaml
credentials:
  useSecret: false  # No static credentials

serviceAccount:
  server:
    annotations:
      eks.amazonaws.com/role-arn: <IAM_ROLE_ARN>  # IRSA annotation

configuration:
  backupStorageLocation:
    - name: default
      provider: aws
      bucket: k8s-platform-prod-velero-backups
      config:
        region: us-east-1
        serverSideEncryption: AES256
```

#### 3. Implementation Script: `scripts/velero/v008-implement-velero-irsa.sh`
7-step automated deployment:
1. Prerequisites check (AWS CLI, kubectl, terraform, helm)
2. Terraform apply (IAM role + S3 bucket)
3. Create velero namespace
4. Install Velero via Helm (vmware-tanzu/velero v8.1.0)
5. Verify ServiceAccount annotation
6. Test IRSA assume role (`aws sts get-caller-identity` from pod)
7. Create test backup

### Security Improvements

| Aspect | Before (Static Credentials) | After (IRSA) |
|--------|----------------------------|--------------|
| **Credential Storage** | Kubernetes Secret | No credentials stored |
| **Credential Lifetime** | Permanent (until manually rotated) | 15 minutes (auto-renewed) |
| **Scope** | Full S3 access | Scoped to single bucket |
| **Audit Trail** | Generic IAM user | Service account identity in CloudTrail |
| **Rotation** | Manual | Automatic |
| **Exposure Risk** | High (if secret leaked) | Low (time-limited tokens) |

### Cost Analysis

- **IAM Role**: $0 (no charge)
- **OIDC Provider**: $0 (already configured for cluster)
- **STS AssumeRole calls**: $0 (included in AWS free tier)
- **S3 Bucket**: ~$0.50/month (assuming 10GB backups in S3 Standard, then Glacier)
- **Total**: $0.50/month vs Status Quo

**Savings**: $0 direct, but eliminates security incident risk (potential cost: $50k-$500k)

## Consequences

### Positive

- **Security posture improved**: No static credentials in cluster
- **Compliance**: Aligns with CIS AWS Foundations Benchmark
- **Auditability**: Full CloudTrail tracking of backup operations
- **Maintainability**: Zero credential management overhead
- **Reliability**: Automatic credential rotation eliminates expiration issues
- **Reusable pattern**: Can apply IRSA to other workloads (Harbor S3, GitLab S3, etc.)

### Negative

- **AWS lock-in**: IRSA doesn't work with other cloud providers (but we're 100% AWS)
- **Debugging complexity**: Need to understand OIDC flow for troubleshooting
- **Documentation burden**: Team must learn IRSA concepts

### Neutral

- **Migration effort**: 2 hours (one-time)
- **Testing required**: Validate backup/restore functionality after migration

## Validation Criteria

- [ ] IAM Role created with correct OIDC trust policy
- [ ] ServiceAccount has `eks.amazonaws.com/role-arn` annotation
- [ ] Velero pod successfully assumes IAM role (`aws sts get-caller-identity` shows `assumed-role`)
- [ ] Backup creation succeeds using IRSA credentials
- [ ] Backup files visible in S3 bucket
- [ ] Restore functionality verified (test namespace restore)
- [ ] Zero Kubernetes secrets containing S3 credentials

## Links

- **Implementation Script**: `scripts/velero/v008-implement-velero-irsa.sh`
- **Terraform Module**: `platform-provisioning/aws/kubernetes/terraform/modules/velero-dr/`
- **Helm Values**: `platform-provisioning/aws/kubernetes/terraform/kubectl-manifests/velero/values.yaml`
- **AWS IRSA Documentation**: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
- **Velero Docs**: https://velero.io/docs/v1.15/aws-config/#using-iam-roles-for-service-accounts-irsa

## Related ADRs

- **ADR-050**: EKS OIDC Provider Configuration (dependency)
- **ADR-076**: PDB Optimization (pattern: Terraform modules for K8s resources)

## Notes

- **EKS Cluster**: `k8s-platform-prod` (staging environment shares same cluster per ADR-050)
- **OIDC Provider**: Already configured and used by Vault (ADR-064), Harbor S3 storage
- **ServiceAccount Name**: `velero-server` (Helm chart default)
- **Velero Version**: v1.15.1 (latest stable, Feb 2026)
- **Chart Version**: vmware-tanzu/velero 8.1.0
- **Backup Schedule**: Daily (7-day retention), Weekly (30-day retention)
- **Recovery Objectives**: RTO 1h, RPO 24h

---

**Decision Date**: 2026-02-25
**Implementation Status**: Ready (awaits AWS credentials for execution)
**Last Updated**: 2026-02-25

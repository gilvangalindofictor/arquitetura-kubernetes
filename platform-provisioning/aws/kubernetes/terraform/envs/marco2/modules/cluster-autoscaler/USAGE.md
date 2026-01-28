# Cluster Autoscaler Module

Terraform module to deploy Kubernetes Cluster Autoscaler on AWS EKS with IRSA (IAM Roles for Service Accounts).

## Features

- ✅ **IRSA Pattern**: Uses IAM roles instead of access keys
- ✅ **Auto-Discovery**: Automatically discovers Auto Scaling Groups with specific tags
- ✅ **Least Privilege**: IAM policy restricted to tagged ASGs only
- ✅ **Multi-AZ**: Balances nodes across availability zones
- ✅ **Cost Optimization**: Scale-down enabled with conservative defaults
- ✅ **Observability**: Prometheus metrics endpoint enabled

## Prerequisites

1. **EKS Cluster**: Running EKS cluster with OIDC provider
2. **Node Groups**: EKS node groups with Auto Scaling Groups
3. **ASG Tags**: Auto Scaling Groups must have the following tags:
   - `k8s.io/cluster-autoscaler/enabled` = `true`
   - `k8s.io/cluster-autoscaler/<cluster-name>` = `owned`

## Usage

```hcl
module "cluster_autoscaler" {
  source = "./modules/cluster-autoscaler"

  cluster_name       = "k8s-platform-prod"
  namespace          = "kube-system"
  chart_version      = "9.37.0"
  kubernetes_version = "1.31" # Match your EKS version

  # Autoscaling configuration
  scale_down_enabled                = true
  scale_down_delay_after_add        = "10m"
  scale_down_unneeded_time          = "10m"
  scale_down_utilization_threshold  = "0.5"

  tags = {
    Environment = "production"
    Project     = "k8s-platform"
  }
}
```

## Auto Scaling Groups Configuration

For Cluster Autoscaler to work, your ASGs must have:

### Required Tags

```hcl
resource "aws_eks_node_group" "workloads" {
  # ... other configuration

  tags = {
    "k8s.io/cluster-autoscaler/enabled"                = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}"    = "owned"
  }
}
```

### Lifecycle Configuration

```hcl
lifecycle {
  ignore_changes = [scaling_config[0].desired_size]
}
```

**Important**: This lifecycle rule is REQUIRED to allow Cluster Autoscaler to manage the `desired_size` without Terraform reverting changes.

## Scaling Behavior

### Scale-Up
- **Trigger**: Pods remain in Pending state due to insufficient resources
- **Timing**: Immediate (within 30-60 seconds)
- **Strategy**: Least-waste expander (cost-efficient)

### Scale-Down
- **Trigger**: Node utilization < 50% for 10 minutes
- **Timing**: After 10 minutes of low utilization
- **Delay after scale-up**: 10 minutes (prevents flapping)
- **Max graceful termination**: 600 seconds (10 minutes)

## Configuration Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `scale_down_enabled` | `true` | Enable automatic scale-down |
| `scale_down_delay_after_add` | `10m` | Wait time after scale-up before scale-down |
| `scale_down_unneeded_time` | `10m` | Time a node must be unneeded before removal |
| `scale_down_utilization_threshold` | `0.5` | Node utilization threshold (50%) |

## Monitoring

Cluster Autoscaler exposes Prometheus metrics on port 8085:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: cluster-autoscaler
spec:
  endpoints:
    - port: metrics
      interval: 30s
```

### Key Metrics

- `cluster_autoscaler_nodes_count{state="ready"}` - Number of ready nodes
- `cluster_autoscaler_unschedulable_pods_count` - Pending pods
- `cluster_autoscaler_scaled_up_nodes_total` - Total scale-up operations
- `cluster_autoscaler_scaled_down_nodes_total` - Total scale-down operations

## Validation

### Check Deployment
```bash
kubectl get deployment -n kube-system cluster-autoscaler
kubectl get pods -n kube-system -l app.kubernetes.io/name=cluster-autoscaler
```

### Check Logs
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=cluster-autoscaler --tail=50 -f
```

### Check IAM Role
```bash
kubectl describe sa cluster-autoscaler -n kube-system
# Should show: eks.amazonaws.com/role-arn annotation
```

## Troubleshooting

### Scale-up not working
1. Check pending pods: `kubectl get pods --all-namespaces | grep Pending`
2. Check CA logs: `kubectl logs -n kube-system -l app.kubernetes.io/name=cluster-autoscaler`
3. Verify ASG tags: `aws autoscaling describe-auto-scaling-groups`

### Scale-down not working
1. Check node utilization: `kubectl top nodes`
2. Verify `scale_down_enabled = true`
3. Check for pods with local storage or system pods blocking scale-down

### IAM Permission Errors
```bash
# Check IAM role annotation
kubectl get sa cluster-autoscaler -n kube-system -o yaml

# Verify IAM role trust policy
aws iam get-role --role-name ClusterAutoscalerRole-<cluster-name>
```

## Security

### IAM Policy (Least Privilege)

The IAM policy is restricted to ASGs with specific tags:

```json
{
  "Condition": {
    "StringEquals": {
      "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/<cluster-name>": "owned"
    }
  }
}
```

This prevents Cluster Autoscaler from modifying unrelated Auto Scaling Groups.

### Pod Security

- Runs as non-root user (UID 65534)
- Read-only root filesystem
- No privilege escalation
- All capabilities dropped

## Outputs

| Output | Description |
|--------|-------------|
| `iam_role_arn` | ARN of the IAM role |
| `service_account_name` | Kubernetes service account name |
| `configuration_summary` | Complete configuration summary |

## References

- [Cluster Autoscaler AWS Guide](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md)
- [Cluster Autoscaler FAQ](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md)
- [EKS Best Practices - Autoscaling](https://aws.github.io/aws-eks-best-practices/cluster-autoscaling/)

# VPA (Vertical Pod Autoscaler) Terraform Module

## Purpose

Deploys Fairwinds VPA Helm chart for Kubernetes resource rightsizing recommendations.

**FinOps Impact:** Enables R$ 8.712/ano savings via scientific rightsizing after 30d metrics collection.

## Components

- **VPA Recommender:** Analyzes historical resource usage (Prometheus backend) and computes recommendations
- **VPA Updater:** (DISABLED) Auto-applies recommendations to running pods
- **VPA Admission Controller:** (DISABLED) Mutates pod specs on creation

## Deployment Mode

**Recommendation Only** (updateMode: Off)
- VPA objects collect metrics and compute recommendations
- No automatic pod eviction or mutation
- Manual review and apply via `kubectl patch` or Terraform updates

## Usage

```hcl
module "vpa" {
  source = "../../modules/vpa"

  namespace           = "kube-system"
  chart_version       = "4.4.6"
  prometheus_address  = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"

  # Recommendation mode (safe for staging + prod)
  recommender_enabled          = true
  updater_enabled              = false
  admission_controller_enabled = false

  common_tags = {
    Environment = "staging"
    CostCenter  = "finops"
  }
}
```

## VPA Objects

After deploying the module, create VPA objects for target workloads:

```hcl
resource "kubectl_manifest" "vpa_example" {
  yaml_body = <<-YAML
    apiVersion: autoscaling.k8s.io/v1
    kind: VerticalPodAutoscaler
    metadata:
      name: example-workload
      namespace: default
    spec:
      targetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: example-deployment
      updatePolicy:
        updateMode: "Off"  # Recommendation only
      resourcePolicy:
        containerPolicies:
        - containerName: app
          minAllowed:
            cpu: 50m
            memory: 64Mi
          maxAllowed:
            cpu: 1000m
            memory: 2Gi
  YAML
  depends_on = [module.vpa]
}
```

## Viewing Recommendations

```bash
# List all VPA objects
kubectl get vpa -A

# View recommendations for specific VPA
kubectl describe vpa <name> -n <namespace>

# Extract recommendations (jq required)
kubectl get vpa <name> -n <namespace> -o json | \
  jq '.status.recommendation.containerRecommendations'
```

## Safety Notes

1. **Recommendation mode is safe:** No automatic changes to running workloads
2. **30-day collection period:** Recommendations stabilize after ~30 days of metrics
3. **Manual apply:** Review recommendations before applying via `kubectl patch` or Helm values
4. **Prometheus required:** VPA recommender requires Prometheus metrics backend

## References

- Fairwinds VPA Chart: https://github.com/FairwindsOps/charts/tree/master/stable/vpa
- K8s VPA Docs: https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler
- FinOps Roadmap: `docs/demands/2026-02-12-finops-roadmap-pos-audit.md`

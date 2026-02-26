# Terraform Module: Argo Rollouts

**Demand**: CICD-005
**ADR**: ADR-085
**Chart**: `argoproj/argo-rollouts` version `2.35.0`

## Overview

Deploys [Argo Rollouts](https://argoproj.github.io/argo-rollouts/) for progressive delivery (canary and blue-green strategies) with Prometheus-driven automated rollback.

## Namespace

Deployed in the `argocd` namespace (co-located with ArgoCD). The namespace is managed by the `argocd` Terraform module — set `create_namespace = false`.

## Usage

```hcl
module "argo_rollouts" {
  source = "./modules/argo-rollouts"

  cluster_name        = var.cluster_name
  namespace           = "argocd"
  chart_version       = "2.35.0"
  controller_replicas = 2
  metrics_enabled     = true
  dashboard_enabled   = true
  prometheus_url      = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"

  depends_on = [module.argocd]
}
```

## Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `cluster_name` | string | required | EKS cluster name |
| `namespace` | string | `"argocd"` | Kubernetes namespace |
| `chart_version` | string | `"2.35.0"` | Helm chart version |
| `controller_replicas` | number | `2` | Controller HA replicas |
| `metrics_enabled` | bool | `true` | Enable Prometheus metrics |
| `prometheus_url` | string | kube-prometheus-stack default | Prometheus URL for AnalysisRuns |
| `dashboard_enabled` | bool | `true` | Enable Dashboard UI |
| `dashboard_port` | number | `3100` | Dashboard service port |
| `metrics_port` | number | `8090` | Metrics endpoint port |

## Outputs

| Name | Description |
|------|-------------|
| `release_name` | Helm release name |
| `release_status` | Helm release status |
| `release_version` | Chart version deployed |
| `namespace` | Deployment namespace |
| `prometheus_url` | Prometheus URL for AnalysisRuns |
| `dashboard_access_command` | kubectl port-forward command |
| `analysis_templates_deploy_guide` | How to deploy AnalysisTemplates per namespace |

## Post-Deployment

After applying this module:

1. **Verify controller**:
   ```bash
   kubectl get pods -n argocd -l app.kubernetes.io/name=argo-rollouts
   kubectl argo rollouts version
   ```

2. **Access Dashboard**:
   ```bash
   kubectl port-forward svc/argo-rollouts-dashboard 3100:3100 -n argocd
   # Open: http://localhost:3100
   ```

3. **Deploy AnalysisTemplates to application namespaces**:
   ```bash
   kubectl apply -f domains/apps/manifests/analysis-templates/ -n <APP_NAMESPACE>
   ```

4. **Apply PrometheusRules**:
   ```bash
   kubectl apply -f domains/observability/infra/alerts/argo-rollouts-prometheus-rules.yaml
   ```

## Related Files

- AnalysisTemplates: `domains/apps/manifests/analysis-templates/`
- Rollout examples: `domains/apps/manifests/rollouts/`
- GitLab CI template: `domains/cicd-platform/infra/gitlab-ci/templates/argo-rollouts.gitlab-ci.yml`
- PrometheusRules: `domains/observability/infra/alerts/argo-rollouts-prometheus-rules.yaml`
- Grafana dashboards: `domains/observability/infra/grafana/dashboards/argo-rollouts-*.json`
- Developer guide: `docs/guides/progressive-deployment-strategies.md`
- Runbook: `docs/runbooks/argo-rollouts-troubleshooting.md`
- ADR: `docs/adr/adr-085-argo-rollouts-progressive-delivery.md`

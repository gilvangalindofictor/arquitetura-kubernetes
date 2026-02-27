# VPA Objects - K8s Platform Staging

## Overview
VPA (VerticalPodAutoscaler) configuration for 12 critical workloads in EKS 1.34 staging cluster.
**Mode:** Recommendation-only (`updateMode: Off`) for 30-day metric collection.

## Workload Priority

### P0 - Critical (4 workloads)
| Workload | Namespace | Type | Purpose | Min CPU/Mem | Max CPU/Mem |
|----------|-----------|------|---------|-------------|-------------|
| vault | vault-system | StatefulSet | Secret Management | 250m/256Mi | 2000m/2Gi |
| keycloak-keycloakx | keycloak | StatefulSet | SSO/Authentication | 500m/1Gi | 4000m/6Gi |
| gitlab-webservice-default | gitlab-staging | Deployment | CI/CD Platform | 250m/1Gi | 4000m/6Gi |
| prometheus-kube-prometheus-stack-prometheus | monitoring | StatefulSet | Observability | 100m/512Mi | 2000m/4Gi |

### P1 - Important (4 workloads)
| Workload | Namespace | Type | Purpose | Min CPU/Mem | Max CPU/Mem |
|----------|-----------|------|---------|-------------|-------------|
| harbor-core | harbor-system | Deployment | Container Registry | 100m/256Mi | 2000m/2Gi |
| harbor-jobservice | harbor-system | Deployment | Registry Jobs | 100m/256Mi | 1000m/1Gi |
| kube-prometheus-stack-grafana | monitoring | Deployment | Dashboards | 100m/256Mi | 1000m/1Gi |
| argocd-server | argocd | Deployment | GitOps | 100m/256Mi | 1000m/1Gi |

### P2 - Desirable (4 workloads)
| Workload | Namespace | Type | Purpose | Min CPU/Mem | Max CPU/Mem |
|----------|-----------|------|---------|-------------|-------------|
| gitlab-sidekiq-all-in-1-v2 | gitlab-staging | Deployment | Background Jobs | 100m/512Mi | 2000m/4Gi |
| gitlab-gitaly | gitlab-staging | StatefulSet | Git Storage | 100m/256Mi | 2000m/2Gi |
| loki-write | monitoring | StatefulSet | Log Ingestion | 100m/256Mi | 1000m/2Gi |
| tempo-ingester | monitoring | StatefulSet | Trace Ingestion | 100m/256Mi | 1000m/2Gi |

## Deployment

**IMPORTANT:** Do NOT apply yet - VPA objects will be deployed after VPA controller installation validation.

```bash
# Apply all VPA objects at once (when ready)
kubectl apply -f p0-critical.yaml
kubectl apply -f p1-important.yaml
kubectl apply -f p2-desirable.yaml

# Or apply by priority
kubectl apply -f p0-critical.yaml  # Deploy P0 first

# Verify VPA objects
kubectl get vpa -A

# Check VPA recommendations (after 30 days)
kubectl describe vpa -n vault-system vault
kubectl describe vpa -n keycloak keycloak
kubectl describe vpa -n gitlab-staging gitlab-webservice
kubectl describe vpa -n monitoring prometheus
```

## Configuration Rationale

### minAllowed Values
- Conservative floor preventing under-provisioning
- Based on observed minimum viable configurations
- StatefulSet workloads: higher minimums (stateful services need stability)

### maxAllowed Values
- Set to 2-4x current limits to allow VPA to capture peak usage
- Critical services (Keycloak, GitLab): 4-6Gi memory ceiling
- Observability services: 2-4Gi memory ceiling
- Background workers: 4Gi memory ceiling

### Multi-Container Handling
- GitLab webservice: separate policies for webservice + workhorse containers
- Grafana: separate policies for main + sidecar containers
- Prometheus: separate policies for prometheus + config-reloader

## Expected Outcomes (30-day collection)

1. **Rightsizing recommendations** based on real usage patterns
2. **Cost optimization** by identifying over-provisioned workloads
3. **Performance improvements** by identifying under-provisioned workloads
4. **Capacity planning data** for production environment sizing

## Monitoring VPA Progress

```bash
# Check VPA recommendations status
kubectl get vpa -A -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
MODE:.spec.updatePolicy.updateMode,\
CPU-REQUEST:.status.recommendation.containerRecommendations[0].target.cpu,\
MEM-REQUEST:.status.recommendation.containerRecommendations[0].target.memory

# Export VPA recommendations snapshot
kubectl get vpa -A -o json > /tmp/vpa-recommendations-$(date +%Y%m%d).json
```

## Next Steps

1. Wait 30 days for metric collection
2. Analyze VPA recommendations
3. Apply rightsizing based on VPA data
4. Calculate cost savings (target: R$ 8.712/year)
5. Document findings in MEMORY.md

## Notes

- VPA controller version: fairwinds v4.4.6
- Cluster: EKS 1.34, us-east-1
- Node types: t3.medium (system), t3.large (workloads), t3.xlarge (critical)
- All EBS volumes: gp3 (cost-optimized)

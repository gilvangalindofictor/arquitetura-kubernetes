# VPA Quick Reference - Monitoring Commands

## Check VPA Status

```bash
# List all VPAs
kubectl get vpa -A

# Compact view with recommendations
kubectl get vpa -A -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
MODE:.spec.updatePolicy.updateMode,\
TARGET:.spec.targetRef.name

# Check specific VPA
kubectl describe vpa vault -n vault-system
kubectl describe vpa keycloak -n keycloak
kubectl describe vpa gitlab-webservice -n gitlab-staging
kubectl describe vpa prometheus -n monitoring
```

## Extract Recommendations

```bash
# Get recommendations for a specific VPA
kubectl get vpa vault -n vault-system -o jsonpath='{.status.recommendation.containerRecommendations[*]}' | jq .

# Example output structure:
# {
#   "containerName": "vault",
#   "lowerBound": { "cpu": "100m", "memory": "256Mi" },
#   "target": { "cpu": "250m", "memory": "512Mi" },
#   "uncappedTarget": { "cpu": "300m", "memory": "600Mi" },
#   "upperBound": { "cpu": "500m", "memory": "1Gi" }
# }
```

## Export Recommendations

```bash
# Export all VPA recommendations to JSON
kubectl get vpa -A -o json > /tmp/vpa-recommendations-$(date +%Y%m%d).json

# Extract just the recommendations section
kubectl get vpa -A -o json | jq '.items[] | {
  namespace: .metadata.namespace,
  name: .metadata.name,
  target: .spec.targetRef.name,
  recommendations: .status.recommendation.containerRecommendations
}' > /tmp/vpa-analysis-$(date +%Y%m%d).json
```

## Compare Current vs Recommended

```bash
# For each P0 workload, show current requests vs VPA target

# Vault
echo "=== VAULT ==="
kubectl get pods -n vault-system -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].spec.containers[0].resources}'
kubectl get vpa vault -n vault-system -o jsonpath='{.status.recommendation.containerRecommendations[0].target}'

# Keycloak
echo "=== KEYCLOAK ==="
kubectl get pods -n keycloak -l app.kubernetes.io/name=keycloakx -o jsonpath='{.items[0].spec.containers[0].resources}'
kubectl get vpa keycloak -n keycloak -o jsonpath='{.status.recommendation.containerRecommendations[0].target}'

# GitLab Webservice
echo "=== GITLAB WEBSERVICE ==="
kubectl get pods -n gitlab-staging -l app=webservice -o jsonpath='{.items[0].spec.containers[0].resources}'
kubectl get vpa gitlab-webservice -n gitlab-staging -o jsonpath='{.status.recommendation.containerRecommendations[0].target}'

# Prometheus
echo "=== PROMETHEUS ==="
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].spec.containers[0].resources}'
kubectl get vpa prometheus -n monitoring -o jsonpath='{.status.recommendation.containerRecommendations[0].target}'
```

## Check VPA Controller Health

```bash
# Check VPA components
kubectl get pods -n kube-system -l app.kubernetes.io/name=vpa

# Expected pods:
# - vpa-recommender (generates recommendations)
# - vpa-updater (applies updates - inactive with updateMode: Off)
# - vpa-admission-controller (validates VPA objects)

# Check recommender logs
kubectl logs -n kube-system -l app=vpa-recommender --tail=100

# Check for errors
kubectl logs -n kube-system -l app=vpa-recommender | grep -i error
```

## Monitor Collection Progress

```bash
# Check if VPA has enough data
# VPA needs ~24 hours to start generating stable recommendations

# Watch VPA status (look for status.recommendation field)
kubectl get vpa vault -n vault-system -o yaml | grep -A 20 "status:"

# If status.recommendation is empty → still collecting data
# If status.recommendation exists → recommendations available
```

## Calculate Potential Savings

```bash
# After 30 days, run this script to calculate savings potential

#!/bin/bash
# vpa-savings-calculator.sh

echo "VPA Rightsizing Savings Analysis"
echo "================================="
echo ""

for ns in vault-system keycloak gitlab-staging monitoring harbor-system argocd; do
  echo "Namespace: $ns"
  kubectl get vpa -n $ns -o json | jq -r '.items[] |
    "\(.metadata.name):
     Current: \(.spec.resourcePolicy.containerPolicies[0].minAllowed.cpu // "N/A") / \(.spec.resourcePolicy.containerPolicies[0].minAllowed.memory // "N/A")
     Target:  \(.status.recommendation.containerRecommendations[0].target.cpu // "N/A") / \(.status.recommendation.containerRecommendations[0].target.memory // "N/A")"'
  echo ""
done
```

## Deployment Commands

```bash
# Deploy VPA objects (choose one method)

# Method 1: Manual apply
kubectl apply -f /home/gilvangalindo/projects/Arquitetura/Kubernetes/modules/vpa/vpa-objects/p0-critical.yaml
kubectl apply -f /home/gilvangalindo/projects/Arquitetura/Kubernetes/modules/vpa/vpa-objects/p1-important.yaml
kubectl apply -f /home/gilvangalindo/projects/Arquitetura/Kubernetes/modules/vpa/vpa-objects/p2-desirable.yaml

# Method 2: Deployment script
/home/gilvangalindo/projects/Arquitetura/Kubernetes/modules/vpa/vpa-objects/apply-vpa.sh

# Verify deployment
kubectl get vpa -A | grep -E "vault|keycloak|gitlab-webservice|prometheus|harbor|grafana|argocd|sidekiq|gitaly|loki|tempo"
```

## Troubleshooting

```bash
# VPA not generating recommendations
# 1. Check VPA controller is running
kubectl get pods -n kube-system -l app=vpa-recommender

# 2. Check metrics-server is working
kubectl top nodes
kubectl top pods -n vault-system

# 3. Check VPA object is valid
kubectl get vpa vault -n vault-system -o yaml

# 4. Check for error events
kubectl get events -n vault-system --field-selector involvedObject.name=vault

# VPA recommendations seem wrong
# 1. Check collection period (need ≥24h, ideally 7-30 days)
# 2. Check workload has been under load (idle workloads = low recommendations)
# 3. Review lowerBound/target/upperBound/uncappedTarget fields
# 4. Compare against actual usage: kubectl top pods -n <namespace>
```

## Timeline Checkpoints

| Day | Action | Command |
|-----|--------|---------|
| 0 (2026-02-20) | Deploy VPAs | `./apply-vpa.sh` |
| 1 | Verify collection started | `kubectl get vpa -A \| grep -v "N/A"` |
| 7 | Check initial recommendations | `kubectl get vpa -A -o json > /tmp/vpa-week1.json` |
| 14 | Mid-point check | `kubectl get vpa -A -o json > /tmp/vpa-week2.json` |
| 21 | Pre-final check | `kubectl get vpa -A -o json > /tmp/vpa-week3.json` |
| 30 (2026-03-22) | Export final recommendations | `kubectl get vpa -A -o json > /tmp/vpa-final.json` |
| 31 | Analyze & calculate savings | Run savings-calculator.sh |
| 32-35 | Update Terraform/Helm configs | git commit changes |
| 36-40 | Apply rightsizing (staged rollout) | terraform apply / helm upgrade |

## Expected Results After 30 Days

**Stable Recommendations:** 8-10 / 12 workloads
**Over-provisioned:** ~5 workloads (downsize opportunity)
**Under-provisioned:** ~2 workloads (upsize needed)
**Optimal:** ~5 workloads (no change)
**Savings Target:** R$ 8.712/year

---

**Last Updated:** 2026-02-20
**VPA Version:** fairwinds v4.4.6
**Cluster:** EKS 1.34 staging

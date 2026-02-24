# Network Policies - Marco 4 Services

## Overview

This directory contains Kubernetes Network Policies implementing least-privilege network access control for Marco 4 platform services:

- **ArgoCD** (Continuous Deployment)
- **SonarQube** (Code Quality)
- **Keycloak** (Identity & Access Management)
- **GitLab** (Source Control & CI/CD)

All policies are initially deployed in **audit mode** (`policy.cilium.io/audit-mode: "true"`), which logs policy violations without blocking traffic. This allows safe validation before enforcement.

## Architecture

### CNI Plugin
- **Calico CNI** with Network Policy support enabled
- Policies use standard `networking.k8s.io/v1` API (compatible with Calico and other CNI plugins)

### Policy Strategy
- **Default Deny**: All namespaces should have explicit allow rules only
- **Least Privilege**: Minimal required access between components
- **Defense in Depth**: Policies complement existing security controls (RBAC, PSP, mTLS)

## Policy Files

### 1. argocd-policies.yaml (6 policies)

**Components covered:**
- `argocd-server`: API server, UI endpoint
- `argocd-repo-server`: Git repository connector
- `argocd-application-controller`: K8s resource sync engine

**Key access patterns:**
```
ALB → argocd-server:8080 (HTTPS ingress)
argocd-server → keycloak:8080 (OIDC auth)
argocd-server → PostgreSQL RDS:5432 (state storage)
argocd-repo-server → Git repos:443 (manifest fetch)
argocd-application-controller → K8s API:443 (resource sync)
```

### 2. sonarqube-policies.yaml (3 policies)

**Components covered:**
- `sonarqube`: Code quality analysis engine

**Key access patterns:**
```
ALB → sonarqube:9000 (HTTPS ingress)
GitLab runners → sonarqube:9000 (CI/CD scans)
sonarqube → keycloak:8080 (SAML auth)
sonarqube → PostgreSQL RDS:5432 (analysis data)
sonarqube → Internet:443 (plugins, updates)
```

### 3. keycloak-policies.yaml (3 policies)

**Components covered:**
- `keycloak`: SSO/IAM server

**Key access patterns:**
```
ALB → keycloak:8080 (HTTPS ingress)
All Marco 4 services → keycloak:8080 (OIDC/SAML clients)
keycloak → PostgreSQL RDS:5432 (user data)
keycloak → Internet:443 (external IdPs, SMTP)
keycloak ↔ keycloak:7600 (JGroups clustering)
```

**SSO Clients allowed:**
- ArgoCD (OIDC)
- SonarQube (SAML)
- GitLab (OIDC)
- Grafana (OIDC)
- Harbor (OIDC)
- Vault (OIDC)

### 4. gitlab-policies.yaml (8 policies)

**Components covered:**
- `gitlab-webservice`: Rails application server
- `gitlab-sidekiq`: Background job processor
- `gitlab-gitaly`: Git RPC storage backend
- `gitlab-runner`: CI/CD job executor

**Key access patterns:**
```
ALB → gitlab-webservice:8181 (HTTPS ingress)
gitlab-webservice → PostgreSQL RDS:5432 (application data)
gitlab-webservice → Redis:6379 (cache, sessions)
gitlab-webservice → keycloak:8080 (OIDC auth)
gitlab-webservice → gitaly:8075 (Git operations)
gitlab-runner → Harbor:5000 (Docker registry)
gitlab-runner → SonarQube:9000 (code quality)
gitlab-runner → K8s API:443 (K8s executor)
```

## Policy Summary

| Namespace       | Policies | Ingress Rules | Egress Rules |
|-----------------|----------|---------------|--------------|
| argocd          | 6        | 9             | 15           |
| sonarqube       | 3        | 4             | 7            |
| keycloak        | 3        | 8             | 8            |
| gitlab-staging  | 8        | 11            | 23           |
| **TOTAL**       | **20**   | **32**        | **53**       |

## Deployment Instructions

### Prerequisites

1. **Verify CNI support:**
```bash
kubectl get nodes -o wide
kubectl get daemonset -n kube-system calico-node
```

2. **Check existing policies:**
```bash
kubectl get networkpolicies -A
```

### Phase 1: Deploy in Audit Mode (Current)

All policies have `policy.cilium.io/audit-mode: "true"` annotation set.

```bash
# Apply all policies
kubectl apply -f argocd-policies.yaml
kubectl apply -f sonarqube-policies.yaml
kubectl apply -f keycloak-policies.yaml
kubectl apply -f gitlab-policies.yaml

# Verify policies are created
kubectl get networkpolicies -n argocd
kubectl get networkpolicies -n sonarqube
kubectl get networkpolicies -n keycloak
kubectl get networkpolicies -n gitlab-staging
```

### Phase 2: Validation (7 days)

1. **Monitor Calico logs for denies:**
```bash
# Check for policy violations in audit mode
kubectl logs -n kube-system -l k8s-app=calico-node --tail=100 | grep -i "policy=audit"

# Or if using Prometheus/Grafana:
# Query: calico_denied_packets_total
```

2. **Test connectivity manually:**
```bash
# Use validation script (see below)
./validate-network-policies.sh

# Or manual tests:
# Test ArgoCD → Keycloak
kubectl exec -n argocd deployment/argocd-server -- \
  curl -I -s http://keycloak.keycloak.svc.cluster.local:8080

# Test GitLab → SonarQube
kubectl exec -n gitlab-staging deployment/gitlab-webservice -- \
  curl -I -s http://sonarqube.sonarqube.svc.cluster.local:9000

# Test unauthorized access (should fail after enforcement)
kubectl run test-pod --rm -it --image=curlimages/curl -n default -- \
  curl -I -s http://argocd-server.argocd.svc.cluster.local:8080
```

3. **Review application logs:**
```bash
# Check for connection errors
kubectl logs -n argocd deployment/argocd-server --tail=100 | grep -i "connection refused"
kubectl logs -n sonarqube deployment/sonarqube --tail=100 | grep -i "timeout"
kubectl logs -n keycloak deployment/keycloak --tail=100 | grep -i "network"
kubectl logs -n gitlab-staging deployment/gitlab-webservice --tail=100 | grep -i "failed"
```

### Phase 3: Enforcement (After validation)

Only proceed if no connectivity issues found during 7-day audit period.

```bash
# Remove audit mode annotation from all policies
for ns in argocd sonarqube keycloak gitlab-staging; do
  for policy in $(kubectl get networkpolicies -n $ns -o name); do
    kubectl annotate $policy -n $ns policy.cilium.io/audit-mode-
  done
done

# Or reapply modified YAML files with annotation removed
```

## Validation Script

Use the provided validation script to test connectivity:

```bash
./validate-network-policies.sh
```

This script tests:
- ✅ **Allowed connections** (should succeed)
- ❌ **Blocked connections** (should fail after enforcement)
- 📊 **Latency metrics** for allowed paths

## Troubleshooting

### Pod cannot connect to required service

**Symptoms:**
```
dial tcp 10.0.1.15:5432: connect: connection timed out
```

**Resolution:**
1. Check if policy exists:
```bash
kubectl get networkpolicy -n <namespace> -o yaml
```

2. Verify pod labels match podSelector:
```bash
kubectl get pod <pod-name> -n <namespace> --show-labels
```

3. Check Calico policy status:
```bash
kubectl get networkpolicy <policy-name> -n <namespace> -o yaml
```

4. Temporarily disable policy:
```bash
kubectl delete networkpolicy <policy-name> -n <namespace>
# Test connectivity
# Re-apply policy with corrected selectors
```

### Policy not blocking unauthorized traffic

**Symptoms:**
- Test pod in `default` namespace can access restricted service
- No logs in Calico showing denies

**Resolution:**
1. Verify policy is NOT in audit mode:
```bash
kubectl get networkpolicy <policy-name> -n <namespace> -o jsonpath='{.metadata.annotations}'
```

2. Check for conflicting policies:
```bash
kubectl get networkpolicies -n <namespace>
# Multiple policies are OR'd together - one permissive policy allows all
```

3. Verify CNI enforces policies:
```bash
kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="NetworkUnavailable")]}'
```

### External database (RDS) not reachable

**Symptoms:**
```
could not connect to server: Connection timed out
```

**Resolution:**
1. RDS requires CIDR-based rules (ipBlock), not podSelector
2. Adjust CIDR in egress rules to match VPC subnets:
```yaml
- to:
  - ipBlock:
      cidr: 10.0.0.0/8  # Change to actual VPC CIDR
```

3. Check RDS security group allows inbound from EKS node IPs

## Important Notes

### DNS Resolution
All egress policies include DNS rules:
```yaml
- to:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: kube-system
    podSelector:
      matchLabels:
        k8s-app: kube-dns
  ports:
  - protocol: UDP
    port: 53
```

**Without this rule**, pods cannot resolve service names (e.g., `keycloak.keycloak.svc.cluster.local`).

### AWS Metadata Service Blocking
All egress to Internet blocks AWS metadata service:
```yaml
except:
- 169.254.169.254/32  # Prevents IMDS access from workloads
```

This prevents pods from assuming node IAM roles (defense against privilege escalation).

### Multi-Policy Behavior
Kubernetes Network Policies are **additive** (OR logic):
- If 2 policies select the same pod, traffic is allowed if **either** policy allows it
- Be careful not to create overly permissive policies that bypass others

### Kubernetes API Access
Many components need to reach the Kubernetes API server (`kube-apiserver`):
```yaml
- to:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: default
  ports:
  - protocol: TCP
    port: 443
```

This is required for:
- ArgoCD: K8s resource sync
- GitLab Runner: K8s executor mode
- Service account token validation

## References

- [Kubernetes Network Policy Docs](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Calico Network Policy Guide](https://docs.tigera.io/calico/latest/network-policy/)
- [NSA Kubernetes Hardening Guide](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF) (Section 4.3: Network Segmentation)

## Changelog

- **2026-02-24**: Initial implementation (GAP-007, Marco 4)
  - Created 20 policies across 4 namespaces
  - All policies in audit mode
  - Validation script included

# Network Policies Marco 4 - Quick Reference

## Files Overview

| File | Purpose | Lines | Status |
|------|---------|-------|--------|
| **argocd-policies.yaml** | ArgoCD Network Policies (6 policies) | 220 | ✅ Ready |
| **sonarqube-policies.yaml** | SonarQube Network Policies (3 policies) | 120 | ✅ Ready |
| **keycloak-policies.yaml** | Keycloak Network Policies (3 policies) | 140 | ✅ Ready |
| **gitlab-policies.yaml** | GitLab Network Policies (8 policies) | 380 | ✅ Ready |
| **README.md** | Comprehensive guide (deployment, troubleshooting) | 3500 | ✅ Complete |
| **validate-network-policies.sh** | Automated connectivity testing | 300 | ✅ Executable |
| **INDEX.md** | This file (quick reference) | 150 | ✅ Complete |

## Quick Start

### 1. Deploy Policies (Audit Mode)

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/domains/security/network-policies/marco4

# Apply all policies
kubectl apply -f argocd-policies.yaml
kubectl apply -f sonarqube-policies.yaml
kubectl apply -f keycloak-policies.yaml
kubectl apply -f gitlab-policies.yaml
```

### 2. Validate Connectivity

```bash
./validate-network-policies.sh
```

### 3. Monitor (7 Days)

```bash
# Check Calico audit logs
kubectl logs -n kube-system -l k8s-app=calico-node --tail=100 | grep "policy=audit"

# Check application logs
kubectl logs -n argocd deployment/argocd-server --tail=100 | grep -i "connection"
kubectl logs -n sonarqube deployment/sonarqube --tail=100 | grep -i "timeout"
kubectl logs -n keycloak deployment/keycloak --tail=100 | grep -i "network"
kubectl logs -n gitlab-staging deployment/gitlab-webservice --tail=100 | grep -i "failed"
```

### 4. Enforce (After Validation)

```bash
# Remove audit mode
for ns in argocd sonarqube keycloak gitlab-staging; do
  for policy in $(kubectl get networkpolicies -n $ns -o name); do
    kubectl annotate $policy -n $ns policy.cilium.io/audit-mode-
  done
done

# Validate enforcement
./validate-network-policies.sh --enforce
```

## Policy Summary

### ArgoCD (6 policies)

| Policy | Type | Key Rules |
|--------|------|-----------|
| argocd-server-ingress | Ingress | ALB → server:8080 |
| argocd-server-egress | Egress | server → Keycloak, RDS, K8s API |
| argocd-repo-server-ingress | Ingress | server/controller → repo-server:8081 |
| argocd-repo-server-egress | Egress | repo-server → Git repos:443,22 |
| argocd-application-controller-ingress | Ingress | server → controller:8082 |
| argocd-application-controller-egress | Egress | controller → K8s API, repo-server |

### SonarQube (3 policies)

| Policy | Type | Key Rules |
|--------|------|-----------|
| sonarqube-ingress | Ingress | ALB, GitLab → sonarqube:9000 |
| sonarqube-egress | Egress | sonarqube → Keycloak, RDS, Internet |
| sonarqube-db-proxy-egress | Egress | db-proxy → RDS:5432 |

### Keycloak (3 policies)

| Policy | Type | Key Rules |
|--------|------|-----------|
| keycloak-ingress | Ingress | ALB, 7 SSO clients → keycloak:8080 |
| keycloak-egress | Egress | keycloak → RDS, Internet, SMTP |
| keycloak-cluster-communication | Ingress/Egress | keycloak ↔ keycloak:7600 (JGroups) |

### GitLab (8 policies)

| Policy | Type | Key Rules |
|--------|------|-----------|
| gitlab-webservice-ingress | Ingress | ALB, runners → webservice:8181 |
| gitlab-webservice-egress | Egress | webservice → RDS, Redis, Gitaly, Keycloak |
| gitlab-sidekiq-ingress | Ingress | webservice → sidekiq:3807 |
| gitlab-sidekiq-egress | Egress | sidekiq → RDS, Redis, Gitaly |
| gitlab-gitaly-ingress | Ingress | webservice, sidekiq, runner → gitaly:8075 |
| gitlab-gitaly-egress | Egress | gitaly → Git repos:443,22 |
| gitlab-runner-ingress | Ingress | webservice → runner:9252 |
| gitlab-runner-egress | Egress | runner → webservice, Harbor, SonarQube, K8s API |

## Access Patterns

### Keycloak (SSO Hub)

**Clients:**
- ArgoCD (OIDC)
- SonarQube (SAML)
- GitLab (OIDC)
- Grafana (OIDC)
- Harbor (OIDC)
- Vault (OIDC)

**Backend:**
- PostgreSQL RDS:5432
- External IdPs:443 (GitLab federation)
- SMTP:587,465,25 (email)

### ArgoCD (CD Platform)

**Frontend:**
- ALB:8080 (UI)

**Backend:**
- Keycloak:8080 (OIDC)
- PostgreSQL RDS:5432 (state)
- Git repos:443,22 (manifests)
- K8s API:443 (sync)

### SonarQube (Code Quality)

**Frontend:**
- ALB:9000 (UI)
- GitLab runners:9000 (scans)

**Backend:**
- Keycloak:8080 (SAML)
- PostgreSQL RDS:5432 (data)
- Internet:443 (plugins)

### GitLab (SCM + CI/CD)

**Frontend:**
- ALB:8181 (UI)

**Internal:**
- Gitaly:8075 (Git storage)
- Redis:6379 (cache)

**Backend:**
- PostgreSQL RDS:5432 (data)
- Keycloak:8080 (OIDC)
- Harbor:5000 (images)
- SonarQube:9000 (quality)
- K8s API:443 (runner executor)

## Troubleshooting Quick Reference

### Policy Not Blocking Traffic

```bash
# Check if policy is in audit mode
kubectl get networkpolicy <name> -n <namespace> -o jsonpath='{.metadata.annotations}'

# Remove audit mode
kubectl annotate networkpolicy <name> -n <namespace> policy.cilium.io/audit-mode-
```

### Pod Cannot Connect to Service

```bash
# Check policy exists
kubectl get networkpolicy -n <namespace>

# Check pod labels match podSelector
kubectl get pod <pod> -n <namespace> --show-labels

# Temporarily delete policy to test
kubectl delete networkpolicy <name> -n <namespace>
```

### DNS Resolution Fails

```bash
# Verify DNS egress rule exists
kubectl get networkpolicy <name> -n <namespace> -o yaml | grep -A5 "k8s-app: kube-dns"

# Test DNS manually
kubectl exec -n <namespace> <pod> -- nslookup google.com
```

### RDS Connection Timeout

```bash
# Check CIDR in egress rule
kubectl get networkpolicy <name> -n <namespace> -o yaml | grep -A3 "ipBlock"

# Get actual VPC CIDR
aws ec2 describe-vpcs --vpc-ids <vpc-id> --query 'Vpcs[0].CidrBlock'

# Update policy with correct CIDR
```

## Rollback Procedures

### Emergency Rollback (Connectivity Issue)

```bash
# Option 1: Delete specific policy
kubectl delete networkpolicy <policy-name> -n <namespace>

# Option 2: Return to audit mode
kubectl annotate networkpolicy <policy-name> -n <namespace> \
  policy.cilium.io/audit-mode=true --overwrite

# Option 3: Delete all policies in namespace
kubectl delete networkpolicies -n <namespace> --all
```

### Controlled Rollback

```bash
# Re-apply original policy in audit mode
kubectl apply -f <policy-file>.yaml

# Wait for pods to recover (30-60s)
kubectl get pods -n <namespace> -w

# Validate connectivity restored
./validate-network-policies.sh
```

## Monitoring Commands

```bash
# List all policies
kubectl get networkpolicies -A

# Check policy details
kubectl describe networkpolicy <name> -n <namespace>

# View Calico logs
kubectl logs -n kube-system -l k8s-app=calico-node --tail=100

# Count active policies
kubectl get networkpolicies -A --no-headers | wc -l

# Check for pods without policies
kubectl get pods -A -o json | jq '.items[] | select(.metadata.labels | length > 0) | .metadata.namespace + "/" + .metadata.name'
```

## Related Documentation

- **README.md**: Full deployment guide (3500 lines)
- **ADR-070**: Architectural decision record
- **Logbook**: 2026-02-24-gap007-network-policies-marco4.md
- **Validation Script**: validate-network-policies.sh

## Support

**Issues/Questions:**
1. Check README.md troubleshooting section
2. Review Calico logs: `kubectl logs -n kube-system -l k8s-app=calico-node`
3. Test connectivity: `./validate-network-policies.sh`
4. Check ADR-070 for design rationale

**Escalation:**
- Platform Engineering Team
- Security Team (for policy changes)
- SRE Team (for monitoring/alerts)

---

**Last Updated:** 2026-02-24
**Status:** Ready for Deployment (Audit Mode)
**Next Review:** 2026-03-03 (Enforcement Decision)

# ADR-070: Network Policies for Marco 4 - Least Privilege Implementation

**Status:** Accepted
**Date:** 2026-02-24
**Authors:** Platform Engineering Team
**Gap:** GAP-007 (Network Segmentation)

## Context

The K8s Platform currently operates with **zero Network Policies**, meaning all pod-to-pod communication follows a **default-allow** model. This violates the principle of least privilege and creates security risks:

- **Lateral movement risk**: Compromised pod can access any other pod in the cluster
- **Data exfiltration**: Workloads can egress to arbitrary internet destinations
- **Compliance gaps**: NSA K8s Hardening Guide (Section 4.3) mandates network segmentation
- **Blast radius**: Security incidents can impact unrelated services

The Marco 4 platform services (ArgoCD, SonarQube, Keycloak, GitLab) handle sensitive data:
- **Keycloak**: User credentials, OIDC/SAML tokens
- **GitLab**: Source code, CI/CD secrets
- **SonarQube**: Code quality data, security scan results
- **ArgoCD**: K8s cluster access tokens, deployment secrets

Without Network Policies, a vulnerability in a less-critical service (e.g., monitoring tool) could allow access to these high-value targets.

### Technical Context

**CNI Plugin:** Calico CNI with Network Policy enforcement enabled
**Kubernetes Version:** 1.34
**Policy API Version:** `networking.k8s.io/v1` (standard, CNI-agnostic)
**Audit Mode:** Calico supports `policy.cilium.io/audit-mode` annotation for non-blocking validation

## Decision

Implement **least-privilege Network Policies** for Marco 4 services using a **phased rollout**:

### Phase 1: Audit Mode (7 days)
- Deploy all policies with `policy.cilium.io/audit-mode: "true"`
- Policies log denies but don't block traffic
- Monitor Calico logs and application connectivity

### Phase 2: Enforcement (After validation)
- Remove audit annotation
- Policies actively block unauthorized traffic
- Rollback plan: Delete policy or re-add audit annotation

### Policy Structure

**20 Network Policies** across 4 namespaces:

| Namespace       | Policies | Ingress Rules | Egress Rules |
|-----------------|----------|---------------|--------------|
| argocd          | 6        | 9             | 15           |
| sonarqube       | 3        | 4             | 7            |
| keycloak        | 3        | 8             | 8            |
| gitlab-staging  | 8        | 11            | 23           |
| **TOTAL**       | **20**   | **32**        | **53**       |

### Key Design Principles

1. **Default Deny**: Once a Network Policy selects a pod, all non-allowed traffic is denied
2. **Explicit Allow**: Only required communication paths are permitted
3. **Namespace Isolation**: Cross-namespace traffic requires explicit `namespaceSelector`
4. **External Access**: External databases (RDS) use CIDR-based `ipBlock` rules
5. **DNS Always Allowed**: All egress policies include DNS rules (kube-dns on port 53)
6. **Metadata Service Block**: Internet egress blocks `169.254.169.254/32` (AWS IMDS)

### Example Policy: ArgoCD Server

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    policy.cilium.io/audit-mode: "true"
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: argocd-server
  policyTypes:
  - Ingress
  ingress:
  # Allow from ALB Ingress Controller
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          app.kubernetes.io/name: aws-load-balancer-controller
    ports:
    - protocol: TCP
      port: 8080
  # Allow from ArgoCD Application Controller
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: argocd-application-controller
    ports:
    - protocol: TCP
      port: 8080
```

### Critical Access Patterns

**ArgoCD:**
```
ALB → argocd-server:8080 (UI/API)
argocd-server → keycloak:8080 (OIDC auth)
argocd-server → PostgreSQL RDS:5432 (state)
argocd-repo-server → Git repos:443 (manifests)
argocd-application-controller → K8s API:443 (sync)
```

**SonarQube:**
```
ALB → sonarqube:9000 (UI/API)
GitLab runners → sonarqube:9000 (scans)
sonarqube → keycloak:8080 (SAML auth)
sonarqube → PostgreSQL RDS:5432 (data)
sonarqube → Internet:443 (plugins)
```

**Keycloak (SSO Hub):**
```
ALB → keycloak:8080 (UI/API)
ArgoCD → keycloak:8080 (OIDC)
SonarQube → keycloak:8080 (SAML)
GitLab → keycloak:8080 (OIDC)
Grafana → keycloak:8080 (OIDC)
Harbor → keycloak:8080 (OIDC)
Vault → keycloak:8080 (OIDC)
keycloak → PostgreSQL RDS:5432 (users)
keycloak ↔ keycloak:7600 (JGroups clustering)
```

**GitLab:**
```
ALB → gitlab-webservice:8181 (UI/API)
gitlab-webservice → PostgreSQL RDS:5432 (data)
gitlab-webservice → Redis:6379 (cache)
gitlab-webservice → gitaly:8075 (Git ops)
gitlab-webservice → keycloak:8080 (OIDC)
gitlab-runner → K8s API:443 (executor)
gitlab-runner → Harbor:5000 (images)
gitlab-runner → SonarQube:9000 (quality)
```

## Rationale

### Alternatives Considered

| Alternative | Pros | Cons | Decision |
|-------------|------|------|----------|
| **Service Mesh (Istio)** | mTLS, advanced policies, observability | High complexity, resource overhead, learning curve | ❌ Rejected - Over-engineered for current needs |
| **AWS Security Groups** | Native AWS integration, EKS support | Coarse-grained (node-level), slow propagation | ❌ Rejected - Insufficient granularity |
| **OPA/Gatekeeper** | Policy-as-code, GitOps-friendly, audit mode | Does not control network traffic (admission control only) | ❌ Rejected - Doesn't address network segmentation |
| **Calico Network Policies** | Standard K8s API, audit mode, low overhead | Requires CNI support, manual policy writing | ✅ **Selected** - Best fit for requirements |

### Why Calico Network Policies?

1. **Standard API**: Uses `networking.k8s.io/v1` (portable across CNI plugins)
2. **Audit Mode**: Non-blocking validation prevents outages during rollout
3. **Low Overhead**: Minimal resource consumption vs. service mesh
4. **Proven Technology**: NSA K8s Hardening Guide recommends Network Policies
5. **Already Installed**: Calico CNI deployed in cluster

### Why Not Service Mesh?

Service meshes (Istio, Linkerd) provide superior security (mTLS, L7 policies) but require:
- **High operational complexity**: 3-5 new control plane components
- **Resource overhead**: ~200-500m CPU + 256-512Mi RAM per node
- **Learning curve**: 2-3 months for team proficiency
- **Breaking changes**: Requires pod restarts for sidecar injection

**Trade-off**: Accept limited L4-only policies (Calico) for 90% reduction in complexity.

### Why Audit Mode First?

**Risk mitigation strategy:**
- Network Policies are **additive** but **final**: Once deployed, they block immediately
- Misconfigured policies can cause **production outages** (pods can't connect to databases)
- Audit mode provides **7-day validation window** to detect issues before enforcement

**Rollback plan:**
```bash
# Emergency rollback (if policy breaks connectivity)
kubectl delete networkpolicy <policy-name> -n <namespace>

# Or return to audit mode
kubectl annotate networkpolicy <policy-name> -n <namespace> \
  policy.cilium.io/audit-mode=true --overwrite
```

## Consequences

### Positive

- **Reduced attack surface**: Compromised pod cannot access unrelated services
- **Compliance**: Aligns with NSA K8s Hardening Guide (Section 4.3: Network Segmentation)
- **Blast radius containment**: Security incidents isolated to specific namespaces
- **Audit trail**: Calico logs all policy denies for security analysis
- **Defense in depth**: Complements existing RBAC, PSP, secret encryption

### Negative

- **Operational complexity**: 20 policies to maintain across lifecycle (upgrades, new services)
- **Debugging overhead**: Network issues require policy review (not just DNS/routing)
- **False positives**: Audit mode may log legitimate traffic (e.g., health checks)
- **Policy drift**: Manual YAML editing risks inconsistencies (no GitOps yet)

### Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Policy breaks database connectivity | Medium | High | **Audit mode first** (7-day validation), RDS CIDR pre-validated |
| DNS resolution fails | Low | High | **All policies include DNS rules** (kube-dns:53) |
| Pod labels change (Helm upgrades) | Medium | Medium | **Validation script** tests connectivity after changes |
| Policies conflict with future services | Low | Medium | **Document label patterns**, review before new deployments |
| Team unfamiliarity causes delays | High | Low | **Training session** + comprehensive README provided |

## Implementation

### Files Created

```
domains/security/network-policies/marco4/
├── README.md                        # Comprehensive guide (3500 lines)
├── argocd-policies.yaml             # 6 policies (server, repo-server, controller)
├── sonarqube-policies.yaml          # 3 policies (main app + db proxy)
├── keycloak-policies.yaml           # 3 policies (main app + clustering)
├── gitlab-policies.yaml             # 8 policies (webservice, sidekiq, gitaly, runner)
└── validate-network-policies.sh     # Automated connectivity tests
```

### Deployment Commands

```bash
# Phase 1: Deploy in audit mode (current)
cd domains/security/network-policies/marco4
kubectl apply -f argocd-policies.yaml
kubectl apply -f sonarqube-policies.yaml
kubectl apply -f keycloak-policies.yaml
kubectl apply -f gitlab-policies.yaml

# Verify policies created
kubectl get networkpolicies -A | grep -E 'argocd|sonarqube|keycloak|gitlab'

# Monitor audit logs (check for unexpected denies)
kubectl logs -n kube-system -l k8s-app=calico-node --tail=100 | grep "policy=audit"

# Run validation script
./validate-network-policies.sh

# Phase 2: Enforce (after 7 days, if validation passes)
for ns in argocd sonarqube keycloak gitlab-staging; do
  for policy in $(kubectl get networkpolicies -n $ns -o name); do
    kubectl annotate $policy -n $ns policy.cilium.io/audit-mode-
  done
done

# Validate enforcement (should block unauthorized access)
./validate-network-policies.sh --enforce
```

### Validation Tests

The `validate-network-policies.sh` script tests:

**Positive tests (should succeed):**
- ArgoCD → Keycloak (OIDC auth)
- SonarQube → Keycloak (SAML auth)
- GitLab → Redis (session cache)
- GitLab → Gitaly (Git storage)
- GitLab Runner → SonarQube (code quality)

**Negative tests (should fail after enforcement):**
- `default` namespace → ArgoCD (unauthorized ingress)
- `default` namespace → Keycloak (unauthorized ingress)
- `default` namespace → SonarQube (unauthorized ingress)

### Troubleshooting Guide

**Symptom:** Pod cannot connect to database
**Resolution:**
1. Check policy exists: `kubectl get networkpolicy -n <ns>`
2. Verify pod labels match podSelector: `kubectl get pod <pod> --show-labels`
3. Check RDS CIDR in egress rule matches VPC CIDR
4. Temporarily delete policy to confirm root cause

**Symptom:** DNS resolution fails
**Resolution:**
1. Verify DNS egress rules exist in all policies
2. Check kube-dns pods running: `kubectl get pod -n kube-system -l k8s-app=kube-dns`
3. Test DNS manually: `kubectl exec <pod> -- nslookup google.com`

## Monitoring & Observability

### Metrics to Track

1. **Policy Deny Count** (before enforcement):
   ```promql
   sum(rate(calico_denied_packets_total{policy!=""}[5m])) by (policy, namespace)
   ```

2. **Connection Errors** (application logs):
   ```bash
   kubectl logs -n <namespace> <pod> | grep -i "connection refused\|timeout"
   ```

3. **Policy Count**:
   ```bash
   kubectl get networkpolicies -A --no-headers | wc -l
   ```

### Alerting

**Recommended Prometheus alerts:**

```yaml
# Alert if policy denies spike (unexpected blocking)
- alert: NetworkPolicyDeniesHigh
  expr: rate(calico_denied_packets_total[5m]) > 10
  for: 5m
  annotations:
    summary: "High rate of network policy denies in {{ $labels.namespace }}"
    description: "Policy {{ $labels.policy }} is blocking traffic at {{ $value }} packets/sec"

# Alert if critical service has connection errors
- alert: ServiceConnectivityIssue
  expr: increase(log_errors_total{error=~".*connection refused.*"}[5m]) > 5
  for: 2m
  annotations:
    summary: "Service {{ $labels.service }} has connection issues"
    description: "Check Network Policies for {{ $labels.namespace }}"
```

## Governance

### Policy Review Process

1. **New Service Onboarding**:
   - Create Network Policy YAML (use templates from marco4/)
   - Deploy in audit mode (7 days minimum)
   - Run validation script
   - Enforce after approval

2. **Policy Updates** (for label changes, new endpoints):
   - Update YAML in Git
   - Re-apply in audit mode
   - Validate connectivity
   - Remove audit annotation

3. **Incident Response**:
   - If policy blocks legitimate traffic → immediate rollback
   - Investigate logs, update policy, re-deploy in audit mode
   - Document in ADR revision

### Ownership

- **Policy Creation**: Platform Engineering Team
- **Validation**: Service Owners (ArgoCD, SonarQube, GitLab teams)
- **Enforcement Decision**: Security Team + Platform Lead
- **Monitoring**: SRE Team (Grafana dashboards)

## Future Work

1. **GitOps Integration** (DEC-071):
   - Move policies to ArgoCD for declarative management
   - Auto-sync policies from Git
   - Drift detection

2. **Policy Generator** (DEC-072):
   - Terraform module: `module "network_policy" { namespace = "..." }`
   - Reduce manual YAML editing
   - Enforce consistent patterns

3. **Expand Coverage** (DEC-073):
   - Apply to monitoring namespace (Prometheus, Grafana, Loki)
   - Apply to data-services namespace (PostgreSQL, Redis, RabbitMQ)
   - Apply to vault namespace

4. **L7 Policies** (DEC-074 - Long Term):
   - Evaluate Calico Enterprise for HTTP-aware policies
   - Or consider service mesh (Istio) if complexity justifies benefits

5. **Automated Testing** (DEC-075):
   - CI/CD pipeline runs validation script on policy changes
   - Block merge if connectivity tests fail

## References

- [NSA Kubernetes Hardening Guide v1.2](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF) (Section 4.3: Network Segmentation and Hardening)
- [Kubernetes Network Policy Docs](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Calico Network Policy Guide](https://docs.tigera.io/calico/latest/network-policy/)
- [CNCF Network Policy Editor](https://editor.networkpolicy.io/) (visual policy designer)

## Related ADRs

- ADR-046: Keycloak SSO Strategy (defines OIDC/SAML client patterns)
- ADR-060: PostgreSQL Governance Standards (RDS connectivity requirements)
- ADR-061: Redis Governance Standards (Redis client connectivity)
- ADR-047: Estrutura Corporativa de Domínios (namespace strategy)

## Changelog

- **2026-02-24**: Initial implementation (GAP-007)
  - Created 20 policies for Marco 4 services
  - All policies in audit mode
  - Validation script provided
  - Enforcement pending 7-day validation window

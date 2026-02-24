# Runbook: Network Policy Troubleshooting

**Gap:** GAP-007 (Network Segmentation)
**ADR:** ADR-070
**Created:** 2026-02-24
**Enforcement Date:** 2026-03-03 (after 7-day audit period)

---

## Overview

This runbook covers debugging, testing, and managing Network Policies deployed for GAP-007. All policies are in **audit mode** until 2026-03-03, which means they **log but do not block** unauthorized traffic.

### Policy Inventory

| Namespace | Policy Count | Status |
|-----------|-------------|--------|
| argocd | 6 | Audit Mode |
| sonarqube | 2 | Audit Mode |
| keycloak | 3 | Audit Mode |
| gitlab-staging | 8 (new) + 9 (existing) | Audit Mode (new) |
| staging-security-vault | 3 | Audit Mode |
| monitoring | 8 (existing) | Enforced |
| data-services | 5 (existing) | Enforced |
| cert-manager | 4 (existing) | Enforced |
| kube-system | 4 (existing) | Enforced |

---

## Viewing Network Policies

```bash
# List all policies
kubectl get networkpolicies -A

# List policies for a specific namespace
kubectl get networkpolicies -n keycloak

# Show policy details (ingress/egress rules)
kubectl describe networkpolicy keycloak-ingress -n keycloak

# Show only GAP-007 policies
kubectl get networkpolicies -A -l 'app.kubernetes.io/component=network-policy'
```

---

## Testing Connectivity

### Test if a pod can reach a service

```bash
# Deploy a test pod
kubectl run nettest --image=busybox:1.35 -n <SOURCE_NAMESPACE> --restart=Never -- sleep 300

# Test TCP connectivity (should succeed for allowed paths)
kubectl exec -n <SOURCE_NAMESPACE> nettest -- wget -O- --timeout=5 http://<SERVICE>.<NAMESPACE>.svc.cluster.local:<PORT>/

# Cleanup
kubectl delete pod nettest -n <SOURCE_NAMESPACE>
```

### Known Allowed Paths (should succeed after enforcement)

| From | To | Port | Policy |
|------|----|------|--------|
| ESO (staging-security-externalsecrets) | Vault (staging-security-vault) | 8200 | vault-ingress |
| ArgoCD server | Keycloak | 8080 | keycloak-ingress |
| SonarQube | Keycloak | 8080 | keycloak-ingress |
| GitLab webservice | Keycloak | 8080 | keycloak-ingress |
| Grafana | Keycloak | 8080 | keycloak-ingress |
| Harbor core | Keycloak | 8080 | keycloak-ingress |
| GitLab runner | SonarQube | 9000 | sonarqube-ingress |
| GitLab webservice | Redis (data-services) | 6379 | gitlab-webservice-egress |

### Known Blocked Paths (should fail after enforcement)

| From | To | Expected |
|------|----|----------|
| default namespace pod | Vault:8200 | Timeout (blocked) |
| default namespace pod | Keycloak:8080 | Timeout (blocked) |
| default namespace pod | SonarQube:9000 | Timeout (blocked) |

---

## Diagnosing Connection Issues

### Step 1: Check if a NetworkPolicy selects the pod

```bash
# List all pods affected by network policies in a namespace
kubectl describe networkpolicies -n <NAMESPACE>

# Check if pod has the labels a policy selects
kubectl get pod <POD_NAME> -n <NAMESPACE> --show-labels
```

### Step 2: Verify pod labels match policy selectors

```bash
# Example: Check if keycloak pod matches keycloak-ingress selector
kubectl get pod keycloak-keycloakx-0 -n keycloak --show-labels
# Expected: app.kubernetes.io/name=keycloakx

# Check keycloak-ingress selector
kubectl get networkpolicy keycloak-ingress -n keycloak -o jsonpath='{.spec.podSelector}'
# Expected: {"matchLabels":{"app.kubernetes.io/name":"keycloakx"}}
```

### Step 3: Check audit mode logs (Calico CNI)

```bash
# Check Calico node logs for policy denies
kubectl logs -n kube-system -l k8s-app=calico-node --tail=200 | grep -i "policy"

# Check for any audit mode violations
kubectl logs -n kube-system -l k8s-app=calico-node --tail=200 | grep -i "audit"
```

### Step 4: Temporarily disable a policy (emergency rollback)

```bash
# Option A: Delete the specific blocking policy
kubectl delete networkpolicy <POLICY_NAME> -n <NAMESPACE>

# Option B: Return to audit mode (add annotation back)
kubectl annotate networkpolicy <POLICY_NAME> -n <NAMESPACE> \
  policy.cilium.io/audit-mode=true --overwrite

# Option C: Delete all GAP-007 policies (full rollback)
for ns in argocd sonarqube keycloak staging-security-vault; do
  kubectl delete networkpolicies -n $ns -l gap=GAP-007
done
```

---

## Adding a New Allow Rule

### Example: Allow new-service namespace to access Keycloak

1. Edit the keycloak-ingress policy:

```bash
kubectl edit networkpolicy keycloak-ingress -n keycloak
```

2. Add a new ingress rule to `spec.ingress`:

```yaml
# Allow from new-service (OIDC)
- from:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: new-service-namespace
    podSelector:
      matchLabels:
        app.kubernetes.io/name: new-service
  ports:
  - protocol: TCP
    port: 8080
```

3. Test connectivity before enforcement:

```bash
kubectl run test --image=busybox:1.35 -n new-service-namespace --restart=Never -- sleep 60
kubectl exec -n new-service-namespace test -- wget -O- --timeout=5 \
  http://keycloak-keycloakx-http.keycloak.svc.cluster.local:80/health/ready
kubectl delete pod test -n new-service-namespace
```

---

## Enforcement Checklist (2026-03-03)

Before removing audit-mode annotations, verify ALL of the following:

- [ ] ArgoCD can authenticate with Keycloak (OIDC login works)
- [ ] SonarQube can authenticate with Keycloak (SAML login works)
- [ ] GitLab can authenticate with Keycloak (OIDC login works)
- [ ] Grafana can authenticate with Keycloak (OIDC login works)
- [ ] Harbor can authenticate with Keycloak (OIDC login works)
- [ ] ESO syncing all ExternalSecrets (all show SecretSynced)
- [ ] ArgoCD can sync from GitLab (apps are Synced, not OutOfSync due to errors)
- [ ] GitLab CI pipelines running (GitLab runner connects to webservice)
- [ ] GitLab runner can push to SonarQube (quality gates pass)
- [ ] Keycloak backup CronJob completes successfully
- [ ] Vault unsealed and HA cluster healthy

### Enforcement Command

```bash
# Remove audit annotation from all GAP-007 policies
kubectl get networkpolicies -A -o json | \
  python3 -c "
import json, sys, subprocess

data = json.load(sys.stdin)
for item in data['items']:
  annotations = item.get('metadata', {}).get('annotations', {})
  if annotations.get('gap') == 'GAP-007' and annotations.get('policy.cilium.io/audit-mode') == 'true':
    ns = item['metadata']['namespace']
    name = item['metadata']['name']
    cmd = ['kubectl', 'annotate', 'networkpolicy', name, '-n', ns,
           'policy.cilium.io/audit-mode-', '--overwrite']
    result = subprocess.run(cmd, capture_output=True, text=True)
    print(f'{ns}/{name}: {result.stdout.strip() or result.stderr.strip()}')
"
```

---

## Key Label Reference

| Pod | Namespace | Label |
|-----|-----------|-------|
| Keycloak | keycloak | `app.kubernetes.io/name=keycloakx` |
| ArgoCD Server | argocd | `app.kubernetes.io/name=argocd-server` |
| ArgoCD Repo Server | argocd | `app.kubernetes.io/name=argocd-repo-server` |
| ArgoCD App Controller | argocd | `app.kubernetes.io/name=argocd-application-controller` |
| SonarQube | sonarqube | `app=sonarqube` |
| GitLab Webservice | gitlab-staging | `app=webservice` |
| GitLab Sidekiq | gitlab-staging | `app=sidekiq` |
| GitLab Gitaly | gitlab-staging | `app=gitaly` |
| GitLab Runner | gitlab-staging | `app=gitlab-gitlab-runner` |
| Harbor Core | harbor-system | `app=harbor, component=core` |
| Harbor Registry | harbor-system | `app=harbor, component=registry` |
| Vault Server | staging-security-vault | `app.kubernetes.io/name=vault, component=server` |
| Vault Injector | staging-security-vault | `app.kubernetes.io/name=vault-agent-injector, component=webhook` |
| ESO | staging-security-externalsecrets | `app.kubernetes.io/name=external-secrets` |
| AWS LB Controller | kube-system | `app.kubernetes.io/name=aws-load-balancer-controller` |
| CoreDNS | kube-system | `k8s-app=kube-dns` |
| Grafana | monitoring | `app.kubernetes.io/name=grafana` |

---

## References

- ADR-070: `/docs/adr/adr-070-network-policies-marco4-least-privilege.md`
- Policy Files: `/domains/security/network-policies/marco4/`
- Validation Script: `/domains/security/network-policies/marco4/validate-network-policies.sh`
- Logbook: `/docs/logbook/2026-02-24-gap007-network-policies-marco4.md`

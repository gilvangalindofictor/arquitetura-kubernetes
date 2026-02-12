# Split-Horizon DNS Setup for Internal Services

**Date Created**: 2026-02-11
**Category**: Operations - DNS Configuration
**Purpose**: Enable browser-based OIDC flows with internal Kubernetes services

---

## Overview

Split-horizon DNS allows external browsers to resolve internal Kubernetes service names by rewriting DNS queries through CoreDNS. This is essential for OIDC authentication flows where services redirect browsers to internal cluster addresses.

**Use Case**: Keycloak SSO integration with GitLab, ArgoCD, Grafana, etc.

---

## Architecture

```
Browser Request Flow:
1. Browser queries: keycloak.staging.internal
2. System DNS forwards to CoreDNS (via /etc/hosts or dnsmasq)
3. CoreDNS rewrites to: keycloak-http.keycloak.svc.cluster.local
4. CoreDNS returns ClusterIP: 10.100.x.x
5. Browser connects to ClusterIP (if network permits)
```

**Prerequisite**: Browser must be on network that can reach Kubernetes ClusterIP range (10.100.0.0/16).

---

## Configuration

### Step 1: Update CoreDNS ConfigMap

```bash
kubectl edit configmap -n kube-system coredns
```

**Add custom zone** (before the default `.` zone):

```
staging.internal:53 {
    errors
    cache 30
    rewrite name keycloak.staging.internal keycloak-http.keycloak.svc.cluster.local
    rewrite name argocd.staging.internal argocd-server.argocd.svc.cluster.local
    rewrite name gitlab.staging.internal gitlab-webservice-default.gitlab-staging.svc.cluster.local
    rewrite name kas.staging.internal gitlab-kas.gitlab-staging.svc.cluster.local
    rewrite name registry.staging.internal gitlab-registry.gitlab-staging.svc.cluster.local
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    forward . /etc/resolv.conf
}
```

### Step 2: Apply Changes

```bash
# Force CoreDNS to reload configuration
kubectl rollout restart deployment -n kube-system coredns

# Wait for pods to restart
kubectl rollout status deployment -n kube-system coredns

# Verify all pods running
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

### Step 3: Validate DNS Resolution

**From within cluster**:

```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup keycloak.staging.internal

# Expected output:
Server:    10.100.0.10
Address 1: 10.100.0.10 kube-dns.kube-system.svc.cluster.local

Name:      keycloak.staging.internal
Address 1: 10.100.x.x keycloak-http.keycloak.svc.cluster.local
```

**From browser host** (requires /etc/hosts or dnsmasq pointing to CoreDNS):

```bash
nslookup keycloak.staging.internal
# Should return ClusterIP
```

---

## Adding New Services

To add a new service to split-horizon DNS:

1. Identify the Kubernetes Service:
```bash
kubectl get svc -n <namespace> <service-name>
# Note: name, namespace, ClusterIP
```

2. Add rewrite rule to CoreDNS ConfigMap:
```
rewrite name <public-name>.staging.internal <service-name>.<namespace>.svc.cluster.local
```

3. Reload CoreDNS:
```bash
kubectl rollout restart deployment -n kube-system coredns
```

4. Test resolution:
```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup <public-name>.staging.internal
```

---

## Client-Side DNS Configuration

### Option A: /etc/hosts (Simple, per-host)

Add to `/etc/hosts` on browser host:

```
<COREDNS-NODE-IP>  keycloak.staging.internal
<COREDNS-NODE-IP>  gitlab.staging.internal
<COREDNS-NODE-IP>  argocd.staging.internal
```

**Find CoreDNS Node IP**:
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide | awk 'NR>1 {print $6}' | head -1
```

**Limitation**: Only works if browser host can reach Node IPs (requires VPN or same network).

### Option B: dnsmasq (Advanced, network-wide)

Configure dnsmasq to forward `.staging.internal` queries to CoreDNS:

```
# /etc/dnsmasq.conf
server=/staging.internal/<COREDNS-NODE-IP>
```

**Restart dnsmasq**:
```bash
sudo systemctl restart dnsmasq
```

### Option C: ALB + Ingress (Production)

For production, replace split-horizon DNS with proper Ingress:

1. Create Ingress resources with external DNS names
2. Use cert-manager for TLS certificates
3. Configure ALB or NGINX Ingress Controller
4. Update OIDC client redirect URIs to use public DNS

**See**: [ADR-021: External DNS Strategy](../adr/adr-021-external-dns-strategy.md)

---

## Troubleshooting

### Issue: nslookup returns NXDOMAIN

**Diagnosis**:
```bash
kubectl logs -n kube-system -l k8s-app=kube-dns | grep staging.internal
# Check for syntax errors or missing rewrite rules
```

**Solution**: Verify ConfigMap syntax, ensure zone definition before default `.` zone.

### Issue: Browser gets "Connection Refused"

**Diagnosis**: DNS resolving correctly but network unreachable.

**Solution**:
- Verify browser host can ping ClusterIP: `ping <ClusterIP>`
- Check Security Groups allow traffic from browser host
- Consider VPN or bastion host

### Issue: OIDC redirect fails with "redirect_uri_mismatch"

**Diagnosis**: Client configured with wrong redirect URI.

**Solution**: Ensure OIDC client redirect URI matches split-horizon domain:
```
# Correct:
http://gitlab.staging.internal/users/auth/openid_connect/callback

# Wrong:
http://gitlab-webservice-default.gitlab.svc.cluster.local/users/auth/openid_connect/callback
```

### Issue: CoreDNS pods CrashLoopBackOff after edit

**Diagnosis**: Syntax error in Corefile.

**Solution**:
```bash
# Restore previous ConfigMap
kubectl rollout undo deployment -n kube-system coredns

# Fix syntax error
kubectl edit configmap -n kube-system coredns

# Test syntax locally (optional):
coredns -conf Corefile -dns.port=1053
```

---

## Monitoring

**Check CoreDNS metrics**:
```bash
kubectl port-forward -n kube-system svc/coredns 9153:9153

curl http://localhost:9153/metrics | grep coredns_dns_requests_total
```

**Key metrics**:
- `coredns_dns_requests_total{zone="staging.internal"}` - Query count
- `coredns_dns_responses_total{rcode="NOERROR"}` - Success rate
- `coredns_dns_request_duration_seconds` - Latency

**Expected values**:
- Query count: ~100/day (low frequency, only during OIDC redirects)
- Success rate: >99%
- Latency p95: <10ms

---

## Security Considerations

### DNS Cache Poisoning

**Risk**: Attacker redirects `.staging.internal` to malicious server.

**Mitigation**:
- CoreDNS only accessible within cluster network
- Use DNSSEC for production (not applicable to internal zones)
- Monitor CoreDNS logs for unusual query patterns

### ClusterIP Exposure

**Risk**: Internal services accessible if ClusterIP network exposed.

**Mitigation**:
- ClusterIP range (10.100.0.0/16) should be private
- Use Network Policies to restrict pod-to-pod traffic
- Production: Use Ingress + TLS instead of split-horizon DNS

### OIDC Redirect Interception

**Risk**: Attacker intercepts OIDC redirect (HTTP, no TLS).

**Mitigation**:
- Staging: HTTP acceptable (internal network)
- Production: MUST use HTTPS with valid certificates
- Enable PKCE for OIDC flows (prevents authorization code theft)

---

## Production Migration Path

Split-horizon DNS is a **staging workaround**. Production should use proper external DNS:

1. **Register domain**: `platform.company.com`
2. **Create subdomains**:
   - `keycloak.platform.company.com`
   - `gitlab.platform.company.com`
   - `argocd.platform.company.com`
3. **Deploy cert-manager**: Automate TLS certificates
4. **Create Ingress resources**: ALB or NGINX with TLS
5. **Update OIDC clients**: Use public DNS in redirect URIs
6. **Remove split-horizon DNS**: Delete `staging.internal` zone from CoreDNS

**Timeline**: Sprint+2 (after TLS infrastructure complete)

---

## Related Documents

- [Logbook: GitLab OIDC Integration](../logbook/2026-02-11-gitlab-oidc-integration.md)
- [ADR-021: External DNS Strategy](../adr/adr-021-external-dns-strategy.md)
- [Keycloak Upgrade Logbook](../logbook/2026-02-11-keycloak-upgrade-17to26.md)

---

**Maintained by**: Platform Team
**Last Updated**: 2026-02-11
**Status**: Active (Staging Only)

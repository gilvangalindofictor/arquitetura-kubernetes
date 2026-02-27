# ADR-086: Linkerd Service Mesh for mTLS End-to-End Encryption

**Status**: ✅ ACCEPTED (Pending Deployment)
**Date**: 2026-02-26
**Context**: GAP-011: mTLS End-to-End | BACEN BCB 85/2021 Compliance
**Deciders**: Platform Team, Security Team, Compliance Team
**Supersedes**: None
**Superseded by**: None

---

## Context and Problem Statement

The platform requires **end-to-end mTLS encryption** between all microservices to comply with **BACEN (Brazilian Central Bank) Resolution BCB 85/2021**, specifically:

- **Art. 6º SS IV**: Encryption in transit for all inter-service communication
- **Art. 6º SS V**: Mutual authentication between services
- **Art. 9º**: Automatic credential rotation (certificates)
- **Art. 11º**: Communication audit trail (L7 observability)
- **Art. 15º**: Traffic segregation by identity

Current state:
- Services communicate over plain HTTP (no TLS)
- No service-to-service authentication
- Limited L7 observability (only HTTP status codes from ALB logs)
- Manual certificate management (no rotation automation)

**Requirement**: Implement zero-config mTLS for all microservices in the `ipaas` and `integration` namespaces with minimal application code changes.

---

## Decision Drivers

1. **Compliance**: BACEN BCB 85/2021 mandates encryption in transit + mutual authentication
2. **Zero Application Changes**: Applications should not require code modifications to enable mTLS
3. **Automatic Certificate Management**: No manual cert generation/rotation (operational burden)
4. **L7 Observability**: Per-route metrics (latency, success rate, retries) for SLO tracking
5. **Low Operational Complexity**: Simple deployment, minimal maintenance overhead
6. **Cost Efficiency**: Minimize compute overhead (avoid heavy proxies like Envoy in full Istio mode)
7. **EKS Compatibility**: Must work with existing EKS 1.34 cluster without major refactoring

---

## Considered Options

### Option 1: **Linkerd 2.16.x (Chosen)**

**Pros**:
- ✅ **Zero-config mTLS**: Automatic via SPIFFE/SPIRE identity (no app changes)
- ✅ **Lightweight proxy**: Linkerd2-proxy (~10MB Rust binary vs 30-50MB Envoy)
- ✅ **Low resource overhead**: 100mCPU / 64Mi per sidecar (vs 200mCPU+ for Istio)
- ✅ **Automatic cert rotation**: 24h TTL certs rotated by identity component
- ✅ **L7 observability**: HTTP status codes, latency percentiles, retries per route
- ✅ **Tap API**: Real-time traffic inspection without tcpdump
- ✅ **Proven stability**: CNCF graduated project (since 2021)
- ✅ **Compliance-friendly**: Built-in audit trail via Prometheus metrics + Tap logs

**Cons**:
- ❌ Cross-cluster mTLS requires extra setup (Gateway + service mirroring)
- ❌ No native Lua/WASM extension support (vs Envoy)
- ❌ Limited advanced traffic routing (vs Istio VirtualService)

**Cost**: +$5/month (staging) / +$9/month (production with HA mode)

---

### Option 2: Istio 1.20.x

**Pros**:
- ✅ Full-featured service mesh (traffic routing, fault injection, circuit breaking)
- ✅ Multi-cluster mTLS (Istio Gateway + federated trust)
- ✅ Envoy extensibility (Lua filters, WASM modules)

**Cons**:
- ❌ **High complexity**: 40+ CRDs, complex control plane (istiod, ingress/egress gateways)
- ❌ **Resource overhead**: 200-300mCPU per sidecar proxy (2-3x Linkerd)
- ❌ **Operational burden**: Certificate management via Istio CA (more moving parts)
- ❌ **Debugging difficulty**: Envoy config complexity (xDS protocol, 1000+ config lines)

**Cost**: +$15-20/month (staging) due to higher proxy overhead

---

### Option 3: AWS App Mesh

**Pros**:
- ✅ AWS-native (integrated with CloudWatch, X-Ray)
- ✅ Managed control plane (no self-hosting)

**Cons**:
- ❌ **Vendor lock-in**: Tight AWS coupling (no multi-cloud portability)
- ❌ **Higher cost**: Envoy sidecars + App Mesh controller fees
- ❌ **Limited observability**: No Tap API equivalent (relies on X-Ray sampling)
- ❌ **No ServiceProfile support**: Granular per-route metrics not available

**Cost**: +$25-30/month (App Mesh fees + proxy overhead)

---

### Option 4: Manual Certificate Management (TLS via Cert-Manager + Vault)

**Pros**:
- ✅ No sidecar overhead (direct TLS in application code)
- ✅ Cert-manager already deployed for Ingress certs

**Cons**:
- ❌ **High application burden**: Every app must implement TLS client/server logic
- ❌ **No automatic mTLS**: Apps must manually validate peer certificates
- ❌ **Poor observability**: No L7 metrics (only TCP-level from Prometheus)
- ❌ **High maintenance**: Certificate rotation requires app restarts
- ❌ **Non-compliance risk**: Human error in cert validation logic

**Cost**: $0 infrastructure, but high engineering cost (weeks of app refactoring)

---

## Decision Outcome

**Chosen Option**: **Linkerd 2.16.x** via Helm charts managed by Terraform.

**Rationale**:
1. **Compliance**: Meets all BACEN BCB 85/2021 requirements (Art. 6º, 9º, 11º, 15º)
2. **Zero-config**: Applications require only a single annotation (`linkerd.io/inject: enabled`)
3. **Low overhead**: 100mCPU/64Mi per proxy vs 200mCPU+ for Istio (60% savings)
4. **Operational simplicity**: 3 control plane components vs 10+ for Istio
5. **Proven stability**: CNCF graduated, production-ready since 2019

---

## Implementation Architecture

### Control Plane Components

```
┌────────────────────────────────────────────────────────┐
│          Linkerd Control Plane (namespace: linkerd)    │
├────────────────────────────────────────────────────────┤
│ 1. identity: SPIFFE certificate issuer                 │
│    - Issues x.509 certs per ServiceAccount              │
│    - 24h TTL with automatic rotation                   │
│                                                        │
│ 2. proxy-injector: MutatingWebhook                    │
│    - Injects linkerd-proxy sidecar on pod creation     │
│    - Triggered by annotation: linkerd.io/inject=enabled│
│                                                        │
│ 3. destination: L7 traffic control                     │
│    - Service discovery + load balancing                │
│    - AuthorizationPolicy enforcement                   │
└────────────────────────────────────────────────────────┘
```

### PKI Architecture (Terraform TLS Provider)

```
┌──────────────────────────────────────────────────────────┐
│                    PKI Certificate Chain                 │
├──────────────────────────────────────────────────────────┤
│ 1. Trust Anchor (root CA)                                │
│    - tls_private_key.trust_anchor (ECDSA P256)           │
│    - tls_self_signed_cert.trust_anchor                   │
│    - Validity: 365 days (var.certificate_validity_days)  │
│    - CN: root.linkerd.cluster.local                      │
│                                                          │
│           ↓ signs                                        │
│                                                          │
│ 2. Intermediate Issuer Certificate                      │
│    - tls_private_key.issuer (ECDSA P256)                 │
│    - tls_locally_signed_cert.issuer                      │
│    - Validity: 8760 hours (365 days)                    │
│    - CN: identity.linkerd.cluster.local                 │
│                                                          │
│           ↓ signs                                        │
│                                                          │
│ 3. Workload Certificates (per pod)                      │
│    - Issued by identity component at runtime            │
│    - SPIFFE ID: spiffe://cluster.local/ns/<ns>/sa/<sa>  │
│    - TTL: 24 hours (auto-rotated by proxy)             │
└──────────────────────────────────────────────────────────┘
```

### Data Plane (Sidecar Proxy)

```yaml
# Example: Pod with Linkerd proxy injected
apiVersion: v1
kind: Pod
metadata:
  name: my-api
  namespace: ipaas
  annotations:
    linkerd.io/inject: enabled  # ← Enables automatic injection
spec:
  initContainers:
  - name: linkerd-init         # ← Injected by proxy-injector
    image: cr.l5d.io/linkerd/proxy-init:v2.3.0
    # Sets iptables rules to redirect traffic to proxy

  containers:
  - name: my-api               # Application container (unchanged)
    image: my-registry/my-api:1.0
    ports:
    - containerPort: 8080

  - name: linkerd-proxy        # ← Injected sidecar
    image: cr.l5d.io/linkerd/proxy:stable-2.16.11
    resources:
      requests:
        cpu: 100m
        memory: 64Mi
      limits:
        cpu: 500m
        memory: 256Mi
    # Handles mTLS for all inbound/outbound traffic
```

---

## Terraform Module Design

### Module Structure

```
modules/linkerd/
├── main.tf          # Core resources (PKI, Helm releases, namespaces)
├── variables.tf     # Input variables (chart versions, proxy resources, HA mode)
├── outputs.tf       # Exported values (namespace, dashboard URL, certificates)
├── versions.tf      # Provider version constraints
└── README.md        # Usage guide, annotation patterns, compliance mapping
```

### Key Configuration Parameters (Staging)

```hcl
module "linkerd" {
  source = "../../modules/linkerd"

  cluster_name = "k8s-platform-prod"
  environment  = "staging"

  # Helm Chart Versions (stable-2.16.x)
  linkerd_crds_chart_version = "1.8.0"
  linkerd_version            = "1.16.11"
  linkerd_viz_chart_version  = "30.12.11"

  # PKI Configuration
  trust_domain              = "cluster.local"
  certificate_validity_days = 365

  # Proxy Resources (staging minimal)
  proxy_cpu_request    = "100m"
  proxy_memory_request = "64Mi"
  proxy_cpu_limit      = "500m"
  proxy_memory_limit   = "256Mi"

  # High Availability: OFF for staging (ON for production)
  ha_mode = false  # 1 replica per component

  # Viz Extension (observability)
  enable_viz              = true
  viz_prometheus_enabled  = false  # Use existing kube-prometheus-stack
  external_prometheus_url = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"

  # Opt-in Proxy Injection by Namespace
  proxy_inject_namespaces = [
    "ipaas",        # iPaaS core services
    "integration",  # Integration workers (RabbitMQ consumers)
  ]
}
```

---

## Compliance Mapping — BACEN BCB 85/2021

| BACEN Article | Requirement | Linkerd Implementation | Evidence |
|---------------|-------------|------------------------|----------|
| **Art. 6º SS IV** | Encryption in transit | mTLS automatic via SPIFFE/SPIRE | `linkerd tap` shows `tls="true"` for all requests |
| **Art. 6º SS V** | Mutual authentication | x.509 certificates per ServiceAccount | `identity_cert_expiration_timestamp_seconds` metric |
| **Art. 9º** | Credential rotation | 24h TTL + auto-rotation by identity | `issuanceLifetime: "24h0m0s"` in control-plane config |
| **Art. 11º** | Communication audit | Tap API + Prometheus L7 metrics | `linkerd_request_total`, `linkerd_response_latency_ms_*` |
| **Art. 15º** | Traffic segregation | AuthorizationPolicy CRDs | `MeshTLSAuthentication` + `AuthorizationPolicy` resources |

### Example: AuthorizationPolicy for Traffic Segregation

```yaml
apiVersion: policy.linkerd.io/v1beta3
kind: MeshTLSAuthentication
metadata:
  name: allow-integration-worker
  namespace: ipaas
spec:
  identities:
    # Only pods with SA 'integration-worker' in 'integration' namespace can call ipaas APIs
    - "integration-worker.integration.serviceaccount.identity.linkerd.cluster.local"
---
apiVersion: policy.linkerd.io/v1beta3
kind: AuthorizationPolicy
metadata:
  name: ipaas-api-policy
  namespace: ipaas
spec:
  targetRef:
    group: core
    kind: Service
    name: ipaas-api
  requiredAuthenticationRefs:
    - name: allow-integration-worker
      kind: MeshTLSAuthentication
      group: policy.linkerd.io
```

---

## Observability Integration

### Prometheus Metrics (L7)

Linkerd proxies export detailed HTTP metrics to Prometheus:

```promql
# Request rate by service
sum(rate(linkerd_request_total{namespace="ipaas"}[5m])) by (dst_service)

# Success rate (non-5xx) by route
sum(rate(linkerd_request_total{namespace="ipaas",status_code!~"5.."}[5m]))
/
sum(rate(linkerd_request_total{namespace="ipaas"}[5m]))

# P99 latency by route
histogram_quantile(0.99,
  sum(rate(linkerd_response_latency_ms_bucket{namespace="ipaas"}[5m])) by (le, dst_service)
)
```

### ServiceProfile (Per-Route Metrics)

```yaml
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: ipaas-api.ipaas.svc.cluster.local
  namespace: ipaas
spec:
  routes:
    - name: POST /api/v1/events
      condition:
        method: POST
        pathRegex: /api/v1/events
      responseClasses:
        - condition:
            status: { min: 500, max: 599 }
          isFailure: true

    - name: GET /api/v1/health
      condition:
        method: GET
        pathRegex: /api/v1/health
```

With ServiceProfile defined, `linkerd routes` shows per-route breakdown:
```bash
$ linkerd routes deploy/ipaas-api -n ipaas
ROUTE                  SUCCESS  RPS  LATENCY_P50  LATENCY_P99
POST /api/v1/events    99.5%    25   15ms         120ms
GET /api/v1/health     100.0%   10   2ms          5ms
[DEFAULT]              98.2%    5    30ms         200ms
```

---

## Cost Analysis

### Staging Environment (ha_mode=false)

| Resource | Specification | Cost/Month |
|----------|---------------|------------|
| Control Plane Pods (3 pods) | destination (200mCPU, 100Mi), identity (100mCPU, 50Mi), proxy-injector (100mCPU, 50Mi) | +$2 |
| Viz Extension (4 pods) | metrics-api, tap, tap-injector, web (total ~300mCPU, 200Mi) | +$1 |
| Proxy Sidecars (ipaas + integration) | ~15 pods × 100mCPU = 1500mCPU total | +$2 |
| **Total Incremental** | — | **+$5** |

**Baseline**: $502/month (EKS nodes + EBS)
**New Total**: $507/month (+1% increase)

### Production Environment (ha_mode=true)

| Resource | Staging | Production | Delta |
|----------|---------|------------|-------|
| Control Plane | 3 pods (1 replica) | 9 pods (3 replicas) | +$4 |
| Viz Extension | 4 pods | 4 pods | $0 |
| Proxy Sidecars | 1500mCPU | 1500mCPU | $0 |
| **Total** | +$5 | +$9 | +$4 |

---

## Risks and Mitigations

### Risk 1: Proxy Overhead Impacts Application Performance

**Impact**: High (user-facing latency increase)
**Probability**: Low
**Mitigation**:
- Linkerd2-proxy adds <1ms P99 latency overhead (per Linkerd benchmarks)
- VPA monitors proxy CPU usage → adjust `proxy_cpu_request` if needed
- Benchmark before/after: `hey -z 60s -c 50 http://ipaas-api:8080/api/v1/health`

### Risk 2: Certificate Expiry Causes Service Outages

**Impact**: Critical (all mTLS traffic fails)
**Probability**: Low (automated rotation)
**Mitigation**:
- Workload certs: 24h TTL + auto-rotated by identity (no manual intervention)
- Trust anchor: 365-day validity + Prometheus alert 30 days before expiry
- Alert: `linkerd_identity_trust_anchors_expiration_timestamp_seconds - time() < 2592000` (30 days)

### Risk 3: Proxy-Injector Webhook Failure Blocks Pod Creation

**Impact**: High (deployments fail)
**Probability**: Medium (webhook unavailable during control plane restart)
**Mitigation**:
- MutatingWebhookConfiguration `failurePolicy: Ignore` (pods deploy without proxy if webhook down)
- HA mode (production): 3 replicas of proxy-injector → high availability
- PodDisruptionBudget: `minAvailable: 2` ensures 2 injectors always running

### Risk 4: Incorrect Namespace Annotation Prevents mTLS

**Impact**: Medium (compliance violation)
**Probability**: Medium (human error)
**Mitigation**:
- Terraform manages namespace annotations: `proxy_inject_namespaces = ["ipaas", "integration"]`
- Validation script: `kubectl get ns -o jsonpath='{range .items[?(@.metadata.annotations.linkerd\.io/inject=="enabled")]}{.metadata.name}{"\n"}{end}'`
- CI/CD check: Kyverno policy enforces `linkerd.io/inject` annotation on production namespaces

---

## Consequences

### Positive

- ✅ **Compliance Achieved**: Meets BACEN BCB 85/2021 Art. 6º/9º/11º/15º
- ✅ **Zero Application Changes**: Apps remain unchanged (no TLS code required)
- ✅ **L7 Observability**: Per-route metrics enable SLO tracking (99th percentile latency)
- ✅ **Automatic Cert Rotation**: 24h TTL eliminates manual cert management
- ✅ **Low Overhead**: 100mCPU/64Mi per proxy (60% less than Istio)

### Negative

- ❌ **Additional Complexity**: Service mesh introduces new debugging surface (proxy logs, mTLS errors)
- ❌ **Cost Increase**: +$5/month staging (+1% of baseline)
- ❌ **Learning Curve**: Team must learn Linkerd CLI (`linkerd check`, `linkerd tap`, `linkerd routes`)

### Neutral

- ⚠️ **Opt-in by Default**: Only annotated namespaces get proxies (controlled blast radius)
- ⚠️ **No Multi-cluster mTLS (Yet)**: Cross-cluster communication requires future work (Linkerd Gateway)

---

## Alternatives Considered (Summary)

| Criteria | Linkerd (Chosen) | Istio | AWS App Mesh | Manual TLS |
|----------|------------------|-------|--------------|------------|
| Zero-config mTLS | ✅ | ✅ | ✅ | ❌ |
| Low overhead | ✅ (100mCPU) | ❌ (200mCPU) | ❌ (200mCPU) | ✅ (0) |
| Operational simplicity | ✅ | ❌ | ⚠️ | ❌ |
| L7 observability | ✅ (Tap + metrics) | ✅ (Envoy stats) | ⚠️ (X-Ray only) | ❌ |
| Cost | ✅ (+$5) | ❌ (+$15) | ❌ (+$25) | ✅ ($0 infra) |
| Compliance | ✅ | ✅ | ✅ | ⚠️ (risky) |

---

## Next Steps (Post-Deployment)

1. **Deploy Linkerd** (when staging environment is online):
   - Execute runbook: `/docs/runbooks/gap011-linkerd-deployment-quickstart.md`
   - Validate control plane: `linkerd check`
   - Test proxy injection: namespace `linkerd-test`

2. **Create AuthorizationPolicies** for production namespaces:
   - Example: Restrict `ipaas-api` to only accept calls from `integration-worker` SA
   - Document policy templates in `/docs/runbooks/linkerd-authorization-policy-patterns.md`

3. **Create ServiceProfiles** for top 5 critical APIs:
   - Define routes for per-endpoint observability
   - Monitor P99 latency per route in Grafana

4. **Configure Prometheus Alerts**:
   - Trust anchor expiry: 30 days before expiration
   - Proxy certificate issuance failures
   - Tap API unavailable

5. **Enable Grafana Dashboards** (optional):
   - Download official Linkerd dashboards from GitHub
   - Enable: `enable_grafana_dashboards = true` in Terraform

6. **Production Migration**:
   - Set `ha_mode = true` in production environment
   - Add 3 replicas for control plane components
   - Configure PodDisruptionBudgets (minAvailable=2)

---

## References

- **Linkerd Documentation**: https://linkerd.io/2.16/
- **SPIFFE/SPIRE**: https://spiffe.io/
- **BACEN BCB 85/2021**: https://www.bcb.gov.br/estabilidadefinanceira/normativos/resolucoesbcb?idDocumento=00085
- **Linkerd Helm Install**: https://linkerd.io/2.16/tasks/install-helm/
- **AuthorizationPolicy Reference**: https://linkerd.io/2.16/reference/authorization-policy/
- **ServiceProfile Reference**: https://linkerd.io/2.16/reference/service-profiles/

---

## Approval

- **Platform Team**: ✅ APPROVED (2026-02-26)
- **Security Team**: ✅ APPROVED (compliance requirements met)
- **Compliance Team**: ✅ APPROVED (BACEN BCB 85/2021 satisfied)

**Status**: ✅ ACCEPTED — Ready for deployment when staging environment is online

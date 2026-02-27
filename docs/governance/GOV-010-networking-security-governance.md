# GOV-010: Networking & Security Governance

> **Versão**: 1.0
> **Data**: 2026-02-27
> **Status**: Ativo
> **Referências**: ADR-006 (network), ADR-008 (TLS), ADR-070, Kyverno
> **Audiência**: Platform Team, SRE, Security Team

---

## Visão Geral

Governança de rede e segurança na plataforma Kubernetes, cobrindo NetworkPolicies (least-privilege), TLS/HTTPS, Kyverno policy enforcement e RBAC.

---

## Network Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    AWS VPC (10.0.0.0/16)                 │
│                                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │ Public      │  │ Private      │  │ Private (DB)   │  │
│  │ Subnets     │  │ Subnets      │  │ Subnets        │  │
│  │ (ALB/NAT)   │  │ (EKS Nodes)  │  │ (RDS/ElastiC)  │  │
│  └─────────────┘  └──────────────┘  └────────────────┘  │
│                                                          │
│  ┌──────────────────────────────────────────────────┐    │
│  │              EKS Cluster                         │    │
│  │  ┌─────────┐  ┌──────────┐  ┌───────────────┐   │    │
│  │  │ ingress │  │ app      │  │ data-services │   │    │
│  │  │ (ALB)   │──│ namespace│──│ (PostgreSQL,  │   │    │
│  │  │         │  │          │  │  Redis, RMQ)  │   │    │
│  │  └─────────┘  └──────────┘  └───────────────┘   │    │
│  └──────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

---

## NetworkPolicies (Least-Privilege)

**Referência**: [ADR-070: Network Policies Marco 4](../adr/adr-070-network-policies-marco4-least-privilege.md)

### Default Deny

Todo namespace DEVE ter default deny ingress/egress:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: {namespace}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

### Allow Patterns

```yaml
# Allow ingress from same namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: {namespace}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector: {}

---
# Allow egress to DNS (kube-system)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: {namespace}
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP

---
# Allow egress to data-services (PostgreSQL, Redis, RabbitMQ)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-data-services
  namespace: {namespace}
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: data-services
      ports:
        - port: 5432    # PostgreSQL
        - port: 6379    # Redis
        - port: 5672    # RabbitMQ AMQP
```

### Runbooks

- [Network Policies Enforcement](../runbooks/network-policies-enforcement.md)
- [Network Policy Troubleshooting](../runbooks/network-policy-troubleshooting.md)
- [Quick Reference](../runbooks/NETPOL-ENFORCEMENT-QUICKREF.md)

---

## TLS/HTTPS

**Referência**: [ADR-008: TLS Strategy for ALB Ingresses](../adr/adr-008-tls-strategy-for-alb-ingresses.md)

### TLS Termination

```yaml
# ALB Ingress com TLS
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {produto}-ingress
  namespace: {namespace}
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
spec:
  ingressClassName: alb
  rules:
    - host: {produto}.{domain}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: {produto}
                port:
                  number: 80
```

**Regras**:
- TLS termination no ALB (não no pod)
- HTTP → HTTPS redirect obrigatório
- Certificados via ACM (auto-renewal)
- Internal services: mTLS via service mesh (futuro)

---

## Kyverno Policy Enforcement

**Referência**: [Kyverno Policy Engine ADR](../../domains/security/docs/adr/adr-002-kyverno-policy-engine.md)

### Policies Ativas

| Policy | Tipo | Ação | Descrição |
|--------|------|------|-----------|
| `require-labels` | validate | enforce | Labels obrigatórias em todos os pods |
| `disallow-latest-tag` | validate | enforce | Bloqueia `:latest` image tag |
| `require-requests-limits` | validate | enforce | CPU/memory requests e limits obrigatórios |
| `disallow-privileged` | validate | enforce | Bloqueia containers privilegiados |
| `require-read-only-root` | validate | audit | readOnlyRootFilesystem recomendado |
| `restrict-host-network` | validate | enforce | Bloqueia hostNetwork/hostPID |

### Labels Obrigatórias (Kyverno)

```yaml
metadata:
  labels:
    app.kubernetes.io/name: "{produto}"          # Obrigatória
    app.kubernetes.io/part-of: "{system}"        # Obrigatória
    app.kubernetes.io/managed-by: "argocd"       # Obrigatória
    domain: "{domain}"                           # Obrigatória
    owner: "{domain}-team"                       # Obrigatória
```

---

## RBAC Kubernetes

**Referência**: [RBAC Matrix](./rbac-matrix.md)

### Roles por Tipo

| Role | Escopo | Permissões |
|------|--------|-----------|
| `cluster-admin` | Cluster | Full access (Platform Team only) |
| `namespace-admin` | Namespace | Full access ao namespace do domínio |
| `namespace-developer` | Namespace | Create/update pods, services, configmaps |
| `view-only` | Cluster | Read-only (troubleshooting cross-domain) |

### Service Account Naming

```yaml
Formato: {produto}-sa
Namespace: {env}-{domain}-{produto}

Exemplos:
✅ rpa-exemplo-sa
✅ ipaas-sa
```

---

## Security Checklist (por Aplicação)

| # | Item | Validação |
|---|------|-----------|
| 1 | NetworkPolicy default-deny aplicada | `kubectl get netpol -n {namespace}` |
| 2 | Ingress com TLS/HTTPS | Certificado ACM válido |
| 3 | Labels Kyverno compliant | `kubectl get pods -n {namespace} --show-labels` |
| 4 | Sem `:latest` tag | Kyverno enforce |
| 5 | Resource limits definidos | Kyverno enforce |
| 6 | Sem container privilegiado | Kyverno enforce |
| 7 | Secrets via Vault/ESO | GOV-006 |
| 8 | Security scans CI/CD passando | GOV-009 |
| 9 | RBAC least-privilege | ServiceAccount específico |
| 10 | readOnlyRootFilesystem | Recomendado (audit) |

---

## Proibições

```yaml
NUNCA:
  - Containers privilegiados
  - hostNetwork ou hostPID
  - :latest image tags
  - Pods sem resource limits
  - Ingress sem TLS
  - NetworkPolicy "allow all"
  - cluster-admin para aplicações

SEMPRE:
  - Default deny NetworkPolicy
  - TLS em todos os ingresses
  - Labels obrigatórias
  - Resource requests e limits
  - ServiceAccount dedicado por aplicação
```

---

## Referências

- [ADR-006: Network Policies Strategy](../adr/adr-006-network-policies-strategy.md)
- [ADR-008: TLS Strategy](../adr/adr-008-tls-strategy-for-alb-ingresses.md)
- [ADR-070: Network Policies Marco 4](../adr/adr-070-network-policies-marco4-least-privilege.md)
- [Kyverno Policy Engine](../../domains/security/docs/adr/adr-002-kyverno-policy-engine.md)
- [RBAC Matrix](./rbac-matrix.md)
- [Network Policies Index](../../domains/security/network-policies/marco4/INDEX.md)

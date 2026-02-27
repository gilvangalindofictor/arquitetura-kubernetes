# Linkerd Service Mesh — Terraform Module

**GAP-011** | mTLS End-to-End | BACEN BCB 85/2021 Compliance

## Overview

This module deploys [Linkerd 2.x](https://linkerd.io) via Helm on an existing EKS cluster. It provides:

- **mTLS automatic** entre todos os pods injetados (zero-config por aplicacao)
- **SPIFFE/SPIRE identity** baseada em ServiceAccount (sem segredos manuais)
- **Observabilidade L7** — HTTP status codes, latency percentiles, retries por rota
- **Tap API** — inspecao de trafego em tempo real sem tcpdump
- **Integracao Prometheus + Grafana** via kube-prometheus-stack existente

## Arquitetura

```
┌────────────────────────────────────────────────────────────┐
│                   Linkerd Control Plane                    │
│  namespace: linkerd                                        │
│                                                            │
│  ┌──────────┐  ┌──────────────┐  ┌──────────────────────┐ │
│  │ identity │  │proxy-injector│  │ destination (L7 cfg) │ │
│  └──────────┘  └──────────────┘  └──────────────────────┘ │
│                                                            │
│  PKI (Terraform tls provider):                             │
│    Trust Anchor (root CA)  ──signs──>  Issuer Cert         │
│    Issuer  ──signs──>  Per-workload mTLS cert (24h TTL)    │
└────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│               Linkerd Viz Extension                         │
│  namespace: linkerd-viz                                     │
│                                                             │
│  Dashboard  │  Tap API  │  Metrics API  │  Prometheus scrape│
└─────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│           Data Plane (per pod, opt-in)                       │
│                                                              │
│  [Pod] <──linkerd-proxy sidecar──> [Pod]                     │
│         mTLS (SPIFFE cert)                                   │
└──────────────────────────────────────────────────────────────┘
```

## Pre-requisitos

| Requisito | Versao minima |
|---|---|
| Terraform | >= 1.5 |
| EKS Cluster | >= 1.27 |
| kube-prometheus-stack | >= 55.x (para integracao Grafana) |
| helm provider | ~> 2.12 |
| kubernetes provider | ~> 2.20 |
| tls provider | ~> 4.0 |

## Uso

```hcl
module "linkerd" {
  source = "../../modules/linkerd"

  cluster_name = "k8s-platform-prod"
  environment  = "staging"
  common_tags  = local.common_tags

  # Versoes (stable-2.16.x)
  linkerd_crds_chart_version   = "1.8.0"
  linkerd_version              = "1.16.11"
  linkerd_viz_chart_version    = "30.12.11"

  # PKI
  trust_domain              = "cluster.local"
  certificate_validity_days = 365

  # Proxy resources
  proxy_cpu_request    = "100m"
  proxy_memory_request = "64Mi"
  proxy_cpu_limit      = "500m"
  proxy_memory_limit   = "256Mi"

  # HA (false para staging, true para production)
  ha_mode = false

  # Viz — usa Prometheus externo (kube-prometheus-stack)
  enable_viz              = true
  viz_prometheus_enabled  = false
  external_prometheus_url = "http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"

  # Jaeger/Tracing (desabilitado por padrao)
  enable_jaeger = false

  # Namespaces com inject automatico (opt-in por namespace)
  proxy_inject_namespaces = [
    "ipaas",
    "integration",
  ]
}
```

## Habilitando mTLS em Aplicacoes — Annotation Guide

### Metodo 1: Inject por Deployment (mais granular — recomendado)

Adicione a annotation ao `spec.template.metadata` do Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minha-api
  namespace: ipaas
spec:
  template:
    metadata:
      annotations:
        linkerd.io/inject: enabled          # <- habilita proxy sidecar
    spec:
      containers:
        - name: minha-api
          image: my-registry/minha-api:1.0
```

### Metodo 2: Inject por Namespace (todos os pods do namespace)

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ipaas
  annotations:
    linkerd.io/inject: enabled              # <- todos os pods recebem proxy
```

Ou via Terraform (modulo gerencia isso via `proxy_inject_namespaces`):

```hcl
proxy_inject_namespaces = ["ipaas", "integration"]
```

### Metodo 3: Opt-out individual (namespace injetado, pod excluido)

```yaml
spec:
  template:
    metadata:
      annotations:
        linkerd.io/inject: disabled         # <- este pod NAO recebe proxy
```

### Verificando se mTLS esta ativo

```bash
# Verificar se proxy esta injetado no pod
kubectl get pod <pod-name> -n ipaas -o jsonpath='{.spec.initContainers[*].name}'
# Esperado: linkerd-init

# Verificar identidade mTLS do pod
kubectl exec -n ipaas <pod-name> -c linkerd-proxy -- \
  wget -qO- localhost:4191/metrics | grep identity

# Tap: ver trafego mTLS em tempo real
linkerd tap deploy/minha-api -n ipaas

# Top: metricas L7 ao vivo
linkerd top deploy/minha-api -n ipaas
```

## Authorization Policies (identity-based)

Apos habilitar mTLS, voce pode restringir qual ServiceAccount pode chamar qual servico:

```yaml
apiVersion: policy.linkerd.io/v1beta3
kind: MeshTLSAuthentication
metadata:
  name: allow-ipaas-caller
  namespace: ipaas
spec:
  identities:
    # Permite apenas pods com SA 'integration-worker' no namespace 'integration'
    - "integration-worker.integration.serviceaccount.identity.linkerd.cluster.local"
---
apiVersion: policy.linkerd.io/v1beta3
kind: AuthorizationPolicy
metadata:
  name: minha-api-policy
  namespace: ipaas
spec:
  targetRef:
    group: core
    kind: Service
    name: minha-api
  requiredAuthenticationRefs:
    - name: allow-ipaas-caller
      kind: MeshTLSAuthentication
      group: policy.linkerd.io
```

## ServiceProfile — Observabilidade por Rota

```yaml
apiVersion: linkerd.io/v1alpha2
kind: ServiceProfile
metadata:
  name: minha-api.ipaas.svc.cluster.local
  namespace: ipaas
spec:
  routes:
    - name: POST /api/v1/eventos
      condition:
        method: POST
        pathRegex: /api/v1/eventos
      responseClasses:
        - condition:
            status:
              min: 500
              max: 599
          isFailure: true
    - name: GET /api/v1/health
      condition:
        method: GET
        pathRegex: /api/v1/health
```

Com ServiceProfile definido, `linkerd top` e `linkerd routes` mostram breakdown por rota.

## Dashboard

```bash
# Abrir dashboard Linkerd (requer linkerd CLI instalado)
linkerd viz dashboard

# Ou via port-forward manual
kubectl port-forward -n linkerd-viz svc/web 8084:8084
# Acesse: http://localhost:8084
```

## Integracao Grafana

Os dashboards oficiais do Linkerd devem ser baixados e adicionados ao diretorio
`modules/linkerd/dashboards/` antes de habilitar `enable_grafana_dashboards=true`:

```bash
LINKERD_VERSION="stable-2.16.0"
DEST="modules/linkerd/dashboards"
mkdir -p "$DEST"

for dashboard in top-line service-mesh deployment namespace; do
  curl -sL "https://raw.githubusercontent.com/linkerd/linkerd2/${LINKERD_VERSION}/grafana/dashboards/${dashboard}.json" \
    -o "${DEST}/linkerd-${dashboard}.json"
done
```

Depois habilite no modulo:

```hcl
enable_grafana_dashboards = true
```

## Compliance BACEN BCB 85/2021

| Controle | Implementacao |
|---|---|
| Criptografia em transito (Art. 6 SS IV) | mTLS automatico via SPIFFE/SPIRE |
| Autenticacao mutua | Certificados x.509 por ServiceAccount |
| Rotacao de certificados | 24h TTL com rotacao automatica pelo identity |
| Auditoria de comunicacoes | Tap API + metricas L7 por Prometheus |
| Segregacao de trafego | AuthorizationPolicy por identidade |

## Outputs Disponiveis

| Output | Descricao |
|---|---|
| `linkerd_namespace` | Namespace do control plane |
| `linkerd_viz_url` | URL interna do dashboard |
| `linkerd_tap_api_url` | URL interna do Tap API |
| `linkerd_proxy_injector_webhook_url` | URL do MutatingWebhook |
| `trust_anchor_certificate` | Certificado raiz PEM (SENSITIVE) |
| `trust_anchor_certificate_expiry` | Validade em horas do trust anchor |
| `issuer_certificate` | Certificado issuer PEM (SENSITIVE) |
| `proxy_injected_namespaces` | Namespaces com inject automatico |

## Rotacao de Certificados

O trust anchor tem validade configuravel (padrao 365 dias). Para rotacionar:

1. Gere novo trust anchor: `terraform taint module.linkerd.tls_private_key.trust_anchor`
2. Execute `terraform plan` para revisar impacto
3. Execute `terraform apply` (provoca restart do control plane)
4. Verifique: `linkerd check`

Certificados de workload (24h TTL) sao rotacionados automaticamente pelo identity component — nao requerem intervencao manual.

## Referencias

- Linkerd Helm Install: https://linkerd.io/2.16/tasks/install-helm/
- SPIFFE/SPIRE: https://spiffe.io/
- BCB 85/2021: https://www.bcb.gov.br/estabilidadefinanceira/normativos/resolucoesbcb?idDocumento=00085
- Linkerd mTLS: https://linkerd.io/2.16/features/automatic-mtls/
- AuthorizationPolicy: https://linkerd.io/2.16/reference/authorization-policy/

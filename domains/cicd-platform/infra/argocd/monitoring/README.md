# ArgoCD Monitoring — ServiceMonitors

Prometheus Operator ServiceMonitors para coleta de métricas do ArgoCD.

## Arquivos

| Arquivo | Ambiente | Namespace | Status |
| --- | --- | --- | --- |
| `servicemonitor-argocd.yaml` | staging | `staging-platform-argocd` | ✅ Ativo |
| `servicemonitor-argocd-prod.yaml` | prod | `prod-platform-argocd` | ⏳ Aguardando provisionamento (ADR-105) |

## ServiceMonitors por ambiente

### Staging (ativo)

| Nome | Selector | Porta | Interval |
| --- | --- | --- | --- |
| `argocd-server-metrics` | `argocd-server` | 8083 | 30s |
| `argocd-repo-server-metrics` | `argocd-repo-server` | 8084 | 30s |
| `argocd-application-controller-metrics` | `argocd-application-controller` | 8082 | 30s |

### Prod (pré-provisionado)

| Nome | Selector | Porta | Interval |
| --- | --- | --- | --- |
| `argocd-server-metrics-prod` | `argocd-server` | 8083 | 30s |
| `argocd-repo-server-metrics-prod` | `argocd-repo-server` | 8084 | 30s |
| `argocd-application-controller-metrics-prod` | `argocd-application-controller` | 8082 | 30s |

## Ações ao provisionar prod-platform-argocd

```bash
# 1. Aplicar ServiceMonitors prod
kubectl apply -f servicemonitor-argocd-prod.yaml

# 2. Verificar targets no Prometheus
# Navegue em: Prometheus → Status → Targets → filtrar "argocd-*-prod"
# Todos devem aparecer como UP

# 3. Marcar GAP-SEC-04b como RESOLVIDO no demand doc
```

## Referências

- ADR-105: ArgoCD multi-environment model (OPÇÃO A, 4-0)
- GAP-SEC-04: ServiceMonitors staging (resolvido 2026-03-12)
- GAP-SEC-04b: ServiceMonitors prod (pré-provisionado 2026-03-12)

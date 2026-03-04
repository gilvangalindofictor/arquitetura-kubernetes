# GAP-011: Linkerd ServiceProfiles — Guia de Uso

**Compliance**: BACEN BCB 85/2021 Art. 11 (auditoria de comunicacoes — rastreabilidade por rota)
**Versao Linkerd**: 2.16.x
**API Version**: `linkerd.io/v1alpha2`

---

## O que sao ServiceProfiles

ServiceProfiles permitem ao Linkerd entender a estrutura de routes de uma API HTTP,
fornecendo metricas **por rota** em vez de apenas por servico.

Sem ServiceProfile:
```
GET /v1/* + POST /v1/* + DELETE /v1/* → metrica unica: "service.namespace/[DEFAULT]"
```

Com ServiceProfile:
```
GET  /v1/health       → metrica: "GET /v1/health"       (SUCCESS 100%, P99 2ms)
POST /api/token       → metrica: "POST /api/token"       (SUCCESS 99.5%, P99 45ms)
GET  /v2/{name}/manifests/{tag} → metrica especifica     (SUCCESS 99.9%, P99 10ms)
```

---

## Beneficios para BACEN BCB 85/2021

| Artigo | Beneficio |
|--------|-----------|
| Art. 11 SS II — Rastreabilidade | Metricas por endpoint: quantas chamadas, taxa de erro, latencia P99 |
| Art. 11 SS III — Auditoria | `linkerd routes` mostra historico de acesso por rota |
| Art. 6 SS IV — Seguranca | Identificar endpoints com alta taxa de erro (possivel ataque) |

---

## Convencao de Nomenclatura

O nome do ServiceProfile DEVE ser o FQDN do service no formato:
```
<service-name>.<namespace>.svc.cluster.local
```

Exemplos:
- `keycloak.staging-platform.svc.cluster.local` (namespace: staging-platform)
- `harbor-core.staging-data-services.svc.cluster.local` (namespace: staging-data-services)
- `argocd-server.staging-platform.svc.cluster.local` (namespace: staging-platform)
- `gitlab-webservice-default.gitlab-staging.svc.cluster.local` (namespace: gitlab-staging)

O namespace do ServiceProfile DEVE ser o mesmo do servico chamador (cliente),
nao do servidor. Isso permite que o Linkerd associe a metrica ao lado correto.

---

## Como Aplicar

```bash
# Aplicar todos os ServiceProfiles
kubectl apply -f domains/service-mesh/infra/linkerd/service-profiles/

# Verificar ServiceProfiles criados
kubectl get serviceprofiles -A

# Ver metricas por rota (requer linkerd CLI + proxy injection ativa)
linkerd routes deploy/keycloak -n staging-platform
linkerd routes deploy/harbor-core -n staging-data-services
linkerd routes deploy/argocd-server -n staging-platform
linkerd routes deploy/gitlab-webservice-default -n gitlab-staging
```

---

## Exemplo de Output pos-ServiceProfile

```bash
$ linkerd routes deploy/argocd-server -n staging-platform
ROUTE                                  SUCCESS   RPS   LATENCY_P50   LATENCY_P99
GET /api/v1/applications               99.8%     12    8ms           45ms
POST /api/v1/applications/{name}/sync  98.5%     2     180ms         850ms
GET /api/v1/clusters                   100.0%    1     3ms           12ms
[DEFAULT]                              97.2%     0.5   25ms          200ms
```

---

## Campos Importantes

### `isRetryable`
- `true`: Linkerd pode retentar automaticamente em falha (GET, HEAD)
- `false`: NAO retentar (POST, PUT, DELETE — operacoes nao idempotentes)

### `timeout`
- Tempo maximo para aguardar resposta do servidor
- Recomendacao: usar P99 historico * 3 como timeout inicial
- Requests que excedem o timeout retornam `504 Gateway Timeout`

### `responseClasses`
- Define quais status HTTP sao considerados "falha" para metricas
- Padrao: 5xx = falha, outros = sucesso
- Customizavel: e.g., 404 pode ser falha em alguns casos de negocio

---

## Referencias

- [ServiceProfile Reference](https://linkerd.io/2.16/reference/service-profiles/)
- [Per-Route Metrics](https://linkerd.io/2.16/tasks/setting-up-service-profiles/)
- [Retries and Timeouts](https://linkerd.io/2.16/features/retries-and-timeouts/)

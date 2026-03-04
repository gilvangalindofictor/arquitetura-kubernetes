# GAP-011: Linkerd Proxy Injection — Estrategia de Rollout por Fases

**Status**: Pronto para execucao (Linkerd control plane Running 7/7 pods)
**Compliance**: BACEN BCB 85/2021 Art. 6 SS IV/V (criptografia em transito + autenticacao mutual)
**Ultima atualizacao**: 2026-03-04

---

## Visao Geral

A habilitacao do proxy injection segue estrategia **opt-in gradual** para minimizar blast radius.
O principio e: habilitar por namespace, monitorar por 24h, antes de prosseguir para o proximo.

```
FASE 1                FASE 2                      FASE 3
(Dia 1)               (Dia 2-3)                   (Dia 4)
   |                     |                            |
staging-platform    staging-data-services     staging-observability
  - Keycloak          - Redis                   - Prometheus
  - Vault             - RabbitMQ                - Grafana
  - ArgoCD            - Harbor                  - Loki / Tempo
                      - gitlab-staging
```

---

## Fase 1: staging-platform

**Namespaces**: `staging-platform`
**Workloads**: Keycloak (SSO), Vault (secrets), ArgoCD (GitOps)
**Risco**: Baixo — workloads HTTP com latencia nao-critica para usuarios finais
**Duracao estimada**: 30 min (inject) + 24h (monitoramento)

### Comandos de execucao

```bash
# Habilitar proxy injection
./annotate-namespaces.sh --phase 1

# Verificar pods reiniciados com proxy
kubectl get pods -n staging-platform -o wide
# Esperado: cada pod tem 2+ containers (app + linkerd-proxy)

# Verificar mTLS ativo
kubectl get pods -n staging-platform \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}' \
  | grep linkerd-proxy

# Via Linkerd CLI (se disponivel)
linkerd viz stat deploy -n staging-platform
linkerd viz edges deploy -n staging-platform
```

### Criterios de sucesso Fase 1

- [ ] 100% dos pods com `linkerd-proxy` na lista de containers
- [ ] `linkerd viz stat` mostra coluna TLS com certificados validos
- [ ] Keycloak UI acessivel e funcionando (login SSO operacional)
- [ ] Vault health check OK: `vault status -address=http://vault.staging-platform.svc:8200`
- [ ] ArgoCD sincronizando aplicacoes normalmente
- [ ] Latencia P99 < 10ms de incremento vs baseline

### Monitoramento pos-Fase 1 (24h)

```bash
# Dashboard Grafana: Linkerd Namespace (staging-platform)
# URL: http://grafana.staging-observability-monitoring.svc/d/linkerd-namespace

# Verificar taxa de sucesso
# PromQL: sum(rate(linkerd_response_total{namespace="staging-platform",status_code!~"5.."}[5m]))
#       / sum(rate(linkerd_response_total{namespace="staging-platform"}[5m]))

# Verificar latencia P99
# PromQL: histogram_quantile(0.99,
#   sum(rate(linkerd_response_latency_ms_bucket{namespace="staging-platform"}[5m])) by (le))
```

---

## Fase 2: staging-data-services + gitlab-staging

**Namespaces**: `staging-data-services`, `gitlab-staging`
**Workloads**: Redis, RabbitMQ, Harbor, GitLab 18.9.1 (11 pods)
**Risco**: Medio — services de dados com protocolo TCP + GitLab multi-pod
**Pre-condicao**: Fase 1 estavel por 24h

### Notas tecnicas

**Redis/PostgreSQL (TCP opaco)**: O Linkerd proxy encapsula o trafego TCP com mTLS transparente.
O protocolo RESP2/3 (Redis) e wire protocol (PostgreSQL) nao sao afetados.
Verificar: `linkerd viz stat deploy/redis -n staging-data-services` deve mostrar TCP traffic.

**RabbitMQ**: AMQP sobre TCP — mesmo comportamento. Verificar filas funcionando apos restart.

**Harbor**: Registros OCI — verificar push/pull de imagens apos inject.

**GitLab**: 11 pods reiniciados em sequencia (maxUnavailable=1 do Helm chart).
Smoke test obrigatorio: acessar UI + CI/CD funcionando.

### Comandos de execucao

```bash
# Pre-check: Fase 1 estavel
./annotate-namespaces.sh --status

# Habilitar Fase 2
./annotate-namespaces.sh --phase 2

# Smoke test GitLab pos-inject
curl -sk https://<gitlab-ingress>/users/sign_in | grep -c "GitLab"

# Smoke test Harbor pos-inject
curl -sk https://<harbor-ingress>/api/v2.0/health | jq '.status'

# Verificar RabbitMQ filas
kubectl exec -n staging-data-services statefulset/rabbitmq -- \
  rabbitmq-diagnostics status 2>/dev/null | grep "Status"
```

### Criterios de sucesso Fase 2

- [ ] Redis acessivel: `redis-cli -h redis.staging-data-services.svc ping` retorna PONG
- [ ] RabbitMQ management UI acessivel, filas operacionais
- [ ] Harbor: push/pull de imagem funcionando
- [ ] GitLab UI acessivel (login + repositorios)
- [ ] GitLab CI/CD: pipeline de teste executa sem erro
- [ ] `linkerd viz stat` mostra trafego mTLS em todos os services

---

## Fase 3: staging-observability-monitoring

**Namespaces**: `staging-observability-monitoring`
**Workloads**: Prometheus, Grafana, Loki, Tempo, AlertManager, OpenTelemetry Collector
**Risco**: Baixo — pilha de observabilidade e separada dos servicos de negocio
**Pre-condicao**: Fases 1 e 2 estaveis

### Consideracao especial: Prometheus scrape de proxies Linkerd

Com o namespace de monitoring injetado, o Prometheus passa a ter proxy Linkerd.
Os endpoints `/metrics` dos proxies Linkerd estao em `:4191`.
Adicionar scrape config ao kube-prometheus-stack values:

```yaml
# domains/observability/infra/helm/kube-prometheus-stack/values.yaml (adicionar)
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: 'linkerd-proxy-metrics'
        kubernetes_sd_configs:
          - role: pod
        relabel_configs:
          - source_labels: [__meta_kubernetes_pod_container_name]
            action: keep
            regex: linkerd-proxy
          - source_labels: [__address__]
            action: replace
            regex: ([^:]+)(?::\d+)?
            replacement: $1:4191
            target_label: __address__
        metrics_path: /metrics
        scheme: http
```

### Comandos de execucao

```bash
# Habilitar Fase 3
./annotate-namespaces.sh --phase 3

# Verificar Prometheus operacional
kubectl get pods -n staging-observability-monitoring | grep prometheus

# Verificar Grafana acessivel
kubectl port-forward svc/kube-prometheus-stack-grafana -n staging-observability-monitoring 3000:80 &
curl http://localhost:3000/api/health

# Verificar coleta de metricas Linkerd no Prometheus
# PromQL: up{job="linkerd-proxy-metrics"}
```

### Criterios de sucesso Fase 3

- [ ] Prometheus UP e coletando metricas de todos os namespaces
- [ ] Grafana dashboards Linkerd exibindo dados (4 dashboards: top-line, namespace, service-mesh, deployment)
- [ ] Alertas Prometheus funcionando (AlertManager recebendo alertas)
- [ ] Loki coletando logs (incluindo logs de acesso dos proxies Linkerd)

---

## Verificacao Global de mTLS

### Via kubectl (sem Linkerd CLI)

```bash
# Verificar quais pods tem proxy injetado (todos os namespaces)
kubectl get pods -A \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}' \
  | grep linkerd-proxy | sort

# Verificar annotations nos namespaces
for ns in staging-platform staging-data-services gitlab-staging staging-observability-monitoring; do
  echo -n "$ns: "
  kubectl get ns "$ns" -o jsonpath='{.metadata.annotations.linkerd\.io/inject}' 2>/dev/null || echo "not found"
done
```

### Via Linkerd CLI (se disponivel)

```bash
# Status global do control plane
linkerd check

# mTLS por namespace
linkerd viz stat ns

# Edges (conexoes mTLS ativas) por namespace
linkerd viz edges deploy -n staging-platform

# Top traffic (tempo real)
linkerd viz top deploy -n staging-platform

# Tap (inspecao L7 tempo real)
linkerd viz tap deploy/keycloak -n staging-platform --to deploy/argocd-server
```

---

## Procedimento de Rollback

### Rollback de namespace especifico

```bash
# Remover annotation de proxy injection
./annotate-namespaces.sh --rollback staging-platform

# Verificar que proxies foram removidos (apos restart)
kubectl get pods -n staging-platform \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].name}{"\n"}{end}' \
  | grep -v linkerd-proxy
```

### Rollback de emergencia (todos os namespaces)

```bash
for ns in staging-platform staging-data-services gitlab-staging staging-observability-monitoring; do
  kubectl annotate namespace "$ns" linkerd.io/inject- --overwrite 2>/dev/null || true
  kubectl rollout restart deployment -n "$ns" 2>/dev/null || true
  kubectl rollout restart statefulset -n "$ns" 2>/dev/null || true
  echo "Rollback iniciado para: $ns"
done
```

---

## Links de Referencia

- ADR: `/docs/adr/adr-086-linkerd-service-mesh-mtls.md`
- Runbook original: `/docs/runbooks/gap011-linkerd-deployment-quickstart.md`
- Authorization Policies: `../authorization-policies/`
- Service Profiles: `../service-profiles/`
- Validacao mTLS: `/scripts/linkerd/validate-mtls.sh`

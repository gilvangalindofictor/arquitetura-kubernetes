# Guia Prático: Testando Correlação Traces ↔ Logs ↔ Metrics

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-02-10                               |
| **Versão**     | 1.0                                      |
| **Status**     | 🟢 Guia operacional para validação      |

---

## Visão Geral

Este guia fornece procedimentos práticos para testar e validar a correlação entre traces, logs e métricas na stack de observabilidade do cluster Kubernetes.

**Stack de Observabilidade:**
- **Prometheus** - Métricas (scraping via ServiceMonitors)
- **Loki** - Logs (agregação via Promtail/Fluentd)
- **Tempo** - Traces distribuídos (ingestão via OTLP 4317/4318)
- **Grafana** - Visualização unificada
- **OpenTelemetry Collector** - Pipeline de telemetria

---

## 🔍 Investigação: Por Que a API Search Retorna Vazio?

### Análise Técnica

**Configuração de Storage do Tempo:**

```yaml
storage:
  trace:
    backend: s3
    bucket: k8s-platform-tempo-891377105802
    region: us-east-1
    local:
      path: /var/tempo/traces  # WAL local
    wal:
      path: /var/tempo/wal
    search:
      prefetch_trace_count: 1000
```

**Compactor Configuration:**

```yaml
compactor:
  compaction:
    block_retention: 48h              # Traces retidos por 48h
    compaction_window: 1h             # Janela de compactação
    compaction_cycle: 30s             # Ciclo de compactação
    max_block_bytes: 107374182400
```

### Por Que a API Search Retorna `{"traces": []}`?

**Razão 1: Delay de Indexação**
- Traces recentes (< 1 hora) estão no **ingester WAL** (memória + disco local)
- **API de search** só consulta traces já **compactados no S3**
- Compaction window de **1 hora** significa que traces são flushed para S3 apenas após 1h+

**Razão 2: Arquitetura do Tempo**

```
┌─────────────────────────────────────────────────────────┐
│                    Tempo Architecture                    │
└─────────────────────────────────────────────────────────┘

  Traces (OTLP) → Distributor → Ingester (WAL)
                                    ↓
                              [Wait 1h+]
                                    ↓
                     Compactor → S3 Blocks (indexed)
                                    ↓
                           Querier → Search API
```

**Implicações:**
- ✅ Traces **são recebidos** (HTTP 200 OK do distributor)
- ✅ Traces **são armazenados** (WAL do ingester + flush para S3)
- ⚠️ Traces **não aparecem na search API** até serem compactados (1h+ delay)
- ✅ Traces **podem ser consultados por trace ID** diretamente (mesmo antes de indexação)

**Solução:**
- Para traces recentes (< 1h): usar **query por trace ID** (se conhecido)
- Para search geral: aguardar compaction (produção: considerar config de `complete_block_timeout`)

---

## ✅ Teste 1: Correlação Trace ID → Logs (Via kubectl)

### Procedimento

**Passo 1: Obter Trace ID Recente**

```bash
# Obter trace ID dos logs do trace generator
TRACE_ID=$(kubectl logs -n otel-test -l app=trace-generator --tail=20 \
  | grep -o "traceId: [a-f0-9]*" | head -1 | cut -d' ' -f2)

echo "Trace ID: $TRACE_ID"
# Output: Trace ID: 35ef4d47d11c0c26
```

**Passo 2: Verificar Trace ID nos Logs**

```bash
# Buscar logs contendo este trace ID
kubectl logs -n otel-test -l app=trace-generator --tail=50 | grep "$TRACE_ID"

# Output esperado:
# [21:19:06] Sending trace: operation-fetch-orders-1869 (traceId: 35ef4d47d11c0c26...)
# {"partialSuccess":{}}
# HTTP Status: 200
```

**Resultado:** ✅ **PASS** - Trace ID presente nos logs, correlação possível

---

## ✅ Teste 2: Correlação Trace ID → Logs (Via Grafana Explore)

### Procedimento via UI

**Passo 1: Acessar Grafana**

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Acessar: http://localhost:3000
# User: admin
# Password: (obter com comando abaixo)
kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

**Passo 2: Navegar para Explore**

1. Menu lateral → **Explore** (ícone de bússola)
2. Datasource: Selecionar **Loki**

**Passo 3: Query LogQL**

```logql
# Query 1: Listar todos os logs do namespace otel-test com trace IDs
{namespace="otel-test"} |~ "traceId"

# Query 2: Buscar logs de um trace ID específico
{namespace="otel-test"} |~ "35ef4d47d11c0c26"

# Query 3: Extrair trace IDs dos logs (pattern matching)
{namespace="otel-test"}
  | regexp "traceId: (?P<trace_id>[a-f0-9]+)"
  | line_format "{{.trace_id}}"
```

**Passo 4: Navegar para Trace (Future Feature)**

- Em logs com trace_id, Grafana pode exibir link "View Trace"
- Click no link abre Tempo com trace completo
- **Requisito:** Configurar `derivedFields` no datasource Loki

**Configuração Derived Fields (Loki → Tempo):**

```yaml
# Em Grafana > Configuration > Data Sources > Loki
derivedFields:
  - name: TraceID
    matcherRegex: "traceId: ([a-f0-9]+)"
    url: "http://tempo-query-frontend.monitoring.svc.cluster.local:3200/api/traces/${__value.raw}"
    datasourceUid: tempo  # UID do datasource Tempo
```

**Resultado:** ✅ **Correlação funcional** (logs contêm trace IDs, UI config pendente)

---

## ✅ Teste 3: Query Trace por ID Direto

### Procedimento

**Passo 1: Obter Trace ID Completo**

```bash
# Traces do trace-generator têm IDs de 64 bits (16 hex chars)
# Tempo requer IDs de 128 bits (32 hex chars) - padding com zeros
TRACE_ID_SHORT="35ef4d47d11c0c26"
TRACE_ID_FULL="0000000000000000${TRACE_ID_SHORT}"

echo "Full Trace ID: $TRACE_ID_FULL"
# Output: 000000000000000035ef4d47d11c0c26
```

**Passo 2: Query Trace via API**

```bash
# Query trace específico (funciona mesmo antes de indexação)
kubectl exec -n monitoring tempo-query-frontend-5b69f45f5d-h5jf7 -- \
  wget -qO- "http://localhost:3200/api/traces/${TRACE_ID_FULL}" \
  2>/dev/null | jq . | head -50

# Ou via port-forward local:
kubectl port-forward -n monitoring svc/tempo-query-frontend 3200:3200 &
curl -s "http://localhost:3200/api/traces/${TRACE_ID_FULL}" | jq .
```

**Resultado Esperado:**

```json
{
  "batches": [
    {
      "resource": {
        "attributes": [
          {"key": "service.name", "value": {"stringValue": "trace-generator"}},
          {"key": "service.version", "value": {"stringValue": "1.0.0"}}
        ]
      },
      "scopeSpans": [
        {
          "spans": [
            {
              "traceId": "000000000000000035ef4d47d11c0c26",
              "spanId": "abc123...",
              "name": "operation-fetch-orders",
              "startTimeUnixNano": "...",
              "endTimeUnixNano": "...",
              "attributes": [...]
            }
          ]
        }
      ]
    }
  ]
}
```

**Status:** ⚠️ **BLOCKED** (traces podem não estar disponíveis se < 1h ou já expirados)

---

## ✅ Teste 4: Correlação Metrics → Traces (Exemplars)

### O Que São Exemplars?

**Exemplars** são pontos de dados de métricas Prometheus que incluem referências a traces específicos.

**Exemplo:**

```
http_requests_total{job="trace-generator"} 1543 @1707598800
  # Exemplar: trace_id="35ef4d47d11c0c26" @1707598800
```

### Status Atual

**Configuração Necessária (Pendente):**

1. **Tempo Metrics Generator** - Criar exemplars a partir de traces
2. **Prometheus** - Scrape exemplars dos metrics endpoints
3. **Grafana** - Exibir exemplars como pontos clicáveis em gráficos

**Verificar se Metrics Generator está ativo:**

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/component=metrics-generator

# Verificar configuração
kubectl get configmap -n monitoring tempo-config -o yaml \
  | grep -A20 "metrics_generator:"
```

**Resultado:** 📋 **TODO** - Configuração de exemplars pendente

---

## 🎯 Teste 5: Workflow Completo (End-to-End)

### Cenário: Investigar Latência Alta

**Passo 1: Identificar Spike em Dashboard SLI**

1. Abrir **Grafana** → Dashboards → **SLI Overview**
2. Observar gráfico **P95 Latency** (painel superior direito)
3. Identificar spike (exemplo: P95 > 1s às 14:35)

**Passo 2: Drill Down em Métricas**

```promql
# Query Prometheus para latência P95 no horário do spike
histogram_quantile(0.95,
  sum(rate(http_request_duration_seconds_bucket{
    job="gitlab"
  }[5m])) by (le)
)
```

**Passo 3: Click em Exemplar (Future)**

- Grafana exibe ponto clicável no spike
- Click abre **Tempo Trace View**
- Trace mostra spans detalhados:
  - `GET /api/projects` - 850ms
  - `DB Query` - 720ms (bottleneck!)
  - `Cache Lookup` - 50ms

**Passo 4: Navegar para Logs**

- No Tempo Trace View, click **Logs** button
- Abre Loki query: `{namespace="gitlab"} |~ "35ef4d47d11c0c26"`
- Logs mostram:
  ```
  [14:35:22] ERROR: Slow query detected (720ms)
  [14:35:22] Query: SELECT * FROM projects WHERE ...
  [14:35:22] traceId: 35ef4d47d11c0c26
  ```

**Resultado:** Identificado que query lenta no PostgreSQL causou latência alta

---

## 📋 Checklist de Validação

### Infraestrutura

- [x] Prometheus operacional (40 ServiceMonitors)
- [x] Loki operacional (11 pods Running)
- [x] Tempo operacional (10/11 pods Running)
- [x] Grafana operacional (dashboards SLI deployed)
- [x] OpenTelemetry Collector operacional (2 pods)
- [x] Trace Generator enviando traces (HTTP 200 OK)

### Correlação

- [x] **Trace ID presente nos logs** (validated via kubectl logs)
- [ ] **Trace ID → Logs via Grafana** (UI config pendente: derived fields)
- [ ] **Trace query por ID funcional** (blocked: traces < 1h ou expirados)
- [ ] **Exemplars configurados** (TODO: metrics generator config)
- [ ] **Workflow end-to-end** (blocked: exemplars + derived fields)

---

## 🔧 Ações Corretivas Recomendadas

### Curto Prazo (Esta Semana)

1. **Configurar Derived Fields no Loki Datasource** (30min)
   - Grafana UI → Configuration → Data Sources → Loki
   - Adicionar regex pattern para extrair trace IDs
   - Linkar para Tempo datasource

2. **Validar Metrics Generator** (1h)
   - Verificar se metrics-generator pod está Running
   - Configurar exemplars para métricas HTTP
   - Testar exemplar link em Grafana

3. **Documentar Runbook** (1h)
   - Como seguir um trace completo
   - Como correlacionar logs de erro com traces
   - Como usar exemplars para troubleshooting

### Médio Prazo (Sprint 4)

4. **Instrumentar Aplicações Reais** (8h)
   - Adicionar trace_id em logs de GitLab, ArgoCD, Harbor
   - Configurar OTLP exporters em aplicações
   - Validar correlação com workloads reais (não apenas trace-generator)

5. **Configurar Search Optimization** (2h)
   - Considerar reduzir `compaction_window` (tradeoff: mais IOPS S3)
   - Habilitar cache de search results
   - Configurar `complete_block_timeout` menor

---

## 📊 Métricas de Sucesso

| Métrica                              | Atual  | Alvo   | Status |
|--------------------------------------|--------|--------|--------|
| Trace ID em logs                     | ✅ 100% | 100%   | ✅ OK  |
| Traces query por ID                  | ⚠️ 0%  | 80%    | 🔧 WIP |
| Exemplars configurados               | ❌ 0%   | 100%   | 📋 TODO|
| Derived fields Loki → Tempo          | ❌ 0%   | 100%   | 📋 TODO|
| End-to-end correlation workflow      | ❌ 0%   | 100%   | 📋 TODO|
| MTTD (Mean Time to Detect) via traces| N/A    | < 5min | 📋 TODO|

---

## 🔗 Comandos Úteis

### Obter Trace ID dos Logs

```bash
kubectl logs -n otel-test -l app=trace-generator --tail=20 \
  | grep -o "traceId: [a-f0-9]*" | head -1
```

### Query Loki por Trace ID

```bash
# Via kubectl exec
kubectl exec -n monitoring loki-gateway-xxx -- \
  wget -qO- "http://loki-read:3100/loki/api/v1/query_range?query={namespace=\"otel-test\"}|~\"TRACE_ID\"&limit=10"
```

### Verificar Traces no S3

```bash
# Listar blocks no S3
aws s3 ls s3://k8s-platform-tempo-891377105802/ --recursive \
  --profile k8s-platform-prod | head -20
```

### Verificar Status Compactor

```bash
kubectl logs -n monitoring -l app.kubernetes.io/component=compactor \
  --tail=50 | grep -E "block|compact|flush"
```

---

## 🔗 Referências

- [Grafana Tempo Search API](https://grafana.com/docs/tempo/latest/api_docs/)
- [Grafana Exemplars Documentation](https://grafana.com/docs/grafana/latest/fundamentals/exemplars/)
- [Loki Derived Fields](https://grafana.com/docs/grafana/latest/datasources/loki/#derived-fields)
- [OpenTelemetry Trace Context](https://www.w3.org/TR/trace-context/)
- [CORRELATION-VALIDATION-REPORT.md](../domains/observability/docs/CORRELATION-VALIDATION-REPORT.md)

---

**Status:** 🟢 Guia operacional completo
**Próxima Ação:** Configurar derived fields Loki → Tempo (30min)
**Responsável:** SRE Team
**Validado:** 2026-02-10

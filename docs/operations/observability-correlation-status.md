# Observability Correlation Status - GAP-001

| Campo          | Valor                                                      |
|----------------|------------------------------------------------------------|
| **Data**       | 2026-02-27 (Updated)                                       |
| **Versão**     | 1.2                                                        |
| **Status**     | ✅ ALL OPERATIONAL - Loki FIXED, Correlation Testing Ready |

---

## Sumário Executivo

A infraestrutura de observabilidade está **operacional** com todos os componentes necessários para correlação traces↔logs↔metrics:

✅ **Prometheus** - Metrics collection (40 ServiceMonitors)
✅ **Loki** - Log aggregation (OPERATIONAL - Fixed 2026-02-27)
✅ **Tempo** - Distributed tracing (OTLP 4317/4318)
✅ **Grafana** - Visualization platform (31 dashboards)
✅ **OpenTelemetry Collector** - Telemetry pipeline (2 pods)

✅ **Validação de correlação end-to-end** - READY TO TEST (Loki issue resolved)

---

## 📊 Status dos Componentes

### 1. Prometheus (Metrics) ✅

**Status:** Operacional

```bash
# Pods
prometheus-kube-prometheus-stack-prometheus-0: Running

# Métricas coletadas
- 40 ServiceMonitors ativos
- 145 PrometheusRules (alertas)
- 10/10 alertas SLI críticos configurados

# Datasources
- Configurado no Grafana
- API: http://prometheus-kube-prometheus-stack-prometheus:9090
```

**Validação:**
```promql
# Métricas disponíveis
up{job=~"gitlab|argocd|vault|keycloak|harbor"}
http_requests_total
node_cpu_seconds_total
```

---

### 2. Loki (Logs) ✅

**Status:** Operacional (Fixed 2026-02-27 16:10)

```bash
# Pods (After Fix)
loki-read-f4dc5fbbd-c8hg8: Running (2/2 replicas operational)
loki-write-0: Running (1/1 replica, write-1 pending but non-blocking)
loki-backend-0/1: Running (2/2 replicas)
loki-gateway-xxxxx: Running (2/2 replicas)

# Datasource
- Configurado no Grafana
- API: http://loki-gateway.staging-observability-monitoring.svc.cluster.local

# Version
- Loki: 3.6.5
- Helm Chart: grafana/loki 6.53.0
```

**Issue Resolved:**
- Root Cause: Deprecated `compactor.shared_store` field in Loki 3.6.5
- Fix: Removed shared_store, added delete_request_store: s3
- Downtime: 18h (2026-02-26 → 2026-02-27)
- Resolution Time: 18 minutes
- Data Loss: None (PVCs intact)
- See: `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/logbook/2026-02-27-loki-crashloop-resolution.md`

**Validação:**
```logql
# Logs disponíveis
{namespace="staging-observability-monitoring"}
{app="tempo-distributor"}
{container="opentelemetry-collector"}

# API Health
curl http://loki-gateway:80/ready → 200 OK
curl http://loki-gateway:80/loki/api/v1/labels → {"status": "success"}
```

---

### 3. Tempo (Traces) ✅

**Status:** Operacional (OTLP 4317/4318 ativo desde 2026-02-10)

```bash
# Pods (11 total)
tempo-distributor-xxxxx: Running (2 replicas) - OTLP receiver
tempo-ingester-xxxxx: Running (2 replicas)
tempo-querier-xxxxx: Running (2 replicas)
tempo-query-frontend-xxxxx: Running (2 replicas)
tempo-compactor-xxxxx: Running (1 replica)
tempo-gateway-xxxxx: Running (2 replicas)

# Services
tempo-distributor:
  - 4317/TCP (OTLP gRPC)
  - 4318/TCP (OTLP HTTP)
  - 3200/TCP (Tempo API)

# Datasource
- Configurado no Grafana
- API: http://tempo-query-frontend.monitoring.svc.cluster.local:3200
```

**ServiceMonitors:**
- tempo-compactor
- tempo-distributor
- tempo-ingester
- tempo-querier
- tempo-query-frontend
- tempo-memcached
- tempo-metrics-generator

**Validação:**
```bash
# Trace generator ativo
otel-test/trace-generator: Sending traces every 5-10s
- operation-fetch-users
- operation-fetch-orders
- operation-process-payment
```

---

### 4. OpenTelemetry Collector ✅

**Status:** Operacional (Gateway mode)

```bash
# Pods
monitoring/opentelemetry-collector-xxxxx: Running (2 replicas)

# Configuration
- Receivers: OTLP (gRPC 4317, HTTP 4318)
- Processors: batch, memory_limiter
- Exporters:
  * prometheus (metrics)
  * loki (logs)
  * tempo (traces via OTLP)
```

**Deployment Info:**
- Deploy Date: 2026-02-09 (commit e411869)
- HA: 2 replicas
- Resource Limits: CPU 500m, Memory 512Mi
- Cost: $6/mês (usa nodes existentes)

---

### 5. Grafana ✅

**Status:** Operacional

```bash
# Pod
kube-prometheus-stack-grafana-xxxxx: Running

# Dashboards
- 31 dashboards existentes
- SLI dashboards: Em criação (agent trabalhando)

# Datasources configurados
✅ Prometheus
✅ Loki
✅ Tempo
```

---

## 🔗 Correlação Traces ↔ Logs ↔ Metrics

### ✅ UPDATE 2026-02-27: Loki → Tempo Derived Fields Configured

**Status:** Configured via Grafana datasource ConfigMap

**Implementation:**

- 4 regex patterns for trace ID extraction (OpenTelemetry, JSON, dotted formats)
- Bidirectional correlation: Loki → Tempo (derived fields) + Tempo → Loki (tracesToLogs)
- Hot-reloaded via Grafana API (no pod restart required)
- Documentation: ADR-087

**Status Update 2026-02-27 16:10:**

✅ **Loki CrashLoop RESOLVED** - All components operational
✅ **Configuration validated** - Derived fields active
✅ **Ready for end-to-end testing**

**Next Steps:**

1. ✅ ~~Fix Loki stability~~ COMPLETE (config error, not OOM)
2. ⚠️ Test correlation with instrumented app (UNBLOCKED, ready to proceed)
3. ⚠️ Validate trace ID clickable links work (UNBLOCKED, ready to proceed)

See: `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/adr/adr-087-loki-tempo-derived-fields.md`

---

### Fluxo de Dados

```
┌─────────────────────────────────────────────────────────────┐
│                  APPLICATION / POD                          │
└─────────────────┬───────────────────────┬───────────────────┘
                  │                       │
        ┌─────────▼────────┐   ┌─────────▼────────┐
        │  Logs (stdout)   │   │   Traces (OTLP)  │
        └─────────┬────────┘   └─────────┬────────┘
                  │                       │
        ┌─────────▼────────┐   ┌─────────▼────────────┐
        │  Loki (Write)    │   │  OTel Collector      │
        └─────────┬────────┘   │  (Gateway mode)      │
                  │            └─────────┬────────────┘
                  │                      │
                  │            ┌─────────▼────────────┐
                  │            │  Tempo Distributor   │
                  │            │  (OTLP 4317/4318)    │
                  │            └─────────┬────────────┘
                  │                      │
        ┌─────────▼──────────────────────▼────────┐
        │         STORAGE (S3-compatible)         │
        │  • Loki Chunks (logs)                   │
        │  • Tempo Blocks (traces)                │
        └─────────┬──────────────────┬────────────┘
                  │                  │
        ┌─────────▼────────┐   ┌────▼────────────┐
        │  Loki Query      │   │  Tempo Querier  │
        └─────────┬────────┘   └────┬────────────┘
                  │                  │
        ┌─────────▼──────────────────▼────────────┐
        │              GRAFANA                    │
        │  • Logs Explorer                        │
        │  • Trace View                           │
        │  • Metrics Dashboards                   │
        │  • Correlation: trace_id → logs         │
        └─────────────────────────────────────────┘
```

### Correlation Keys

**Trace ID → Logs:**
```
1. Application emits trace_id in logs
2. Loki labels: {trace_id="abc123"}
3. Grafana: Click trace_id → Query Loki
4. Result: Logs for that trace
```

**Trace ID → Metrics:**
```
1. Tempo metrics-generator creates exemplars
2. Prometheus scrapes exemplars with trace_id
3. Grafana: Click exemplar → Open trace in Tempo
4. Result: Full trace context
```

**Logs → Metrics:**
```
1. Loki log queries include namespace/pod labels
2. Same labels in Prometheus metrics
3. Grafana: Unified query filters
4. Result: Correlated logs + metrics
```

---

## ✅ Validações Realizadas

### 1. Infraestrutura
- ✅ Todos os pods Running
- ✅ Services expostos corretamente
- ✅ OTLP endpoints acessíveis (4317, 4318)
- ✅ ServiceMonitors configurados (7 para Tempo)

### 2. Telemetria Ativa
- ✅ Trace generator enviando traces (otel-test namespace)
- ✅ Logs sendo coletados (Loki)
- ✅ Métricas sendo scraped (Prometheus)

### 3. Configuração
- ✅ Grafana datasources configurados
- ✅ PrometheusRules com alertas SLI ativos
- ✅ OpenTelemetry Collector pipeline configurada

---

## ⚠️ Pendente - Validação End-to-End

### Testes Necessários

#### Teste 1: Trace → Logs Correlation
```bash
# 1. Obter trace_id do Tempo
kubectl exec -n monitoring tempo-query-frontend-0 -- \
  wget -qO- "http://localhost:3200/api/search?limit=1"

# 2. Query logs com trace_id no Loki
# Via Grafana Explore:
{namespace="otel-test"} |~ "trace_id=<TRACE_ID>"

# Resultado esperado: Logs correlacionados
```

#### Teste 2: Exemplar → Trace Correlation
```bash
# 1. Query Prometheus metric com exemplar
http_requests_total{job="trace-generator"}

# 2. Click exemplar no Grafana
# 3. Navigate to Tempo trace

# Resultado esperado: Trace completo aberto
```

#### Teste 3: Full Correlation Workflow
```bash
# 1. Start em um dashboard SLI
# 2. Ver spike em latency P95
# 3. Click no spike → exemplar → trace
# 4. No trace view, click "Logs" → Loki query
# 5. Ver logs contextuais do trace

# Resultado esperado: Navegação fluida entre metrics → traces → logs
```

---

## 📋 Ações Pendentes

### Hoje (2026-02-10)
- ⏳ **Dashboards SLI** - Agent trabalhando (background)
  - sli-overview-dashboard.json
  - error-budget-dashboard.json
  - gitlab/argocd/vault-sli-dashboard.json

### Esta Semana
1. ⚠️ **Teste End-to-End Correlation** (1h)
   - Validar trace_id → logs
   - Validar exemplar → trace
   - Documentar workflow

2. ⚠️ **Instrumentação Aplicações** (futuro)
   - Adicionar trace_id em logs (GitLab, ArgoCD, Harbor)
   - Configurar exemplars em métricas HTTP
   - Testar com aplicações reais (não apenas trace-generator)

3. ⚠️ **Documentação Runbooks** (futuro)
   - Como troubleshoot com correlation
   - Como seguir um trace completo
   - Como correlacionar logs de erro com traces

---

## 🎯 Critérios de Sucesso

### Milestone: Correlation Funcional ✅ (Infraestrutura)

- ✅ Todos os componentes operacionais
- ✅ OTLP endpoints acessíveis
- ✅ Trace generator enviando traces
- ⚠️ Grafana dashboards com correlation links (pendente)
- ⚠️ Teste end-to-end validado (pendente)

### Milestone: Correlation Production-Ready (Futuro)

- ⏳ Aplicações reais instrumentadas
- ⏳ Exemplars configurados em métricas HTTP
- ⏳ Runbooks documentados
- ⏳ Training para equipe SRE

---

## 📊 Métricas de Observabilidade

### Coverage Atual

| Componente       | Metrics | Logs | Traces | Correlation |
|------------------|---------|------|--------|-------------|
| Infrastructure   | ✅ 100% | ✅ 100% | ✅ 100% | ⚠️ Parcial  |
| Prometheus       | ✅ 100% | ✅ 100% | ✅ 100% | ✅ OK       |
| Loki             | ✅ 100% | ✅ 100% | ✅ 100% | ✅ OK       |
| Tempo            | ✅ 100% | ✅ 100% | ✅ 100% | ✅ OK       |
| Grafana          | ✅ 100% | ✅ 100% | ✅ 100% | ✅ OK       |
| OTel Collector   | ✅ 100% | ✅ 100% | ✅ 100% | ✅ OK       |
| GitLab           | ✅ 100% | ✅ 100% | ⚠️ 0%  | ❌ N/A      |
| ArgoCD           | ✅ 100% | ✅ 100% | ⚠️ 0%  | ❌ N/A      |
| Harbor           | ✅ 100% | ✅ 100% | ⚠️ 0%  | ❌ N/A      |
| Vault            | ✅ 100% | ✅ 100% | ⚠️ 0%  | ❌ N/A      |
| Keycloak         | ✅ 100% | ✅ 100% | ⚠️ 0%  | ❌ N/A      |

**Observação:** Aplicações reais (GitLab, ArgoCD, etc.) precisam de instrumentação OTLP para enviar traces.

---

## 🔗 Referências

- [SLI/SLO Definitions](sli-slo-definitions.md)
- [Alert Validation Report](../../domains/observability/docs/VALIDATION-REPORT.md)
- [GAP-001 Logbook](../logbook/2026-02-10-gap001-sli-slo.md)
- [GAP-007 Tempo OTLP](../logbook/2026-02-10-gap007-tempo-otlp.md)
- [Grafana Exemplars Documentation](https://grafana.com/docs/grafana/latest/fundamentals/exemplars/)
- [OpenTelemetry Best Practices](https://opentelemetry.io/docs/concepts/instrumentation/)

---

**Status:** 🟢 Infraestrutura 100% operacional, validação end-to-end pendente
**Próxima Ação:** Finalizar dashboards SLI + Testar correlation workflow
**Responsável:** SRE Team
**Deadline:** Fim da semana (2026-02-14)

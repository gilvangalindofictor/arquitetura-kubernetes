# 📊 Agente Observability & SRE Specialist

**Função:** Garantir observabilidade completa (monitoring, logging, tracing) e SLOs/SLIs
**Expertise:** **OpenTelemetry**, Prometheus, Grafana, Loki, Tempo, AlertManager, SLOs, Error Budgets

---

## 🎯 Responsabilidades

1. **OpenTelemetry (Camada de Coleta)**
   - **OTEL Collector** deployment (DaemonSet + Gateway)
   - **OTLP protocol** receivers (gRPC/HTTP)
   - **Pipelines:** metrics → Prometheus, logs → Loki, traces → Tempo
   - **Instrumentação de aplicações:** SDKs Python/Java/Go/Node.js
   - Auto-instrumentation (Java, Python) vs manual instrumentation
   - Sampling strategies (1% staging, 10% prod)

2. **Monitoring Stack**
   - Prometheus + Grafana deployment e tuning
   - AlertManager rules (critical, warning, info)
   - ServiceMonitor/PodMonitor CRDs para auto-discovery
   - Métricas customizadas (RED, USE, Four Golden Signals)

2. **Logging Centralizado**
   - Loki/ELK/CloudWatch Logs integration
   - Retention policies (staging: 7d, prod: 30d)
   - Log aggregation de pods, operators, infra
   - Structured logging validation (JSON format)

3. **Distributed Tracing**
   - **Tempo** (via OTEL Collector, S3 backend)
   - **OTLP traces** ingestion (gRPC port 4317, HTTP port 4318)
   - Trace sampling (1% staging, 10% prod)
   - Latency analysis (p50, p95, p99)
   - Trace-to-logs correlation (TraceID injection)

4. **SRE Practices**
   - SLOs/SLIs definidos (availability, latency, error rate)
   - Error budgets (99.9% uptime = 43 min/month downtime)
   - Dashboards por workload (overview, drill-down)
   - On-call alerting (PagerDuty/Opsgenie integration)

5. **Validação Pré e Pós Execução**
   - PRE: Dashboards/alertas para novos componentes planejados
   - POST: Validar métricas fluindo, alertas funcionais, sem gaps

---

## 📋 Checklist PRE-HOOK Observability

- [ ] **OTEL Collector** instalado (DaemonSet + Gateway)
- [ ] **OTLP receivers** configurados (gRPC 4317, HTTP 4318)
- [ ] **Aplicações instrumentadas** com OTEL SDK ou auto-instrumentation
- [ ] **Environment variables** OTEL configuradas (OTEL_EXPORTER_OTLP_ENDPOINT)
- [ ] ServiceMonitor/PodMonitor criados para novos workloads
- [ ] Dashboards Grafana provisionados (não manuais)
- [ ] Alerting rules definidos (CrashLoopBackOff, OOMKill, High Latency)
- [ ] Retention policies configuradas (disk space sufficiency)
- [ ] Trace sampling configurado (% adequado ao ambiente)
- [ ] Log labels standardizados (app, env, version, namespace)

---

## 📋 Checklist POST-HOOK Observability

- [ ] Métricas aparecendo no Prometheus (query: `up{job="<workload>"}`)
- [ ] Dashboards renderizando sem erros (Grafana API check)
- [ ] Alertas testados (simulate: kill pod → alert fires → recovery)
- [ ] Logs centralizados (Loki query: `{namespace="<ns>"}`)
- [ ] Traces coletados (Jaeger UI: ver sample traces)
- [ ] No silent failures (AML detectou gap em métricas/logs)

---

## 🔍 Análise Observability STAGING

### Stack Atual (Validar/Criar)

| Componente | Status | Ação Necessária |
|------------|--------|-----------------|
| **OpenTelemetry Collector** | ⏸️ Pendente | Deploy OTEL Collector (DaemonSet + Gateway) |
| **Prometheus** | ⏸️ Pendente | Deploy kube-prometheus-stack (Helm) |
| **Grafana** | ⏸️ Pendente | Incluído no kube-prometheus-stack |
| **Loki** | ⏸️ Pendente | Deploy Loki stack (fluent-bit + loki + grafana datasource) |
| **Tempo** | ⏸️ Pendente | Deploy Tempo (S3 backend) |
| **AlertManager** | ⏸️ Pendente | Incluído no kube-prometheus-stack |

### Dashboards Obrigatórios (Staging)

1. **Cluster Overview**
   - Node CPU/Memory/Disk usage
   - Pod count, restarts, CrashLoops
   - PVC usage, network I/O

2. **OpenTelemetry Stack**
   - OTEL Collector metrics (pipeline throughput, dropped spans/logs)
   - OTLP receiver status (gRPC/HTTP endpoints)
   - Exporter health (Prometheus, Loki, Tempo connections)

3. **Workload-Specific**
   - Redis Operator: master/replica lag, memory usage, hit rate
   - RabbitMQ Operator: queue depth, message rate, consumers
   - PostgreSQL: connections, transactions, cache hit ratio
   - GitLab: job queue, runner utilization
   - **Custom Apps:** RED metrics via OTEL (Rate, Errors, Duration)

4. **FinOps Integration**
   - Node count vs workload demand (right-sizing)
   - Idle resources (CPU request vs usage gap)
   - Startup/shutdown metrics (economia validada)

### Alerting Rules Críticos

```yaml
# CrashLoopBackOff > 5 min
- alert: PodCrashLooping
  expr: rate(kube_pod_container_status_restarts_total[5m]) > 0
  severity: critical

# OOMKilled detection
- alert: PodOOMKilled
  expr: kube_pod_container_status_terminated_reason{reason="OOMKilled"} > 0
  severity: critical

# High latency (p95 > 2s)
- alert: HighLatency
  expr: histogram_quantile(0.95, http_request_duration_seconds) > 2
  severity: warning

# Disk space < 10%
- alert: DiskSpaceLow
  expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.1
  severity: warning
```

### SLOs Staging

| Workload | SLI | Target | Measurement |
|----------|-----|--------|-------------|
| **GitLab** | Availability | 99% | `sum(up{job="gitlab-webservice"}) / count(up{job="gitlab-webservice"})` |
| **Redis** | Latency (p95) | < 10ms | `histogram_quantile(0.95, redis_command_duration_seconds)` |
| **RabbitMQ** | Message Loss | 0% | `rabbitmq_queue_messages_unacked / rabbitmq_queue_messages_total` |

### Decisão Final

⚠️ **BLOQUEADOR PARCIAL** - Staging eficiente REQUER observability básica
**Ação:** Deploy **OpenTelemetry Collector** + kube-prometheus-stack + Loki + Tempo ANTES de node optimization
**Prazo:** Marco 4 (junto com secrets migration)

**Ordem de Deploy (conforme Quickstart Sprint 2):**
1. ✅ OTEL Collector (DaemonSet + Gateway) - 12h
2. ✅ kube-prometheus-stack (Prometheus + Grafana + AlertManager) - 16h
3. ✅ Loki + Fluent Bit - 12h
4. ✅ Tempo - 8h
5. ✅ OTEL Pipelines integration - 8h
6. ✅ Dashboards + Alerts - 16h

**Total esforço:** 72h eng (~9 dias para 1 eng, ~4.5 dias para 2 eng)

---

## 🔄 Integração com AML

Durante execução via AML, Observability Specialist monitora:

```bash
# Ciclo AML - Verificações Adicionais
├─ Prometheus targets up? (kubectl get servicemonitor)
├─ Grafana datasources healthy? (curl grafana API)
├─ Alertmanager firing alerts? (kubectl logs alertmanager)
└─ Loki ingesting logs? (logcli query '{namespace="X"}' --limit=10)
```

**Report AML Compacto:**
```
[AML-C5] 75s | Obs | Prometheus: 12/12 targets up | Loki: 45 log/s | Alerts: 0 firing | ✅
```

---

## 🔧 Instrumentação de Aplicações (OpenTelemetry)

### Estratégia: OpenTelemetry como Padrão

**Referência:** [Quickstart Sprint 2](../../plan/quickstart/aws-eks-gitlab-quickstart.md#sprint-2--observability-baseline-84h)

Todas as aplicações custom **DEVEM** ser instrumentadas com OpenTelemetry para enviar telemetria padronizada (metrics, logs, traces) via OTLP protocol.

### SDKs por Linguagem

| Linguagem | SDK | Auto-Instrumentation | Esforço | Exemplo |
|-----------|-----|---------------------|---------|---------|
| **Python** | `opentelemetry-distro[otlp]` | ✅ Sim (Flask, FastAPI, Django) | 5 min | `opentelemetry-instrument python app.py` |
| **Java** | `opentelemetry-javaagent.jar` | ✅ Sim (Spring Boot, Quarkus) | 2 min | `-javaagent:path/to/opentelemetry-javaagent.jar` |
| **Go** | `go.opentelemetry.io/otel` | ❌ Manual (net/http, gRPC) | 30 min | Código manual por handler |
| **Node.js** | `@opentelemetry/auto-instrumentations-node` | ✅ Sim (Express, Fastify) | 5 min | `node --require @opentelemetry/auto-instrumentations-node/register app.js` |

### Configuração Padrão (Environment Variables)

Todas as aplicações instrumentadas devem ter estas env vars:

```yaml
# Deployment manifest (exemplo Python FastAPI)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: staging
spec:
  template:
    spec:
      containers:
      - name: app
        image: myapp:latest
        env:
        # OTEL Exporter (OTLP)
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://otel-collector-gateway.observability.svc.cluster.local:4318"
        - name: OTEL_EXPORTER_OTLP_PROTOCOL
          value: "http/protobuf"

        # Service metadata
        - name: OTEL_SERVICE_NAME
          value: "myapp"
        - name: OTEL_SERVICE_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: OTEL_SERVICE_VERSION
          value: "1.0.0"

        # Resource attributes (K8s metadata)
        - name: OTEL_RESOURCE_ATTRIBUTES
          value: "deployment.environment=staging,k8s.cluster.name=eks-staging"

        # Sampling (1% staging, 10% prod)
        - name: OTEL_TRACES_SAMPLER
          value: "parentbased_traceidratio"
        - name: OTEL_TRACES_SAMPLER_ARG
          value: "0.01"  # 1% sampling

        # Logs (inject TraceID)
        - name: OTEL_LOGS_EXPORTER
          value: "otlp"
        - name: OTEL_PYTHON_LOG_CORRELATION
          value: "true"
```

### Exemplo Prático: Python FastAPI

**1. Instalar SDK:**
```bash
pip install opentelemetry-distro[otlp]
pip install opentelemetry-instrumentation-fastapi
```

**2. Auto-instrumentação (zero code changes):**
```bash
# Dockerfile
RUN opentelemetry-bootstrap -a install

# Executar
CMD ["opentelemetry-instrument", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**3. Validar telemetria:**
```bash
# Verificar traces no Grafana Tempo
# Verificar logs com TraceID injetado no Loki
# Verificar métricas RED no Prometheus
```

### Checklist de Instrumentação (Obrigatório)

Antes de deploy em staging/prod:

- [ ] **SDK instalado** (auto-instrumentation ou manual)
- [ ] **OTEL_EXPORTER_OTLP_ENDPOINT** configurado (OTEL Gateway)
- [ ] **OTEL_SERVICE_NAME** único e descritivo
- [ ] **Sampling configurado** (1% staging, 10% prod)
- [ ] **TraceID injection** em logs habilitado
- [ ] **Teste local:** `docker-compose` com OTEL Collector → validar telemetria
- [ ] **Grafana dashboards:** RED metrics visíveis pós-deploy

### Troubleshooting Comum

| Problema | Diagnóstico | Solução |
|----------|-------------|---------|
| **Traces não aparecem no Tempo** | OTEL endpoint incorreto | Validar DNS: `nslookup otel-collector-gateway.observability.svc.cluster.local` |
| **Logs sem TraceID** | Log correlation desabilitado | Habilitar `OTEL_PYTHON_LOG_CORRELATION=true` |
| **Métricas não aparecem** | Prometheus não scraping | Criar `ServiceMonitor` para expor `/metrics` |
| **Sampling 100%** | `OTEL_TRACES_SAMPLER_ARG` não configurado | Definir 0.01 (1%) ou 0.10 (10%) |

---

## 📊 Custo Observability Stack (Staging)

| Componente | Recursos | Custo/mês AWS |
|------------|----------|---------------|
| Prometheus | 2 vCPU, 4GB RAM, 50GB EBS | ~$35 |
| Grafana | 1 vCPU, 2GB RAM | ~$15 |
| Loki | 1 vCPU, 2GB RAM, 30GB EBS | ~$20 |
| **Total** | - | **~$70/mês** |

**Alternativa:** CloudWatch Insights ~$150/mês (métrica + logs + retention)
**Economia:** $80/mês = $960/ano (open-source stack)

---

**Criado em:** 2026-02-09
**Próxima Revisão:** Pós-deploy kube-prometheus-stack (validar targets, dashboards, alerts)

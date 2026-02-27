# GOV-008: Observability Stack Governance

> **Versão**: 1.0
> **Data**: 2026-02-27
> **Status**: Ativo
> **Referências**: ADR-005, ADR-006, ADR-080
> **Audiência**: Desenvolvedores, SRE, Platform Team

---

## Visão Geral

A stack de observabilidade segue o modelo dos **três pilares**: Métricas (Prometheus), Logs (Loki) e Traces (Tempo), com correlação via OpenTelemetry.

**Stack**:
- **Métricas**: Prometheus (kube-prometheus-stack) + Grafana dashboards
- **Logs**: Loki + Promtail (log aggregation)
- **Traces**: Tempo + OpenTelemetry Collector
- **Alertas**: Alertmanager → Slack/Email
- **SLI/SLO**: Definidos em [sli-slo-definitions.md](../operations/sli-slo-definitions.md)

---

## Instrumentação Obrigatória

Toda aplicação DEVE expor:

### 1. Métricas (Prometheus)

```yaml
# ServiceMonitor para scraping automático
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {produto}-metrics
  namespace: {namespace}
  labels:
    release: kube-prometheus-stack    # Label para discovery
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: {produto}
  endpoints:
    - port: http-metrics
      path: /metrics
      interval: 30s
```

**Métricas obrigatórias** (RED method):
- **Rate**: `http_requests_total` (counter)
- **Errors**: `http_requests_errors_total` (counter)
- **Duration**: `http_request_duration_seconds` (histogram)

### 2. Logs (JSON Estruturado)

```json
{
  "timestamp": "2026-02-27T10:30:00Z",
  "level": "INFO",
  "message": "Request processed",
  "service": "{produto}",
  "domain": "{domain}",
  "trace_id": "abc123def456",
  "span_id": "789ghi",
  "request_id": "req-uuid-123",
  "duration_ms": 42
}
```

**Regras**:
- Formato: JSON (nunca plain text)
- Campos obrigatórios: `timestamp`, `level`, `message`, `service`
- Campos recomendados: `trace_id`, `span_id`, `request_id`, `duration_ms`
- Output: stdout/stderr (Promtail coleta automaticamente)

### 3. Traces (OpenTelemetry)

```yaml
# Environment variables para SDK
OTEL_EXPORTER_OTLP_ENDPOINT: "http://opentelemetry-collector.observability:4317"
OTEL_SERVICE_NAME: "{produto}"
OTEL_RESOURCE_ATTRIBUTES: "domain={domain},environment=staging"
```

**Referência**: [OpenTelemetry Developer Guide](../OPENTELEMETRY-DEVELOPER-GUIDE.md)

---

## Naming Conventions

### Grafana Dashboards

```yaml
Formato: {domain}-{produto}-{tipo}
Exemplos:
✅ data-rpa-exemplo-overview
✅ platform-postgresql-performance
✅ integration-ipaas-api-latency
```

### Alert Rules

```yaml
Formato: {Produto}{Condição}
Exemplos:
✅ PostgreSQLConnectionsHigh
✅ RedisHighMemory
✅ RabbitMQQueueDepth
✅ RpaExemploErrorRateHigh
```

### Recording Rules

```yaml
Formato: {namespace}:{metric}:{aggregation}
Exemplos:
✅ data:http_requests_total:rate5m
✅ integration:http_request_duration_seconds:p99
```

---

## Alerting Tiers

| Tier | Severidade | Notificação | Exemplos |
|------|-----------|-------------|----------|
| **P1 - Critical** | `critical` | Slack + PagerDuty (24/7) | Service down, data loss |
| **P2 - Warning** | `warning` | Slack (#alerts) | High latency, high error rate |
| **P3 - Info** | `info` | Slack (#monitoring) | Disk 80%, connection pool 70% |

### Alert Template

```yaml
groups:
  - name: {produto}-alerts
    rules:
      - alert: {Produto}ErrorRateHigh
        expr: |
          rate(http_requests_errors_total{service="{produto}"}[5m])
          / rate(http_requests_total{service="{produto}"}[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
          domain: {domain}
          product: {produto}
        annotations:
          summary: "Error rate > 5% for {produto}"
          runbook_url: "https://docs.internal/{produto}/runbooks/error-rate-high"
```

---

## SLI/SLO Standards

| Indicador | SLI | SLO Target |
|-----------|-----|------------|
| **Availability** | Successful requests / Total requests | 99.9% (monthly) |
| **Latency** | p99 response time | < 500ms |
| **Error Rate** | Error requests / Total requests | < 0.1% |
| **Throughput** | Requests per second | Baseline ± 20% |

**Referência**: [SLI/SLO Definitions](../operations/sli-slo-definitions.md)

---

## Correlation: Métricas ↔ Logs ↔ Traces

```
Grafana Dashboard → Drill-down via trace_id
     │
     ├── Prometheus (métricas) → Rate, Errors, Duration
     ├── Loki (logs)          → JSON logs filtrados por trace_id
     └── Tempo (traces)       → Distributed trace visualization
```

**Referência**: [Observability Correlation Status](../operations/observability-correlation-status.md)

---

## Runbooks Index

Toda aplicação DEVE ter runbooks para alertas críticos:

| Alerta | Runbook |
|--------|---------|
| PostgreSQL Down | [dt005-postgresql-down.md](../../domains/observability/docs/runbooks/dt005-postgresql-down.md) |
| PostgreSQL Connections High | [dt005-postgresql-connections-high.md](../../domains/observability/docs/runbooks/dt005-postgresql-connections-high.md) |
| Redis Down | [dt005-redis-down.md](../../domains/observability/docs/runbooks/dt005-redis-down.md) |
| Redis High Memory | [dt005-redis-high-memory.md](../../domains/observability/docs/runbooks/dt005-redis-high-memory.md) |
| RabbitMQ Down | [dt005-rabbitmq-down.md](../../domains/observability/docs/runbooks/dt005-rabbitmq-down.md) |
| RabbitMQ Queue Depth | [dt005-rabbitmq-queue-depth.md](../../domains/observability/docs/runbooks/dt005-rabbitmq-queue-depth.md) |
| Vault Sealed | [dt005-vault-sealed.md](../../domains/observability/docs/runbooks/dt005-vault-sealed.md) |

**Índice completo**: [Runbooks README](../../domains/observability/docs/runbooks/README.md)

---

## Best Practices

1. **RED method**: Toda API expõe Rate, Errors, Duration
2. **JSON logs**: Nunca plain text (Loki parseia JSON nativamente)
3. **Trace propagation**: Propagar `trace_id` em chamadas inter-serviço
4. **ServiceMonitor**: Toda aplicação tem ServiceMonitor (não scrape manual)
5. **Runbook URLs**: Todo alerta tem `runbook_url` annotation
6. **Dashboard as Code**: Dashboards Grafana versionados em Git (JSON)
7. **Alert testing**: Testar alertas em staging antes de produção

---

## Referências

- [ADR-005: Logging Strategy](../adr/adr-005-logging-strategy.md)
- [ADR-006: Observabilidade Transversal](../adr/adr-006-observabilidade-transversal.md)
- [ADR-080: OpenTelemetry Collector Implementation](../adr/adr-080-opentelemetry-collector-implementation.md)
- [OpenTelemetry Developer Guide](../OPENTELEMETRY-DEVELOPER-GUIDE.md)
- [SLI/SLO Definitions](../operations/sli-slo-definitions.md)
- [Grafana Dashboards](../../domains/observability/infra/grafana/dashboards/README.md)

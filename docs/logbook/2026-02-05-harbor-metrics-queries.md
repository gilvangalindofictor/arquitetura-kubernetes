# 📊 Harbor Metrics - PromQL Queries

**Data:** 2026-02-05
**ServiceMonitor:** harbor-system/harbor
**Endpoint:** http-metrics
**Status:** ✅ Operacional

---

## Métricas Disponíveis (20+)

### Health & Info
```promql
# Harbor health status (1=healthy, 0=unhealthy)
harbor_health

# Harbor system info
harbor_system_info

# JobService info
harbor_jobservice_info
```

### Projects & Repos
```promql
# Total de projetos
harbor_project_total

# Total de repositórios por projeto
harbor_project_repo_total

# Total de membros por projeto
harbor_project_member_total
```

### Storage & Quota
```promql
# Quota total por projeto (bytes)
harbor_project_quota_byte

# Uso de quota por projeto (bytes)
harbor_project_quota_usage_byte

# Percentual de uso
(harbor_project_quota_usage_byte / harbor_project_quota_byte) * 100
```

### HTTP Requests (Core API)
```promql
# Total de requests
harbor_core_http_request_total

# Requests por status code
sum by (code) (rate(harbor_core_http_request_total[5m]))

# Request duration (p95)
histogram_quantile(0.95, rate(harbor_core_http_request_duration_seconds_bucket[5m]))

# Requests in-flight
harbor_core_http_inflight_requests
```

### Artifacts
```promql
# Total de artifacts pulled
harbor_artifact_pulled

# Pull rate (últimos 5min)
rate(harbor_artifact_pulled[5m])
```

### JobService Tasks
```promql
# Total de tasks
harbor_jobservice_task_total

# Task processing time (p95)
histogram_quantile(0.95, rate(harbor_jobservice_task_process_time_seconds_bucket[5m]))

# Task queue latency
harbor_task_queue_latency

# Task concurrency
harbor_task_concurrency
```

---

## Alertas Recomendados (TODO)

### Critical
```yaml
# Harbor Down
- alert: HarborDown
  expr: harbor_health == 0
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "Harbor registry is down"

# Quota Exceeded
- alert: HarborQuotaExceeded
  expr: (harbor_project_quota_usage_byte / harbor_project_quota_byte) > 0.95
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Harbor project quota > 95%"
```

### Performance
```yaml
# High Request Latency
- alert: HarborHighLatency
  expr: histogram_quantile(0.95, rate(harbor_core_http_request_duration_seconds_bucket[5m])) > 2
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Harbor API p95 latency > 2s"

# High Error Rate
- alert: HarborHighErrorRate
  expr: sum(rate(harbor_core_http_request_total{code=~"5.."}[5m])) / sum(rate(harbor_core_http_request_total[5m])) > 0.05
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Harbor API error rate > 5%"
```

---

## Validação Atual (2026-02-05)

| Métrica | Valor | Status |
|---------|-------|--------|
| harbor_health | 1 | ✅ Healthy |
| harbor_project_total | 1 | ✅ 1 projeto |
| harbor_artifact_pulled | 0 | ⚠️ Sem uso ainda |
| harbor_core_http_request_total | 4 séries | ✅ Coletando |

**Próximo:** Criar PrometheusRule com alertas recomendados (opcional)

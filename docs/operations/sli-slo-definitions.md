# SLI/SLO Definitions - Staging Environment

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-02-10                               |
| **Versão**     | 1.0                                      |
| **Status**     | Draft → Review                           |
| **Owner**      | SRE Team                                 |
| **Ambiente**   | Staging (k8s-platform-prod)              |

---

## Objetivos

Este documento define os **Service Level Indicators (SLIs)** e **Service Level Objectives (SLOs)** para o ambiente de staging, estabelecendo:

1. Métricas mensuráveis de qualidade de serviço (SLIs)
2. Targets aceitáveis para cada métrica (SLOs)
3. Métodos de medição e alertas associados
4. Error budgets para inovação controlada

**Filosofia:** Baseado no Google SRE - "Hope is not a strategy, instrumentation is."

---

## 📊 SLIs Críticos (5 Golden Signals)

### 1. Availability (Disponibilidade)

**Definição:** Percentual de tempo que os serviços críticos estão acessíveis e funcionais.

**Fórmula:**
```
Availability = (Total Time - Downtime) / Total Time × 100%
```

**Medição:**
- **Fonte:** Prometheus `up` metric + Blackbox Exporter probes
- **Query:**
  ```promql
  avg_over_time(up{job=~"gitlab|argocd|harbor|vault|keycloak"}[5m])
  ```

**SLO Targets:**

| Serviço    | SLO Target  | Error Budget | Downtime Permitido/Mês |
|------------|-------------|--------------|------------------------|
| Vault      | 99.5%       | 0.5%         | 3h 36min               |
| Keycloak   | 99.0%       | 1.0%         | 7h 12min               |
| GitLab     | 98.0%       | 2.0%         | 14h 24min              |
| ArgoCD     | 98.0%       | 2.0%         | 14h 24min              |
| Harbor     | 97.0%       | 3.0%         | 21h 36min              |

**Alertas:**
- **Critical:** Availability < 95% por 5 minutos (any service)
- **Warning:** Availability < SLO target por 15 minutos

---

### 2. Latency (Latência de Requisição)

**Definição:** Tempo de resposta de requisições HTTP/gRPC dos serviços.

**Métricas:**
- **P50:** 50% das requisições completam em X segundos (mediana)
- **P95:** 95% das requisições completam em X segundos
- **P99:** 99% das requisições completam em X segundos

**Medição:**
- **Fonte:** ServiceMonitor metrics (`http_request_duration_seconds`)
- **Query P95:**
  ```promql
  histogram_quantile(0.95,
    rate(http_request_duration_seconds_bucket{job="gitlab"}[5m])
  )
  ```

**SLO Targets:**

| Serviço    | P50    | P95    | P99    | Método                      |
|------------|--------|--------|--------|-----------------------------|
| Vault      | 50ms   | 200ms  | 500ms  | `/v1/secret/data/*`         |
| Keycloak   | 100ms  | 500ms  | 1s     | `/auth/realms/*/protocol/*` |
| GitLab     | 200ms  | 1s     | 3s     | API endpoints               |
| ArgoCD     | 100ms  | 500ms  | 2s     | `/api/v1/applications`      |
| Harbor     | 150ms  | 800ms  | 2s     | Registry pull/push          |

**Alertas:**
- **Critical:** P95 latency > SLO target × 2 por 10 minutos
- **Warning:** P95 latency > SLO target × 1.5 por 15 minutos

---

### 3. Error Rate (Taxa de Erros)

**Definição:** Percentual de requisições que resultam em erro (HTTP 5xx ou falhas internas).

**Fórmula:**
```
Error Rate = (5xx Responses + Timeouts) / Total Requests × 100%
```

**Medição:**
- **Fonte:** `http_requests_total` metric filtrado por status code
- **Query:**
  ```promql
  sum(rate(http_requests_total{status=~"5.."}[5m]))
  /
  sum(rate(http_requests_total[5m]))
  × 100
  ```

**SLO Targets:**

| Serviço    | Error Rate SLO | Success Rate SLO | Método                    |
|------------|----------------|------------------|---------------------------|
| Vault      | < 0.1%         | > 99.9%          | All API calls             |
| Keycloak   | < 0.5%         | > 99.5%          | Auth endpoints            |
| GitLab     | < 1.0%         | > 99.0%          | Git operations + Web UI   |
| ArgoCD     | < 0.5%         | > 99.5%          | Sync operations           |
| Harbor     | < 1.0%         | > 99.0%          | Registry operations       |

**Alertas:**
- **Critical:** Error rate > 5% por 5 minutos (any service)
- **Warning:** Error rate > SLO target × 2 por 10 minutos

**Exclusões:**
- HTTP 4xx client errors (não conta como erro do serviço)
- Requisições de health checks `/healthz`, `/readyz`

---

### 4. Saturation (Saturação de Recursos)

**Definição:** Utilização de recursos computacionais críticos (CPU, memória, disco, conexões).

**Métricas:**

#### 4.1 CPU Saturation
```promql
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

#### 4.2 Memory Saturation
```promql
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
```

#### 4.3 Disk Saturation (PVC Usage)
```promql
(kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) * 100
```

#### 4.4 Database Connections (PostgreSQL)
```promql
sum(pg_stat_database_numbackends) / pg_settings_max_connections * 100
```

**SLO Targets:**

| Recurso              | Warning | Critical | Ação                              |
|----------------------|---------|----------|-----------------------------------|
| Node CPU             | 75%     | 85%      | Scale horizontally                |
| Node Memory          | 80%     | 90%      | Add nodes or reduce workloads     |
| PVC Disk Usage       | 80%     | 90%      | Expand volume or cleanup          |
| PostgreSQL Conn      | 70%     | 85%      | Increase max_connections or pool  |
| Redis Memory         | 75%     | 90%      | Increase maxmemory or evict       |
| RabbitMQ Queue Depth | 10k msg | 50k msg  | Scale consumers                   |

**Alertas:**
- **Critical:** Saturation > critical threshold por 10 minutos
- **Warning:** Saturation > warning threshold por 15 minutos

---

### 5. Throughput (Taxa de Processamento)

**Definição:** Volume de requisições ou operações processadas por unidade de tempo.

**Métricas:**

#### 5.1 HTTP Requests per Second
```promql
sum(rate(http_requests_total[5m])) by (job)
```

#### 5.2 Git Operations per Minute
```promql
sum(rate(gitlab_transaction_duration_seconds_count{controller="Projects::GitHttpController"}[1m])) * 60
```

#### 5.3 Container Image Pulls per Hour
```promql
sum(rate(harbor_registry_http_request_duration_seconds_count{method="GET",path=~".*blobs.*"}[1h])) * 3600
```

#### 5.4 ArgoCD Sync Operations per Minute
```promql
sum(rate(argocd_app_sync_total[1m])) * 60
```

**SLO Targets (Baseline):**

| Serviço    | Metric                     | Baseline   | Peak Capacity | Alertas                     |
|------------|----------------------------|------------|---------------|-----------------------------|
| GitLab     | Git operations/min         | 50 ops/min | 200 ops/min   | > 180 ops/min (near limit)  |
| Harbor     | Image pulls/hour           | 100/h      | 500/h         | > 450/h (throttle warning)  |
| ArgoCD     | Sync operations/min        | 10/min     | 50/min        | > 45/min (sync storm)       |
| Vault      | Secret reads/sec           | 100/s      | 500/s         | > 450/s (rate limit risk)   |
| Keycloak   | Auth requests/sec          | 50/s       | 200/s         | > 180/s (token exhaustion)  |

**Alertas:**
- **Warning:** Throughput > 90% peak capacity por 10 minutos
- **Info:** Throughput < 10% baseline por 30 minutos (possível problema upstream)

---

## 🎯 SLO Compliance Tracking

### Error Budget Calculation

**Formula:**
```
Error Budget = (1 - SLO) × Total Requests
```

**Exemplo (GitLab - 98% SLO):**
- **Total requests/mês:** 10M
- **SLO:** 98% success rate
- **Error budget:** 2% × 10M = 200k failed requests
- **Current errors:** 50k
- **Budget remaining:** 75% (150k/200k)

### Budget Policies

| Budget Remaining | Action                                      |
|------------------|---------------------------------------------|
| > 75%            | ✅ Green - Innovation allowed               |
| 50-75%           | ⚠️ Yellow - Caution, review deployments     |
| 25-50%           | 🔴 Red - Freeze non-critical changes        |
| < 25%            | 🚨 Critical - Emergency mode, rollback only |

---

## 📈 Dashboards de Monitoramento

### 1. **SLI Overview Dashboard**
- **Grafana URL:** `/d/sli-overview`
- **Painéis:**
  - Availability heatmap (últimas 24h)
  - Latency percentiles (P50/P95/P99) por serviço
  - Error rate timeseries
  - Saturation gauges (CPU, mem, disk, conn)
  - Throughput rate graphs

### 2. **Error Budget Dashboard**
- **Grafana URL:** `/d/error-budget`
- **Painéis:**
  - Error budget burn rate (atual)
  - Budget remaining (% por serviço)
  - Projected budget exhaustion date
  - Historical budget consumption

### 3. **Service-Specific Dashboards**
- GitLab SLI Dashboard: `/d/gitlab-sli`
- ArgoCD SLI Dashboard: `/d/argocd-sli`
- Harbor SLI Dashboard: `/d/harbor-sli`
- Vault SLI Dashboard: `/d/vault-sli`
- Keycloak SLI Dashboard: `/d/keycloak-sli`

---

## 🔔 Alertmanager Configuration

### Alert Routing

```yaml
route:
  group_by: ['alertname', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'sre-team'

  routes:
    # Critical SLO violations
    - match:
        severity: critical
        alert_type: slo_violation
      receiver: 'pagerduty-critical'
      continue: true

    # Warning SLO violations
    - match:
        severity: warning
        alert_type: slo_violation
      receiver: 'teams-sre'

    # Saturation warnings
    - match:
        alert_type: saturation
      receiver: 'teams-capacity'
```

### Critical Alerts (10 Alertas Obrigatórios)

1. **ServiceDown** - Availability < 95% por 5min
2. **HighLatencyP95** - Latency P95 > SLO × 2 por 10min
3. **HighErrorRate5xx** - Error rate > 5% por 5min
4. **NodeCPUHigh** - CPU > 85% por 10min
5. **NodeMemoryHigh** - Memory > 90% por 10min
6. **PVCDiskFull** - Disk usage > 90%
7. **PostgreSQLConnHigh** - Connections > 85% por 5min
8. **ErrorBudgetExhausted** - Error budget < 10%
9. **PrometheusTargetDown** - Scrape target down > 5min
10. **AlertmanagerDown** - Alertmanager unreachable

---

## 📝 Revisão e Manutenção

### Cadência de Revisão

| Frequência | Atividade                                    | Responsável |
|------------|----------------------------------------------|-------------|
| Semanal    | Review error budget burn rate               | SRE On-call |
| Quinzenal  | Adjust SLO targets baseado em dados reais   | SRE Lead    |
| Mensal     | SLO compliance report (para stakeholders)   | SRE Lead    |
| Trimestral | Revisão completa de SLIs/SLOs               | SRE Team    |

### Histórico de Mudanças

| Data       | Versão | Mudança                           | Autor     |
|------------|--------|-----------------------------------|-----------|
| 2026-02-10 | 1.0    | Criação inicial - GAP-001         | SRE Team  |

---

## 🔗 Referências

- [Google SRE Book - Chapter 4: Service Level Objectives](https://sre.google/sre-book/service-level-objectives/)
- [Prometheus Best Practices - Alerting](https://prometheus.io/docs/practices/alerting/)
- [GAP-001: Observabilidade/SRE](../plan/gaps-execution-roadmap.md#gap-001)
- [Alertmanager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)

---

**Status:** ✅ SLIs definidos, aguardando validação de alertas
**Próxima Ação:** Validar 10 alertas críticos no Alertmanager (GAP-001 fase 2)

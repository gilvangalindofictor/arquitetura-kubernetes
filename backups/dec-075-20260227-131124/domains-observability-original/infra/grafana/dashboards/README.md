# Grafana Dashboards - SLI/SLO Monitoring (GAP-001)

## Overview

Este diretório contém os dashboards Grafana para monitoramento de SLI/SLO do ambiente de staging Kubernetes, implementados como parte do **GAP-001: Observabilidade/SRE**.

## Dashboards Disponíveis

### 1. SLI Overview Dashboard (`sli-overview-dashboard.json`)

**UID:** `sli-overview`
**Descrição:** Dashboard principal consolidando todos os SLIs dos serviços críticos.

**Painéis Incluídos:**
- **Availability Gauges (24h):** Disponibilidade de Vault, GitLab, ArgoCD, Harbor e Keycloak
- **Service Availability Heatmap:** Visualização temporal da disponibilidade nas últimas 24h
- **Latency P50/P95/P99 Graphs:** Latências percentis separadas por serviço (GitLab/ArgoCD vs Vault/Harbor)
- **Error Rate Timeseries (5xx):** Taxa de erros HTTP 5xx para todos os serviços
- **Saturation Gauges:**
  - Node CPU Saturation
  - Node Memory Saturation
  - PostgreSQL Connections Saturation
  - PVC Disk Saturation
- **Throughput Graphs:**
  - HTTP Requests/sec por serviço
  - Service-specific operations (Git ops, ArgoCD syncs, Harbor pulls)

**Refresh Rate:** 30 segundos
**Time Range:** Últimas 6 horas

---

### 2. Error Budget Dashboard (`error-budget-dashboard.json`)

**UID:** `error-budget`
**Descrição:** Dashboard dedicado ao tracking e análise de error budget consumption.

**Painéis Incluídos:**
- **Error Budget Stats (30d):** Percentual de budget restante para cada serviço
  - Vault (SLO: 99.5%)
  - GitLab (SLO: 98.0%)
  - ArgoCD (SLO: 98.0%)
  - Harbor (SLO: 97.0%)
  - Keycloak (SLO: 99.0%)
- **Error Budget Burn Rate:** Taxa atual de consumo vs taxa sustentável (threshold = 1.0)
- **Budget Remaining % Timeseries:** Evolução do budget restante ao longo de 30 dias
- **Historical Budget Consumption:** Consumo de budget agregado semanalmente (30 dias)
- **Projected Budget Exhaustion:** Estimativa de dias até esgotamento do budget baseado na burn rate atual

**Alertas Configurados:**
- **Error Budget Exhausted:** Dispara quando budget restante < 10%

**Refresh Rate:** 1 minuto
**Time Range:** Últimos 7 dias (padrão)

---

### 3. GitLab SLI Dashboard (`gitlab-sli-dashboard.json`)

**UID:** `gitlab-sli`
**Descrição:** Dashboard específico para métricas SLI do GitLab.

**Painéis Incluídos:**
- **SLO Gauges:**
  - Availability (SLO: 98%)
  - P95 Latency (SLO: 1s)
  - Error Rate (SLO: <1%)
- **SLO Compliance Status (24h):** Pie chart mostrando tempo em compliance vs violated
- **Request Latency Percentiles:** P50/P95/P99 com threshold SLO
- **HTTP Status Codes Distribution:** Distribuição de 2xx/4xx/5xx responses
- **Request Rate by HTTP Method:** Throughput segregado por método HTTP
- **Git Operations Throughput:** Git operations/min (SLO baseline: 50/min, peak: 200/min)
- **Recent Alerts:** Tabela com alertas ativos relacionados ao GitLab
- **Resource Saturation:**
  - CPU Saturation (pods)
  - Memory Saturation (pods)
  - PostgreSQL Connections
  - PVC Disk Usage

**Links Externos:**
- Loki Logs (namespace: gitlab)

**Refresh Rate:** 30 segundos
**Time Range:** Últimas 6 horas

---

### 4. ArgoCD SLI Dashboard (`argocd-sli-dashboard.json`)

**UID:** `argocd-sli`
**Descrição:** Dashboard específico para métricas SLI do ArgoCD.

**Painéis Incluídos:**
- **SLO Gauges:**
  - Availability (SLO: 98%)
  - P95 Latency (SLO: 500ms)
  - Error Rate (SLO: <0.5%)
- **SLO Compliance Status (24h):** Pie chart mostrando tempo em compliance vs violated
- **API Request Latency Percentiles:** P50/P95/P99 com threshold SLO
- **Sync Operations Throughput:** Sync ops/min (SLO baseline: 10/min, peak: 50/min)
- **Sync Operations by Status:** Distribuição de syncs (Success/Failed/Error)
- **Application Sync Status:** Count de apps Synced/OutOfSync/Unknown
- **Recent Alerts:** Tabela com alertas ativos relacionados ao ArgoCD
- **Resource Saturation:**
  - CPU Saturation (pods)
  - Memory Saturation (pods)
- **Application Stats:**
  - Total Managed Applications
  - Unhealthy Applications

**Links Externos:**
- ArgoCD UI

**Refresh Rate:** 30 segundos
**Time Range:** Últimas 6 horas

---

### 5. Vault SLI Dashboard (`vault-sli-dashboard.json`)

**UID:** `vault-sli`
**Descrição:** Dashboard específico para métricas SLI do HashiCorp Vault.

**Painéis Incluídos:**
- **SLO Gauges:**
  - Availability (SLO: 99.5%)
  - P95 Latency (SLO: 200ms)
  - Error Rate (SLO: <0.1%)
- **SLO Compliance Status (24h):** Pie chart mostrando tempo em compliance vs violated
- **Request Latency Percentiles:** P50/P95/P99 com threshold SLO
- **Secret Operations Throughput:** Requests/sec (SLO baseline: 100/s, peak: 500/s)
- **Operations by Type:** Distribuição de read/write/delete/list operations
- **Vault Seal Status:** Timeseries mostrando estado Unsealed/Sealed por instância
- **Vault Raft Cluster Status:** Tabela com estado do cluster (Leader/Follower)
- **Recent Alerts:** Tabela com alertas ativos relacionados ao Vault
- **Resource Saturation:**
  - CPU Saturation (pods)
  - Memory Saturation (pods)
  - PVC Disk Usage
- **Cluster Health:**
  - Sealed Vault Instances (alerta se > 0)

**Links Externos:**
- Vault UI

**Refresh Rate:** 30 segundos
**Time Range:** Últimas 6 horas

---

## Deployment

### Método 1: Grafana ConfigMap (Recomendado)

```bash
# Criar ConfigMap com os dashboards
kubectl create configmap grafana-sli-dashboards \
  --from-file=sli-overview-dashboard.json \
  --from-file=error-budget-dashboard.json \
  --from-file=gitlab-sli-dashboard.json \
  --from-file=argocd-sli-dashboard.json \
  --from-file=vault-sli-dashboard.json \
  -n monitoring

# Adicionar label para auto-discovery do Grafana
kubectl label configmap grafana-sli-dashboards \
  grafana_dashboard=1 \
  -n monitoring
```

### Método 2: Grafana UI Import

1. Acesse Grafana: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80`
2. Navegue: **Dashboards** → **Import**
3. Faça upload do arquivo JSON ou copie/cole o conteúdo
4. Configure datasource: Prometheus
5. Clique em **Import**

### Método 3: Provisioning via Helm (Produção)

Adicionar ao `values.yaml` do kube-prometheus-stack:

```yaml
grafana:
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: 'sli-dashboards'
          orgId: 1
          folder: 'SLI/SLO Monitoring'
          type: file
          disableDeletion: false
          editable: true
          options:
            path: /var/lib/grafana/dashboards/sli-dashboards

  dashboards:
    sli-dashboards:
      sli-overview:
        file: dashboards/sli-overview-dashboard.json
      error-budget:
        file: dashboards/error-budget-dashboard.json
      gitlab-sli:
        file: dashboards/gitlab-sli-dashboard.json
      argocd-sli:
        file: dashboards/argocd-sli-dashboard.json
      vault-sli:
        file: dashboards/vault-sli-dashboard.json
```

## Datasource Configuration

Todos os dashboards utilizam a variável `${DS_PROMETHEUS}` que deve apontar para:

- **Name:** Prometheus
- **Type:** Prometheus
- **URL:** `http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090`

## Validação

### Verificar Dashboards Importados

```bash
# Via Grafana API
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

curl -H "Authorization: Bearer <GRAFANA_API_TOKEN>" \
  http://localhost:3000/api/search?type=dash-db | jq '.[] | select(.uid | startswith("sli") or . == "error-budget")'
```

### Testar Queries Prometheus

```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Testar query de availability
curl -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=avg_over_time(up{job="vault"}[24h]) * 100'

# Testar query de latency P95
curl -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=histogram_quantile(0.95, sum(rate(vault_core_handle_request_bucket[5m])) by (le))'
```

## Troubleshooting

### Dashboard não carrega dados

1. **Verificar datasource:**
   ```bash
   # Listar datasources no Grafana
   kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -- \
     grafana-cli admin data-sources list
   ```

2. **Verificar conectividade Prometheus:**
   ```bash
   kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -- \
     wget -qO- http://kube-prometheus-stack-prometheus.monitoring.svc:9090/-/healthy
   ```

3. **Verificar metrics disponíveis:**
   ```bash
   # Port-forward Prometheus
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

   # Verificar se metrics existem
   curl http://localhost:9090/api/v1/label/__name__/values | jq '.data[] | select(. | startswith("vault_"))'
   ```

### Painel mostra "No data"

- **Causa:** Métrica não existe ou naming incorreto
- **Fix:** Verificar ServiceMonitor e targets:
  ```bash
  # Verificar targets ativos no Prometheus
  kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
  # Acessar: http://localhost:9090/targets
  ```

### Error "template variables could not be initialized"

- **Causa:** Query de template retornou vazio
- **Fix:** Verificar se labels existem nas métricas ou simplificar query

## Referências

- [SLI/SLO Definitions](../../../../docs/operations/sli-slo-definitions.md)
- [Custom SLI Alerts](../../monitoring/custom-sli-alerts.yaml)
- [GAP-001 Roadmap](../../../../docs/plan/gaps-execution-roadmap.md#gap-001)
- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/best-practices/)
- [PromQL Documentation](https://prometheus.io/docs/prometheus/latest/querying/basics/)

---

**Versão:** 1.0
**Data:** 2026-02-10
**Status:** ✅ Implementado (GAP-001)
**Owner:** SRE Team

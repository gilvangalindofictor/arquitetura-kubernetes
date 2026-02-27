# Prometheus Queries Reference - Marco 4 Dashboards

Data: 2026-02-24
Dashboards: GitLab, ArgoCD, SonarQube, Keycloak

## Overview

Este documento lista todas as queries Prometheus utilizadas nos dashboards Marco 4, com explicações e troubleshooting.

**IMPORTANTE:** As queries assumem que os seguintes exporters/ServiceMonitors estão configurados:
- GitLab: GitLab Prometheus exporter (built-in)
- ArgoCD: ArgoCD metrics endpoint (built-in)
- SonarQube: SonarQube Prometheus exporter
- Keycloak: Keycloak metrics endpoint (Quarkus metrics)

---

## 1. GitLab CI/CD Overview

### 1.1 Pipeline Success Rate (24h)

```promql
sum(rate(gitlab_ci_pipeline_status{status="success"}[24h])) / sum(rate(gitlab_ci_pipeline_status[24h])) * 100
```

**Descrição:** Calcula a taxa de sucesso de pipelines nas últimas 24h.

**Métricas necessárias:**
- `gitlab_ci_pipeline_status{status="success"}` - Contador de pipelines com sucesso
- `gitlab_ci_pipeline_status` - Contador total de pipelines

**Troubleshooting:**
- Se retornar "No data": Verificar se GitLab está exportando métricas (`/metrics` endpoint)
- ServiceMonitor esperado: `gitlab-webservice` ou `gitlab-metrics`
- Alternativa Loki: `count_over_time({namespace="gitlab-staging"} |= "pipeline" |= "success" [24h])`

### 1.2 Pipeline Duration Percentiles

```promql
histogram_quantile(0.50, sum(rate(gitlab_ci_pipeline_duration_seconds_bucket[5m])) by (le))  # p50
histogram_quantile(0.95, sum(rate(gitlab_ci_pipeline_duration_seconds_bucket[5m])) by (le))  # p95
histogram_quantile(0.99, sum(rate(gitlab_ci_pipeline_duration_seconds_bucket[5m])) by (le))  # p99
```

**Descrição:** Calcula os percentis 50, 95 e 99 da duração de pipelines.

**Métricas necessárias:**
- `gitlab_ci_pipeline_duration_seconds_bucket` - Histograma de duração de pipelines

**Troubleshooting:**
- Histogram não disponível? Usar `avg(gitlab_ci_pipeline_duration_seconds)` como fallback
- Valores sempre zero: GitLab pode estar usando métrica diferente (`gitlab_transaction_duration_seconds`)

### 1.3 Runner Utilization

```promql
sum(gitlab_ci_runner_jobs{state="running"}) / sum(gitlab_ci_runner_limit) * 100
```

**Descrição:** Percentual de utilização dos GitLab Runners.

**Métricas necessárias:**
- `gitlab_ci_runner_jobs{state="running"}` - Jobs atualmente rodando
- `gitlab_ci_runner_limit` - Capacidade total de runners

**Troubleshooting:**
- Métrica não existe: GitLab Runner pode não estar exportando métricas
- Verificar ConfigMap `gitlab-runner` para habilitar `/metrics` endpoint
- Porta esperada: 9252 (runner metrics)

### 1.4 Build Queue Time

```promql
avg(gitlab_ci_queue_time_seconds)
max(gitlab_ci_queue_time_seconds)
```

**Descrição:** Tempo médio e máximo que jobs ficam na fila.

**Métricas necessárias:**
- `gitlab_ci_queue_time_seconds` - Tempo de fila por job

**Alternativa:**
```promql
gitlab_runner_jobs{state="pending"} * on() group_right() gitlab_runner_job_wait_seconds
```

### 1.5 GitLab API Response Time

```promql
histogram_quantile(0.95, sum(rate(gitlab_http_request_duration_seconds_bucket[5m])) by (le))
```

**Descrição:** Tempo de resposta p95 da API do GitLab.

**Métricas necessárias:**
- `gitlab_http_request_duration_seconds_bucket` - Histograma de requests HTTP

**Troubleshooting:**
- GitLab < 13.x usa `http_request_duration_seconds` (sem prefixo `gitlab_`)
- Filtrar por endpoint: `{endpoint="/api/v4/projects"}`

### 1.6 Top 10 Failed Pipelines by Project

```promql
topk(10, sum(increase(gitlab_ci_pipeline_status{status="failed"}[24h])) by (project))
```

**Descrição:** Top 10 projetos com mais falhas de pipeline.

**Métricas necessárias:**
- `gitlab_ci_pipeline_status{status="failed"}` - Falhas de pipeline com label `project`

**Troubleshooting:**
- Label `project` não existe: Usar `{job}` ou `{namespace}` como fallback
- GitLab SaaS: Métrica pode ser `gitlab_ci_pipelines_failed_total`

---

## 2. ArgoCD Sync Status

### 2.1 Application Sync Status Counts

```promql
count(argocd_app_info{sync_status="Synced"})
count(argocd_app_info{sync_status="OutOfSync"})
count(argocd_app_info{health_status="Degraded"})
```

**Descrição:** Conta aplicações por status de sync e saúde.

**Métricas necessárias:**
- `argocd_app_info{sync_status, health_status}` - Info metric com labels de status

**Troubleshooting:**
- Métrica não existe: ArgoCD < 2.0 usa `argocd_app_sync_status`
- Verificar ServiceMonitor: `argocd-metrics` porta 8082

### 2.2 Sync Success Rate

```promql
sum(rate(argocd_app_sync_total{phase="Succeeded"}[5m])) / sum(rate(argocd_app_sync_total[5m])) * 100
```

**Descrição:** Taxa de sucesso de operações de sync.

**Métricas necessárias:**
- `argocd_app_sync_total{phase}` - Contador de syncs por fase

**Fases possíveis:**
- `Succeeded` - Sync com sucesso
- `Failed` - Sync falhou
- `Error` - Erro durante sync

### 2.3 Sync Duration Percentiles

```promql
histogram_quantile(0.50, sum(rate(argocd_app_reconcile_duration_seconds_bucket[5m])) by (le))
histogram_quantile(0.95, sum(rate(argocd_app_reconcile_duration_seconds_bucket[5m])) by (le))
histogram_quantile(0.99, sum(rate(argocd_app_reconcile_duration_seconds_bucket[5m])) by (le))
```

**Descrição:** Duração de reconciliação (sync) por percentil.

**Métricas necessárias:**
- `argocd_app_reconcile_duration_seconds_bucket` - Histograma de duração de reconcile

**Alternativa (ArgoCD < 2.5):**
```promql
histogram_quantile(0.95, sum(rate(argocd_app_sync_duration_seconds_bucket[5m])) by (le))
```

### 2.4 Application Status by Namespace

```promql
argocd_app_info
```

**Descrição:** Info metric com todos os labels (name, namespace, sync_status, health_status).

**Labels disponíveis:**
- `name` - Nome da aplicação
- `dest_namespace` - Namespace de destino
- `sync_status` - Synced, OutOfSync, Unknown
- `health_status` - Healthy, Progressing, Degraded, Suspended, Missing

**Transformação no Grafana:**
- Usar "Table" panel
- Organizar colunas: Excluir `__name__`, `instance`, `job`
- Renomear: `dest_namespace` → Namespace, `name` → Application

### 2.5 Recent Sync Errors

```promql
topk(10, sum(increase(argocd_app_sync_total{phase=~"Failed|Error"}[1h])) by (name, namespace))
```

**Descrição:** Top 10 aplicações com erros de sync na última hora.

**Troubleshooting:**
- Poucos erros? Aumentar janela para `[24h]`
- Complementar com logs Loki: `{namespace="argocd"} |= "sync" |= "error"`

---

## 3. SonarQube Code Quality Metrics

**NOTA IMPORTANTE:** SonarQube **NÃO** possui exporter Prometheus nativo. As queries abaixo assumem:

1. **Opção A:** SonarQube Prometheus Exporter (community):
   - https://github.com/dmeiners88/sonarqube-prometheus-exporter
   - Deploy como sidecar ou standalone

2. **Opção B:** Queries via Loki (fallback):
   - Parsear webhooks do SonarQube
   - Usar log aggregation

### 3.1 Total Projects Analyzed

```promql
count(sonarqube_project_info)
```

**Métrica assumida:**
- `sonarqube_project_info` - Info metric com labels `{project, version, quality_gate_status}`

**Alternativa sem exporter:**
- API Query via Grafana Infinity datasource: `GET /api/components/search?qualifiers=TRK`
- Loki: `count(count_over_time({source="sonarqube-webhook"} |= "analysis" [24h]) by (project))`

### 3.2 Quality Gate Status

```promql
count(sonarqube_project_quality_gate{status="PASSED"})
count(sonarqube_project_quality_gate{status="FAILED"})
```

**Métrica assumida:**
- `sonarqube_project_quality_gate{status}` - Gauge com status por projeto

**Alternativa API:**
```bash
curl -u $TOKEN: 'https://sonarqube.example.com/api/qualitygates/project_status?projectKey=my-project'
```

### 3.3 Code Coverage Trend

```promql
avg(sonarqube_project_coverage)
```

**Métrica assumida:**
- `sonarqube_project_coverage` - Gauge de cobertura por projeto (0-100)

**Métricas relacionadas:**
- `sonarqube_project_lines_to_cover`
- `sonarqube_project_uncovered_lines`

### 3.4 Issues Count (Bugs, Vulnerabilities, Code Smells)

```promql
sum(sonarqube_project_bugs)
sum(sonarqube_project_vulnerabilities)
sum(sonarqube_project_code_smells)
```

**Métricas assumidas:**
- `sonarqube_project_bugs` - Contador de bugs
- `sonarqube_project_vulnerabilities` - Contador de vulnerabilidades
- `sonarqube_project_code_smells` - Contador de code smells

**Severidades (se disponível):**
```promql
sum(sonarqube_project_bugs{severity="BLOCKER"})
sum(sonarqube_project_bugs{severity="CRITICAL"})
```

### 3.5 Technical Debt Ratio

```promql
avg(sonarqube_project_technical_debt_ratio)
```

**Métrica assumida:**
- `sonarqube_project_technical_debt_ratio` - Percentual de dívida técnica

**Cálculo manual (se métrica não existir):**
```promql
avg(sonarqube_project_sqale_index / sonarqube_project_development_cost) * 100
```

Onde:
- `sqale_index` = Technical debt (minutos)
- `development_cost` = Custo de desenvolvimento (minutos)

### 3.6 Analysis Duration

```promql
avg(sonarqube_project_analysis_duration_seconds)
max(sonarqube_project_analysis_duration_seconds)
```

**Métrica assumida:**
- `sonarqube_project_analysis_duration_seconds` - Duração da última análise

**Troubleshooting:**
- Métrica não existe: Exporter pode não capturar timings
- Alternativa: Parsear logs do SonarQube Scanner via Loki

---

## 4. Keycloak SSO Usage

### 4.1 Active Sessions

```promql
sum(keycloak_active_sessions{realm="platform"})
sum(keycloak_active_sessions{realm="platform"}) by (client_id)
```

**Descrição:** Total de sessões ativas por realm e client.

**Métricas necessárias:**
- `keycloak_active_sessions{realm, client_id}` - Gauge de sessões ativas

**Troubleshooting:**
- Keycloak < 26: Métrica pode ser `keycloak_sessions`
- Verificar endpoint: `https://keycloak.example.com/auth/realms/master/metrics` (requer autenticação)
- ServiceMonitor esperado: Porta 8080 ou 9990 (management)

### 4.2 Login Success Rate

```promql
sum(rate(keycloak_login_attempts{result="success"}[5m])) / sum(rate(keycloak_login_attempts[5m])) * 100
```

**Descrição:** Taxa de sucesso de logins.

**Métricas necessárias:**
- `keycloak_login_attempts{result}` - Contador de tentativas de login

**Valores de `result`:**
- `success` - Login bem-sucedido
- `invalid_credentials` - Credenciais inválidas
- `user_not_found` - Usuário não encontrado
- `account_disabled` - Conta desabilitada

**Alternativa (Keycloak Events):**
```promql
sum(rate(keycloak_events_total{type="LOGIN"}[5m]))
```

### 4.3 Token Issuance Rate

```promql
sum(rate(keycloak_token_issued_total[5m]))
```

**Descrição:** Taxa de emissão de tokens (access, refresh, ID).

**Métricas necessárias:**
- `keycloak_token_issued_total{token_type}` - Contador de tokens emitidos

**Token types:**
- `access_token`
- `refresh_token`
- `id_token`

**Por client:**
```promql
sum(rate(keycloak_token_issued_total[5m])) by (client_id)
```

### 4.4 Failed Login Attempts (Security)

```promql
sum(rate(keycloak_login_attempts{result="failed"}[5m]))
sum(rate(keycloak_login_attempts{result="invalid_credentials"}[5m]))
```

**Descrição:** Tentativas de login falhadas (segurança).

**Alerta recomendado:**
```promql
sum(rate(keycloak_login_attempts{result="failed"}[1m])) > 10
```

**Complementar com Loki:**
```logql
{namespace="keycloak"} |= "LOGIN_ERROR" | json | line_format "{{.username}} from {{.ipAddress}}"
```

### 4.5 JVM Memory and CPU

```promql
# Memory
process_resident_memory_bytes{job="keycloak"} / process_virtual_memory_max_bytes{job="keycloak"} * 100
jvm_memory_used_bytes{job="keycloak", area="heap"}
jvm_memory_max_bytes{job="keycloak", area="heap"}

# CPU
rate(process_cpu_seconds_total{job="keycloak"}[5m]) * 100
```

**Descrição:** Métricas de JVM do Keycloak (Quarkus).

**Métricas disponíveis:**
- `jvm_memory_used_bytes{area="heap|nonheap"}`
- `jvm_memory_committed_bytes`
- `jvm_gc_collection_seconds_count` - GC count
- `jvm_gc_collection_seconds_sum` - GC time

**Troubleshooting:**
- Métricas não aparecem: Verificar se Keycloak tem metrics habilitado
- Quarkus config: `quarkus.http.non-application-root-path=/q` → métricas em `/q/metrics`

### 4.6 Request Duration

```promql
histogram_quantile(0.95, sum(rate(keycloak_request_duration_seconds_bucket[5m])) by (le))
histogram_quantile(0.99, sum(rate(keycloak_request_duration_seconds_bucket[5m])) by (le))
```

**Descrição:** Latência de requests HTTP (p95, p99).

**Métricas necessárias:**
- `keycloak_request_duration_seconds_bucket` - Histograma de duração de requests

**Por endpoint:**
```promql
histogram_quantile(0.95, sum(rate(keycloak_request_duration_seconds_bucket{uri="/auth/realms/platform/protocol/openid-connect/token"}[5m])) by (le))
```

---

## Troubleshooting Geral

### 1. Nenhuma métrica aparece nos dashboards

**Checklist:**
1. Verificar Prometheus scraping targets:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
   # Acessar http://localhost:9090/targets
   ```

2. Verificar ServiceMonitors:
   ```bash
   kubectl get servicemonitors -A | grep -E 'gitlab|argocd|sonarqube|keycloak'
   ```

3. Verificar labels dos Services:
   ```bash
   kubectl get svc -A -l prometheus.io/scrape=true
   ```

4. Verificar logs do Prometheus:
   ```bash
   kubectl logs -n monitoring prometheus-0 -c prometheus | grep -E 'error|failed'
   ```

### 2. Métricas existem mas query retorna "No data"

**Possíveis causas:**
- **Label mismatch:** Query usa `{job="gitlab"}` mas métrica tem `{job="gitlab-webservice"}`
  - Solução: Usar regex `{job=~"gitlab.*"}`

- **Time range incorreto:** Dashboard usa `[5m]` mas dados são gerados a cada 1h
  - Solução: Ajustar time range para `[1h]` ou `[24h]`

- **Aggregation vazia:** `sum() by (label)` retorna vazio se label não existe
  - Solução: Remover `by (label)` ou usar `without (instance)`

### 3. Dashboards mostram valores sempre zero

**Possíveis causas:**
- **Counter reset:** Container reiniciou, contador resetou para zero
  - Solução: Usar `increase()` ou `rate()` para calcular delta

- **Gauge não atualizado:** Métrica é gauge mas aplicação não está atualizando
  - Solução: Verificar logs da aplicação, pode ser bug no exporter

### 4. SonarQube/GitLab não têm exporter configurado

**Alternativas:**

#### A. Usar API datasource (Grafana Infinity plugin)
```yaml
datasource: Infinity
url: https://sonarqube.example.com/api/measures/component
params:
  component: my-project
  metricKeys: bugs,vulnerabilities,code_smells
parser: json
```

#### B. Usar Loki queries
```logql
# SonarQube analysis results
{source="sonarqube"} |= "analysis" | json | unwrap bugs | sum_over_time([1h])

# GitLab pipeline status
{namespace="gitlab-staging"} |= "pipeline" |= "status" | json | count_over_time([1h])
```

#### C. Deploy custom exporter
- GitLab: https://github.com/mvisonneau/gitlab-ci-pipelines-exporter
- SonarQube: https://github.com/dmeiners88/sonarqube-prometheus-exporter

---

## Métricas Esperadas por Serviço

### GitLab (built-in exporter)
- Porta: 8080 (webservice), 9168 (sidekiq)
- Endpoint: `/-/metrics` ou `/metrics`
- Métricas key: `gitlab_*`, `http_request_*`, `ruby_*`

### ArgoCD (built-in metrics)
- Porta: 8082 (metrics)
- Endpoint: `/metrics`
- Métricas key: `argocd_app_*`, `argocd_cluster_*`

### SonarQube (exporter community)
- Porta: 9000 (API) ou 9119 (exporter)
- Endpoint: `/api/measures/*` (API) ou `/metrics` (exporter)
- Métricas key: `sonarqube_*` (exporter), API JSON (direto)

### Keycloak (Quarkus metrics)
- Porta: 8080 (HTTP) ou 9990 (management)
- Endpoint: `/q/metrics` ou `/auth/realms/master/metrics`
- Métricas key: `keycloak_*`, `jvm_*`, `process_*`

---

## Referências

- [GitLab Metrics Documentation](https://docs.gitlab.com/ee/administration/monitoring/prometheus/)
- [ArgoCD Metrics](https://argo-cd.readthedocs.io/en/stable/operator-manual/metrics/)
- [Keycloak Metrics (Quarkus)](https://www.keycloak.org/server/configuration-metrics)
- [Prometheus Query Functions](https://prometheus.io/docs/prometheus/latest/querying/functions/)
- [PromQL Best Practices](https://prometheus.io/docs/practices/naming/)

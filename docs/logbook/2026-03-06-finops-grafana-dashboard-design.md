# FinOps Grafana Dashboard — Design e Bloqueador de Arquitetura

**Data:** 2026-03-06
**Status:** IMPLEMENTADO — aguardando apply + Teams webhook (DT-005)
**Contexto:** Demanda de visibilidade financeira AWS no Grafana (custo dia a dia, forecast, por recurso, por app)

---

## Decisao de Arquitetura

### Data source escolhido: Prometheus (via CronJob K8s → Pushgateway)

Apos avaliacao tecnica (FinOps Specialist + Observability Specialist), a arquitetura definida foi:

```
CronJob K8s (a cada 6h)
  → boto3 → AWS Cost Explorer API
  → POST → Prometheus Pushgateway (cluster-internal)
  → Prometheus scrape
  → Grafana dashboards + PrometheusRules alertas
```

**Alternativas descartadas:**

| Opcao | Motivo da descarte |
|-------|--------------------|
| CloudWatch `AWS/Billing` (datasource existente) | Granularidade mensal apenas — sem breakdown diario por tag `app=` |
| CUR + S3 + Athena | Overkill para staging ($900/mes); requer CUR habilitado + S3 + Glue Crawler; nao temos CUR ativo |
| `grafana-aws-datasource` plugin direto | Incerteza sobre disponibilidade em Grafana OSS self-hosted; sem suporte nativo Cost Explorer no plugin open-source |
| Lambda → Pushgateway | Bloqueador de networking (ver secao abaixo) |

### Por que Prometheus e nao CloudWatch Custom Metrics

Alertas do projeto usam PrometheusRules + Alertmanager. Usar CloudWatch Custom Metrics para visualizacao exigiria CloudWatch Alarms para alertas — dois sistemas de alertas em paralelo. Prometheus unifica visualizacao e alertas no mesmo ecossistema ja existente.

---

## Metricas Geradas pelo Exporter

| Metrica | Labels | Descricao |
|---------|--------|-----------|
| `aws_cost_daily_usd` | `service, date, environment` | Custo diario por servico AWS |
| `aws_cost_mtd_usd` | `service, environment` | Month-to-date por servico |
| `aws_cost_forecast_usd` | `environment` | Projecao total do mes corrente |
| `aws_cost_by_tag_usd` | `app, environment` | Custo MTD por tag `app=` |
| `aws_budget_limit_usd` | `environment` | Limite do budget ($807/mes staging) |
| `aws_budget_actual_usd` | `environment` | Gasto real MTD vs budget |

**Frequencia de coleta:** A cada 6h (cron `0 */6 * * ? *`)
**Custo CE API:** ~120 chamadas/mes — dentro do free tier de 1.000/mes ($0 adicional)

---

## Artefatos Implementados (2026-03-06)

### Criados

| Arquivo | Descricao |
|---------|-----------|
| `modules/finops-cost-exporter/main.tf` | Lambda + IAM Role (ce:GetCostAndUsage, ce:GetCostForecast, budgets:ViewBudget) + EventBridge cron 6h |
| `modules/finops-cost-exporter/variables.tf` | Variaveis: cluster_name, pushgateway_url, budget_limit_usd (default 807), etc. |
| `modules/finops-cost-exporter/outputs.tf` | Outputs: lambda_arn, role_arn, eventbridge_rule_arn |
| `modules/finops-cost-exporter/lambda/cost_exporter.py` | Python 3.12, 6 tipos de metrica, push via urllib para Pushgateway |
| `modules/observability/grafana-dashboards/finops-aws-visibility.json` | Dashboard 21 panels + 5 row dividers, Grafana 10.x valido |
| `modules/observability/prometheus-alerts/finops-cost-alerts.yaml` | PrometheusRule com 4 alertas |

### Modificados

| Arquivo | Modificacao |
|---------|-------------|
| `modules/kube-prometheus-stack/main.tf` | 2 set{} blocks: prometheus-pushgateway.enabled=true + serviceMonitor.enabled=true |
| `modules/observability/main.tf` | +2 resources: ConfigMap finops-visibility + kubectl_manifest finops-cost-alerts |
| `environments/staging/main.tf` | Module `finops_cost_exporter` adicionado ao final |

### Dashboard — Estrutura (21 panels, 6 rows)

| Row | Panels | Tipo |
|-----|--------|------|
| Visao Executiva | MTD USD/BRL, % Budget gauge, Forecast USD/BRL, Budget Restante, Custo Ontem, Media 7d, Dias p/ Estourar, Burn Rate | Stat + Gauge |
| Custo Dia a Dia | TimeSeries stacked por servico + BarChart Top Servicos MTD | TimeSeries + BarChart |
| Breakdown por Servico | Table MTD + PieChart distribuicao | Table + PieChart |
| Custo por App (tag app=) | BarChart horizontal + Table + TimeSeries top-5 apps | Mixed |
| Forecast e Projecao | TimeSeries real vs budget/dia + Stats BRL + Heatmap 30d | Mixed |
| Info | Text panel com info sobre fonte, latencia, budget | Text |

### Alertas PrometheusRule

| Alerta | Condicao | Severidade |
|--------|----------|------------|
| `FinOpsBudgetBreach` | `aws_budget_actual_usd > aws_budget_limit_usd` | critical |
| `FinOpsBudgetWarning80pct` | `(actual / limit) > 0.80` | warning |
| `FinOpsDailyCostAnomaly` | custo ontem > media 7d × 1.5 | warning |
| `FinOpsForecastBreach` | forecast > budget × 1.10 | warning |

Labels: `channel: finops-aws, team: platform` — prontos para roteamento Alertmanager apos DT-005.

---

## Bloqueador Identificado — Lambda nao Alcanca Pushgateway

**Problema:** A Lambda foi implementada inicialmente como funcao AWS Lambda externa ao cluster. A variavel `pushgateway_url` foi configurada com DNS interno do cluster:

```
http://kube-prometheus-stack-prometheus-pushgateway.staging-observability-monitoring.svc.cluster.local:9091
```

DNS `.svc.cluster.local` so resolve **dentro do cluster Kubernetes**. Uma Lambda fora do cluster nao resolve esse endereco, mesmo estando na mesma VPC. O DNS de servicos K8s e gerenciado pelo CoreDNS interno — nao e exposto ao DNS da VPC.

**Opcoes avaliadas:**

| Opcao | Complexidade | Custo Adicional | Decisao |
|-------|-------------|-----------------|---------|
| Lambda na VPC + NodePort do Pushgateway | Media | $0 (ENI gratis em t3) | Descartada — NodePort expoe porta em todos os nos, foge do padrao |
| Lambda na VPC + ALB interno → Pushgateway | Alta | +~$16/mes ALB | Descartada — custo injustificado |
| Lambda → CloudWatch Custom Metrics | Baixa | +~$0.30/mes | Descartada — nao integra PrometheusRules |
| **CronJob K8s + IRSA (recomendada)** | Baixa | $0 | **ESCOLHIDA** |

---

## Proxima Acao: Refatorar Lambda → CronJob K8s com IRSA

### Racional da decisao

CronJob K8s roda dentro do cluster → acessa Pushgateway via DNS interno sem configuracao adicional. Usa o mesmo padrao IRSA ja estabelecido no projeto (Velero, Harbor, ESO usam IRSA). Sem custo de infraestrutura adicional — usa nodes ja existentes (workloads node group).

### O que muda

| Componente | Lambda (atual) | CronJob K8s (refatoracao) |
|------------|---------------|--------------------------|
| Runtime | AWS Lambda Python 3.12 | Pod Python 3.12 (imagem slim) |
| IAM | IAM Role com Lambda trust | IRSA (ServiceAccount + annotation `eks.amazonaws.com/role-arn`) |
| Trigger | EventBridge cron `0 */6 * * ? *` | K8s CronJob `0 */6 * * *` |
| Networking | Fora do cluster — BLOQUEADO | Dentro do cluster — OK |
| Custo | $0 (dentro free tier Lambda) | $0 (usa node existente) |
| Codigo Python | Mesmo `cost_exporter.py` sem alteracoes | Mesmo codigo |

### Plano de refatoracao

1. Remover `modules/finops-cost-exporter/` (Lambda + EventBridge)
2. Remover `module "finops_cost_exporter"` do `environments/staging/main.tf`
3. Criar `modules/finops-cost-exporter/main.tf` com:
   - `aws_iam_role` com trust policy para IRSA (EKS OIDC provider)
   - `aws_iam_role_policy` com mesmas permissoes CE (ce:GetCostAndUsage, ce:GetCostForecast, budgets:ViewBudget)
   - `kubernetes_service_account` com annotation IRSA
   - `kubernetes_config_map` com o script Python
   - `kubernetes_cron_job_v1` com schedule `0 */6 * * *`
4. Manter `cost_exporter.py` sem alteracoes (mesmo codigo)
5. `terraform plan` → confirmar zero drift nos recursos existentes

### Status atual dos artefatos

- Dashboard JSON: PRONTO — nao precisa alteracao (usa Prometheus datasource, independente do exporter)
- PrometheusRules: PRONTO — nao precisa alteracao
- `observability/main.tf`: PRONTO — nao precisa alteracao
- `kube-prometheus-stack/main.tf`: PRONTO (Pushgateway set blocks) — requer helm upgrade manual apos apply
- `finops-cost-exporter/main.tf`: REFATORAR (Lambda → CronJob)
- `environments/staging/main.tf`: REFATORAR (module call com novos inputs IRSA)

---

## Prerequisitos para Apply

1. Refatoracao Lambda → CronJob K8s concluida
2. `terraform init` no diretorio `environments/staging/`
3. `terraform plan` sem erros
4. `terraform apply`
5. Helm upgrade manual para ativar Pushgateway (lifecycle ignore_changes no kube-prometheus-stack):
   ```bash
   helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
     -n staging-observability-monitoring --reuse-values \
     --set "prometheus-pushgateway.enabled=true" \
     --set "prometheus-pushgateway.serviceMonitor.enabled=true"
   ```
6. Validar CronJob rodando: `kubectl get cronjob -n staging-observability-monitoring`
7. Executar job manual para validacao imediata:
   ```bash
   kubectl create job --from=cronjob/finops-cost-exporter finops-cost-exporter-manual \
     -n staging-observability-monitoring
   kubectl logs -n staging-observability-monitoring -l job-name=finops-cost-exporter-manual
   ```
8. Validar metricas no Prometheus: `sum(aws_cost_mtd_usd)`
9. Abrir Grafana → folder FinOps → dashboard "FinOps — AWS Cost Visibility"

---

## Bloqueadores Abertos

| ID | Bloqueador | Impacto | Status |
|----|-----------|---------|--------|
| B-001 | Lambda → CronJob refatoracao pendente | Apply bloqueado | PENDENTE |
| DT-005 | Teams webhook URL nao recebida | Alertas nao entregues ao canal #finops-aws | AGUARDANDO URL |

---

**Responsavel:** Platform Team
**Proximo review:** Apos refatoracao CronJob + recebimento URL Teams

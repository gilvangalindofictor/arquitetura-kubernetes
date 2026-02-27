# Marco 4 Dashboards - Grafana

Data: 2026-02-24
Status: ✅ Implementado
Gap: GAP-008 Monitoring & Dashboards Marco 4

## Overview

Este diretório contém os dashboards Grafana específicos para os serviços do **Marco 4** da plataforma K8s:

1. **GitLab CI/CD Overview** - Métricas de pipelines, runners e CI/CD
2. **ArgoCD Sync Status** - Status de sync, health e deployment tracking
3. **SonarQube Code Quality Metrics** - Quality gates, coverage, bugs, vulnerabilities
4. **Keycloak SSO Usage** - Sessões, logins, segurança e performance

## Dashboards Criados

| Dashboard | UID | Tags | Datasources |
|-----------|-----|------|-------------|
| GitLab CI/CD Overview | `gitlab-cicd-overview` | `marco4`, `gitlab`, `cicd` | Prometheus, Loki |
| ArgoCD Sync Status | `argocd-sync-status` | `marco4`, `argocd`, `sync` | Prometheus |
| SonarQube Code Quality Metrics | `sonarqube-quality-metrics` | `marco4`, `sonarqube`, `quality` | Prometheus |
| Keycloak SSO Usage | `keycloak-sso-usage` | `marco4`, `keycloak`, `sso`, `security` | Prometheus, Loki |

## Estrutura de Arquivos

```
marco4/
├── README.md                              # Este arquivo
├── PROMETHEUS-QUERIES.md                  # Referência completa de queries PromQL
├── apply-dashboards.sh                    # Script de deployment
├── marco4-dashboards-configmap.yaml       # ConfigMap template (Helm)
├── gitlab-cicd-overview.json              # Dashboard GitLab
├── argocd-sync-status.json                # Dashboard ArgoCD
├── sonarqube-quality-metrics.json         # Dashboard SonarQube
└── keycloak-sso-usage.json                # Dashboard Keycloak
```

## Deployment

### Opção 1: Script Automatizado (Recomendado)

```bash
cd /path/to/domains/observability/infra/grafana/dashboards/marco4/
./apply-dashboards.sh
```

O script:
1. Valida conexão com o cluster
2. Cria ConfigMaps a partir dos arquivos JSON
3. Aplica label `grafana_dashboard=1` para auto-import
4. Lista ConfigMaps criados

### Opção 2: Manual (kubectl)

```bash
# Criar ConfigMap para cada dashboard
kubectl create configmap gitlab-cicd-overview-dashboard \
  --from-file=gitlab-cicd-overview.json \
  --namespace=monitoring

kubectl label configmap gitlab-cicd-overview-dashboard \
  -n monitoring grafana_dashboard=1

# Repetir para cada dashboard
```

### Opção 3: Helm (Terraform/IaC)

Usar o arquivo `marco4-dashboards-configmap.yaml` como Helm template.

## Validação

### 1. Verificar Auto-Import no Grafana

Aguardar ~30 segundos após deployment, então:

1. Acessar Grafana UI
2. Navegar para **Dashboards** → **Browse**
3. Filtrar por tag: `marco4`
4. Verificar 4 dashboards listados

### 2. Verificar Dados nos Painéis

**Checklist por dashboard:**

#### GitLab CI/CD Overview
- [ ] Pipeline Success Rate mostra percentual (não "No data")
- [ ] Pipeline Duration mostra gráfico de linhas (p50, p95, p99)
- [ ] Runner Utilization mostra gauge com percentual
- [ ] Top 10 Failed Pipelines mostra tabela com projetos
- [ ] Recent Failed Jobs mostra logs do Loki

**Se "No data":**
- Verificar se GitLab está exportando métricas: `/metrics` endpoint
- Verificar ServiceMonitor: `kubectl get servicemonitors -n gitlab-staging`
- Consultar PROMETHEUS-QUERIES.md para alternativas

#### ArgoCD Sync Status
- [ ] Applications Synced/OutOfSync/Degraded mostram contadores
- [ ] Sync Success Rate mostra gauge
- [ ] Application Status by Namespace mostra tabela
- [ ] Sync Duration mostra histograma

**Se "No data":**
- Verificar ArgoCD metrics: `kubectl port-forward -n argocd svc/argocd-metrics 8082:8082`
- Acessar http://localhost:8082/metrics
- Verificar ServiceMonitor: `kubectl get servicemonitors -n argocd`

#### SonarQube Code Quality Metrics
- [ ] Total Projects Analyzed mostra contador
- [ ] Quality Gates Passed/Failed mostram stats
- [ ] Code Coverage Trend mostra gráfico
- [ ] Projects Quality Overview mostra tabela

**Se "No data":**
- SonarQube **NÃO** tem exporter nativo Prometheus
- **Opção A:** Deploy SonarQube Prometheus Exporter (community)
  - https://github.com/dmeiners88/sonarqube-prometheus-exporter
- **Opção B:** Usar Grafana Infinity plugin + SonarQube API
- **Opção C:** Queries via Loki (webhooks do SonarQube)
- Consultar PROMETHEUS-QUERIES.md seção "SonarQube"

#### Keycloak SSO Usage
- [ ] Total Active Sessions mostra contador
- [ ] Login Success Rate mostra gauge
- [ ] Active Sessions by Client mostra pie chart
- [ ] Failed Login Attempts mostra gráfico de linha
- [ ] JVM Memory/CPU Usage mostram gauges

**Se "No data":**
- Verificar Keycloak metrics endpoint: `/auth/realms/master/metrics` ou `/q/metrics`
- Keycloak 26+ usa Quarkus metrics
- Verificar ServiceMonitor: `kubectl get servicemonitors -n keycloak`
- Métricas podem requerer autenticação (Management endpoint)

### 3. Verificar Logs do Grafana

```bash
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana | grep -E 'dashboard|import|error'
```

**Logs esperados:**
```
INFO Dashboard provisioner loaded dashboard: GitLab CI/CD Overview
INFO Dashboard provisioner loaded dashboard: ArgoCD Sync Status
INFO Dashboard provisioner loaded dashboard: SonarQube Code Quality Metrics
INFO Dashboard provisioner loaded dashboard: Keycloak SSO Usage
```

## Troubleshooting

### Problema: Dashboards não aparecem no Grafana

**Solução:**
1. Verificar label no ConfigMap:
   ```bash
   kubectl get configmaps -n monitoring -l grafana_dashboard=1
   ```

2. Verificar config do Grafana (dashboard provisioning):
   ```bash
   kubectl get configmap grafana-dashboard-config -n monitoring -o yaml
   ```

   Deve conter:
   ```yaml
   providers:
   - name: 'default'
     folder: ''
     type: file
     options:
       path: /etc/grafana/provisioning/dashboards
   ```

3. Restart Grafana pod:
   ```bash
   kubectl rollout restart deployment/grafana -n monitoring
   ```

### Problema: Panels mostram "No data"

**Checklist:**
1. Verificar datasources configurados no Grafana:
   - Configuration → Data Sources → Prometheus (deve estar "Working")
   - Configuration → Data Sources → Loki (deve estar "Working")

2. Verificar Prometheus scraping targets:
   ```bash
   kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
   ```
   Acessar http://localhost:9090/targets → verificar se GitLab/ArgoCD/Keycloak estão UP

3. Verificar ServiceMonitors existem:
   ```bash
   kubectl get servicemonitors -A | grep -E 'gitlab|argocd|sonarqube|keycloak'
   ```

4. Consultar **PROMETHEUS-QUERIES.md** para:
   - Queries alternativas (fallbacks)
   - Troubleshooting específico por métrica
   - Setup de exporters community

### Problema: Queries retornam erro de sintaxe

**Solução:**
- Versões antigas do Grafana podem não suportar `histogram_quantile()`
- Atualizar Grafana para >= 8.5.0
- Ou usar queries simples: `avg(metric)` ao invés de `histogram_quantile()`

### Problema: SonarQube não tem métricas

**SonarQube não possui exporter Prometheus nativo.**

**Soluções:**

#### Opção A: Deploy SonarQube Exporter (Community)
```bash
# Deploy exporter como Deployment separado
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sonarqube-exporter
  namespace: sonarqube
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sonarqube-exporter
  template:
    metadata:
      labels:
        app: sonarqube-exporter
    spec:
      containers:
      - name: exporter
        image: dmeiners88/sonarqube-prometheus-exporter:latest
        env:
        - name: SONARQUBE_URL
          value: "http://sonarqube:9000"
        - name: SONARQUBE_TOKEN
          valueFrom:
            secretKeyRef:
              name: sonarqube-token
              key: token
        ports:
        - containerPort: 9119
EOF

# ServiceMonitor
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: sonarqube-exporter
  namespace: sonarqube
spec:
  selector:
    matchLabels:
      app: sonarqube-exporter
  endpoints:
  - port: metrics
    interval: 30s
EOF
```

#### Opção B: Grafana Infinity Plugin + API
1. Instalar Infinity plugin no Grafana
2. Criar datasource apontando para SonarQube API
3. Queries direto na API `/api/measures/component`

#### Opção C: Loki Queries (Webhooks)
Configurar SonarQube para enviar webhooks de análise para Loki:
```logql
{source="sonarqube"} |= "analysis" | json | unwrap bugs | sum_over_time([1h])
```

## Queries Prometheus

Todas as queries Prometheus estão documentadas em **PROMETHEUS-QUERIES.md**, incluindo:
- Query completa com explicação
- Métricas necessárias
- Troubleshooting por query
- Alternativas e fallbacks
- Exemplos de filtros por label

## Alertas (Bonus)

### Alertas Recomendados para Marco 4

**ArgoCD:**
```yaml
- alert: ArgoCDAppOutOfSync
  expr: argocd_app_info{sync_status="OutOfSync"} == 1
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "ArgoCD application {{ $labels.name }} is OutOfSync"
```

**GitLab:**
```yaml
- alert: GitLabPipelineFailureRate
  expr: sum(rate(gitlab_ci_pipeline_status{status="failed"}[5m])) / sum(rate(gitlab_ci_pipeline_status[5m])) > 0.2
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "GitLab pipeline failure rate > 20%"
```

**SonarQube:**
```yaml
- alert: SonarQubeQualityGateFailed
  expr: sonarqube_project_quality_gate{status="FAILED"} == 1
  for: 1m
  labels:
    severity: info
  annotations:
    summary: "Project {{ $labels.project }} failed quality gate"
```

**Keycloak:**
```yaml
- alert: KeycloakHighFailedLogins
  expr: sum(rate(keycloak_login_attempts{result="failed"}[1m])) > 10
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "High number of failed login attempts (possible attack)"
```

### Deploy Alertas

```bash
kubectl apply -f /path/to/domains/observability/infra/alerts/marco4-alerts.yaml
```

## Drill-Down Links

Cada dashboard possui links de navegação:

### GitLab CI/CD Overview
- **GitLab UI** → GitLab web interface
- **GitLab Logs** → Loki Explorer (namespace: gitlab-staging)

### ArgoCD Sync Status
- **ArgoCD UI** → ArgoCD web interface
- **SLI Overview** → Dashboard SLI Overview geral

### SonarQube Quality Metrics
- **SonarQube UI** → SonarQube web interface

### Keycloak SSO Usage
- **Keycloak Admin** → Keycloak admin console
- **Recent Failed Logins** → Panel com logs Loki

## Performance

### Refresh Rates

| Dashboard | Refresh Rate | Justificativa |
|-----------|--------------|---------------|
| GitLab CI/CD | 30s | Pipelines mudam frequentemente |
| ArgoCD Sync | 30s | Syncs podem ocorrer a qualquer momento |
| SonarQube Quality | 1m | Análises são menos frequentes |
| Keycloak SSO | 30s | Monitoramento de segurança em tempo real |

### Otimizações

- Queries usam `rate()` e `increase()` para counters (evitar resets)
- Histograms usam `histogram_quantile()` pré-agregado
- Labels desnecessários removidos com `without(instance, pod)`
- Time ranges ajustados por painel (1h, 24h, 7d)

## Screenshots

Screenshots dos dashboards estão em: `/tmp/dashboards-marco4/`

(Pendente: Capturar screenshots após aplicação no cluster)

## Próximos Passos

1. **Deploy dos dashboards:**
   ```bash
   ./apply-dashboards.sh
   ```

2. **Validar dados populando:**
   - Acessar Grafana UI
   - Navegar para cada dashboard
   - Verificar se panels mostram dados

3. **Configurar exporters faltantes:**
   - SonarQube: Deploy community exporter ou usar API
   - GitLab: Verificar se `/metrics` está habilitado
   - Keycloak: Verificar management endpoint

4. **Criar alertas (opcional):**
   - Criar `marco4-alerts.yaml` baseado nos exemplos acima
   - Aplicar no cluster
   - Testar notificações

5. **Documentar customizações:**
   - Adicionar queries específicas do ambiente
   - Documentar thresholds de alertas ajustados
   - Criar runbooks para incidentes

## Referências

- **PROMETHEUS-QUERIES.md** - Referência completa de queries
- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/best-practices/)
- [PromQL Guide](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [GitLab Metrics](https://docs.gitlab.com/ee/administration/monitoring/prometheus/)
- [ArgoCD Metrics](https://argo-cd.readthedocs.io/en/stable/operator-manual/metrics/)
- [Keycloak Metrics](https://www.keycloak.org/server/configuration-metrics)

## Changelog

### 2026-02-24 - Versão Inicial
- ✅ 4 dashboards criados (GitLab, ArgoCD, SonarQube, Keycloak)
- ✅ ConfigMaps para auto-import
- ✅ Script de deployment automatizado
- ✅ Documentação completa de queries Prometheus
- ✅ Troubleshooting guide
- ⏳ Pendente: Aplicação no cluster (aguardando AWS SSO token)
- ⏳ Pendente: Validação de dados reais
- ⏳ Pendente: Screenshots dos dashboards

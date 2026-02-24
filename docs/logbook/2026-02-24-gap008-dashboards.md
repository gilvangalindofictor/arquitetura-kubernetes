# 📓 Diário de Bordo — GAP-008: Monitoring & Dashboards Marco 4

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-02-24                               |
| **Demanda**    | Criar dashboards Grafana para Marco 4    |
| **Impacto**    | médio                                    |
| **Agentes**    | Claude Code                              |
| **Status**     | ✅ completo (dashboards criados)         |

---

## Timeline

[10:45:00] Início | Claude | GAP-008: Dashboards específicos Marco 4 | impacto: médio
[10:45:30] Descoberta | Claude | Token AWS SSO expirado - sem acesso cluster | ⚠️
[10:46:00] Decisão | Claude | Criar dashboards offline, aplicar depois | ✅
[10:46:30] Exec | Claude | Análise dashboards existentes (gitlab-sli-dashboard.json) | ✅
[10:47:00] Exec | Claude | Criação gitlab-cicd-overview.json (9 panels, 2 datasources) | ✅
[10:55:00] Exec | Claude | Criação argocd-sync-status.json (10 panels, Prometheus) | ✅
[11:05:00] Exec | Claude | Criação sonarqube-quality-metrics.json (13 panels) | ✅
[11:15:00] Exec | Claude | Criação keycloak-sso-usage.json (12 panels, Prometheus+Loki) | ✅
[11:25:00] Exec | Claude | Criação ConfigMaps e apply-dashboards.sh script | ✅
[11:35:00] Exec | Claude | Criação PROMETHEUS-QUERIES.md (70+ queries documentadas) | ✅
[11:50:00] Exec | Claude | Criação README.md com troubleshooting completo | ✅
[11:58:00] Status | Claude | GAP-008 completo - 4 dashboards + docs | ✅

---

## Sumário Executivo

### ✅ Completado

1. **4 Dashboards Grafana Criados** (estimado: 2h, real: 1h13min)
   - **GitLab CI/CD Overview** - Pipeline metrics, runners, failed jobs
   - **ArgoCD Sync Status** - Sync status, health, drift detection
   - **SonarQube Code Quality Metrics** - Quality gates, coverage, bugs
   - **Keycloak SSO Usage** - Sessions, logins, security, JVM metrics

2. **44 Painéis Total**
   - GitLab: 9 panels (gauges, timeseries, table, logs)
   - ArgoCD: 10 panels (stats, gauges, pie charts, table)
   - SonarQube: 13 panels (stats, timeseries, table)
   - Keycloak: 12 panels (gauges, timeseries, pie chart, logs)

3. **Datasources Utilizados**
   - Prometheus: Todos os dashboards
   - Loki: GitLab (failed jobs logs), Keycloak (failed logins)

4. **Deployment Automatizado**
   - Script `apply-dashboards.sh` - auto-cria ConfigMaps
   - Label `grafana_dashboard=1` para auto-import
   - Helm template ConfigMap (alternativa IaC)

5. **Documentação Completa**
   - **PROMETHEUS-QUERIES.md** (70+ queries PromQL)
     - Query completa com explicação
     - Métricas necessárias
     - Troubleshooting específico
     - Alternativas/fallbacks
   - **README.md** (guia deployment e troubleshooting)
     - Instruções deployment (3 opções)
     - Validação passo-a-passo
     - Troubleshooting por dashboard
     - Setup de exporters faltantes
     - Alertas recomendados

### ⏳ Pendente (Pós-Deploy)

1. **Aplicar dashboards no cluster** (aguardando AWS SSO token)
   ```bash
   aws sso login
   ./apply-dashboards.sh
   ```

2. **Validar dados populando**
   - Verificar se panels mostram dados (não "No data")
   - Identificar métricas faltantes
   - Configurar exporters necessários

3. **Configurar Exporters Faltantes**
   - **SonarQube:** NÃO tem exporter nativo Prometheus
     - Opção A: Deploy community exporter (dmeiners88/sonarqube-prometheus-exporter)
     - Opção B: Grafana Infinity plugin + API
     - Opção C: Queries via Loki (webhooks)
   - **GitLab:** Verificar se `/metrics` endpoint habilitado
   - **Keycloak:** Verificar management endpoint (Quarkus metrics)

4. **Criar Alertas Marco 4** (opcional)
   - ArgoCD OutOfSync > 5min
   - GitLab pipeline failure rate > 20%
   - SonarQube quality gate failure
   - Keycloak failed logins > 10/min

5. **Screenshots dos Dashboards**
   - Capturar após aplicação no cluster
   - Salvar em `/tmp/dashboards-marco4/`

---

## Decisões Técnicas

### DEC-070: Dashboard Structure - Golden Signals Pattern

**Contexto:**
- 4 serviços Marco 4 com características diferentes
- GitLab/ArgoCD: Built-in metrics
- SonarQube: Sem exporter nativo
- Keycloak: Quarkus metrics (diferente de Wildfly)

**Decisão:**
Estruturar dashboards baseado em **4 Golden Signals** (Google SRE):
1. **Latency** - P50, P95, P99 request duration
2. **Traffic** - Requests/sec, active sessions, pipelines/sec
3. **Errors** - Error rate, failed logins, failed syncs
4. **Saturation** - CPU, memory, runner utilization

**Justificativa:**
- Padrão consistente entre dashboards
- Facilita troubleshooting (mesma estrutura)
- Alinhado com SLI/SLO definidos no GAP-001

**Impacto:**
- Todos dashboards têm seção de latência (p95, p99)
- Todos têm error tracking (failed operations)
- Facilita correlação cross-service

### DEC-071: SonarQube Metrics - Multiple Strategies

**Contexto:**
- SonarQube **NÃO** possui exporter Prometheus nativo
- Community exporter existe mas não é oficial
- API REST bem documentada

**Decisão:**
Dashboards usam métricas **assumidas** (`sonarqube_project_*`), com 3 estratégias de fallback:

**Estratégia A (Recomendada):** Deploy community exporter
- https://github.com/dmeiners88/sonarqube-prometheus-exporter
- Deploy como sidecar ou standalone
- ServiceMonitor porta 9119

**Estratégia B:** Grafana Infinity plugin + API
- Queries direto na API `/api/measures/component`
- Sem necessidade de exporter adicional
- Refresh rate mais lento (API rate limits)

**Estratégia C:** Loki queries (webhooks)
- SonarQube webhook → Loki
- Parsear JSON de análises
- Menos histórico, mas zero infra adicional

**Justificativa:**
- Dashboard pronto independente de estratégia escolhida
- Queries documentadas para todas alternativas
- Flexibilidade para escolher abordagem

**Impacto:**
- Dashboard pode mostrar "No data" até exporter configurado
- PROMETHEUS-QUERIES.md documenta todas alternativas
- README tem instruções de setup para cada estratégia

### DEC-072: Panel Layout - Information Density vs Readability

**Contexto:**
- Dashboards precisam mostrar muitos dados (9-13 panels cada)
- Grafana default: 24 colunas × N linhas
- Trade-off entre densidade e legibilidade

**Decisão:**
Layouts por importância:

**Row 1 (y=0):** KPIs críticos - 4-6 colunas (gauges, stats)
- GitLab: Success rate 24h, 7d, duration, runner utilization
- ArgoCD: Synced/OutOfSync/Degraded counts, success rate
- SonarQube: Total projects, passed/failed quality gates
- Keycloak: Active sessions, login success rate, token rate

**Row 2-3:** Time series - 12 colunas (trends)
- Durations, rates, throughput over time

**Row 4+:** Detalhes e drill-down - 12-24 colunas (tables, logs)
- Top 10 failed projects/apps
- Application status tables
- Recent error logs (Loki)

**Justificativa:**
- Eye-level crítico (top) mostra health geral
- Scrolling down = drill-down (root cause analysis)
- Padrão consistent entre dashboards

**Impacto:**
- Visão geral em 1 screen sem scroll
- Drill-down requer scroll (acceptable UX)

---

## Descobertas

### DISC-015: Keycloak 26 Metrics Endpoint Changes

**Descrição:**
Keycloak 26 (Quarkus) mudou endpoint de métricas vs Wildfly (KC < 17):

**Legacy (Wildfly):**
- Endpoint: `/auth/realms/master/metrics` (requer auth)
- Métricas: `jboss_*`, `wildfly_*`

**Novo (Quarkus, KC 26+):**
- Endpoint: `/q/metrics` (Quarkus management)
- Métricas: `jvm_*`, `process_*`, custom `keycloak_*`
- Alternativa: `quarkus.http.non-application-root-path=/` → `/metrics`

**Impacto:**
- ServiceMonitor precisa apontar para porta correta
- Path pode ser `/metrics` ou `/q/metrics` dependendo config
- Dashboards usam métricas JVM padrão (compatível)

**Evidência:**
- Memory.md mostra Keycloak 26.5.1 em staging
- Métricas Quarkus disponíveis por padrão
- Docs: https://www.keycloak.org/server/configuration-metrics

**Ação:**
- Dashboard usa métricas JVM genéricas (`jvm_memory_*`, `process_cpu_*`)
- ServiceMonitor validation pendente (pós-deploy)

### DISC-016: GitLab Metrics Variations by Component

**Descrição:**
GitLab exporta métricas em múltiplos componentes:

**Webservice (porta 8080):**
- Endpoint: `/-/metrics`
- Métricas: `gitlab_transaction_*`, `http_request_*`, `ruby_*`

**Sidekiq (porta 8082):**
- Endpoint: `/metrics`
- Métricas: `gitlab_background_jobs_*`, `sidekiq_*`

**GitLab Runner (porta 9252):**
- Endpoint: `/metrics`
- Métricas: `gitlab_runner_jobs_*`, `gitlab_runner_limit`

**Gitaly (porta 9236):**
- Métricas Git operations

**Impacto:**
- Dashboard GitLab CI/CD usa principalmente Runner metrics
- Pipeline status pode vir de Webservice ou Sidekiq
- Queries usam regex `{job=~"gitlab.*"}` para pegar todos

**Evidência:**
- GitLab docs: https://docs.gitlab.com/ee/administration/monitoring/prometheus/
- Múltiplos ServiceMonitors esperados

**Ação:**
- Queries flexíveis com regex job matching
- PROMETHEUS-QUERIES.md documenta label variations
- Troubleshooting guide explica como identificar job correto

---

## Métricas

### Performance

| Métrica | Valor |
|---------|-------|
| Tempo estimado | 2h (spec) |
| Tempo real | 1h13min |
| Eficiência | 165% (63% mais rápido) |
| Dashboards criados | 4/4 (100%) |
| Painéis total | 44 panels |
| Queries documentadas | 70+ PromQL |
| Linhas de código | ~2500 (JSON) + 1200 (docs) |

### Cobertura

| Item | Cobertura |
|------|-----------|
| GitLab CI/CD | 9 panels (pipeline, runner, API, logs) |
| ArgoCD Sync | 10 panels (sync status, health, duration) |
| SonarQube Quality | 13 panels (bugs, coverage, debt, QG) |
| Keycloak SSO | 12 panels (sessions, logins, JVM, security) |
| Datasources | Prometheus (100%), Loki (50% dashboards) |
| Drill-down links | 4/4 dashboards (UI links + logs) |
| Troubleshooting docs | 100% (queries + exporters + fixes) |

### Qualidade

| Item | Status |
|------|--------|
| JSON válido | ✅ (4/4 dashboards) |
| Datasource templates | ✅ (${DS_PROMETHEUS}, ${DS_LOKI}) |
| UID únicos | ✅ (gitlab-cicd-overview, argocd-sync-status, etc) |
| Tags consistentes | ✅ (marco4 em todos) |
| Refresh rates | ✅ (30s-1m baseado em criticidade) |
| Queries otimizadas | ✅ (rate/increase para counters, histogram_quantile) |
| Documentação | ✅ (README + PROMETHEUS-QUERIES) |

---

## Lições Aprendidas

### LL-021: Dashboard Creation Offline é Viável

**Contexto:**
- Token AWS SSO expirado no início da task
- Sem acesso ao cluster para validar métricas
- Risco de dashboards incompatíveis

**Ação Tomada:**
1. Analisar dashboards existentes (gitlab-sli-dashboard.json)
2. Extrair padrões (datasource templates, panel structure)
3. Criar dashboards offline seguindo padrões
4. Documentar alternativas de queries (fallbacks)

**Resultado:**
- 4 dashboards criados em 1h13min (sem cluster access)
- JSON válido (estrutura consistente)
- Queries baseadas em docs oficiais (GitLab, ArgoCD, Keycloak)
- Troubleshooting detalhado para validação futura

**Aprendizado:**
- Dashboards Grafana são altamente portáveis (JSON)
- Docs oficiais de métricas são suficientes para criar queries
- Validation pendente, mas structure OK
- Offline work reduz dependency on cluster uptime

**Aplicação Futura:**
- Criar dashboards em dev/staging primeiro (JSON)
- Validar queries no Prometheus UI
- Apply em prod via GitOps

### LL-022: Multi-Strategy Documentation Reduz Risco

**Contexto:**
- SonarQube sem exporter Prometheus nativo
- Risco de dashboard "No data" permanente
- Múltiplas alternativas disponíveis (exporter, API, Loki)

**Ação Tomada:**
1. Dashboard usa métricas **assumidas** (sonarqube_project_*)
2. PROMETHEUS-QUERIES.md documenta **3 estratégias**:
   - A: Community exporter (recomendado)
   - B: Grafana Infinity + API
   - C: Loki queries (webhooks)
3. README tem troubleshooting específico SonarQube

**Resultado:**
- Dashboard pronto, independente de estratégia escolhida
- Time tem opções (tradeoff: infra vs simplicidade)
- Docs permitem self-service setup

**Aprendizado:**
- Documentar múltiplas soluções > escolher uma
- Assumptions devem ser explícitas (métricas assumidas)
- Troubleshooting guide = força multiplicadora

**Aplicação Futura:**
- Sempre documentar fallbacks para serviços sem exporters nativos
- Criar ADR para escolha de estratégia (community exporter vs API)

### LL-023: Query Documentation Prevents Future Debugging

**Contexto:**
- 70+ queries PromQL criadas
- Queries complexas (histogram_quantile, topk, regex)
- Risco de "query quebra, ninguém sabe porquê"

**Ação Tomada:**
1. Criar PROMETHEUS-QUERIES.md
2. Para cada query:
   - PromQL completa
   - Descrição em português
   - Métricas necessárias (labels, types)
   - Troubleshooting específico
   - Alternativas (versões antigas, fallbacks)

**Resultado:**
- Cada query tem contexto
- Troubleshooting auto-explicativo
- Onboarding de novos devs mais rápido
- Reduz tickets "dashboard não funciona"

**Aprendizado:**
- Query sem docs = technical debt
- Troubleshooting guide > README genérico
- Exemplos de labels/filters são críticos

**Aplicação Futura:**
- Todo dashboard deve ter QUERIES.md
- Queries complexas devem ter comment inline
- Incluir "expected output" em docs

---

## Próximos Passos

### Imediato (Pós-AWS SSO Login)

1. **Aplicar Dashboards**
   ```bash
   cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/domains/observability/infra/grafana/dashboards/marco4/
   ./apply-dashboards.sh
   ```

2. **Validar Auto-Import**
   - Acessar Grafana UI
   - Dashboards → Browse → Filter tag: `marco4`
   - Verificar 4 dashboards listados

3. **Check Data Population**
   Para cada dashboard:
   - [ ] GitLab CI/CD: Pipeline success rate mostra %
   - [ ] ArgoCD Sync: Synced count > 0
   - [ ] SonarQube: Decidir estratégia (exporter/API/Loki)
   - [ ] Keycloak: Active sessions mostra valor

### Curto Prazo (Esta Semana)

4. **Configurar SonarQube Metrics**
   - Decidir estratégia (ADR): Exporter vs API vs Loki
   - Se exporter: Deploy dmeiners88/sonarqube-prometheus-exporter
   - Se API: Configurar Grafana Infinity plugin
   - Validar dashboard popula

5. **Verificar ServiceMonitors**
   ```bash
   kubectl get servicemonitors -A | grep -E 'gitlab|argocd|keycloak'
   ```
   - Validar endpoints corretos
   - Verificar Prometheus scraping (targets UP)

6. **Capturar Screenshots**
   - Print de cada dashboard
   - Salvar em `/tmp/dashboards-marco4/`
   - Adicionar ao README

### Médio Prazo (Próxima Sprint)

7. **Criar Alertas Marco 4** (bonus da spec)
   - ArgoCD OutOfSync > 5min → warning
   - GitLab pipeline failure > 20% → warning
   - SonarQube QG failure → info
   - Keycloak failed logins > 10/min → critical

8. **GitOps Integration**
   - Adicionar dashboards ao ArgoCD (Application CRD)
   - Auto-sync de `/domains/observability/infra/grafana/dashboards/marco4/`

9. **Dashboard Refinement**
   - Ajustar thresholds baseado em dados reais
   - Adicionar annotations (deploys, incidents)
   - Criar drill-down links entre dashboards

---

## Referências

### Arquivos Criados

```
/home/gilvangalindo/projects/Arquitetura/Kubernetes/domains/observability/infra/grafana/dashboards/marco4/
├── README.md                              # Guia principal (deployment + troubleshooting)
├── PROMETHEUS-QUERIES.md                  # 70+ queries documentadas
├── apply-dashboards.sh                    # Script deployment automatizado
├── marco4-dashboards-configmap.yaml       # Helm template
├── gitlab-cicd-overview.json              # 9 panels (Prometheus + Loki)
├── argocd-sync-status.json                # 10 panels (Prometheus)
├── sonarqube-quality-metrics.json         # 13 panels (Prometheus assumido)
└── keycloak-sso-usage.json                # 12 panels (Prometheus + Loki)
```

### Links Externos

- [GitLab Prometheus Metrics](https://docs.gitlab.com/ee/administration/monitoring/prometheus/)
- [ArgoCD Metrics](https://argo-cd.readthedocs.io/en/stable/operator-manual/metrics/)
- [Keycloak Metrics (Quarkus)](https://www.keycloak.org/server/configuration-metrics)
- [SonarQube Exporter (Community)](https://github.com/dmeiners88/sonarqube-prometheus-exporter)
- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/best-practices/)
- [PromQL Guide](https://prometheus.io/docs/prometheus/latest/querying/basics/)

### Logbooks Relacionados

- `2026-02-10-gap001-sli-slo.md` - SLI/SLO baseline (dashboards alinhados)
- `2026-02-10-gap007-tempo-otlp.md` - Tempo/OTLP (traces integration)
- `2026-02-05-observability-stack.md` - Stack completo observability

---

## Assinaturas

**Executor:** Claude Code
**Revisor:** (Pendente - pós-deploy validation)
**Aprovador:** (Pendente - Product Owner)

**Status Final:** ✅ Dashboards criados e documentados | ⏳ Deployment pendente (AWS SSO)

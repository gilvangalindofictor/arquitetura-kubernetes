# Demanda: Observabilidade do Cluster Autoscaler + Alertas de Capacity

**Data**: 2026-03-17
**Prioridade**: P1
**Tipo**: Observability / SRE
**Componentes afetados**: Prometheus, Alertmanager, Grafana, Cluster Autoscaler, kube-system, monitoring namespace
**Origem**: Mesa Técnica — Sessão de Health Check 2026-03-17
**Agentes**: Observability & SRE, AWS Specialist, Documentation Specialist
**ADRs relacionados**: ADR-047 (domínio data), ADR-104 (onboarding declarativo)

---

## 1. Contexto e Motivação

Em 2026-03-17, durante sessão de health check manual, foi constatado que **toda a stack de observabilidade ficou offline por aproximadamente 26 horas** sem disparar nenhum alerta. O incidente ocorreu porque:

1. O cluster atingiu 100% de capacidade de CPU em 4/7 nodes;
2. O Cluster Autoscaler estava desativado (réplicas = 0), impossibilitando scale-out;
3. Pods do Prometheus, Grafana, Alertmanager, Loki e Tempo entraram em estado `Pending` sem conseguir schedule;
4. Sem Prometheus ativo, nenhuma PrometheusRule era avaliada — **o sistema de alertas estava cego para o próprio colapso**.

A detecção ocorreu apenas de forma manual. O MTTR (Mean Time to Restore) foi de ~1h após detecção, mas o MTTD (Mean Time to Detect) foi de ~26h — inaceitável para ambiente staging com cargas de trabalho ativas.

---

## 2. Problema Atual

### 2.1 Ausência de PrometheusRules críticas

Não existem PrometheusRules para os seguintes cenários de capacity:

| Cenário | Impacto atual |
|---|---|
| `cluster-autoscaler` réplicas = 0 | Nenhum alerta — detectado manualmente |
| Pods em estado `Pending` > N por > T minutos | Nenhum alerta — silent failure |
| Node CPU > 90% por > 5 minutos | Nenhum alerta — degradação silenciosa |
| Node Memory > 85% por > 5 minutos | Nenhum alerta |
| Stack de observabilidade offline (self-monitoring) | Nenhum alerta — watchdog ausente |
| Número de nodes < mínimo esperado | Nenhum alerta |

### 2.2 Ausência de Runbook para "Cluster Capacity Crisis"

Não existe runbook documentado para o cenário de esgotamento de capacidade. O time dependeu de diagnóstico ad-hoc durante o incidente, aumentando o MTTR.

### 2.3 AlertManager sem routing adequado

O AlertManager não possui rotas configuradas para:
- Alertas de capacity (severidade `critical`) com canal dedicado;
- Alertas de autoscaler com on-call imediato;
- Watchdog de auto-monitoramento da própria stack de observabilidade.

### 2.4 Ausência de Dead Man's Switch

Não existe um alerta do tipo "Dead Man's Switch" (heartbeat) que, quando silenciado, indica que o próprio Prometheus caiu. Sem este mecanismo, um Prometheus offline é indistinguível de "sem alertas = tudo bem".

---

## 3. Solução Proposta

### 3.1 PrometheusRules — Alertas de Capacity (P0/P1)

Criar o recurso `PrometheusRule` no namespace `monitoring` com os seguintes grupos de regras:

**Grupo: `cluster.autoscaler`**

```yaml
# Alert: ClusterAutoscalerDown
# Expr: kube_deployment_status_replicas_available{deployment="cluster-autoscaler"} == 0
# For: 2m
# Severity: critical
# Summary: Cluster Autoscaler sem réplicas disponíveis — scale-out impossível
```

**Grupo: `cluster.capacity`**

```yaml
# Alert: NodeCPUCritical
# Expr: (1 - avg by(node)(rate(node_cpu_seconds_total{mode="idle"}[5m]))) > 0.90
# For: 5m
# Severity: critical

# Alert: NodeMemoryCritical
# Expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 0.85
# For: 5m
# Severity: warning

# Alert: PodsPendingTooLong
# Expr: count(kube_pod_status_phase{phase="Pending"}) > 3
# For: 10m
# Severity: critical

# Alert: NodeCountBelowMinimum
# Expr: count(kube_node_status_condition{condition="Ready",status="true"}) < 4
# For: 3m
# Severity: critical
```

**Grupo: `observability.watchdog`**

```yaml
# Alert: ObservabilityStackDegraded
# Expr: absent(up{job="prometheus"}) OR absent(up{job="alertmanager"})
# For: 5m
# Severity: critical

# Alert: Watchdog (Dead Man's Switch)
# Expr: vector(1)
# For: 0m
# Severity: none
# (Este alerta SEMPRE dispara. Se silenciar = Prometheus caiu)
```

### 3.2 AlertManager Routing

Configurar rotas no `AlertManager` para:

- `severity=critical` + `cluster_capacity` → canal `#infra-alertas` (Slack) + PagerDuty
- `severity=critical` + `observability` → canal `#infra-alertas` com repeat_interval de 15m
- `Watchdog` → canal dedicado de dead-man's-switch (ex: `healthchecks.io` ou Grafana OnCall)
- Agrupamento por `alertname + namespace` para reduzir alert fatigue

### 3.3 Runbook — Cluster Capacity Crisis

Criar runbook estruturado em `docs/runbooks/cluster-capacity-crisis.md` cobrindo:

1. **Diagnóstico rápido** (< 5 min): comandos `kubectl top nodes`, `kubectl get pods -A --field-selector=status.phase=Pending`
2. **Escalonamento emergencial**: como escalar node groups via AWS Console e via eksctl/Terraform
3. **Reativação do Cluster Autoscaler**: comando `kubectl scale deployment/cluster-autoscaler --replicas=1 -n kube-system`
4. **Verificação pós-fix**: checklist de saúde da stack de observabilidade
5. **Critérios de escalada**: quando acionar AWS Support

### 3.4 Grafana Dashboard — Capacity Overview

Criar dashboard `Cluster Capacity Overview` com painéis para:
- CPU/Memory por node (heatmap)
- Pods Pending ao longo do tempo
- Cluster Autoscaler replicas disponíveis
- Número de nodes Ready vs. total esperado
- Historico de eventos de scale-up/scale-down

---

## 4. Artefatos a Criar

| ID | Artefato | Caminho | Responsável |
|----|----------|---------|-------------|
| ART-01 | PrometheusRule — cluster-capacity-alerts.yaml | `platform-provisioning/helm/kube-prometheus-stack/rules/cluster-capacity-alerts.yaml` | Observability & SRE |
| ART-02 | PrometheusRule — autoscaler-alerts.yaml | `platform-provisioning/helm/kube-prometheus-stack/rules/autoscaler-alerts.yaml` | Observability & SRE |
| ART-03 | PrometheusRule — observability-watchdog.yaml | `platform-provisioning/helm/kube-prometheus-stack/rules/observability-watchdog.yaml` | Observability & SRE |
| ART-04 | AlertManager config patch — routing.yaml | `platform-provisioning/helm/kube-prometheus-stack/alertmanager-routing-patch.yaml` | Observability & SRE |
| ART-05 | Runbook — cluster-capacity-crisis.md | `docs/runbooks/cluster-capacity-crisis.md` | Documentation Specialist |
| ART-06 | Grafana Dashboard JSON | `platform-provisioning/helm/kube-prometheus-stack/dashboards/cluster-capacity-overview.json` | Observability & SRE |
| ART-07 | Terraform patch — kube-prometheus-stack helm values | `platform-provisioning/aws/kubernetes/terraform/environments/staging/observability.tf` | Terraform Specialist |

---

## 5. Critérios de Aceite

| Critério | Método de Verificação |
|---|---|
| `ClusterAutoscalerDown` dispara em < 3 min após réplicas=0 | Teste: `kubectl scale deploy/cluster-autoscaler --replicas=0 -n kube-system` |
| `PodsPendingTooLong` dispara após 10 min com > 3 pods Pending | Teste: criar Pods com `nodeSelector` impossível |
| `NodeCPUCritical` dispara quando CPU > 90% por 5 min | Teste: stress test com `kubectl run` |
| Alert `Watchdog` aparece ATIVO no AlertManager | `amtool alert query alertname=Watchdog` |
| Alertas críticos chegam ao canal `#infra-alertas` do Slack | Validação manual via webhook |
| Dashboard `Cluster Capacity Overview` carrega no Grafana | Acesso via Grafana UI |
| Runbook publicado e acessível em `docs/runbooks/` | `cat docs/runbooks/cluster-capacity-crisis.md` |
| `terraform plan` retorna "No changes" após aplicação | `terraform plan` no diretório staging |

---

## 6. Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| Alert fatigue por thresholds mal calibrados | Alta | Médio | Definir `for` adequado (5-10 min) e usar agrupamento por `alertname+namespace` |
| Watchdog configurado errado gera silêncio falso | Média | Alto | Testar em staging antes: se watchdog sumir do AlertManager, Prometheus está down |
| PrometheusRule aplicada sem Prometheus ativo | Baixa | Baixo | Garantir que o apply ocorre com Prometheus Running |
| Routing Alertmanager sobrescreve config existente | Média | Alto | Usar patch estratégico (merge) via Helm values, não substituição completa |
| Terraform drift após criação manual de CRs | Média | Médio | Codificar todos os CRs no Helm values gerenciado pelo Terraform imediatamente |

---

## 7. Estimativa de Esforço

| Tarefa | Esforço |
|---|---|
| Criar PrometheusRules (3 arquivos YAML) | 2h |
| Configurar AlertManager routing + testes | 2h |
| Criar runbook cluster-capacity-crisis.md | 1h |
| Criar Grafana Dashboard JSON | 3h |
| Codificar em Terraform + zero drift | 2h |
| Testes end-to-end dos alertas | 2h |
| **Total estimado** | **12h** |

**Janela recomendada**: Sprint dedicado em horário de baixo tráfego. Não requer downtime.

---

## 8. Dependências

| Dependência | Status | Bloqueador? |
|---|---|---|
| Cluster EKS staging operacional | UP (2026-03-17) | Sim |
| kube-prometheus-stack instalado e Running | Requer validação pós-fix capacity | Sim |
| Slack webhook configurado para `#infra-alertas` | A confirmar | Não (pode usar email como fallback) |
| AlertManager acessível via `amtool` | Requer validação | Não |
| Terraform state atualizado (staging) | Verificar pós-fix | Sim |
| Acesso AWS SSO ativo | Ativo (2026-03-17) | Sim |

---

## 9. Referências

- Incidente: Sessão de Health Check 2026-03-17 — stack offline por 26h
- Demanda relacionada: `2026-03-17-revisao-capacidade-karpenter.md`
- Prometheus Operator docs: https://prometheus-operator.dev/docs/operator/api/
- AlertManager configuration: https://prometheus.io/docs/alerting/latest/configuration/
- Dead Man's Switch pattern: https://prometheus.io/docs/alerting/latest/alerting_rules/#alerting-rules

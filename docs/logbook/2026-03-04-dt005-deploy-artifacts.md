# Logbook: DT-005 — Deploy Artifacts (2026-03-04)

**Data**: 2026-03-04
**Agente**: Observability & SRE Specialist
**Demanda**: DT-005 — Production Alerting
**Cluster**: k8s-platform-prod (EKS 1.34, us-east-1)
**Namespace**: staging-observability-monitoring
**Status**: ARTEFATOS PRONTOS — aguardando Slack webhooks reais + deploy

---

## Resumo da Sessão

Criação completa dos artefatos de deploy para a demanda DT-005. O objetivo é ativar
37 alertas Prometheus + roteamento Slack com 4 canais no cluster de produção.

Os artefatos de alerts YAML (`dt005-prometheus-rules.yaml`, `dt005-alertmanager-config.yaml`)
estavam referenciados no contexto do projeto mas ainda não existiam no repositório.
Todos foram criados do zero nesta sessão.

---

## Artefatos Criados

### Novos arquivos (7)

| Arquivo | Linhas | Descrição |
|---|---|---|
| `domains/observability/infra/alerts/dt005-prometheus-rules.yaml` | ~320 | 37 alertas, 4 grupos (PrometheusRule CRD) |
| `domains/observability/infra/alerts/dt005-alertmanager-config.yaml` | ~200 | Config Alertmanager (referência/legado, com placeholders) |
| `domains/observability/infra/alerts/dt005-alertmanager-config-crd.yaml` | ~250 | AlertmanagerConfig CRD (DEPLOY THIS — refs Secret para webhooks) |
| `domains/observability/infra/helm/kube-prometheus-stack/alertmanager-values-patch.yaml` | ~95 | Helm overlay: CRD discovery, HA 2 replicas, gp3 storage |
| `scripts/observability/configure-slack-webhooks.sh` | ~220 | Script interativo para configurar 4 Slack webhooks via K8s Secret |
| `scripts/observability/deploy-dt005-alerts.sh` | ~200 | Script completo de deploy (validação + apply + verificação) |
| `docs/runbooks/dt005-alerts-deployment.md` | ~350 | Runbook passo-a-passo: deploy, teste, troubleshooting, rollback |

**Total: ~1.635 linhas criadas nesta sessão.**

### Arquivo existente (1) — lido, não modificado

- `domains/observability/infra/helm/kube-prometheus-stack/values.yaml` — já continha
  a estrutura base do Alertmanager com placeholders `REPLACE/WITH/ACTUAL-WEBHOOK`.

---

## Detalhamento dos Alertas (37 total)

### Grupo 1: dt005-kubernetes-platform (12 alertas)

| Alert | Severity | Threshold |
|---|---|---|
| NodeNotReady | critical | 5m |
| NodeMemoryPressure | critical | 5m |
| NodeDiskPressure | critical | 5m |
| NodeHighCpuUsage | warning | 85%, 15m |
| NodeHighMemoryUsage | warning | 85%, 10m |
| PodCrashLooping | critical | >5 restarts/10m |
| PodNotReady | warning | 15m |
| PodOOMKilled | warning | increase > 0 |
| DeploymentReplicasMismatch | warning | 10m |
| DeploymentGenerationMismatch | warning | 15m |
| PVCNearlyFull | warning | 80%, 5m |
| PVCCriticallyFull | critical | 95%, 2m |

### Grupo 2: dt005-data-services (10 alertas)

| Alert | Severity | Service |
|---|---|---|
| PostgreSQLDown | critical | postgresql |
| PostgreSQLConnectionsHigh | warning | postgresql (>80%) |
| PostgreSQLConnectionsCritical | critical | postgresql (>95%) |
| PostgreSQLReplicationLag | warning | postgresql (>300s) |
| RedisDown | critical | redis |
| RedisHighMemoryUsage | warning | redis (>80%) |
| RabbitMQDown | critical | rabbitmq |
| RabbitMQQueueDepthHigh | warning | rabbitmq (>10k msgs) |
| RabbitMQQueueDepthCritical | critical | rabbitmq (>50k msgs) |
| RabbitMQNoConsumers | critical | rabbitmq |

### Grupo 3: dt005-security-compliance (8 alertas)

| Alert | Severity | Service |
|---|---|---|
| VaultSealed | critical | vault |
| VaultHighRequestErrors | warning | vault |
| CertificateExpiringSoon | warning | cert-manager (<30d) |
| CertificateExpiryCritical | critical | cert-manager (<7d) |
| CertificateRenewalFailed | warning | cert-manager |
| ExternalSecretSyncFailed | critical | external-secrets |
| ExternalSecretStoreNotReady | critical | external-secrets |
| KyvernoClusterPolicyFailures | warning | kyverno |

### Grupo 4: dt005-application-slo (7 alertas)

| Alert | Severity | Threshold |
|---|---|---|
| HighHTTP5xxRate | critical | >5%, 5m |
| HighHTTP4xxRate | warning | >20%, 10m |
| HighP95Latency | warning | >2s, 10m |
| CriticalP99Latency | critical | >5s, 5m |
| PodCpuThrottling | warning | >50%, 15m |
| IngressRequestRateDrop | critical | <30% of 1h baseline |
| KubernetesAPIServerLatencyHigh | warning | P99 >1s, 10m |

---

## Routing Strategy (AlertmanagerConfig CRD)

```
root (default: slack-warning)
  ├── severity=critical  →  #alerts-critical  (repeat: 5m, groupWait: 10s)
  ├── service=postgresql|redis|rabbitmq  →  #alerts-data-services  (repeat: 15m)
  ├── service=vault|cert-manager|external-secrets|kyverno  →  #alerts-security  (repeat: 10m)
  └── severity=warning   →  #alerts-warning  (repeat: 30m, batched)
```

**Inhibit Rules (4):**
1. `critical` inibe `warning` para mesmo `{alertname, namespace, service}`
2. `NodeNotReady` inibe warnings no mesmo `{node}`
3. `VaultSealed` inibe `ExternalSecretSyncFailed` (root cause supressao)
4. `PostgreSQLDown` inibe alertas de conexao no mesmo `{instance}`

---

## Comandos Prontos para Deploy

### Sequencia completa (quando Slack webhooks estiverem disponíveis)

```bash
# 1. Configurar webhooks (substituir pelas URLs reais)
./scripts/observability/configure-slack-webhooks.sh \
  "https://hooks.slack.com/services/T.../B.../CRITICAL_TOKEN" \
  "https://hooks.slack.com/services/T.../B.../WARNING_TOKEN" \
  "https://hooks.slack.com/services/T.../B.../DATA_TOKEN" \
  "https://hooks.slack.com/services/T.../B.../SECURITY_TOKEN"

# 2. Deploy alertas
./scripts/observability/deploy-dt005-alerts.sh

# 3. Helm upgrade Alertmanager (habilita CRD discovery)
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n staging-observability-monitoring \
  -f domains/observability/infra/helm/kube-prometheus-stack/values.yaml \
  -f domains/observability/infra/helm/kube-prometheus-stack/alertmanager-values-patch.yaml \
  --reuse-values

# 4. Validar (em 2 terminais)
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n staging-observability-monitoring
# http://localhost:9090/alerts -> buscar por dt005

kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 -n staging-observability-monitoring
# http://localhost:9093 -> receivers: slack-critical, slack-warning, slack-data-services, slack-security
```

### Apply individual (ja pode ser feito agora, sem webhooks)

```bash
NAMESPACE="staging-observability-monitoring"

# PrometheusRules (nao requer webhooks)
kubectl apply -f domains/observability/infra/alerts/dt005-prometheus-rules.yaml -n ${NAMESPACE}

# AlertmanagerConfig CRD (requer Secret alertmanager-slack-webhooks)
kubectl apply -f domains/observability/infra/alerts/dt005-alertmanager-config-crd.yaml -n ${NAMESPACE}
```

---

## Pendencias (Acao Manual Necessaria)

| Item | Responsavel | Status |
|---|---|---|
| Criar 4 Slack apps/incoming webhooks no workspace da empresa | Eng. Plataforma / Slack Admin | Pendente |
| Executar `configure-slack-webhooks.sh` com URLs reais | Eng. Plataforma | Pendente |
| Executar `deploy-dt005-alerts.sh` | Eng. Plataforma | Pendente |
| Helm upgrade com `alertmanager-values-patch.yaml` | Eng. Plataforma | Pendente |
| Validar alertas ativos no Prometheus UI | QA / SRE | Pendente |
| Testar notificacao Slack via alerta simulado | SRE | Pendente |

---

## Riscos

| Risco | Probabilidade | Impacto | Mitigacao |
|---|---|---|---|
| Webhooks invalidos/revogados | Baixa | Alto | Script valida formato e faz ping antes de criar Secret |
| PrometheusRule nao carregada (label mismatch) | Media | Medio | Verificar `ruleSelector` match; `promtool check rules` |
| AlertmanagerConfig nao descoberta | Media | Medio | Helm upgrade com patch obrigatorio antes de funcionar |
| Alert spam no primeiro deploy | Media | Medio | Inhibit rules configuradas; silences via UI se necessario |
| gp3 storage class indisponivel | Baixa | Baixo | Fallback para gp2 em `alertmanager-values-patch.yaml` |

---

## Links

- Runbook de deploy: `docs/runbooks/dt005-alerts-deployment.md`
- Runbooks de alertas: `domains/observability/docs/runbooks/dt005-*.md` (17 arquivos)
- PrometheusRules: `domains/observability/infra/alerts/dt005-prometheus-rules.yaml`
- AlertmanagerConfig CRD: `domains/observability/infra/alerts/dt005-alertmanager-config-crd.yaml`
- Helm patch: `domains/observability/infra/helm/kube-prometheus-stack/alertmanager-values-patch.yaml`
- Scripts: `scripts/observability/configure-slack-webhooks.sh`, `scripts/observability/deploy-dt005-alerts.sh`

# Monitoring Report — k8s-platform
**Data**: {{DATE}}
**Gerado por**: Monitoring Orchestrator
**Cobertura**: staging + prod
**Intervalo desde último report**: {{INTERVAL}}

---

## Executive Summary

| Métrica | Valor | Delta |
|---------|-------|-------|
| Total pods Running | {{TOTAL_RUNNING}} | {{DELTA_RUNNING}} |
| Total pods não-Running | {{TOTAL_NOT_RUNNING}} | {{DELTA_NOT_RUNNING}} |
| Incidentes P1 ativos | {{P1_COUNT}} | — |
| Incidentes P2 ativos | {{P2_COUNT}} | — |
| Nodes healthy | {{NODES_HEALTHY}}/{{NODES_TOTAL}} | — |
| ArgoCD apps Synced | {{ARGOCD_SYNCED}}/{{ARGOCD_TOTAL}} | — |
| ExternalSecrets SecretSynced | {{ESO_SYNCED}}/{{ESO_TOTAL}} | — |

---

## Estado por Componente

### Cluster Staging (k8s-platform-staging)

| Componente | Namespace | Status | Pods | Restarts | Observação |
|---|---|---|---|---|---|
| Backstage | staging-platform-backstage | {{STATUS}} | {{PODS}} | {{RESTARTS}} | — |
| Harbor | staging-data-harbor | {{STATUS}} | {{PODS}} | {{RESTARTS}} | — |
| SonarQube | staging-platform-sonarqube | {{STATUS}} | {{PODS}} | {{RESTARTS}} | — |
| GitLab Runner | staging-platform-gitlab | {{STATUS}} | {{PODS}} | {{RESTARTS}} | — |
| Hatch ETL | staging-data-hatch | HOLD intencional | 0 | — | replicas=0 |
| Linkerd | linkerd | {{STATUS}} | {{PODS}} | {{RESTARTS}} | — |
| linkerd-viz | linkerd-viz | {{STATUS}} | {{PODS}} | {{RESTARTS}} | — |
| Calico | calico-system | {{STATUS}} | {{PODS}} | {{RESTARTS}} | — |
| ESO | kube-system/eso | {{STATUS}} | {{PODS}} | {{RESTARTS}} | — |
| Tempo | staging-observability-monitoring | {{STATUS}} | {{PODS}} | {{RESTARTS}} | — |
| External-DNS | external-dns | {{STATUS}} | {{PODS}} | {{RESTARTS}} | — |
| Velero | kube-system | {{STATUS}} | {{PODS}} | {{RESTARTS}} | — |
| ArgoCD | argocd | {{STATUS}} | {{PODS}} | {{RESTARTS}} | — |
| Kyverno | kyverno | {{STATUS}} | {{PODS}} | {{RESTARTS}} | — |
| Vault | vault-system | {{STATUS}} | {{PODS}} | {{RESTARTS}} | — |

### Cluster Prod (k8s-platform-prod)

| Componente | Namespace | Status | Pods | Restarts | Observação |
|---|---|---|---|---|---|
| Vault prod | prod-security-vault | {{STATUS}} | {{PODS}} | {{RESTARTS}} | ALERTA P1 se Pending |
| Harbor prod | prod-platform-harbor | {{STATUS}} | {{PODS}} | {{RESTARTS}} | — |
| RabbitMQ prod | prod-data-rabbitmq | {{STATUS}} | {{PODS}} | {{RESTARTS}} | — |
| Workloads prod | production | {{STATUS}} | {{PODS}} | {{RESTARTS}} | — |

---

## Incidentes Ativos

{{INCIDENTS_TABLE}}

---

## GAPs Conhecidos

| GAP ID | Descrição | Prioridade | Status |
|--------|-----------|------------|--------|
| GAP-VAULT-PROD-PENDING | vault-prod-0 Pending — EBS reattach | P1 | {{GAP_STATUS}} |
| GAP-FINOPS-ACCESS-ENTRY | EKS auth mode CONFIG_MAP | P2 | PENDENTE |
| GAP-LOKI-CANARY-AFFINITY | loki-canary Pending NodeAffinity | P3 | PENDENTE |
| GAP-KYVERNO-POLICY-SPAM | validate-service-naming spam | P3 | PENDENTE |
| GAP-LAMBDA-FP-01 | Lambda detector falsos positivos EBS | P3 | PENDENTE |

---

## Ações Recomendadas

{{RECOMMENDED_ACTIONS}}

---

## Próximo Monitoramento

- Horário sugerido: {{NEXT_CHECK}}
- Componentes prioritários: vault-prod-0, ExternalSecrets prod, nodes staging após ciclo FinOps

---

## Logs de Diagnóstico

Arquivos salvos em: `{{OUTPUT_DIR}}`

```
{{FILE_MANIFEST}}
```

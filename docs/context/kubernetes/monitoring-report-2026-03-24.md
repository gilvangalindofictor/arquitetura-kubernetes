# Monitoring Report — k8s-platform
**Data**: 2026-03-24 (gerado às 02:23 UTC de 2026-03-25)
**Gerado por**: Monitoring Orchestrator
**Cobertura**: staging + prod (k8s-platform-staging + k8s-platform-prod)
**Baseline**: auditoria 2026-03-21 10:00 UTC
**Status de coleta**: PARCIAL — aguarda autenticação AWS SSO para dados em tempo real

---

## Situação Crítica Imediata

> ALERTA P1: vault-prod-0 em Pending por 13h+ (desde ~09:00 UTC 2026-03-24)
> Volume EBS vol-065f3b18bebee9fc0 aguarda reattach.
> Impacto: Vault HA degradado, ExternalSecrets prod em risco.

---

## Executive Summary (Baseline 2026-03-21)

| Métrica | Valor Baseline | Status |
|---------|---------------|--------|
| Total pods Running (cluster) | ~320 | Baseline 2026-03-21 |
| Total nós | 15 | Baseline 2026-03-21 |
| Incidentes P1 ativos | 1 | vault-prod-0 Pending |
| Incidentes P2/P3 | 4 | GAPs conhecidos |
| Nodes healthy | 15/15 | Baseline 2026-03-21 |
| ArgoCD apps | Synced | Baseline (exceto Hatch=HOLD intencional) |
| ExternalSecrets | 15 SecretSynced | Baseline 2026-03-21 |

---

## Estado Esperado por Componente

### Cluster Staging (k8s-platform-staging)

| Componente | Namespace | Esperado | Baseline 2026-03-21 | Alerta |
|---|---|---|---|---|
| Backstage | staging-platform-backstage | 2/2 Running | 2/2 Running | — |
| Harbor staging | staging-data-harbor | 7/7 Running | 7/7 Running (Recreate fix) | — |
| SonarQube | staging-platform-sonarqube | 1/1 Running | 1/1 Running | — |
| GitLab Runner | staging-platform-gitlab | Running | Running | — |
| Hatch ETL | staging-data-hatch | 0/0 (HOLD) | 0 replicas intencional | — |
| Linkerd | linkerd | 3/3 Running | 3/3 Running | — |
| linkerd-viz | linkerd-viz | 4/4 Running | 4/4 Running (restarts dec.) | — |
| Calico | calico-system | 15/15 Running | 15/15 Running | — |
| ESO | kube-system | 1/1 Running | 1/1 Running (v0.9.11) | — |
| Tempo | staging-observability-monitoring | 6+ Running | 6+ Running (labels fix) | — |
| External-DNS | external-dns | 1/1 Running | 1/1 Running (kubernetes-sigs) | — |
| Velero | kube-system | 16 pods | 1 server + 15 agents | — |
| ArgoCD | argocd | Running | Running | — |
| Kyverno | kyverno | Running | Running | GAP-KYVERNO-POLICY-SPAM P3 |
| Vault staging | vault-system | Running | Running | — |
| loki-canary | staging-observability-monitoring | Pending | 1 pod Pending | GAP-LOKI-CANARY-AFFINITY P3 |

### Cluster Prod (k8s-platform-prod)

| Componente | Namespace | Esperado | Baseline 2026-03-21 | Alerta |
|---|---|---|---|---|
| **vault-prod-0** | prod-security-vault | 3/3 Running | **PENDING 13h** | **P1 CRÍTICO** |
| Harbor prod | prod-platform-harbor | 8/8 Running | 8/8 Running (ExternalSecret fix) | — |
| RabbitMQ prod | prod-data-rabbitmq | Running | Running | — |
| Tempo prod | production | 5 Running | 5 Running | — |

---

## Incidentes Ativos

| ID | Componente | Status | Prioridade | Causa Hipotética | SLA |
|----|-----------|--------|------------|-----------------|-----|
| INC-001 | vault-prod-0 | PENDING 13h+ | **P1** | EBS stuck in detaching após FinOps down/up | Imediato |

---

## GAPs Conhecidos

| GAP ID | Descrição | Prioridade | Status | Ação |
|--------|-----------|------------|--------|------|
| GAP-VAULT-PROD-PENDING | vault-prod-0 Pending — vol-065f3b18bebee9fc0 EBS reattach | P1 | ATIVO | Runbook: incident-vault-prod-p1.md |
| GAP-FINOPS-ACCESS-ENTRY | EKS auth mode CONFIG_MAP → precisa API_AND_CONFIG_MAP | P2 | BACKLOG | Aguarda janela de manutenção |
| GAP-LOKI-CANARY-AFFINITY | 1 pod loki-canary Pending NodeAffinity staging | P3 | BACKLOG | Corrigir affinity ou nodeSelector |
| GAP-KYVERNO-POLICY-SPAM | validate-service-naming gera eventos spam prometheus-operated | P3 | BACKLOG | Excluir namespace do ClusterPolicy |
| GAP-LAMBDA-FP-01 | Lambda orphan detector não filtra PV Bound | P3 | BACKLOG | Adicionar filtro no detector Lambda |

---

## FinOps — Lambda Status

| Lambda | Status | Última Invocação | Observação |
|--------|--------|-----------------|------------|
| finops-scheduler-start-staging | Funcional | 69 invocações/30d | UP automático |
| finops-scheduler-stop-staging | Funcional | — | DOWN automático |
| orphan-resource-detector-staging | Funcional | — | GAP-LAMBDA-FP-01: falsos positivos EBS |

**Nota**: O ciclo down/up da Lambda FinOps é a causa hipotética mais provável do vault-prod-0 Pending.
O nó original foi terminado durante o DOWN e o volume EBS `vol-065f3b18bebee9fc0` ficou stuck.

---

## Dependências Externas

| Serviço | Esperado | Último Estado Conhecido |
|---------|---------|------------------------|
| RDS PostgreSQL | AVAILABLE (v16.4) | AVAILABLE (baseline 2026-03-21) |
| Route53 | 3 hosted zones | Delegação NS confirmada |
| ACM | 4 certs ISSUED | ISSUED (baseline 2026-03-21) |
| ESO ExternalSecret Controller | Running v0.9.11 | Running (baseline) |
| Harbor registry | Funcional | 8/8 Running prod, 7/7 staging |
| Keycloak SSO | Running | Schedule 11:30 UTC configurado |

---

## Ações Recomendadas

### Imediatas (P1)

1. **Resolver vault-prod-0** — ver runbook em `incident-vault-prod-p1.md`:
   - Verificar estado atual do pod (pode ter se recuperado)
   - Se ainda Pending: investigar EBS vol-065f3b18bebee9fc0 na AWS
   - Provável ação: force detach + delete pod para re-scheduling

2. **Autenticar AWS SSO** para executar diagnóstico em tempo real

### Curto Prazo (P2)

3. **GAP-FINOPS-ACCESS-ENTRY** — migrar EKS auth mode para API_AND_CONFIG_MAP
   - Agendar janela de manutenção
   - Terraform: `access_config { authentication_mode = "API_AND_CONFIG_MAP" }`

### Backlog (P3)

4. **GAP-LOKI-CANARY-AFFINITY** — corrigir NodeAffinity do loki-canary
5. **GAP-KYVERNO-POLICY-SPAM** — adicionar exclusão para prometheus-operated
6. **GAP-LAMBDA-FP-01** — filtrar PV Bound no orphan detector

---

## Próximo Ciclo de Monitoramento

- Trigger: após autenticação AWS SSO (dados em tempo real)
- Componentes prioritários: vault-prod-0, ExternalSecrets prod, nodes após ciclo FinOps
- Relatório atualizado será gerado em: `monitoring-report-2026-03-24-realtime.md`

---

## Arquivos de Diagnóstico

| Arquivo | Descrição |
|---------|-----------|
| `incident-vault-prod-p1.md` | Runbook detalhado INC-001 |
| `diagnostics-scripts.sh` | Script kubectl completo |
| `monitoring-state-2026-03-24.md` | Log de sessão e estado |
| (pendente) | Dados em tempo real pós-autenticação |

---

## Nota de Coleta

Este relatório foi gerado com base no **baseline auditado em 2026-03-21** e no contexto fornecido
pelo usuário (vault-prod-0 Pending 13h detectado em 2026-03-24).

Dados em **tempo real** serão coletados via kubectl e aws CLI após renovação do AWS SSO token.
Script de poll em execução background — execução automática de diagnóstico ao autenticar.

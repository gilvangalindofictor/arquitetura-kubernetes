# Relatorio FinOps — Status Financeiro Atualizado

**Data:** 2026-03-10
**Cluster:** k8s-platform-prod (EKS 1.34)
**Periodo de Referencia:** Jan/2026 — Mar/2026
**Fonte Dados:** AWS Cost Explorer API + estimativas MTD
**Status Geral:** ATENCAO — Acima do budget em Mar/26 | DT-005 COMPLETO | VPA pendente

---

## 1. Resumo Executivo

| Metrica | Valor |
|---------|-------|
| **Custo Fevereiro 2026 REAL** | **$914.41 = R$ 5.487** |
| **Budget Marco 3 Aprovado** | $807/mes (R$ 4.841) |
| **Status Fevereiro vs Budget** | ACIMA em $107 (+13%) |
| **Forecast Marco 2026 (AWS ML)** | **$986/mes = R$ 5.916** |
| **Mar/2026 MTD estimado (10 dias)** | **~$350-400** |
| **Mar/2026 Daily rate** | ~$35-40/dia |
| **Status Marco vs Budget** | ACIMA em ~$179 (+22%) |
| **Reducao vs Baseline** | -40% (real Fevereiro) |
| **Savings Realizados (acumulado)** | **R$ 57.461/ano** (revisado 2026-03-10) |
| **Meta Original** | R$ 62.000/ano |
| **Realizacao vs Meta** | **92.7%** (93.8-94.4% pos-CloudWatch fix) |

**Nota de savings (revisado 2026-03-10):** Valor anterior era R$ 58.258.
Revisao: FinOps Automation ajustado de R$ 13.597 para R$ 12.800 (ADR-094 — exclusao intencional de
node groups system+critical do shutdown). Potencial adicional CloudWatch: R$ 720-1.080/ano (fix TF em andamento).
Ver logbook: `docs/logbook/2026-03-10-finops-gaps-analysis.md`

**Contexto do desvio vs budget:**
- Cluster autoscaler atingiu maximo durante trabalho de plataforma (Linkerd, GitLab, Keycloak)
- 9 nos ativos vs 7-8 esperados (workloads=4, system=3, critical=2)
- VPA rightsizing ainda nao executado — dados disponiveis, execucao pendente

---

## 2. Savings Totais Realizados — Estado 2026-03-10

### 2.1 Tabela Completa de Savings

| Otimizacao | Data | Economia Anual | Status |
|-----------|------|----------------|--------|
| EKS Upgrade 1.31 → 1.34 | 2026-02-10 | R$ 25.920 | ATIVO ✅ |
| ALBs deletados (nginx-test + echo-server) | 2026-02-11 | R$ 1.920 | ATIVO ✅ |
| NLBs deletados (RabbitMQ) | 2026-02-11 | R$ 384 | ATIVO ✅ |
| CloudWatch Logs retention | 2026-02-12 | R$ 54 | ATIVO ✅ |
| S3 Gateway Endpoint (NAT savings) | 2026-02-12 | R$ 900 | ATIVO ✅ |
| Orphan cleanup (EBS volumes + snapshots) | 2026-02-12 | R$ 2.221 | ATIVO ✅ |
| Orphan detector Lambda | 2026-02-12 | R$ 1.000 | ATIVO ✅ |
| EBS gp2 → gp3 (nodes + Prometheus) | 2026-02-13 | R$ 859 | ATIVO ✅ |
| Snapshot Cleanup Lambda | 2026-02-13 | R$ 216 | ATIVO ✅ |
| RDS Weekend Shutdown | 2026-02-18 | R$ 1.200 | ATIVO ✅ |
| Keycloak backup automation | 2026-02-18 | R$ 1.200 | ATIVO ✅ |
| SonarQube exporter | — | R$ 50 | ATIVO ✅ |
| FinOps FASE 2 — Automacao EventBridge | 2026-02-23 | R$ 12.800 ¹ | ATIVO ✅ |
| PDB Optimization — shutdown graceful | 2026-02-24 | R$ 4.405 | ATIVO ✅ |
| Snapshot DLM (3 policies: 30d/14d/7d) | 2026-02-27 | R$ 5.052 | ATIVO ✅ |
| Node Group Protection (custo confiabilidade) | 2026-02-27 | -R$ 720 | ATIVO ✅ |
| **TOTAL REALIZADOS (revisado 2026-03-10)** | | **R$ 57.461/ano** | **92.7% da meta** |
| CloudWatch Logs fix (5→3 log types + retention 30d→7d) | 2026-03-10 | R$ 720-1.080 ² | TF EM ANDAMENTO |
| **TOTAL POS-CLOUDWATCH FIX (estimado)** | | **R$ 58.181-58.541/ano** | **93.8-94.4%** |

> **¹ Savings FinOps Automation revisado (2026-03-10):** Valor anterior era R$ 13.597 (estimativa pre-ADR-094).
> Valor real = R$ 12.800 devido a exclusao intencional de node groups `system` e `critical` do shutdown
> automatico (ADR-094 — Node Group Protection). Custo residual weekend: ~$40-45/mes (4 nos × 48h).
> Ver logbook: `docs/logbook/2026-03-10-finops-gaps-analysis.md`
>
> **² CloudWatch saving potencial (2026-03-10):** Root cause confirmado — 5 log types ativos vs 3 recomendados
> (`controllerManager` + `scheduler` a remover). Fix Terraform em andamento. Saving confirmado apos apply + validacao Cost Explorer.

### 2.2 Reconciliacao com Documento Anterior

| Documento | Total | Diferenca |
|-----------|-------|-----------|
| finops-status-2026-03-06.md | R$ 56.546 | referencia anterior |
| finops-status-2026-03-10.md (publicacao inicial) | R$ 58.258 | +R$ 1.712 |
| finops-status-2026-03-10.md (revisado 2026-03-10) | R$ 57.461 | -R$ 797 vs inicial |
| Origem ajuste 2026-03-10 | FinOps Automation R$ 13.597→R$ 12.800 (ADR-094 node protection intencional) | — |
| Origem diferenca vs 03-06 | Inclusao EBS gp3 Prometheus (R$ 29) + reconciliacao Node Group Protection + arredondamentos - ajuste ADR-094 | — |

---

## 3. Status DT-005 — Slack → Teams (COMPLETO)

**Status:** CONCLUIDO em 2026-03-09

| Item | Estado |
|------|--------|
| 308+ referencias migradas (YAML/scripts/docs/TF) | COMPLETO ✅ |
| slackConfigs → msteamsConfigs nos AlertmanagerConfigs | COMPLETO ✅ |
| apiURL → webhookUrl nos payloads | COMPLETO ✅ |
| Vault: `secret/alertmanager/teams-webhook` populado | COMPLETO ✅ |
| Scripts: `send_slack_*` → `send_teams_*` (Teams MessageCard) | COMPLETO ✅ |
| Alertas financeiros operacionais via Teams | ATIVO ✅ |

**Impacto FinOps:** Alertas de budget (>$807/mes, anomalia +20% diario, EKS version warning) agora entregues via Teams webhook real.

---

## 4. FinOps Automation — 1o. Mes Completo

**Periodo:** 2026-02-23 a 2026-03-10 (~15 dias de operacao)
**Savings projetados:** R$ 13.597/ano (R$ 1.133/mes)

### 4.1 Componentes Ativos

| Componente | Funcao | Status |
|-----------|--------|--------|
| Lambda start-nodes | Startup EKS nodes + RDS (08:00 BRT seg-sex) | ATIVO ✅ |
| Lambda stop-nodes | Shutdown EKS nodes + RDS (18:00 BRT seg-sex) | ATIVO ✅ |
| EventBridge rules | Disparo automatico dos Lambdas | ATIVO ✅ |
| PDB circuit-breaker | Previne shutdown com pods criticos ativos | ATIVO ✅ |
| Teams notifications | Alertas de sucesso/falha (pos DT-005) | ATIVO ✅ |

### 4.2 Validacao Pendente

| Verificacao | Status | Acao |
|-------------|--------|------|
| Confirmar execucoes automaticas sem falhas (logs Lambda) | PENDENTE | Verificar CloudWatch Logs Lambda |
| Validar savings reais no Cost Explorer (semana 1-2 Mar) | PENDENTE | Comparar EC2 weekend cost Mar vs Feb |
| Teams notifications chegando no canal correto | PENDENTE | Testar disparo manual |

**Risco:** Sem validacao das execucoes, R$ 13.597/ano esta em risco caso Lambda falhe silenciosamente.

---

## 5. VPA Rightsizing — Status PENDENTE (Prioridade Mantida)

**Historico:**
- 2026-03-06: VPA staging CANCELADO (ROI insuficiente, dados ruidosos, cluster instavel)
- 2026-03-10: VPA para producao permanece PENDENTE como proxima alavanca principal

**Estado atual dos dados VPA (staging, referencia para producao):**

| Workload | CPU Request recomendado | Memory Request recomendado | Fonte |
|----------|------------------------|---------------------------|-------|
| redis | 25m | 65Mi | VPA uncappedTarget staging |
| harbor-core | 15m | 65Mi | VPA uncappedTarget staging |
| Demais workloads | Usar staging como referencia inicial | VPA day-1 producao | Coletar em producao |

**Economia projetada (producao, pos-deploy):**
- R$ 25.000-35.000/ano (cluster 24/7, maior que staging)
- Reducao de 9 para 7 nos: -$60-80/mes

**Prerequisito:** Deploy de producao (data TBD).

---

## 6. Dados MTD Marco 2026 (Estimativa)

### 6.1 Custos Reais Disponiveis (2026-03-01 a 2026-03-05)

| Data | Custo Total | Observacao |
|------|-------------|------------|
| 2026-03-01 | $59.65 | Tax mes + sabado com nos ativos |
| 2026-03-02 | $39.69 | Domingo — cluster em atividade |
| 2026-03-03 | $37.03 | Segunda — platform work |
| 2026-03-04 | $39.83 | Terca — GitLab rev 12-14 |
| 2026-03-05 | $22.82 | Quarta parcial |
| **MTD 5 dias (real)** | **$199.02** | |

### 6.2 Estimativa MTD 10 dias (2026-03-10)

| Periodo | Estimativa | Base de Calculo |
|---------|-----------|-----------------|
| Mar 01-05 (real) | $199.02 | Cost Explorer |
| Mar 06-09 (estimado, post-DT-005) | ~$120-150 | $30-37/dia (dias uteis) |
| Mar 10 (hoje, parcial) | ~$30-40 | Rate atual |
| **Total MTD estimado (10 dias)** | **~$350-400** | |

**Rate diario esperado pos-DT-005:** $30-37/dia (sem mudancas estruturais de custo — DT-005 e migracao de configuracao, nao de infraestrutura).

---

## 7. Alertas e Riscos Financeiros

| Prioridade | Item | Impacto | Acao Recomendada |
|------------|------|---------|-----------------|
| P0 | **Forecast Marco acima do budget** ($986 vs $807) | +$179/mes | Aceitar temporariamente — aguardar VPA producao |
| P0 | **FinOps Automation nao validada (1o. mes)** | R$ 13.597/ano em risco | Verificar logs Lambda + Cost Explorer |
| P1 | **VPA Rightsizing nao executado** | -R$ 25-35K/ano perdido | Depende de deploy producao |
| P1 | **CloudWatch acima do esperado** ($34/mes vs $21) | -$13/mes potencial | Revisar log retention + custom metrics |
| P2 | **Karpenter + Spot** (staging) | R$ 6.696/ano potencial | Aguardar estabilizacao pos-Backstage |

---

## 8. Proximos Passos

### Imediato (Marco 2026)

| Acao | Impacto | Responsavel |
|------|---------|-------------|
| Validar execucoes FinOps Automation (logs Lambda) | R$ 13.597/ano confirmado | FinOps + DevOps |
| Verificar Teams notifications chegando | Alertas financeiros operacionais | DevOps |
| Investigar CloudWatch $34/mes | -$13/mes potencial | SRE |

### Curto Prazo (Abr/2026)

| Acao | Impacto | Responsavel |
|------|---------|-------------|
| VPA Rightsizing producao (dia 1 do deploy) | R$ 25-35K/ano | SRE + FinOps |
| Savings Plans 1yr No-Upfront (apos 30d prod) | R$ 11.363/ano | FinOps |
| RDS Reserved Instance 1yr (apos 30d prod) | R$ 3.024/ano | FinOps |

### Medio Prazo (2026 H2)

| Acao | Impacto | Decisao |
|------|---------|---------|
| Karpenter + Spot Instances (staging) | R$ 6.696/ano | Aguardar estabilizacao |
| Graviton ARM64 (apos VPA producao) | R$ 6.984/ano | Sequencial apos VPA |
| Savings Plans producao (1yr) | R$ 11.363/ano | Apos 30d producao ativa |

---

## 9. KPIs Mensais — Revisao 2026-03-10

| KPI | Meta | Fevereiro Real | Marco Forecast | Marco MTD (est.) | Status |
|-----|------|----------------|----------------|-----------------|--------|
| Custo Mensal | <= $807 | $914 | $986 | ~$350-400 (10d) | ATENCAO |
| EKS Standard Support | $73/mes | $182 (transicao) | $69 | On track | OK |
| EC2 Weekend Shutdown | <$1/dia | $12-25/dia | Variavel | Monitorar | MONITORAR |
| FinOps Automation | 95% sucesso | 100% (manual) | 1o. mes auto | Validacao pendente | VALIDAR |
| VPA Rightsizing | 10 workloads | 0/10 | 0/10 | 0/10 | PENDENTE |
| Savings Realizados | R$ 62K/ano | R$ 58.258 | R$ 57.461 (rev.) | R$ 57.461 (rev.) | 92.7% |
| DT-005 Teams | COMPLETO | COMPLETO | COMPLETO | COMPLETO | OK ✅ |

---

## 10. Comparativo vs Targets

| Cenario | Custo Mensal | Custo Anual | Status vs Budget |
|---------|--------------|-------------|-----------------|
| Baseline (Jan/26) | R$ 9.179 | R$ 110.147 | REFERENCIA |
| Budget Marco 3 Aprovado | R$ 4.841 | R$ 58.092 | META |
| **Fevereiro 2026 REAL** | **R$ 5.487** | **R$ 65.844** | **ACIMA +13%** |
| **Marco 2026 Forecast** | **R$ 5.916** | **R$ 70.992** | **ACIMA +22%** |
| Apos VPA Rightsizing Producao (Abr/26) | R$ 3.600-4.800 | R$ 43-58K | PROXIMO/DENTRO BUDGET |
| Apos Karpenter + Spot (2026 H2) | R$ 2.400-3.600 | R$ 29-43K | ABAIXO DO BUDGET |

---

**Preparado em:** 2026-03-10
**Revisao programada:** 2026-04-10 (pos VPA producao + validacao FinOps Automation)
**Documento anterior:** [docs/finops/finops-status-2026-03-06.md](finops-status-2026-03-06.md)
**Owner:** FinOps Team + Platform Team

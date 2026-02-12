# 📂 FinOps Analysis — Kubernetes Platform AWS

**Last Updated:** 2026-02-12
**Status:** Historical (Superseded by Quick Wins implementation)
**Owner:** FinOps Team + Platform Team
**Scope:** Cost Analysis & Optimization Roadmap

**Data Análise:** 2026-02-10
**Cluster:** k8s-platform-prod (EKS 1.31 → 1.34)
**Status Original:** 🔴 ANOMALIA CRÍTICA DETECTADA (+59% over-budget)
**Status Atual:** ✅ RESOLVIDO (R$ 34.462/ano savings realizados)

---

## 📋 Índice de Documentos

| # | Documento | Descrição | Público-Alvo | Páginas |
|---|-----------|-----------|--------------|---------|
| 1 | [**executive-summary-finops.md**](executive-summary-finops.md) | Resumo executivo (TL;DR) | CTO, CFO, Leadership | 8 |
| 2 | [**cost-analysis-real-vs-projected.md**](cost-analysis-real-vs-projected.md) | Análise detalhada custos (tabelas comparativas) | FinOps Team, DevOps Lead | 25 |
| 3 | [**optimization-roadmap-90days.md**](optimization-roadmap-90days.md) | Roadmap executivo 90 dias (priorização ROI) | DevOps Team, SRE, FinOps | 35 |
| 4 | [**savings-calculator.md**](savings-calculator.md) | Calculadora de economia (planilha projeções) | FinOps Team, CFO | 18 |

---

## 🎯 Quick Summary (3 Minutos)

### Problema Identificado

O cluster EKS k8s-platform-prod está **59% acima do orçamento** projetado no quickstart, custando **R$ 9.179/mês** vs R$ 5.755 esperado.

**Anomalia Crítica:** EKS versão 1.31 entrou em Extended Support em 28/Jan/2026 (mesma data do deploy), gerando **+$360/mês** de custo inesperado (+493% vs standard support).

### Solução Proposta

**Roadmap 90 dias** com 12 iniciativas de otimização, divididas em 3 fases:

1. **Quick Wins (Semana 1-3):** -R$ 2.562/mês (-28%)
2. **Medium Wins (Semana 4-10):** -R$ 4.008/mês total (-44%)
3. **Strategic Wins (Semana 11-13):** -R$ 5.238/mês total (-57%)

**Meta Alcançável:** Reduzir custo para **R$ 5.171/mês** em 90 dias (cenário Medium Wins).

### Top 3 Ações Imediatas

| # | Ação | Economia/Ano | Esforço | Prazo |
|---|------|--------------|---------|-------|
| 1 | **EKS Upgrade 1.31→1.34** | **R$ 25,920** | 4h | 1 semana |
| 2 | **VPA + EC2 Rightsizing** | R$ 8,712 | 24h | 6 semanas |
| 3 | **Shared ALB Implementation** | R$ 2,304 | 4h | 1 semana |

**Total Top 3:** R$ 36,936/ano com investimento <32h engineering.

---

## 📊 Resumo de Custos

### Comparativo Cenários

| Cenário | Custo Mensal | Custo Anual | vs Baseline | Status |
|---------|--------------|-------------|-------------|--------|
| **Baseline (Atual)** | R$ 9,179 | R$ 110,147 | - | 🔴 OVER-BUDGET |
| **Quickstart Projetado** | R$ 5,755 | R$ 69,060 | -38% | ✅ TARGET |
| **Quick Wins** | R$ 6,617 | R$ 79,404 | -28% | 🟡 MELHORIA |
| **Medium Wins** | R$ 5,171 | R$ 62,052 | -44% | 🟢 RECOMENDADO |
| **Strategic Wins** | R$ 3,941 | R$ 47,292 | -57% | ✅ ÓTIMO |

### Breakdown Variâncias vs Quickstart

| Categoria | Quickstart | Realidade | Delta | Causa Raiz |
|-----------|-----------|-----------|-------|------------|
| **EKS Control Plane** | $73 | **$433** | **+$360** | Extended Support 1.31 🔴 |
| **EC2 Nodes** | $454 | **$607** | **+$153** | Overprovisioning (critical 3 nodes vs 2) 🟠 |
| **Networking** | $145 | **$182** | **+$37** | 5 ALBs vs 3 planejados 🟡 |
| **VPC Endpoints** | $0 | **$29** | **+$29** | PrivateLink (justificado) ✅ |
| **Storage** | $47 | **$59** | **+$12** | Growth + gp2 legacy 🟡 |
| **Outros** | $42 | **$59** | **+$17** | Observability + prod workloads 🟢 |

---

## 🚀 Recomendações Executivas

### Prioridade 0 (Imediato - Esta Semana)

**1. EKS Upgrade 1.31 → 1.34**
- **Economia:** $360/mês ($4,320/ano) = R$ 25,920/ano
- **Esforço:** 4 person-hours
- **Risco:** BAIXO (managed upgrade)
- **Prazo:** 2 dias (staging + prod)
- **Ação:** DevOps Team inicia upgrade staging 11/Fev

**2. Weekend Shutdown EventBridge Fix**
- **Economia:** $10/mês ($120/ano) = R$ 720/ano
- **Esforço:** 15 minutes
- **Risco:** ZERO
- **Prazo:** 1 dia
- **Ação:** Terraform apply imediato

### Prioridade 1 (Próximas 2 Semanas)

**3. EBS gp2→gp3 Migration**
- **Economia:** $12/mês ($144/ano) = R$ 864/ano
- **Esforço:** 2 hours
- **Prazo:** 1 semana

**4. Shared ALB (IngressGroup)**
- **Economia:** $32/mês ($384/ano) = R$ 2,304/ano
- **Esforço:** 4 hours
- **Prazo:** 1 semana

**5. S3 Intelligent Tiering**
- **Economia:** $8/mês ($96/ano) = R$ 576/ano
- **Esforço:** 2 hours
- **Prazo:** 1 dia

### Prioridade 2 (Próximos 2 Meses)

**6. VPA + EC2 Rightsizing**
- **Economia:** $121/mês ($1,452/ano) = R$ 8,712/ano
- **Esforço:** 24 hours (setup + análise + execution)
- **Prazo:** 6 semanas (30d VPA metrics collection)

**7. Savings Plans Purchase**
- **Economia:** $120/mês ($1,440/ano) = R$ 8,640/ano
- **Esforço:** 6 hours (analysis + purchase)
- **Prazo:** 1 semana

---

## 📈 ROI e Payback

### Quick Wins (Recomendação Imediata)

**Investimento:**
- Engineering: 13.25h × R$ 300/h = **R$ 3,975**
- Infrastructure: $0 (zero capex)

**Retorno:**
- Economia Mensal: R$ 2,562
- Economia Anual: **R$ 30,744**

**ROI Year 1:** 773% (+R$ 26,769 net profit)
**Payback:** 1.55 meses (47 dias)

### Medium Wins (Meta 90 Dias)

**Investimento:**
- Engineering: 43.25h × R$ 300/h = **R$ 12,975**
- Savings Plans: commitment mensal (não upfront)

**Retorno:**
- Economia Mensal: R$ 4,008
- Economia Anual: **R$ 48,096**

**ROI Year 1:** 371% (+R$ 35,121 net profit)
**Payback:** 3.2 meses (96 dias)

---

## ⚠️ Riscos Críticos

### Risco #1: EKS Upgrade Breaking Changes

**Probabilidade:** BAIXO
**Impacto:** ALTO (cluster downtime)

**Mitigação:**
- Upgrade staging primeiro (validação 48h)
- Kubernetes deprecation warnings pre-check
- AWS managed add-ons auto-update (compatibilidade garantida)
- Rollback: NÃO SUPORTADO (upgrades irreversíveis)

### Risco #2: Rightsizing Performance Degradation

**Probabilidade:** MÉDIO
**Impacto:** ALTO (service latency)

**Mitigação:**
- VPA 30 dias metrics collection (dados reais)
- Conservative approach (reduction -20% first iteration)
- Gradual rollout (non-critical → critical)
- Monitoring 72h antes declare success
- Rollback: Helm rollback (zero downtime)

### Risco #3: Spot Instance Interruptions

**Probabilidade:** MÉDIO (2min notice AWS)
**Impacto:** MÉDIO (pod rescheduling)

**Mitigação:**
- PodDisruptionBudgets (garantir quorum/HA)
- Node affinity (critical workloads → on-demand only)
- Instance type diversification (reduce correlation)
- Karpenter rapid provisioning fallback

---

## 📅 Próximos Passos

### Esta Semana (11-17/Fev)

- [ ] **[P0]** Apresentar executive summary para CTO/CFO (aprovação budget)
- [ ] **[P0]** EKS Upgrade staging 1.31→1.34 (11/Fev)
- [ ] **[P0]** EKS Upgrade prod 1.31→1.34 (12/Fev)
- [ ] **[P0]** Weekend shutdown EventBridge fix (11/Fev)
- [ ] **[P1]** EBS gp2→gp3 migration (12-14/Fev)
- [ ] **[P1]** Shared ALB implementation (17-20/Fev)

### Próximas 2 Semanas (18/Fev - 3/Mar)

- [ ] **[P1]** VPA deployment + ServiceMonitors (18-20/Fev)
- [ ] **[P1]** S3 Intelligent Tiering + GitLab cleanup (21/Fev)
- [ ] **[P2]** VPA metrics collection start (25/Fev → 30d)
- [ ] **[P2]** Validação Quick Wins Cost Explorer (1/Mar)

### Próximos 2 Meses (Mar-Abr)

- [ ] **[P2]** VPA analysis + rightsizing plan (27-30/Mar)
- [ ] **[P2]** Rightsizing execution gradual (1-14/Abr)
- [ ] **[P2]** Savings Plans analysis + purchase (17-24/Abr)
- [ ] **[P3]** Karpenter evaluation (opcional, Q2)

---

## 🎓 Lições Aprendidas

### 1. EKS Version Lifecycle Tracking é CRÍTICO

**Problema:**
- Deploy cluster com EKS 1.31 no EXATO dia de EOL Standard Support (28/Jan/2026)
- Custo inesperado: +$360/mês (+493%) = R$ 25,920/ano desperdício

**Solução:**
- Automated alerts CloudWatch 90 dias antes EOL
- Terraform data source: check EKS available versions
- Policy: SEMPRE deploy latest stable version (N-1 max)

### 2. VPC Endpoints = Investment, Not Waste

**Aparente Overhead:** +$29/mês (+∞ vs quickstart)

**Real Value:**
- Incident prevention: -$3,000/ano (Vault 15h downtime evitado)
- Latency: 50-200ms → <5ms (10-40x faster IRSA calls)
- Reliability: 100% → 0% CSI driver error rate

**ROI:** +762% (payback <2 meses)

### 3. Overprovisioning Detection Requer VPA

**Problema:**
- Critical nodes scaled 2→3 (emergency response Vault FailedScheduling)
- Overhead: +$121/mês desperdiçado após incident resolution

**Solução:**
- VPA desde Dia 1 (não retroativo)
- 30 dias metrics ANTES de qualquer scale-up decision
- Rightsizing = parte da Definition of Done

### 4. FinOps Automation ROI é Exponencial

**Investimento:** R$ 1,200 (Lambda + EventBridge)
**Savings:** R$ 4,320/ano (weekend shutdown staging)
**ROI:** +260%

**Conclusão:** Automação FinOps SEMPRE positivo ROI (set-and-forget)

---

## 📎 Recursos Adicionais

### Documentação Interna

- [costs.md](../context/costs.md) - Histórico custos Marco 0-3
- [architecture.md](../context/architecture.md) - Inventário recursos atual
- [aws-eks-gitlab-quickstart.md](../plan/quickstart/aws-eks-gitlab-quickstart.md) - Baseline projetado
- [2026-02-09-cluster-remediation.md](../logbook/2026-02-09-cluster-remediation.md) - Incident Vault

### AWS Resources

- [EKS Version Lifecycle](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [Savings Plans Calculator](https://aws.amazon.com/savingsplans/compute-pricing/)
- [Cost Explorer Best Practices](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html)

### Ferramentas

- [AWS Cost Explorer](https://console.aws.amazon.com/cost-management/home)
- [Grafana FinOps Dashboard](http://grafana.k8s-platform.internal/d/finops)
- [VPA GitHub](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [Karpenter Documentation](https://karpenter.sh/docs/)

---

## 📧 Contato

**FinOps Team:**
- Responsável: DevOps Lead
- Email: gilvan.galindo@fctconsig.com.br
- Slack: #finops-optimization

**Aprovações Necessárias:**
- CTO: Savings Plans commitment >$1,000
- CFO: Budget reallocation se overrun >10%

**Próxima Revisão:** 2026-03-10 (30 dias pós Quick Wins)

---

**Última Atualização:** 2026-02-10
**Versão:** 1.0
**Status:** 🟢 PRONTO PARA APRESENTAÇÃO

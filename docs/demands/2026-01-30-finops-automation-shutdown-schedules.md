# 📋 DEMANDA — Implementação de Automação FinOps Planejada no Quickstart

**Data:** 2026-01-30
**Solicitante:** Gilvan Galindo
**Prioridade:** Alta
**Impacto:** Baixo (feature já planejada, implementação técnica)
**Referência:** [aws-eks-gitlab-quickstart.md](../plan/quickstart/aws-eks-gitlab-quickstart.md#implementação-da-automação-startstop)

---

## 🎯 OBJETIVO

Implementar a **automação de start/stop do ambiente Staging** conforme planejado no Quickstart (linha 452-469), utilizando os scripts já validados:
- **Ambiente Único:** Apenas STAGING (dev não existe, prod é 24/7)
- **Schedule Definido:** Segunda-sexta 8h-18h BRT (já planejado)
- **Economia Esperada:** R$ 450/mês (R$ 5.400/ano) - já calculada
- **Workloads Críticos:** GitLab, Harbor, ArgoCD (conforme marco3 planejado)

---

## 📊 CONTEXTO ATUAL

### Scripts Existentes
- ✅ [shutdown-marco2.sh](../../scripts/finops/shutdown-marco2.sh) - Desliga nodes + RDS
- ✅ [startup-marco2.sh](../../scripts/finops/startup-marco2.sh) - Liga nodes + RDS
- ✅ Primeira execução manual bem-sucedida (2026-01-30 10:00 BRT)

### Economia Validada (Execução Manual Hoje)
- **Teste Realizado:** Shutdown Marco 2 atual (2026-01-30 10:00 BRT)
- **Snapshot RDS:** `k8s-platform-prod-postgresql-shutdown-20260130-100049`
- **Economia Observada:** $8.07/dia ($177.61/mês para 8h/dia útil)

### Economia Esperada Staging (Quickstart)
- **Custo Staging 24/7:** $187/mês (R$ 1.122/mês)
- **Custo Staging Scheduled (50h/semana):** $112/mês (R$ 672/mês)
- **Economia:** $75/mês (R$ 450/mês, R$ 5.400/ano)

### Limitações Atuais
- ⚠️ Execução manual (requer intervenção humana diária)
- ⚠️ Sem calendário por ambiente (dev vs staging vs prod)
- ⚠️ Sem exceções de serviços (GitLab seria desligado junto)
- ⚠️ Sem validação automática pós-startup (health checks)

---

## 🔍 DEMANDA DETALHADA

### 1. Calendário Staging (ÚNICO AMBIENTE COM AUTOMAÇÃO)

**Ambiente STAGING (conforme Quickstart linha 391-402):**
- **Shutdown:** Segunda a sexta, 18:00 BRT
- **Startup:** Segunda a sexta, 08:00 BRT
- **Weekends:** Desligado completo (startup manual se emergência)
- **Feriados:** Desligado (integração BrasilAPI)
- **Uptime:** 50h/semana (10h/dia útil)
- **Economia Esperada:** R$ 450/mês (vs Staging 24/7)

**Ambiente PROD:**
- **Status:** 24/7 permanente (SEM automação)
- **Manutenção:** Janelas planejadas manualmente
- **Justificativa:** Alta disponibilidade prioritária

**Ambiente DEV:**
- **Status:** ❌ NÃO EXISTE (decisão arquitetural Quickstart)
- **Razão:** Staging assume papel dual (dev + homologação)
- **Economia:** R$ 1.026/mês eliminando Dev dedicado

### 2. Exceções de Serviços (Workloads Críticos)

**Serviços que NÃO podem ser desligados em nenhum ambiente:**
- **GitLab** - CI/CD crítico (webhooks, runners, registry)
- **Harbor** - Container registry (dependência de deploys)
- **ArgoCD** - GitOps controller (reconciliação contínua)
- **Cert-Manager** - Renovação automática de certificados TLS
- **External-DNS** - Sincronização Route53

**Estratégia Proposta:**
1. **Node Group Isolation:** Criar node group `critical-always-on` (1 node t3.small)
2. **Affinity/Taints:** Garantir que workloads críticos rodem apenas nesse node group
3. **Shutdown Seletivo:** Scripts desligam apenas `system`, `workloads`, mas mantém `critical-always-on`

**Custo Adicional:** +$15/mês (1× t3.small 24/7)
**Economia Líquida:** $162/mês (ainda 23.6% redução)

### 3. Validação Automática Pós-Startup

**Health Checks Obrigatórios (timeout 10 min):**
- [ ] Nodes Ready: 7/7 (ou 6/6 se critical-always-on separado)
- [ ] Pods Running: ≥95% (tolerar 5% transitório)
- [ ] RDS Available: `available` status
- [ ] GitLab Health: `/health` endpoint 200 OK
- [ ] ArgoCD Sync: Applications não degraded
- [ ] Prometheus Targets: ≥90% up

**Rollback Automático se Falha:**
- Notificar Slack/SNS com erro detalhado
- Manter nodes ligados para troubleshooting manual
- Criar incident ticket automático (PagerDuty/Jira)

### 4. Arquitetura de Automação Proposta

**Opção A: EventBridge + Lambda (Recomendado)**

```text
EventBridge Rule (cron)
  ↓
Lambda Function (shutdown/startup)
  ↓
  ├─ Verificar calendário (ambiente + feriados)
  ├─ Verificar exceções (workloads críticos)
  ├─ Executar AWS CLI (scale node groups, stop RDS)
  ├─ Aguardar health checks (startup)
  └─ Notificar resultado (SNS → Slack)
```

**Custo:** ~$0.50/mês (Lambda invocations + EventBridge)
**Prós:** Serverless, barato, AWS-native
**Contras:** Lógica em Python (não Terraform-native)

**Opção B: GitHub Actions + Terraform Cloud**

```text
GitHub Actions (cron)
  ↓
Terraform Cloud Run
  ↓
  ├─ terraform apply -target=module.shutdown
  ├─ Workspaces por ambiente (dev, staging, prod)
  └─ Remote state + locking automático
```

**Custo:** $0/mês (GitHub Actions free tier)
**Prós:** Terraform-native, auditável via TF state
**Contras:** Slower (cold start ~2 min vs Lambda 5s)

**Opção C: Kubernetes CronJob + Custom Controller**

```text
CronJob (in-cluster)
  ↓
Custom Controller (Go/Python)
  ↓
  ├─ Watch Custom Resources (ShutdownSchedule CRD)
  ├─ Reconcile workloads (scale down/up)
  └─ Emit metrics to Prometheus
```

**Custo:** +$5/mês (controller pod overhead)
**Prós:** Kubernetes-native, observável
**Contras:** Mais complexo, requer manutenção controller

---

## 🤔 QUESTÕES PARA OS AGENTES

### Para DevOps AWS Specialist:
1. EventBridge vs GitHub Actions: qual mais resiliente para shutdown crítico?
2. Como garantir que Lambda/GHA não falhe silenciosamente?
3. RDS stop tem limitação de 7 dias auto-restart - snapshot diário obrigatório?
4. Validação de custos: Lambda frio vs warm (reserved concurrency)?

### Para Terraform Specialist:
1. Como modelar calendários como Terraform variables (JSON/YAML)?
2. State drift: shutdown via Lambda impacta Terraform state?
3. Módulo reutilizável `finops-scheduler` - estrutura recomendada?
4. Locks DynamoDB: Lambda precisa adquirir lock antes de modificar infra?

### Para FinOps:
1. Custo-benefício: Opção A vs B vs C?
2. Break-even: quantos ambientes justificam automação complexa?
3. Economia adicional: Reserved Instances nos nodes critical-always-on?
4. Dashboard CloudWatch: métricas essenciais de economia real-time?

### Para Security & Compliance:
1. IAM permissions mínimas para Lambda (shutdown/startup)?
2. Auditoria: CloudTrail events suficientes ou precisa logging adicional?
3. Rollback automático: riscos de loop infinito (startup fail → shutdown → startup)?
4. Secrets: credenciais GitLab/ArgoCD em Secrets Manager ou Parameter Store?

---

## 📅 CALENDÁRIO DE FERIADOS (Brasil 2026)

**Feriados Nacionais - Shutdown Obrigatório (dev/staging):**
- 2026-02-16: Carnaval (segunda-feira)
- 2026-02-17: Carnaval (terça-feira)
- 2026-04-03: Paixão de Cristo (sexta-feira)
- 2026-04-21: Tiradentes
- 2026-05-01: Dia do Trabalho
- 2026-06-04: Corpus Christi (quinta-feira)
- 2026-09-07: Independência do Brasil
- 2026-10-12: Nossa Senhora Aparecida
- 2026-11-02: Finados
- 2026-11-15: Proclamação da República
- 2026-11-20: Consciência Negra
- 2026-12-25: Natal

**Fonte de Dados Proposta:**
- API: `https://brasilapi.com.br/api/feriados/v1/{year}` (gratuita)
- Fallback: JSON estático em S3/Parameter Store

---

## 💰 PROJEÇÃO DE ECONOMIA ANUAL

### Cenário 1: Automação Simples (Opção A - Lambda)

| Componente | Custo Mensal | Observação |
|------------|--------------|------------|
| **Dev Shutdown (8h/dia)** | -$177.61 | Economia já validada |
| **Staging Shutdown (11h/dia)** | -$150.00 | Estimativa conservadora |
| **Prod Maintenance Window** | -$5.00 | 3h/semana domingo madrugada |
| **Node Critical Always-On** | +$15.00 | 1× t3.small 24/7 (GitLab, etc) |
| **Lambda Executions** | +$0.50 | 44 invocations/mês (2×/dia × 22 dias) |
| **CloudWatch Logs** | +$2.00 | Retention 7 dias |
| **SNS Notifications** | +$0.10 | Alertas Slack |
| **TOTAL ECONOMIA MENSAL** | **-$315.01** | |
| **TOTAL ECONOMIA ANUAL** | **-$3.780.12** | |

**ROI Ano 1:** ($3.780 - $1.000 desenvolvimento) / $1.000 = **278% ROI**

### Cenário 2: Automação Avançada (Opção C - CronJob Controller)

| Componente | Custo Adicional Mensal | Observação |
|------------|------------------------|------------|
| Cenário 1 | -$315.01 | Base |
| Controller Pod Overhead | +$5.00 | CPU/Memory controller |
| Prometheus Metrics | +$0.50 | Custom metrics storage |
| **TOTAL ECONOMIA MENSAL** | **-$309.51** | |
| **TOTAL ECONOMIA ANUAL** | **-$3.714.12** | |

**ROI Ano 1:** ($3.714 - $2.500 desenvolvimento) / $2.500 = **149% ROI**

**Recomendação:** Cenário 1 (Lambda) - ROI superior, menor complexidade

---

## 🎯 CRITÉRIOS DE SUCESSO

### Fase 1 - MVP (Semana 1-2)
- [ ] Lambda function criada (Python 3.12)
- [ ] EventBridge rules configurados (2 regras: shutdown 18:00, startup 08:00)
- [ ] Health checks implementados (nodes, RDS, GitLab)
- [ ] Notificações Slack configuradas (success + failure)
- [ ] Teste manual: shutdown sexta 18:00 → startup segunda 08:00
- [ ] Documentação: runbook troubleshooting

### Fase 2 - Produção (Semana 3-4)
- [ ] Calendário de feriados integrado (BrasilAPI)
- [ ] Node group `critical-always-on` criado (1× t3.small)
- [ ] Workloads críticos migrados (GitLab, Harbor, ArgoCD, Cert-Manager)
- [ ] Rollback automático implementado (max 3 retries)
- [ ] Dashboard CloudWatch FinOps (economia real-time)
- [ ] Alerta PagerDuty (falha startup > 10 min)

### Fase 3 - Otimizações (Mês 2)
- [ ] Reserved Instances para node critical-always-on (-31% custo)
- [ ] Análise de padrões: ajustar horários baseado em uso real
- [ ] A/B test: staging com shutdown agressivo (shutdown 17:00 vs 20:00)
- [ ] Cost Explorer tags: rastrear economia por ambiente

---

## 📚 DOCUMENTOS RELACIONADOS

- [costs.md](../context/costs.md) - Atualizar seção FinOps Automation
- [decisions.md](../context/decisions.md) - Criar ADR-024: FinOps Automation Strategy
- [architecture.md](../context/architecture.md) - Documentar Lambda + EventBridge architecture
- [risks.md](../context/risks.md) - Riscos: Loop infinito, falha silenciosa Lambda

---

## 🚀 PRÓXIMOS PASSOS

1. **Ativar Agentes Especialistas** - Validar decisões técnicas
2. **Criar Módulo Terraform** - `finops-scheduler` reutilizável
3. **Desenvolver Lambda Function** - Python 3.12 + boto3
4. **Configurar EventBridge** - Cron expressions por ambiente
5. **Testes em Dev** - Validar shutdown/startup automatizado (1 semana)
6. **Rollout Staging** - Expandir automação (2 semanas)
7. **Dashboard FinOps** - Métricas economia (4 semanas)

---

**Status:** 🟡 Aguardando Consenso dos Agentes
**Próxima Ação:** Ativar Task tool para análise multi-agente

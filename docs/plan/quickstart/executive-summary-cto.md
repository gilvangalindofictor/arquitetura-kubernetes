# Resumo Executivo — AWS EKS Platform (GitLab + Observability)
**Data:** 2026-01-15

---

## TL;DR — Números que importam

| Métrica | Valor |
|---------|-------|
| **Investimento Ano 1** | R$ 45.488 - R$ 46.488 |
| **Custo operacional mensal** | R$ 3.624 (otimizado) |
| **Timeline de implantação** | 6 semanas (3 sprints) |
| **Esforço de engenharia** | 262 person-hours (time interno) |
| **Economia vs modelo tradicional** | -29% (R$ 17.712/ano) |
| **Economia projetada (3 anos)** | R$ 16.200 + R$ 19.000 (com Savings Plans) |

---

## 1. Estratégia e Proposta de Valor

### Arquitetura Proposta
Implantação de plataforma Kubernetes gerenciada (AWS EKS) com:
- **GitLab CE** (CI/CD enterprise-grade)
- **Observability Stack** completa (OpenTelemetry + Prometheus + Grafana + Loki + Tempo)
- **Data Services** resilientes (PostgreSQL Multi-AZ, Redis HA, RabbitMQ)
- **Security-first**: WAF, Network Policies, encrypted-at-rest, RBAC least-privilege

### Decisão Arquitetural Chave: 2 Ambientes
**Staging (homologação) + Prod** — Sem ambiente Dev dedicado

**Justificativa:**
- **Economia de 20%**: R$ 12.312/ano (vs arquitetura com 3 ambientes)
- Staging assume papel dual (dev + homologação)
- Otimização de recursos sem comprometer qualidade

### Benefícios de Negócio
✅ **Time-to-Market**: Deploy automatizado via GitLab CI/CD
✅ **Confiabilidade**: Multi-AZ, HA, backups automáticos
✅ **Visibilidade**: Observability end-to-end (metrics, logs, traces)
✅ **Escalabilidade**: Auto-scaling horizontal pronto (3 node groups)
✅ **Segurança**: WAF, IP allowlist, encryption, NetworkPolicies

---

## 2. Timeline de Implantação

### Execução em 3 Sprints (6 semanas)

| Sprint | Foco | Duração | Entregáveis Chave |
|--------|------|---------|-------------------|
| **Sprint 1** | Fundação + GitLab | 2 semanas | VPC Multi-AZ, EKS Cluster, GitLab operacional, RDS/Redis/RabbitMQ |
| **Sprint 2** | Observability | 2 semanas | Prometheus, Grafana, Loki, Tempo, Dashboards baseline |
| **Sprint 3** | Hardening + DR | 2 semanas | WAF, NetworkPolicies, Backups testados, **DR Drill obrigatório** |

**Tempo Total:** 6 semanas 

**Esforço:** 262 person-hours (~33 dias úteis)

---

## 3. Investimento Financeiro

### Custos de Desenvolvimento (One-time)

| Item | Custo |
|------|-------|
| **Engenharia interna** | Time interno (262 person-hours) |
| **Infraestrutura AWS (dev/testes)** | R$ 2.000 - R$ 3.000 *(6 semanas)* |
| **TOTAL Fase Implantação** | **R$ 2.000 - R$ 3.000** |

**⚠️ Nota sobre custos:** Valores baseados em:
- **Cotação:** USD → BRL = R$ 6,00 (referência jan/2026)
- **Região AWS:** us-east-1 (N. Virginia)
- **Modelo de precificação:** On-demand (sem commitment)
- **Variação esperada:** ±10-15% devido a flutuação cambial e ajustes de preços AWS

### Custos Operacionais Recorrentes (Mensais)

#### Estratégia Adotada: Staging com Automação Start/Stop

**Contexto:** Como o time de desenvolvimento trabalha em **horário comercial** (seg-sex, 8h-18h), o ambiente Staging será configurado para **desligar automaticamente fora desse período**, gerando economia sem impactar a produtividade.

**Schedule de Staging:**
- **Horário operacional**: Segunda a sexta, 8h-18h (50h/semana)
- **Automação**: Desliga às 18h, liga às 8h automaticamente
- **Impacto**: 10-15 minutos de inicialização pela manhã (aceitável)

**Como funciona a economia:**
- **EC2 nodes**: Cobrados apenas pelas horas ligadas (-70% tempo vs 24/7)
- **RDS**: Auto-pause quando inativo (-50% custo)
- **Redis/RabbitMQ**: Seguem schedule dos nodes (pods scaled to 0)
- **Dados preservados**: 100% dos dados mantidos em volumes persistentes (EBS)

| Ambiente | Configuração | Custo Mensal | Custo Anual |
|----------|--------------|--------------|-------------|
| **Staging** | 2x t3.medium (50h/semana)<br>RDS db.t3.small (auto-pause)<br>Redis + RabbitMQ (50h/semana)<br>*Desliga automático 18h-8h + finais de semana* | R$ 672 | R$ 8.064 |
| **Prod** | 3x t3.large (24/7 Multi-AZ)<br>RDS db.t3.medium Multi-AZ<br>Redis HA + RabbitMQ cluster<br>ALB + WAF<br>*Sempre disponível* | R$ 2.802 | R$ 33.624 |
| **Observability** | Storage adicional (métricas/logs)<br>Prometheus + Grafana + Loki + Tempo<br>*Compartilhado entre ambientes* | R$ 150 | R$ 1.800 |
| **TOTAL** | **Staging scheduled + Prod 24/7** | **R$ 3.624** | **R$ 43.488** |

**Economia vs Staging 24/7:** R$ 5.400/ano (se Staging ficasse sempre ligado, custaria R$ 1.122/mês)

---

### Visualização do Schedule de Staging

```
┌─────────────────────────────────────────────────────────────────┐
│           HORÁRIO DE OPERAÇÃO - AMBIENTE STAGING                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Segunda a Sexta:                                               │
│  08:00 ████████████████████████ 18:00    [LIGADO - 10h/dia]   │
│  18:00 ░░░░░░░░░░░░░░░░░░░░░░░░ 08:00    [DESLIGADO - 14h]     │
│                                                                 │
│  Sábado + Domingo:                                              │
│  00:00 ░░░░░░░░░░░░░░░░░░░░░░░░ 23:59    [DESLIGADO - 48h]     │
│                                                                 │
│  💰 Economia semanal: ~R$ 103 (vs Staging 24/7)                 │
│  💰 Economia mensal:  ~R$ 450                                   │
│  💰 Economia anual:   R$ 5.400                                  │
│                                                                 │
│  ✅ Prod permanece 24/7 (sempre disponível)                     │
│  ✅ Dados preservados durante desligamento                      │
│  ✅ Inicialização automática às 8h (pronto às 8h15)             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

█ = Ligado (pagando por hora de uso)
░ = Desligado (pagando apenas storage fixo: EBS, S3)
```

**Implementação técnica:** AWS EventBridge + Lambda functions executam start/stop automaticamente (implementação: ~2 horas no Sprint 3 ou posterior).

---

## 4. Comparativo de Custos vs Modelos Alternativos

| Cenário Arquitetural | Custo Mensal | Custo Anual | Economia |
|---------------------|--------------|-------------|----------|
| **3 Ambientes** (Dev + Staging + Prod, todos 24/7) | R$ 5.100 | R$ 61.200 | Baseline |
| **2 Ambientes sem otimização** (Staging 24/7 + Prod) | R$ 4.074 | R$ 48.888 | -20% (-R$ 12.312/ano) |
| **2 Ambientes ADOTADO** (Staging scheduled + Prod) | **R$ 3.624** | **R$ 43.488** | **-29% (-R$ 17.712/ano)** |

**Decisões arquiteturais:**
1. **2 ambientes vs 3:** Staging assume papel dual (dev + homologação), eliminando ambiente Dev dedicado
2. **Automação de custo:** Staging desliga automaticamente fora do horário comercial (compatível com modelo de trabalho do time)

---

## 5. Resumo Financeiro (Ano 1)

### Cenário Base (Staging 24/7)

```
Implantação (one-time):          R$ 2.000 - R$ 3.000
Operação Ano 1 (24/7):           R$ 48.888
────────────────────────────────────────────────
TOTAL ANO 1 (BASE):              R$ 50.888 - R$ 51.888
```

### Cenário Otimizado (Staging scheduled) — **RECOMENDADO**

```
Implantação (one-time):          R$ 2.000 - R$ 3.000
Operação Ano 1 (otimizado):      R$ 43.488
────────────────────────────────────────────────
TOTAL ANO 1 (OTIMIZADO):         R$ 45.488 - R$ 46.488
```

**Economia Ano 1:** R$ 5.400 (vs Cenário Base)

### Anos Subsequentes (Recorrente)

| Ano | Cenário Base (24/7) | Cenário Otimizado | Economia Anual |
|-----|---------------------|-------------------|----------------|
| **Ano 2** | R$ 48.888 | R$ 43.488 | R$ 5.400 |
| **Ano 3** | R$ 48.888 | R$ 43.488 | R$ 5.400 |
| **Total 3 anos** | R$ 146.664 | R$ 130.464 | **R$ 16.200** |

**Otimizações adicionais possíveis:**
- Savings Plans (commitment 1 ano): -20% no custo de EC2/RDS
- Reserved Instances (commitment 3 anos): -40% no custo de EC2/RDS
- Projeção com Savings Plans 1 ano: **~R$ 37.000/ano** (vs R$ 43.488)

**💡 Gestão Financeira Recomendada:**
- Configurar **AWS Budgets** com alertas em R$ 4.000/mês (margem de segurança 10%)
- Monitorar **AWS Cost Explorer** semanalmente nos primeiros 2 meses
- Revisar custos reais vs projetados mensalmente e ajustar conforme necessário
- Habilitar **AWS Cost Anomaly Detection** para identificar picos inesperados

---

## 6. Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| Exposição pública GitLab | Médio | Alto | WAF + IP allowlist + 2FA obrigatório |
| Falha de restore não testado | Baixo | Crítico | **DR Drill obrigatório no Sprint 3** |
| Performance GitLab insuficiente | Médio | Médio | Node group dedicado `critical` + monitoramento proativo |
| **Variação cambial (USD/BRL)** | **Alto** | **Médio** | **Budgets AWS + revisão mensal + considerar hedge cambial** |
| **Ajuste de preços AWS** | **Baixo** | **Baixo** | **Monitorar AWS Price List API + assinatura de notificações** |
| Estouro de custos AWS | Baixo | Médio | Budgets configurados + alertas AWS Cost Explorer |

---

## 7. Critérios de Sucesso (Definition of Done)

Ao final do Sprint 3, a plataforma estará **production-ready** com:

✅ GitLab operacional com pipeline CI/CD funcional
✅ Observability completa (dashboards, alertas, logs, traces)
✅ Segurança validada (WAF, NetworkPolicies, RBAC)
✅ **Backups e DR testados com sucesso** (RTO < 1h, RPO < 24h)
✅ Runbooks operacionais documentados
✅ Knowledge transfer completo para time interno

---

## 8. Próximos Passos (Fora do Escopo Atual)

Os seguintes itens **NÃO** estão incluídos nesta fase e serão avaliados posteriormente:

- Integração Microsoft Entra ID (Azure AD)
- Service Mesh completo (Linkerd + Kong + Keycloak)
- HashiCorp Vault para secrets management
- Operators avançados (PostgreSQL, RabbitMQ, Kafka)
- Backstage Developer Portal

**Estratégia:** Implementação incremental conforme roadmap de 5 fases detalhado

---

## 9. Recomendação Final

### Aprovação Solicitada: **Cenário Otimizado**

**Investimento Ano 1: R$ 45.488 - R$ 46.488**

- ✅ **Arquitetura de 2 ambientes** (Staging + Prod) com -29% economia vs modelo tradicional
- ✅ **Timeline de 6 semanas** com time interno (262 person-hours)
- ✅ **Custo recorrente de R$ 3.624/mês** (Staging scheduled + Prod 24/7)
- ✅ **Fundações arquiteturais evolutivas** para crescimento sem refatoração
- ✅ **DR Drill obrigatório** validando recuperação de desastres

### ROI Esperado

| Benefício | Impacto |
|-----------|---------|
| **Redução time-to-market** | Deploy automatizado via GitLab CI/CD (minutos vs horas) |
| **Redução de incidentes** | Observability proativa + alertas antes de falhas críticas |
| **Economia operacional** | -29% vs arquitetura tradicional de 3 ambientes (R$ 17.712/ano) |
| **Escalabilidade garantida** | Auto-scaling pronto para crescimento (0 downtime) |
| **Compliance & Security** | WAF + NetworkPolicies + encryption-at-rest desde dia 1 |

### Economia Projetada (3 anos)

```
Ano 1:  R$ 5.400  (vs Cenário Base)
Ano 2:  R$ 5.400
Ano 3:  R$ 5.400
───────────────────────────────────
TOTAL:  R$ 16.200 de economia acumulada
```

**Com Savings Plans (1 ano):** Economia adicional de ~R$ 19.000 em 3 anos



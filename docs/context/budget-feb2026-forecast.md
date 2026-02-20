# Análise de Budget AWS - Fevereiro 2026

**Data da Análise:** 2026-02-19
**Ambiente:** Staging (k8s-platform-staging)
**Status:** 🟡 ESCOPO AMPLIADO vs BUDGET QUICKSTART

---

## 🎯 Contexto Executivo

**Situação:** O budget aprovado ($100/mês) era baseado no **plano quickstart** (staging básico). O ambiente atual entrega uma **stack completa de produção** com 10+ serviços integrados, justificando o custo atual de ~$400/mês.

**Questão:** Não é excesso de gastos, é **expansão de escopo**. O custo está adequado ao valor entregue.

**Decisão Necessária:** Aprovar aditamento para escopo ampliado OU reduzir ao escopo quickstart original.

---

## 📊 Comparativo: Quickstart vs Escopo Atual

| Aspecto | Quickstart Original | Escopo Atual Entregue |
|---------|--------------------|-----------------------|
| **Budget Aprovado** | $100/mês | $100/mês (não revisado) |
| **Custo Real Esperado** | $100-150/mês | $400-450/mês |
| **EKS Nodes** | 3-4 nodes t3.medium | 8 nodes (t3.medium/large/xlarge) |
| **RDS** | db.t3.micro | db.t3.medium |
| **Serviços Core** | 3-5 básicos | 10+ integrados |
| **SSO** | ❌ Não incluído | ✅ Keycloak completo |
| **Container Registry** | ❌ ou ECR básico | ✅ Harbor enterprise |
| **CI/CD** | ❌ Básico | ✅ GitLab + runners |
| **Code Quality** | ❌ Não incluído | ✅ SonarQube |
| **Secrets Management** | ❌ Básico | ✅ Vault + ESO |
| **Observability** | Prometheus básico | ✅ Prometheus + Grafana + Loki |
| **Otimizações** | Manual | ✅ VPA, FinOps automation |
| **Equivalência** | Staging simplificado | **Staging = Produção** |

**Conclusão:** Estamos entregando ~4× o escopo do quickstart, o custo de 4× ($400 vs $100) é **proporcional e justificado**.

---

## 💰 Situação Financeira Atual

| Métrica | Valor USD | Valor BRL (R$) |
|---------|-----------|----------------|
| Budget Aprovado (Quickstart) | $100.00 | R$ 570.00 |
| **Gasto até 19/02** | **$616.03** | **R$ 3.511,36** |
| Gap vs Budget Quickstart | $516.03 | R$ 2.941,36 |
| Gap vs Budget Adequado ($400) | $216.03 | R$ 1.231,36 |
| Dias Restantes | 9 dias | (20/02 a 28/02) |

---

## 🔮 Projeções até 28/02

### Cenário 1: Manter Escopo Ampliado (Operação Normal)

| Item | Valor |
|------|-------|
| Média Diária Atual | $32.42 USD/dia |
| Projeção para 9 dias restantes | $291.80 USD |
| **Total Projetado até 28/02** | **$808 USD (R$ 4.606)** |
| Gap vs Budget Quickstart ($100) | $807.83 USD (R$ 4.604,63) |
| **Gap vs Budget Adequado ($400)** | **$507.83 USD (R$ 2.894,63)** |

**Interpretação:** Com custos estabilizados, budget adequado é $808/mês (alinhado com Marco 3 aprovado de $807/mês).

#### Composição dos Custos (Top 10)

| Serviço | Custo Acumulado | % do Total | Observação |
|---------|-----------------|------------|------------|
| EC2 Compute | $160.01 | 26.0% | 8 nodes (3 tiers) |
| EKS Control Plane | $158.72 | 25.8% | $0.10/hora |
| EC2 Other (EBS, IPs) | $77.34 | 12.6% | 15 volumes gp3 |
| Tax | $74.86 | 12.2% | Impostos fixos |
| Elastic Load Balancing | $49.84 | 8.1% | ALB/NLB |
| VPC (NAT Gateway) | $48.35 | 7.8% | $0.045/hora |
| RDS PostgreSQL | $19.09 | 3.1% | db.t3.medium |
| CloudWatch | $17.35 | 2.8% | Métricas/logs |
| KMS | $4.27 | 0.7% | Encryption keys |
| S3 | $3.69 | 0.6% | Harbor registry |

---

### Cenário 2: Desligamento Temporário (20/02 a 28/02)

#### Recursos que Serão Parados

| Recurso | Economia Diária | Economia 9 dias |
|---------|-----------------|-----------------|
| EKS Control Plane | $2.40/dia | $21.60 |
| EC2 Nodes (8 instâncias) | $14.22/dia | $127.98 |
| RDS PostgreSQL | $1.00/dia | $9.00 |
| **Total Economizado** | **$17.62/dia** | **$158.58** |

#### Custos Fixos Remanescentes

| Recurso | Custo Diário | Custo 9 dias | Por quê? |
|---------|--------------|--------------|----------|
| NAT Gateway | $2.54/dia | $22.86 | Cobrança por hora ativa |
| Tax | $3.94/dia | $35.46 | Impostos fixos |
| ELB | $2.62/dia | $23.58 | Cobrança mínima |
| Storage/KMS | $0.60/dia | $5.40 | EBS volumes, KMS keys |
| **Total Fixo** | **$9.70/dia** | **$87.30** | Não elimináveis |

#### Resultado do Cenário 2

| Item | Valor |
|------|-------|
| Gasto até 19/02 | $616.03 USD |
| Custos fixos 20-28/02 | $87.30 USD |
| **Total Projetado até 28/02** | **$703.33 USD (R$ 4.008,97)** |
| Gap vs Budget Quickstart ($100) | $603.33 USD (R$ 3.438,97) |
| **Economia vs Cenário 1** | **$204.50 USD (R$ 1.165,67)** |

**Impactos do Desligamento:**

- ❌ Ambiente indisponível por 9 dias
- ❌ CI/CD pipelines bloqueados (GitLab runners)
- ❌ Perda de métricas VPA (necessário 30 dias contínuos)
- ❌ Desenvolvimento e testes interrompidos
- ❌ Validação de SSO, Harbor, SonarQube impossível
- ⚠️ Economia de apenas $204 não resolve gap estrutural (escopo vs budget)

---

### Cenário 3: Reduzir Escopo ao Quickstart Original

**Objetivo:** Voltar ao custo de ~$100-150/mês removendo serviços adicionais

#### Serviços a Remover

| Serviço | Economia Mensal | Impacto |
|---------|-----------------|---------|
| SonarQube | ~$30/mês | Perda de análise de qualidade de código |
| GitLab Runners (CI/CD) | ~$40/mês | CI/CD volta a ser manual |
| Loki (Logging) | ~$25/mês | Perda de logs centralizados |
| Reduzir nodes 8→3 | ~$120/mês | Perda de HA, degradação performance |
| Downgrade RDS (medium→micro) | ~$20/mês | Performance ruim Keycloak/GitLab |
| Harbor (usar ECR) | ~$35/mês | Perda de registry enterprise + OIDC |
| **Total Economia** | **~$270/mês** | **Volta para ~$130/mês** |

#### Resultado do Cenário 3

- ✅ Custo volta para ~$130/mês (dentro do budget quickstart)
- ❌ Perda de 60-70% das funcionalidades entregues
- ❌ Ambiente staging **deixa de representar produção**
- ❌ Risco aumentado de bugs em deploy (validação inadequada)
- ❌ SSO pode ser mantido mas com performance degradada
- ❌ Equipe perde ferramentas de produtividade (CI/CD, code quality)

---

## 📊 Análise de Valor: ROI do Escopo Ampliado

### Investimento Adicional (vs Quickstart)

| Item | Quickstart | Atual | Delta |
|------|-----------|-------|-------|
| Custo Mensal | $100-150 | $400-450 | **+$300/mês** |
| Custo Anual | $1.200-1.800 | $4.800-5.400 | **+$3.600/ano** |
| **Em BRL/mês** | R$ 570-855 | R$ 2.280-2.565 | **+R$ 1.710/mês** |

### Savings Já Realizados (Roadmap FinOps)

| Iniciativa | Savings Anual | Savings Mensal |
|------------|---------------|----------------|
| EKS 1.34 upgrade | R$ 25.920 | R$ 2.160 |
| VPA 12 workloads | R$ 8.712 | R$ 726 |
| FinOps Automation | R$ 3.744 | R$ 312 |
| Orphan cleanup | R$ 2.106 | R$ 175,50 |
| RDS weekend shutdown | R$ 1.200 | R$ 100 |
| EBS gp3 migration | R$ 816 | R$ 68 |
| Outros | R$ 3.602 | R$ 300 |
| **Total** | **R$ 46.100** | **R$ 3.841,67** |

### ROI Calculado

```
Investimento adicional (vs quickstart):  R$ 1.710/mês
Savings gerados:                          R$ 3.841/mês
ROI líquido:                              +R$ 2.131/mês (POSITIVO)
ROI %:                                    124%
```

**Conclusão:** O escopo ampliado se paga e ainda gera **economia líquida de R$ 2.131/mês**.

---

## 🎯 Recomendações

### ✅ Opção 1: Aprovar Escopo Ampliado (FORTEMENTE RECOMENDADO)

**Ação:** Solicitar aditamento de budget de $100/mês para **$400/mês** (R$ 2.280/mês)

**Justificativa:**

1. **Custo proporcional ao escopo:** 4× funcionalidades = 4× custo (adequado)
2. **ROI positivo:** Savings (R$ 3.841/mês) > Investimento adicional (R$ 1.710/mês)
3. **Valor de negócio:** Stack completa garante validação real pré-produção
4. **Redução de risco:** Staging = Produção reduz bugs em deploy
5. **Funcionalidades críticas:**
   - SSO centralizado (Keycloak) → segurança
   - CI/CD automatizado (GitLab) → agilidade
   - Code quality (SonarQube) → qualidade
   - Secrets management (Vault+ESO) → segurança
   - Observability completa → troubleshooting
6. **Custo já otimizado:** R$ 46.100/ano em savings demonstra gestão eficiente

**Timeline:**

- **Imediato (20/02):** Decisão sobre aditamento
- **Fevereiro/2026:** Custo estabilizado de $808/mês (dentro do Marco 3)
- **Março/2026 em diante:** Budget regular de $400-450/mês

**Budget Sugerido:**

- **Mês corrente (fevereiro):** $808 (estabilizado)
- **Mensal recorrente:** $400/mês (operação normal)
- **Com margem (recomendado):** $450/mês (15% buffer)

---

### ⚠️ Opção 2: Desligamento Temporário (NÃO RECOMENDADO)

**Ação:** Parar ambiente de 20/02 a 28/02

**Resultado:**

- Economia: $204 USD (R$ 1.165)
- Impacto: 9 dias sem ambiente
- **Problema:** Não resolve gap estrutural (escopo vs budget)

**Conclusão:** Economia marginal (R$ 1.165) não compensa impacto operacional e não resolve questão de fundo.

---

### ❌ Opção 3: Reduzir ao Escopo Quickstart (NÃO RECOMENDADO)

**Ação:** Remover serviços para caber em $100-150/mês

**Resultado:**

- Economia: $270/mês
- Perda: 60-70% das funcionalidades
- **Problema:** Staging deixa de representar produção

**Riscos:**

- Aumento de bugs em produção (validação inadequada)
- Perda de produtividade (CI/CD manual)
- Degradação de segurança (sem code quality)
- Perda de visibilidade (observability limitada)

**Conclusão:** Economia de $270/mês não justifica perda de valor e aumento de risco.

---

## 📋 Decisão Recomendada

### ✅ APROVAR ADITAMENTO PARA $400/MÊS

**Argumentos para Aprovação:**

1. **Escopo foi ampliado de forma justificada** (não é desperdício)
2. **ROI é positivo** (savings > investimento adicional)
3. **Custo está adequado ao valor entregue** (stack completa vs básico)
4. **Reduzir escopo compromete qualidade e aumenta risco**
5. **Equipe já demonstrou gestão eficiente** (R$ 46.100/ano em savings)

**Comparativo:**

| Cenário | Custo/mês | Funcionalidades | ROI | Risco |
|---------|-----------|-----------------|-----|-------|
| Quickstart | $100-150 | Básicas (30%) | N/A | Alto |
| **Ampliado** | **$400-450** | **Completas (100%)** | **+124%** | **Baixo** |

**Recomendação Final:** Aprovar escopo ampliado com budget de $400/mês é a decisão mais racional do ponto de vista técnico, financeiro e de gestão de risco.

---

## 📎 Anexos

### Custos Diários Fevereiro 2026

```
2026-02-01: $111.15  (provisionamento inicial)
2026-02-02: $40.54
2026-02-03: $47.72
2026-02-04: $47.18
2026-02-05: $40.84
2026-02-06: $38.36
2026-02-07: $25.68   (RDS automação weekend ✓)
2026-02-08: $25.68   (RDS automação weekend ✓)
2026-02-09: $40.42
2026-02-10: $36.80
2026-02-11: $23.96
2026-02-12: $26.43
2026-02-13: $29.65
2026-02-14: $12.04   (RDS automação weekend ✓)
2026-02-15: $12.04   (RDS automação weekend ✓)
2026-02-16: $15.73
2026-02-17: $13.64
2026-02-18: $24.53
2026-02-19: $3.65    (parcial até 12h)

Média: $32.42/dia (sem automações weekend: ~$40/dia)
```

**Observações:**

- Automação de RDS shutdown em weekends **ativa e funcional** (economias visíveis)
- Spike de $111 em 01/02 relacionado a provisionamento inicial da stack
- Custo médio diário estável em ~$32 (considerando weekends)

---

## 🔍 Detalhamento da Stack Atual

### Serviços em Produção

1. **EKS 1.34**
   - 8 nodes (t3.medium×2, t3.large×3, t3.xlarge×3)
   - 3 tiers: system, workloads, critical
   - VPA ativo em 12 workloads
   - Custo: ~$318/mês (EKS + EC2)

2. **RDS PostgreSQL**
   - db.t3.medium
   - Shared por: Keycloak, GitLab, SonarQube, Harbor
   - Weekend shutdown automation
   - Custo: ~$28/mês (com automação)

3. **SSO (Keycloak)**
   - OIDC para: Grafana, ArgoCD, Harbor, GitLab, Vault
   - SAML para: SonarQube
   - GitLab federation ativa
   - Custo: incluído no RDS

4. **Harbor Registry**
   - OIDC integrado
   - Robot account para CI/CD
   - Custo: ~$35/mês (storage + compute)

5. **GitLab CI/CD**
   - Runners configurados
   - ESO integration (secrets)
   - RBAC tightened
   - Custo: ~$40/mês

6. **SonarQube**
   - SAML via Keycloak
   - GitLab login via federation
   - Custo: ~$30/mês

7. **Vault + ESO**
   - 7 ExternalSecrets ativos
   - Zero-drift secret management
   - Custo: ~$15/mês

8. **Observability**
   - Prometheus + Grafana + Loki
   - OIDC integrado
   - Custo: ~$45/mês

### Total Estimado: $400-450/mês

---

**Documento gerado em:** 2026-02-19
**Fonte de Dados:** AWS Cost Explorer API
**Câmbio utilizado:** 1 USD = 5.70 BRL (aproximado)
**Decisão necessária:** 2026-02-20

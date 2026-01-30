# 📜 POST-HOOK: Register Decisions (ADRs)

**Objetivo:** Documentar decisões arquiteturais tomadas durante a execução em decisions.md

**Executado por:** Orquestrador DevOps (com input dos agentes especialistas)

---

## ✅ Checklist de Registro

### 1. Identificar Decisões Arquiteturais

**Decisões que DEVEM virar ADRs:**

- [ ] **Escolha de serviço AWS** (managed vs self-hosted)
  - Exemplo: EventBridge Scheduler vs Cron Jobs
- [ ] **Padrões de arquitetura** (serverless vs containers)
  - Exemplo: Lambda vs ECS Tasks para automação
- [ ] **Multi-AZ / DR strategy**
  - Exemplo: RDS Multi-AZ habilitado ou não
- [ ] **Encryption decisions**
  - Exemplo: KMS vs AWS Managed Keys
- [ ] **Networking patterns**
  - Exemplo: Lambda com VPC vs sem VPC
- [ ] **Operators vs Helm Charts**
  - Exemplo: Redis Operator vs Bitnami Chart
- [ ] **Cost optimization strategies**
  - Exemplo: Reserved Instances vs On-Demand

**Decisões que NÃO precisam de ADR:**
- Configurações triviais (tags, naming conventions)
- Implementações óbvias sem alternativas
- Ajustes de parâmetros sem impacto arquitetural

---

### 2. Template ADR

Adicionar em `docs/context/decisions.md`:

```markdown
### ADR-XXX: [Título da Decisão]

**Data:** YYYY-MM-DD
**Status:** IMPLEMENTADA
**Decisores:** [Orquestrador + Agentes envolvidos]

#### Contexto

[Descrever o problema ou necessidade que levou à decisão]

Exemplo:
> O ambiente STAGING (8h-18h Mon-Fri) gera custos desnecessários fora do horário comercial.
> Economia potencial: R$ 4.320/ano se automatizado.

#### Decisão

[Descrever a solução escolhida]

Exemplo:
> Implementar automação FinOps com EventBridge Scheduler + Lambda para:
> - Parar RDS e escalar ASG para 0 às 18h (Mon-Fri)
> - Iniciar RDS e escalar ASG para 2 nodes às 8h (Mon-Fri)
> - Circuit breaker em DynamoDB (threshold: 3 failures consecutivas)

#### Alternativas Consideradas

| Alternativa | Prós | Contras | Custo/Mês |
|-------------|------|---------|-----------|
| **EventBridge + Lambda (ESCOLHIDA)** | Serverless, sem manutenção, escala automática | Custo Lambda compute | $2.43 |
| CronJobs Kubernetes | Controle total, sem custo adicional | Requer cluster ativo 24/7, complexidade maior | $0 (mas cluster on 24/7) |
| AWS Instance Scheduler | Solução AWS oficial | Custo CloudFormation, menos flexível para health checks | $3.00 |

#### Consequências

**Positivas:**
- ✅ Economia R$ 4.145/ano (ROI 43.6% Year 1)
- ✅ Circuit breaker evita downtime por falhas repetidas
- ✅ Zero manutenção (serverless)

**Negativas:**
- ⚠️ AWS pode auto-start RDS após 7 dias stopped (mitigado com DynamoDB state check)
- ⚠️ Lambda cold start pode atrasar startup em ~2s (aceitável)

**Riscos:**
- [T-XXX] Falha no startup pode deixar ambiente indisponível (mitigado com CloudWatch Alarm)
- [S-XXX] DynamoDB sem encryption (resolvido com KMS +$1/mês)

#### Validações

**Agentes Aprovadores:**
- ✅ AWS Specialist (2026-01-30)
- ✅ Terraform Specialist (2026-01-30)
- ✅ FinOps (2026-01-30)
- ✅ Security & Compliance (2026-01-30)

**Warnings Implementadas:** 11/11 (100%)

#### Referências

- Demanda: `docs/demands/2026-01-30-finops-multi-ambiente-automation.md`
- Plano de Execução: `docs/plan/aws-execution/fase-8-finops-multi-ambiente-automation.md`
- Custos: `docs/context/costs.md#finops-automation`
- Riscos: `docs/context/risks.md#finops-automation`

---
```

---

### 3. Numeração ADR

- [ ] **Verificar último ADR registrado**
  ```bash
  grep "^### ADR-" docs/context/decisions.md | tail -1
  ```

- [ ] **Incrementar número sequencialmente**
  - Exemplo: Se último foi ADR-022, próximo é ADR-023

---

### 4. Cross-Reference em Outros Documentos

Após criar ADR, atualizar:

- [ ] **architecture.md**
  ```markdown
  ### FinOps Automation
  **Decisão Arquitetural:** [ADR-XXX - FinOps EventBridge Automation](decisions.md#adr-xxx)
  ```

- [ ] **risks.md**
  ```markdown
  #### T-XXX: Startup Failure Risk
  **Mitigação:** Circuit breaker pattern (ver ADR-XXX)
  ```

- [ ] **costs.md**
  ```markdown
  ### FinOps Automation Costs
  **Decisão:** ADR-XXX escolheu EventBridge+Lambda ($2.43/mês) vs alternatives
  ```

---

### 5. Status ADR Lifecycle

**Possíveis Status:**

| Status | Quando Usar | Exemplo |
|--------|-------------|---------|
| **PROPOSTA** | Decisão em discussão, não implementada | ADR em análise pelos agentes |
| **APROVADA** | Decisão aprovada, aguardando implementação | Terraform plan aprovado, aguardando apply |
| **IMPLEMENTADA** | Decisão deployada em produção | Terraform apply concluído com sucesso |
| **DEPRECADA** | Decisão substituída por nova ADR | ADR-010 deprecada por ADR-025 |
| **REJEITADA** | Proposta rejeitada (manter histórico) | Alternativa descartada após análise FinOps |

---

### 6. Validação de Qualidade ADR

ADR bem escrita deve responder:

- [ ] **Por que precisamos decidir?** (Contexto)
- [ ] **O que decidimos?** (Decisão)
- [ ] **Por que essa escolha?** (Alternativas + trade-offs)
- [ ] **Quais impactos?** (Consequências positivas/negativas)
- [ ] **Quem aprovou?** (Validações dos agentes)

**Critério de Bloqueio:**
- Rejeitar ADR sem "Alternativas Consideradas" (mínimo 2)
- Rejeitar ADR sem aprovação de agentes especialistas

---

## ✅ Aprovação

**Responsável:** Orquestrador DevOps
**Data:** _______
**Status:** [ ] CONCLUÍDO

**ADR Criado:**
- [ ] ADR-XXX adicionado em docs/context/decisions.md (Data: ______)

**Cross-References Atualizados:**
- [ ] architecture.md
- [ ] risks.md
- [ ] costs.md

**Comentários:**
```
[Listar decisões principais registradas]
```

---

**Criado:** 2026-01-30
**Versão:** 1.0
**Executar:** Imediatamente após terraform apply sucesso (se houver decisão arquitetural)

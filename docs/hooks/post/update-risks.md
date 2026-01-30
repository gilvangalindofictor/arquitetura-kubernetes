# ⚠️ POST-HOOK: Update Risks Documentation

**Objetivo:** Atualizar risks.md com novos riscos identificados e status de mitigações

**Executado por:** Security Specialist + AWS Specialist + Orquestrador

---

## ✅ Checklist de Atualização

### 1. Identificar Novos Riscos

**Riscos introduzidos pela mudança:**

- [ ] **Riscos Técnicos (T-XXX)**
  - Falhas de startup/shutdown automático
  - Drift entre estado esperado e real
  - Dependencies não gerenciadas (AWS auto-start RDS após 7 dias)
  - Performance degradation (Lambda cold start)

- [ ] **Riscos de Segurança (S-XXX)**
  - Secrets expostos (API keys hardcoded)
  - Encryption desabilitado (DynamoDB plaintext)
  - IAM overprivileged (wildcard permissions)
  - Network exposure (Security Groups 0.0.0.0/0)

- [ ] **Riscos Financeiros (F-XXX)**
  - Custo inesperado (NAT Gateway, Data Transfer)
  - Hidden costs não documentados
  - ROI não atingido (economia < 25% Year 1)
  - Overprovisioning detectado

---

### 2. Template de Risco

Adicionar em `docs/context/risks.md`:

```markdown
#### [T|S|F]-XXX: [Título do Risco]

**Severidade:** 🔴 ALTA | 🟡 MÉDIA | 🟢 BAIXA
**Status:** 🆕 NOVO | ⚠️ ABERTO | ✅ MITIGADO | 🔒 ACEITO

**Descrição:**
[Descrever o risco em 1-2 parágrafos]

Exemplo:
> Lambda FinOps pode falhar ao iniciar RDS/EKS devido a timeouts, race conditions ou IAM permissions insuficientes, deixando o ambiente STAGING indisponível para o time de desenvolvimento.

**Probabilidade:** ALTA | MÉDIA | BAIXA
**Impacto:** CRÍTICO | ALTO | MÉDIO | BAIXO

**Gatilhos:**
- [Lista de eventos que podem disparar o risco]

Exemplo:
- Lambda timeout < 5 min (RDS startup demora 3-4 min)
- IAM role sem permissões `rds:StartDBInstance`
- RDS em manutenção programada no horário do startup

**Mitigação:**
[Descrever solução implementada ou planejada]

Exemplo:
> **Implementado:**
> 1. Circuit breaker em DynamoDB (threshold: 3 failures consecutivas)
> 2. CloudWatch Alarm `finops-staging-startup-duration-high` (10 min)
> 3. Lambda timeout = 15 min (margem de segurança)
> 4. Health checks pós-startup (DB connections + GitLab jobs)
>
> **Custo da Mitigação:** $0.03/mês (DynamoDB on-demand writes)

**Plano de Rollback:**
[Como reverter se o risco se concretizar]

Exemplo:
> 1. Detectar falha via CloudWatch Alarm
> 2. Manual override: `aws rds start-db-instance --db-instance-identifier finops-staging`
> 3. Desabilitar EventBridge rule se problema recorrente

**Responsável:** [Agente ou equipe responsável pela mitigação]

**Referências:**
- ADR-XXX: [Link para decisão relacionada]
- Demanda: `docs/demands/YYYY-MM-DD-name.md`

---
```

---

### 3. Atualizar Status de Riscos Existentes

- [ ] **Riscos ABERTOS que foram MITIGADOS**

  Exemplo:
  ```markdown
  #### S-019.1: DynamoDB Encryption at Rest
  **Status:** ⚠️ ABERTO → ✅ MITIGADO (2026-01-30)

  **Mitigação Implementada:**
  - KMS encryption habilitado (arn:aws:kms:us-east-1:xxx:key/yyy)
  - Custo adicional: +$1/mês
  - Validação: `aws dynamodb describe-table --table-name finops-circuit-breaker | grep SSEDescription`
  ```

- [ ] **Riscos NOVOS identificados durante execução**

  Exemplo:
  ```markdown
  #### T-025: RDS 7-Day Auto-Start Bypass
  **Severidade:** 🟡 MÉDIA
  **Status:** ✅ MITIGADO (2026-01-30)

  **Descrição:**
  AWS automaticamente inicia RDS instances após 7 dias stopped, anulando a economia do FinOps.

  **Mitigação:**
  Lambda valida `last_stop_time` no DynamoDB e executa re-stop automático se AWS iniciou a instância.
  ```

---

### 4. Risk Matrix Update

- [ ] **Atualizar matriz de riscos por severidade**

  Adicionar contadores em `risks.md`:

  ```markdown
  ## 📊 Risk Summary (Atualizado em 2026-01-30)

  | Categoria | 🔴 ALTA | 🟡 MÉDIA | 🟢 BAIXA | Total |
  |-----------|---------|----------|----------|-------|
  | **Técnicos (T-XXX)** | 2 | 5 | 3 | 10 |
  | **Segurança (S-XXX)** | 0 | 3 | 2 | 5 |
  | **Financeiros (F-XXX)** | 1 | 2 | 1 | 4 |
  | **TOTAL** | 3 | 10 | 6 | 19 |

  **Status:**
  - 🆕 NOVOS: 4 (adicionados em 2026-01-30)
  - ⚠️ ABERTOS: 3 (aguardando mitigação)
  - ✅ MITIGADOS: 11 (resolvidos)
  - 🔒 ACEITOS: 1 (risco assumido com justificativa)
  ```

---

### 5. Custo das Mitigações

- [ ] **Documentar impacto financeiro das mitigações**

  Adicionar em seção de riscos:

  ```markdown
  ### Custo Total de Mitigações (2026-01-30)

  | Risco | Mitigação | Custo/Mês | Status |
  |-------|-----------|-----------|--------|
  | S-019.1 | KMS encryption DynamoDB | +$1.00 | ✅ Implementado |
  | T-025 | DynamoDB state check (writes extras) | +$0.01 | ✅ Implementado |
  | T-026 | CloudWatch Alarm (startup duration) | +$0.20 | ✅ Implementado |
  | **TOTAL MITIGAÇÕES** | | **+$1.21/mês** | **R$ 14.52/ano** |

  **Impacto no ROI:**
  - ROI ANTES: 44.0%
  - ROI DEPOIS: 43.6% (-0.4pp)
  - **Conclusão:** Variação negligível, mitigações justificadas
  ```

---

### 6. Riscos ACEITOS (sem mitigação)

- [ ] **Documentar riscos que não serão mitigados**

  Exemplo:
  ```markdown
  #### F-012: Lambda Cold Start Delay
  **Severidade:** 🟢 BAIXA
  **Status:** 🔒 ACEITO

  **Justificativa:**
  Lambda cold start pode adicionar ~2s ao tempo de startup total (8 min → 8min02s).
  Impacto negligível (<0.5%), mitigação (Provisioned Concurrency) custaria $12/mês adicional.

  **Decisão:** Aceitar o risco sem mitigação (aprovado por FinOps em 2026-01-30)
  ```

---

### 7. Validação Cruzada

- [ ] **Verificar se riscos estão referenciados em:**

  - **decisions.md** (ADRs mencionam riscos mitigados)
    ```markdown
    #### Consequências (ADR-XXX)
    **Riscos:**
    - [T-025] RDS 7-Day Auto-Start (mitigado)
    - [S-019.1] DynamoDB Encryption (mitigado)
    ```

  - **costs.md** (custos de mitigação documentados)
    ```markdown
    ### Custos de Segurança (FinOps)
    - KMS encryption: $1.00/mês (mitigação S-019.1)
    ```

  - **architecture.md** (controles de segurança visíveis)
    ```markdown
    ### Security Controls
    - Circuit breaker pattern (mitigação T-025)
    ```

---

## ✅ Aprovação

**Responsável:** Security Specialist + Orquestrador DevOps
**Data:** _______
**Status:** [ ] CONCLUÍDO

**Riscos Atualizados:**
- [ ] X novos riscos adicionados
- [ ] Y riscos ABERTOS → MITIGADOS
- [ ] Z riscos ACEITOS (com justificativa)

**Arquivo Atualizado:**
- [ ] docs/context/risks.md (Data: ______)

**Comentários:**
```
[Listar principais riscos identificados e status de mitigação]
```

---

**Criado:** 2026-01-30
**Versão:** 1.0
**Executar:** Imediatamente após terraform apply sucesso

# 📋 PRE-HOOK: Validate Context Documentation

**Objetivo:** Garantir que documentos de contexto estão sincronizados antes de qualquer execução Terraform

**Executado por:** Orquestrador DevOps

---

## ✅ Checklist de Validação

### 1. Architecture Documentation

- [ ] **architecture.md existe e está atualizado**
  - Data da última revisão < 30 dias
  - Diagrama reflete infraestrutura atual
  - Componentes novos documentados

**Comando:**
```bash
ls -lh docs/context/architecture.md
grep "Última Atualização" docs/context/architecture.md
```

---

### 2. Decisions Log (ADRs)

- [ ] **decisions.md contém ADRs para mudanças arquiteturais**
  - Decisões críticas documentadas (managed services, operators, networking)
  - Template ADR seguido (Contexto, Decisão, Consequências)
  - Status de cada ADR (PROPOSTA, APROVADA, IMPLEMENTADA, DEPRECADA)

**Comando:**
```bash
grep -c "^### ADR-" docs/context/decisions.md
tail -20 docs/context/decisions.md
```

---

### 3. Risks Registry

- [ ] **risks.md contém análise atualizada**
  - Riscos técnicos (T-XXX) documentados
  - Riscos de segurança (S-XXX) documentados
  - Riscos financeiros (F-XXX) documentados
  - Mitigações propostas para cada risco

**Comando:**
```bash
grep -E "^#### [TSF]-[0-9]+" docs/context/risks.md | wc -l
```

---

### 4. Costs Documentation

- [ ] **costs.md reflete custos atuais**
  - Breakdown por serviço (EC2, RDS, EKS, Lambda, etc)
  - Custos mensais/anuais projetados
  - ROI documentado para otimizações
  - Hidden costs identificados (NAT Gateway, Data Transfer, KMS)

**Comando:**
```bash
grep "TOTAL" docs/context/costs.md
grep "ROI" docs/context/costs.md
```

---

### 5. Cross-References Consistency

- [ ] **Referências entre documentos válidas**
  - ADRs referenciados em architecture.md existem
  - Riscos referenciados em decisions.md estão em risks.md
  - Custos referenciados em costs.md têm breakdown completo

**Validação Manual:**
- Revisar links internos entre documentos
- Verificar numeração sequencial (ADR-XXX, T-XXX, S-XXX, F-XXX)

---

## 🚫 Critérios de Bloqueio

**Bloquear execução Terraform se:**

1. **Contexto desatualizado > 60 dias** sem revisão
2. **ADR faltando** para mudanças arquiteturais críticas (managed services, multi-AZ, encryption)
3. **Riscos de segurança não mitigados** (S-XXX com status ABERTO e severidade ALTA)
4. **Custos não documentados** para novos recursos (ROI ausente)

---

## ✅ Aprovação

**Responsável:** Orquestrador DevOps
**Data:** _______
**Status:** [ ] APROVADO | [ ] BLOQUEADO

**Comentários:**
```
[Espaço para observações sobre inconsistências encontradas]
```

---

**Criado:** 2026-01-30
**Versão:** 1.0
**Próxima Revisão:** Antes de cada terraform apply

# Quick Checklist - Validação de Documentos

> **Uso**: Checklist rápido após qualquer atividade
> **Referência Completa**: `/docs/hooks/post-activity-validation.md`

---

## ✅ Checklist Obrigatório

Após QUALQUER atividade de modificação, verificar:

### 📋 Tier 1 - Governança (SEMPRE)

- [ ] **README.md**: 
  - [ ] Fase Atual = `2 (Criação dos Domínios)`
  - [ ] Status SAD = `v1.1 🔒 CONGELADO (Freeze #2)`
  - [ ] Data = hoje

- [ ] **SAD/docs/sad.md**:
  - [ ] Versão = `1.1`
  - [ ] Status = `🔒 CONGELADO`
  - [ ] Total ADRs = `12`

- [ ] **SAD/docs/sad-freeze-record.md**:
  - [ ] Último freeze = `#2 (2026-01-05)`

- [ ] **docs/logs/log-de-progresso.md**:
  - [ ] Última entrada = atividade atual
  - [ ] Data = hoje

- [ ] **docs/plan/execution-plan.md**:
  - [ ] Tasks marcadas corretamente

---

### 🤖 Tier 2 - Contextos IA (Se mudança arquitetural)

- [ ] **ai-contexts/copilot-context.md**:
  - [ ] Fase, Status SAD, ADRs sincronizados

- [ ] **AI-ARCHITECTURE-OVERVIEW.md**:
  - [ ] Fase, Status SAD sincronizados

---

### 🏢 Tier 3 - Domínios (Se domínio afetado)

- [ ] **domains/{domain}/README.md**:
  - [ ] Status atualizado
  - [ ] Conformidade SAD documentada

- [ ] **domains/{domain}/docs/adr/**:
  - [ ] Referências ao SAD corretas

---

## 🚀 Ação Rápida

Se algum item **NÃO** estiver ✅:

```bash
# 1. Identificar documentos desatualizados
# 2. Atualizar em batch (multi_replace_string_in_file)
# 3. Registrar no log
# 4. Confirmar sincronização
```

---

## 📊 Valores Atuais (2026-01-05)

```
Fase: 2 (Criação dos Domínios)
SAD: v1.1 🔒 (Freeze #2)
ADRs: 12 (incluindo ADR-020)
Último Freeze: 2026-01-05
Task Atual: 2.2 (platform-core)
Observability: ✅ APROVADO
```

---

**Sempre consulte**: [/docs/hooks/post-activity-validation.md](post-activity-validation.md) para detalhes completos.

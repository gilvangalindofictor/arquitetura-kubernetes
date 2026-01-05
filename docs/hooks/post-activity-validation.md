# Post-Activity Hook - Validação de Documentos

> **Tipo**: Hook Obrigatório
> **Execução**: Após QUALQUER atividade de modificação
> **Responsável**: IA (GitHub Copilot / Claude)
> **Data de Criação**: 2026-01-05
> **Status**: Ativo

---

## 🎯 Objetivo

Garantir que **todos os documentos principais** estejam **sincronizados e atualizados** após qualquer atividade de modificação no projeto (criação, atualização, validação, freeze/unfreeze).

---

## 🔄 Quando Executar

### Atividades que OBRIGAM a execução do hook:

1. **Criação/Atualização de ADRs**
   - ADRs globais (`/docs/adr/`)
   - ADRs sistêmicos (`/SAD/docs/adrs/`)
   - ADRs de domínio (`/domains/{domain}/docs/adr/`)

2. **Mudanças no SAD**
   - Congelamento/Descongelamento
   - Criação de novos ADRs sistêmicos
   - Atualização de princípios arquiteturais

3. **Validação de Domínios**
   - Validação inicial
   - Re-validações
   - Aprovação/Reprovação

4. **Criação/Modificação de Domínios**
   - Novo domínio criado
   - Estrutura de domínio alterada
   - Stack técnica modificada

5. **Mudança de Fase**
   - Conclusão de fase
   - Início de nova fase
   - Atualização de status

---

## 📋 Checklist de Documentos Obrigatórios

### ✅ Tier 1 - Governança Central (SEMPRE verificar)

| Documento | Localização | O Que Verificar |
|-----------|-------------|-----------------|
| **README.md** | `/README.md` | Fase atual, Status SAD, Data atualização |
| **SAD** | `/SAD/docs/sad.md` | Versão, Status (congelado/descongelado), Lista ADRs |
| **SAD Freeze Record** | `/SAD/docs/sad-freeze-record.md` | Último freeze registrado, Status atual |
| **Log de Progresso** | `/docs/logs/log-de-progresso.md` | Última atividade registrada, Data |
| **Execution Plan** | `/docs/plan/execution-plan.md` | Tasks marcadas corretamente |

### ✅ Tier 2 - Contextos para IA (Verificar se mudança arquitetural)

| Documento | Localização | O Que Verificar |
|-----------|-------------|-----------------|
| **Copilot Context** | `/ai-contexts/copilot-context.md` | Fase, Status SAD, Domínios, ADRs |
| **AI Architecture Overview** | `/AI-ARCHITECTURE-OVERVIEW.md` | Fase, Status SAD |
| **Context Generator** | `/docs/context/context-generator.md` | Escopo atualizado |

### ✅ Tier 3 - Domínios (Verificar se domínio afetado)

| Documento | Localização | O Que Verificar |
|-----------|-------------|-----------------|
| **Domain README** | `/domains/{domain}/README.md` | Status, Conformidade SAD |
| **Domain ADRs** | `/domains/{domain}/docs/adr/` | Referências ao SAD |
| **Validation Reports** | `/domains/{domain}/docs/` | Versão SAD validada |

---

## 🔍 Matriz de Verificação

### Campos que DEVEM estar consistentes:

| Campo | Localização Principal | Localizações Secundárias |
|-------|----------------------|--------------------------|
| **Fase Atual** | README.md | copilot-context.md, log-de-progresso.md |
| **Status SAD** | SAD/docs/sad.md | README.md, copilot-context.md |
| **Versão SAD** | SAD/docs/sad.md | ADRs atualizados, domain validations |
| **Total de ADRs** | SAD/docs/sad.md | copilot-context.md, SAD freeze record |
| **Último Freeze** | SAD/docs/sad-freeze-record.md | SAD/docs/sad.md |
| **Última Atividade** | docs/logs/log-de-progresso.md | README.md (data atualização) |
| **Tasks Concluídas** | docs/plan/execution-plan.md | log-de-progresso.md |
| **Domínios Status** | copilot-context.md | README.md, domains/*/README.md |

---

## 🛠️ Procedimento de Validação

### Passo 1: Identificar Escopo da Mudança
```
IF mudança em SAD THEN
  verificar_tier1() + verificar_tier2() + verificar_todos_dominios()
ELSE IF mudança em domínio THEN
  verificar_tier1() + verificar_dominio_afetado()
ELSE IF mudança de fase THEN
  verificar_tier1() + verificar_tier2()
ELSE
  verificar_tier1()
END IF
```

### Passo 2: Verificação Automatizada

Para cada documento no escopo:

1. **Ler cabeçalho** (primeiras 10-20 linhas)
2. **Extrair metadados**:
   - Última Atualização
   - Fase Atual
   - Status SAD
   - Versão
3. **Comparar com valores esperados**
4. **Identificar inconsistências**

### Passo 3: Atualização Batch

Se inconsistências encontradas:
1. **Listar todas as inconsistências**
2. **Propor correções** (batch)
3. **Aplicar correções** (usar `multi_replace_string_in_file` quando possível)
4. **Registrar no log**

### Passo 4: Confirmação

Após atualizações:
```
✅ Todos os documentos Tier 1 atualizados
✅ Contextos IA sincronizados
✅ Domínios afetados atualizados
✅ Log de progresso registrado
```

---

## 🤖 Prompt para IA

### Template de Execução

```markdown
## Post-Activity Hook - Validação de Documentos

**Atividade Realizada**: {descrição da atividade}
**Escopo de Impacto**: {SAD | Domínio | Fase | ADR}

### Verificação Tier 1 (Obrigatória)
- [ ] README.md: Fase, Status SAD, Data
- [ ] SAD/docs/sad.md: Versão, Status, ADRs
- [ ] SAD/docs/sad-freeze-record.md: Último freeze
- [ ] docs/logs/log-de-progresso.md: Última entrada
- [ ] docs/plan/execution-plan.md: Tasks atualizadas

### Verificação Tier 2 (Se mudança arquitetural)
- [ ] ai-contexts/copilot-context.md: Sincronizado
- [ ] AI-ARCHITECTURE-OVERVIEW.md: Sincronizado

### Verificação Tier 3 (Se domínio afetado)
- [ ] domains/{domain}/README.md: Status atualizado
- [ ] domains/{domain}/docs/adr/: Referências corretas

### Resultado
{Lista de documentos atualizados ou "✅ Todos sincronizados"}
```

---

## 📊 Valores Atuais (Snapshot 2026-01-05)

### Referência para Validação

```yaml
projeto:
  fase_atual: "2 (Criação dos Domínios)"
  data_atualizacao: "2026-01-05"

sad:
  versao: "1.2"
  status: "🔒 CONGELADO (Freeze #3)"
  total_adrs: 13
  ultimo_freeze: "2026-01-05"
  adrs_novos_v12:
    - "ADR-021: Escolha do Orquestrador (Kubernetes)"
  estrutura_nova:
    - "/platform-provisioning/azure/ (Em construção)"
    - "/platform-provisioning/aws/ (Planejado)"
    - "/platform-provisioning/gcp/ (Planejado)"

fase_2:
  status: "🔄 Em Progresso"
  task_atual: "2.0 (Provisionar Azure) ou 2.2 (platform-core)"
  tasks_concluidas:
    - "2.1: Validação observability ✅ (3 iterações)"

dominios:
  observability:
    status: "✅ Validado (APROVADO) + Consolidado"
    validacoes: 3
    sad_version: "v1.2"
    adrs_locais: 5
    bloqueador: "Refatoração Terraform AWS (não-bloqueante)"
  platform-core:
    status: "🔄 Próximo"
  cicd-platform:
    status: "🔄 Primeiro Objetivo (🎯)"
  data-services:
    status: "🔄 Planejado"
  secrets-management:
    status: "🔄 Planejado"
  security:
    status: "🔄 Planejado"

platform_provisioning:
  azure:
    status: "🔄 Em construção"
    custo: "$615/mês (recomendado CTO)"
  aws:
    status: "⏸️ Planejado"
    custo: "$599/mês"
  gcp:
    status: "⏸️ Planejado"
    custo: "$837/mês"
```

---

## 🚨 Alertas e Exceções

### Quando NÃO executar o hook:
- Correções de typos em documentação secundária
- Adição de comentários em código
- Modificações em arquivos de teste
- Alterações em `.gitignore`, `.editorconfig`, etc.

### Quando executar validação COMPLETA (Tiers 1+2+3):
- Freeze/Unfreeze do SAD
- Criação de novo ADR sistêmico
- Mudança de fase
- Validação de domínio

---

## 📝 Histórico de Execuções

### 2026-01-05 - Execução #3 (Consolidação Observability)
**Atividade**: Consolidação domínio observability (remoção artefatos, ADR-005, validação SAD v1.2)

**Documentos Atualizados**:
- ✅ domains/observability/docs/VALIDATION-REPORT.md (Validação #3)
- ✅ domains/observability/docs/adr/adr-005-revalidacao-sad-v12.md (novo)
- ✅ docs/logs/log-de-progresso.md

**Artefatos Removidos**:
- ❌ domains/observability/CLAUDE.md
- ❌ domains/observability/.claude/
- ❌ domains/observability/.github/
- ❌ domains/observability/Observabilidade.code-workspace

**Resultado**: 3 documentos atualizados, 4 artefatos removidos ✅

---

### 2026-01-05 - Execução #2 (Adequação /platform-provisioning/)
**Atividade**: Criação estrutura /platform-provisioning/, atualização SAD v1.1 → v1.2 (ADR-021)

**Documentos Atualizados**:
- ✅ README.md
- ✅ ai-contexts/copilot-context.md
- ✅ AI-ARCHITECTURE-OVERVIEW.md
- ✅ docs/plan/execution-plan.md
- ✅ docs/logs/log-de-progresso.md
- ✅ platform-provisioning/README.md (novo)
- ✅ platform-provisioning/azure/README.md (novo)
- ✅ SAD/docs/sad.md (v1.2)
- ✅ SAD/docs/sad-freeze-record.md (Freeze #3)

**Resultado**: 9 documentos sincronizados ✅

---

### 2026-01-05 - Execução #1 (Criação do Hook)
**Atividade**: Descongelamento SAD v1.0 → v1.1, ADR-020, Re-validação observability

**Documentos Atualizados**:
- ✅ README.md
- ✅ SAD/docs/sad.md
- ✅ SAD/docs/sad-freeze-record.md
- ✅ SAD/docs/adrs/adr-003-cloud-agnostic.md
- ✅ SAD/docs/adrs/adr-004-iac-gitops.md
- ✅ SAD/docs/adrs/adr-020-provisionamento-clusters.md (novo)
- ✅ ai-contexts/copilot-context.md
- ✅ AI-ARCHITECTURE-OVERVIEW.md
- ✅ domains/observability/README.md
- ✅ domains/observability/docs/adr/adr-001-decisoes-iniciais.md
- ✅ domains/observability/docs/adr/adr-002-mesa-tecnica.md
- ✅ domains/observability/docs/adr/adr-003-validacao-sad.md (novo)
- ✅ domains/observability/docs/adr/adr-004-revalidacao-sad-v11.md (novo)
- ✅ domains/observability/docs/VALIDATION-REPORT.md
- ✅ docs/logs/log-de-progresso.md
- ✅ docs/plan/execution-plan.md

**Resultado**: 16 documentos sincronizados ✅

---

## 🔗 Integração com Agentes

### Architect Guardian
Após validação de domínio:
```bash
execute: post-activity-hook
scope: Tier1 + Tier3(domain)
```

### Orchestrator Guide
Após mudança de fase:
```bash
execute: post-activity-hook
scope: Tier1 + Tier2
```

### Gestor
Após aprovação de ADR:
```bash
execute: post-activity-hook
scope: Tier1 + Tier2 (se sistêmico)
```

---

## ✅ Checklist Rápida (Para IA)

Após QUALQUER atividade, executar:

```
□ README.md tem data de hoje?
□ SAD versão e status corretos?
□ Log de progresso tem última entrada?
□ Copilot context sincronizado?
□ Domínio afetado atualizado?
□ Execution plan tasks marcadas?

Se todos ✅ → Prosseguir
Se algum ❌ → Atualizar ANTES de prosseguir
```

---

**Última Atualização**: 2026-01-05
**Versão**: 1.0
**Status**: Ativo ✅

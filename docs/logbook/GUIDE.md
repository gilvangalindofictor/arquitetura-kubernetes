# 📓 Logbook - Registro de Evolução do Projeto

**Last Updated:** 2026-02-25
**Status:** Living Document
**Owner:** Platform Team
**Purpose:** Logbook Standards & Guidelines

## Propósito

O **logbook** é o registro padronizado e atômico da evolução técnica do projeto. Cada arquivo representa uma tarefa, problema resolvido, ou milestone alcançado de forma independente e focada.

## Por que Logbook ao invés de Diário de Bordo?

### Problemas do Diário de Bordo:
- ❌ Documentos monolíticos e grandes (3000+ linhas)
- ❌ Perdidos no contexto de prompts LLM
- ❌ Difícil navegação e busca
- ❌ Histórico confuso e sem atomicidade

### Benefícios do Logbook:
- ✅ **Documentos atômicos**: um arquivo por tarefa/problema
- ✅ **Nomenclatura padronizada**: `YYYY-MM-DD-nome-descritivo.md`
- ✅ **Estrutura consistente**: fácil de encontrar informações
- ✅ **Contexto preservado**: dentro do limite de tokens
- ✅ **Navegação simplificada**: busca por data ou palavra-chave

## Estrutura de um Logbook

```markdown
# 📓 Título Descritivo da Tarefa/Problema

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | YYYY-MM-DD                               |
| **Demanda**    | Descrição breve                          |
| **Impacto**    | Baixo / Médio / Alto / Crítico           |
| **Agentes**    | Agentes/Pessoas envolvidas               |
| **Status**     | 🔄 Em Progresso / ✅ Concluído / ⚠️ Bloqueado |
| **Duração**    | Tempo estimado ou real                   |

---

## Timeline

```
[HH:MM:SS] Fase | Agente | Descrição | Status
[HH:MM:SS] Fase | Agente | Descrição | Status
...
```

---

## Problemas Identificados e Soluções

### 1. Nome do Problema

**Sintoma:**
Descrição do sintoma observado

**Causa Raiz:**
Análise da causa raiz

**Solução:**
Solução aplicada

**Arquivos:**
- Lista de arquivos modificados

---

## Lições Aprendidas

### 🔒 Categoria 1

| # | Lição | Impacto |
|---|-------|---------|
| 1 | Descrição da lição aprendida | 🔴 Crítico / 🟡 Médio / 🟢 Baixo |

### ⚙️ Categoria 2

| # | Lição | Impacto |
|---|-------|---------|
| 1 | Descrição da lição aprendida | 🔴 Crítico / 🟡 Médio / 🟢 Baixo |

---

## Métricas

| Métrica | Valor |
|---------|-------|
| Tempo total | XX minutos/horas |
| Tentativas de fix | N |
| Pods/recursos recriados | N |
| Downtime | XX min |

---

## Validação Final

```bash
# Comandos de validação executados
# com outputs e resultados
```

---

## Referências

- Links para ADRs relacionados
- Links para documentação externa
- Links para código/módulos Terraform
```

## Convenções de Nomenclatura

### Formato do Nome do Arquivo
```
YYYY-MM-DD-categoria-nome-descritivo.md
```

### Categorias Sugeridas
- `terraform-*`: Mudanças em infraestrutura Terraform
- `k8s-*`: Configurações Kubernetes
- `fix-*`: Correções de bugs/problemas
- `feature-*`: Implementação de features
- `milestone-*`: Marcos importantes do projeto
- `analysis-*`: Análises técnicas

### Exemplos
- `2026-02-03-terraform-redis-user-1000-sync.md`
- `2026-02-03-fix-redis-sentinel-crashloop.md`
- `2026-01-28-milestone-marco2-fase3-complete.md`
- `2026-01-22-analysis-vpc-reuse-decision.md`

## Diretrizes de Escrita

### ✅ Boas Práticas
1. **Seja objetivo**: Foque em fatos, não em narrativas extensas
2. **Use timestamps**: Timeline facilita entendimento cronológico
3. **Categorize lições**: Agrupe por tema (Security, Performance, etc.)
4. **Inclua métricas**: Números ajudam a entender impacto
5. **Adicione referências**: Links para ADRs, código, docs externas
6. **Marque impacto**: Use emoji para classificar (🔴🟡🟢)

### ❌ Evite
1. Narrativas longas e prolixas
2. Misturar múltiplas tarefas em um único arquivo
3. Omitir comandos e outputs relevantes
4. Falta de conclusão/validação final

## Migração do Diário de Bordo

Os diários de bordo antigos foram migrados para logbooks individuais:

### Diários Antigos (Arquivados)
- `docs/plan/aws-execution/00-diario-de-bordo.md` (3643 linhas) → Arquivado em `docs/archive/`
- `docs/plan/aws-execution/diario-marco0-2026-01-23.md` (3375 linhas) → Arquivado em `docs/archive/`

### Logbooks Criados
Cada sessão/entrada dos diários foi extraída para um logbook individual:
- Ver lista completa em `docs/logbook/INDEX.md`

## Índice de Logbooks

Para facilitar navegação, mantenha atualizado o arquivo `INDEX.md` com lista ordenada por data de todos os logbooks.

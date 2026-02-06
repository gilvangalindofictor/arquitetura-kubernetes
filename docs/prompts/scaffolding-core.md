# SCAFFOLD KIT — Core Instructions

> Este documento é o cérebro do sistema. Ele instrui qualquer AI coding assistant
> a orquestrar desenvolvimento autônomo com aprendizagem contínua.
> Não edite diretamente — use o repositório scaffold-kit para versionamento.

---

## 1. BOOTSTRAP — Análise e Configuração Inicial

Ao ler este documento pela primeira vez em um projeto, execute o bootstrap completo.
NÃO pule nenhuma etapa. NÃO assuma nada — analise e pergunte.

### 1.1 Análise do Projeto

Escaneie o projeto e identifique:

```
CHECKLIST DE ANÁLISE:
- [ ] Linguagem(ns) e runtime (package.json, requirements.txt, .csproj, go.mod, Cargo.toml, etc.)
- [ ] Framework(s) e versão
- [ ] Banco(s) de dados (docker-compose, configs, ORMs)
- [ ] Estrutura de pastas existente (listar árvore completa nível 2)
- [ ] Testes existentes (tipo, framework, cobertura)
- [ ] Documentação existente (README, docs/, wikis)
- [ ] CI/CD (GitHub Actions, Dockerfile, etc.)
- [ ] Dependências e suas versões
- [ ] CLAUDE.md ou arquivo de instrução AI existente
- [ ] Markdowns de planejamento existentes
```

### 1.2 Perguntas Iniciais

Após a análise, PERGUNTE ao usuário:

1. **Idioma**: "Qual idioma de comunicação prefere? (Português / English / Outro)"
2. **Arquivo de instrução existente** (se encontrou): "Encontrei um [CLAUDE.md / .cursorrules / etc.]. O que fazer? (Merge preservando o existente / Substituir / Criar separado)"
3. **Planejamento**: "Encontrei markdowns de planejamento em [path]?" ou "Não encontrei documentos de planejamento. Vai fornecer ou quer criar agora?"

### 1.3 Mapeamento de Estrutura

ANTES de criar qualquer arquivo, mapeie a estrutura existente e mostre ao usuário:

**Regras de mapeamento:**

| Situação | Ação |
|----------|------|
| Pasta existe com nome idêntico ao que o scaffold precisa (ex: `docs/` ↔ `docs/`) | ✅ Reaproveita automaticamente |
| Pasta existe com sinergia clara (ex: `documentation/` ↔ `docs/`, `spec/` ↔ `tests/`) | ✅ Reaproveita automaticamente |
| Múltiplas pastas candidatas (ex: `test/` e `__tests__/`) | ⚠ Pergunta ao usuário |
| Pasta não existe | 🆕 Informa que será criada |
| Pasta existe sem sinergia com scaffold | ⏭ Preserva intacta |

**Apresente o mapa ao usuário para aprovação:**

```
MAPEAMENTO DE ESTRUTURA:

Detectado              →  Scaffold vai usar       Status
────────────────────────────────────────────────────────
{pasta_existente}      →  {pasta_scaffold}         ✅ reusa
{outra_pasta}          →  {pasta_scaffold}         ✅ sinergia
{ambigua_1} ou {amb_2} →  {pasta_scaffold}         ⚠ ambíguo — qual usar?
—                      →  {nova_pasta}             🆕 criar
{sem_relação}          →  —                        ⏭ preserva

Aplicar? (Sim / Ajustar / Cancelar)
```

Espere aprovação ANTES de criar ou modificar qualquer coisa.

### 1.4 Criação da Estrutura

Após aprovação, crie APENAS o que não existe:

```
{projeto}/
├── .scaffold/                         ← Pasta de referência do kit (se não existe)
│   ├── skills/                        ← Copiar do scaffold-kit
│   ├── templates/                     ← Copiar do scaffold-kit
│   ├── checklists/                    ← Copiar do scaffold-kit
│   └── agents/                        ← Copiar do scaffold-kit
│
├── {docs_dir}/                        ← Pasta de docs (detectada ou criada)
│   ├── context/                       ← Docs auto-evolutivos
│   │   ├── PROJECT_BRIEF.md           ← Preenchido com dados detectados
│   │   ├── ARCHITECTURE.md            ← Template, preenchido quando possível
│   │   ├── CONVENTIONS.md             ← Inferido do código existente
│   │   ├── CURRENT_STATE.md           ← Reflete estado real do projeto
│   │   └── DECISIONS_LOG.md           ← Vazio, pronto para uso
│   ├── planning/                      ← Markdowns de planejamento (se existem)
│   ├── security/                      ← Relatórios de audit (criado quando necessário)
│   └── logbook/                       ← Diário de bordo (append-only)
│
├── learning/                          ← Sistema de aprendizagem
│   ├── lessons/
│   │   ├── _index.json
│   │   └── LESSONS.md
│   ├── agents/
│   ├── feedback/
│   │   └── entries.jsonl
│   └── knowledge_router.json
│
└── {tests_dir}/                       ← Pasta de testes (detectada ou criada)
    ├── unit/
    ├── integration/
    ├── e2e/                           ← RPA com Playwright
    └── performance/
```

Para cada documento de contexto, use os templates em `.scaffold/templates/`.
Preencha automaticamente o que puder com base na análise do projeto.
O que não souber preencher, deixe com `TODO:` para o usuário completar.

---

## 2. ECONOMIA DE TOKENS — Regra Global de Comunicação

**Todo output deve ser o mais curto e denso possível.** Tokens custam dinheiro e tempo.
Esta regra se aplica a TODAS as respostas, relatórios, logs e documentos gerados.

### Formato Obrigatório

| Regra | ❌ Ruim | ✅ Bom |
|-------|---------|--------|
| Sem introduções genéricas | "Vou analisar a demanda e..." | Ir direto à análise |
| Sem repetir a pergunta | "Você pediu para criar..." | Começar pela resposta |
| Sem explicar o óbvio | "Um teste unitário testa..." | Pular se o usuário sabe |
| Status em 1 linha | Parágrafo descritivo | `✅ endpoint criado | /api/users | 200ms | 3 testes` |
| Listas compactas | Bullet com frase completa | `key: value` em linha única |

### O que NUNCA incluir

- Explicações de conceitos básicos (assume-se usuário sênior)
- Frases de cortesia ("Claro!", "Ótima pergunta!")
- Recapitulação de etapas já concluídas
- Outputs completos de comandos quando um resumo basta
- Blocos de código repetidos (referenciar por nome se já existem)

### Padrão de Resposta dos Agentes

Cada agente responde no formato compacto:

```
[AGENTE] <emoji> <nome>
AVALIAÇÃO: <1-2 frases máximo>
RISCOS: <lista inline ou "nenhum">
AÇÃO: <aprovar / bloquear / condicionar>
```

Exemplo:
```
[REVIEWER] 🔍 Code Reviewer
AVALIAÇÃO: Controller limpo, mas Service com 280 linhas e 3 responsabilidades.
RISCOS: manutenibilidade, testabilidade
AÇÃO: condicionar — extrair AuthService e ValidationService antes de merge
```

---

## 3. DOCUMENTOS DE CONTEXTO — Regras de Uso e Atualização

Estes documentos são a memória do projeto. São auto-evolutivos: atualizados automaticamente
após cada task executada.

### Hierarquia e Responsabilidade

| Documento | Quem atualiza | Quando | Prioridade de leitura |
|-----------|--------------|--------|----------------------|
| `PROJECT_BRIEF.md` | **Usuário** | Quando requisitos mudam | 1 (sempre ler primeiro) |
| `ARCHITECTURE.md` | AI (agente architect) | Após decisões arquiteturais | 2 |
| `CONVENTIONS.md` | **Usuário** + AI | Setup inicial + refinamentos | 3 |
| `CURRENT_STATE.md` | AI (automático) | Após CADA task | 4 |
| `DECISIONS_LOG.md` | AI (automático) | Após decisões significativas | 5 |

### Regras

1. **ANTES de qualquer task**: leia PROJECT_BRIEF.md + CURRENT_STATE.md + CONVENTIONS.md
2. **APÓS qualquer task que modifica código**: atualize CURRENT_STATE.md
3. **APÓS decisão arquitetural**: registre em DECISIONS_LOG.md + atualize ARCHITECTURE.md
4. **NUNCA modifique PROJECT_BRIEF.md** automaticamente — é do usuário
5. Se algo em PROJECT_BRIEF.md parece desatualizado, **avise o usuário**

---

## 4. PLANNING CONSUMER — Interpretação de Demandas

### Quando ativar

Se existem markdowns de planejamento (detectados no bootstrap ou fornecidos depois).

### Fluxo

```
1. Leia TODOS os markdowns de planejamento encontrados
2. Interprete e extraia:
   - Sprints / Marcos / Fases (agrupamentos de qualquer formato)
   - Tasks individuais com descrição
   - Tipo de cada task: backend | frontend | database | devops | infra | docs | outro
   - Dependências entre tasks (se mencionadas ou inferíveis)
   - Critérios de aceite (se mencionados)

3. Se houver DÚVIDAS ou AMBIGUIDADES:
   - PARE e PERGUNTE ao usuário
   - Não assuma — peça clarificação
   - Liste todas as dúvidas de uma vez (não uma por uma)

4. Para cada task detectada, ADICIONE AUTOMATICAMENTE:
   - Test gates obrigatórios (ver seção 6)
   - Security check inline (ver seção 7)
   - Agente responsável (ver seção 4)

5. Ao final de cada sprint/marco, ADICIONE:
   - Security audit completo

6. APRESENTE o plano completo ao usuário:
   - Mostre: sprints → tasks → agentes → dependências → testes → security
   - Mostre dúvidas pendentes se houver
   - Espere APROVAÇÃO antes de executar

7. Após aprovação: execute conforme seção 10 (EXECUÇÃO)
```

### Classificação de tasks

Se o planning não explicita o tipo, infira:

```
Palavras-chave → Tipo:
- API, endpoint, controller, service, repository → backend
- componente, página, tela, UI, CSS, layout → frontend
- tabela, migration, schema, query, índice → database
- docker, CI/CD, pipeline, deploy, infra → devops
- documentação, README, guia, manual → docs
- Ambíguo → perguntar ao usuário
```

---

## 5. AGENTES — Perfis Especializados e Consenso

Cada task é executada por um "agente" — um conjunto de instruções especializadas
que define como a AI deve se comportar para aquela tarefa.

### Agentes disponíveis

Os perfis base estão em `.scaffold/agents/`. Leia o perfil ANTES de executar como aquele agente.

| Agente | Responsabilidade | Lê | Escreve |
|--------|-----------------|-----|---------|
| `architect` | Design, decisões arquiteturais | BRIEF, ARCH, DECISIONS | ARCH, DECISIONS |
| `coder` | Implementação genérica | ARCH, CONVENTIONS, STATE | STATE |
| `backend_coder` | APIs, serviços, banco | ARCH, CONVENTIONS, STATE | STATE |
| `frontend_coder` | UI, componentes, páginas | ARCH, CONVENTIONS, STATE | STATE |
| `tester` | Todos os tipos de teste | STATE, CONVENTIONS | STATE |
| `reviewer` | Code review, qualidade | CONVENTIONS, ARCH, STATE | STATE, DECISIONS |
| `security` | Validação segurança + auditorias | ARCH, CONVENTIONS, STATE | STATE, DECISIONS |
| `docs` | Documentação técnica | STATE, ARCH, CONVENTIONS | STATE |
| `devops` | Infra, CI/CD, containers | ARCH, STATE | STATE, DECISIONS |

### Atribuição automática

```
Tipo da task → Agente padrão:
- backend     → backend_coder (ou coder se não houver especializado)
- frontend    → frontend_coder (ou coder)
- database    → backend_coder
- devops      → devops
- infra       → devops
- docs        → docs
- design/arch → architect
- testes      → tester
- review      → reviewer
- security    → security
```

### Perfis evolutivos

Antes de executar como um agente, TAMBÉM leia:
1. O perfil base em `.scaffold/agents/{agente}.md`
2. O perfil evolutivo em `learning/agents/{agente}.md` (se existir)
3. O perfil evolutivo em `learning/agents/{agente}.json` (se existir)

O perfil evolutivo tem **prioridade sobre o base** quando há conflito.
A seção `## Pinned` no `.md` evolutivo foi editada manualmente pelo usuário e
NUNCA deve ser sobrescrita ou ignorada.

### Protocolo de Consenso

**Nenhuma task é executada sem consenso técnico dos agentes relevantes.**

```
1. Orquestrador analisa a task e identifica agentes relevantes
2. Cada agente relevante avalia (formato compacto da seção 2)
3. Se TODOS aprovam → executa
4. Se algum CONDICIONA → resolver condição primeiro
5. Se algum BLOQUEIA → não executa, resolver bloqueio
```

**Quais agentes participam de quê:**

| Tipo da task | Agentes no consenso |
|-------------|-------------------|
| backend (código) | coder + reviewer |
| backend (API) | coder + tester + security |
| frontend | frontend_coder + tester (RPA) |
| database | coder + reviewer + security |
| devops/infra | devops + security |
| arquitetura | architect + reviewer |

Nem toda task precisa de todos os agentes. O princípio é: **quem é impactado opina.**

---

## 6. KNOWLEDGE SOURCES — Roteamento de Documentação

### Regra de roteamento

Para cada dependência do projeto, determine a melhor fonte de documentação:

```
1. Leia o manifesto de dependências:
   package.json / requirements.txt / .csproj / go.mod / Cargo.toml / etc.

2. Para CADA dependência relevante para a task atual:

   VERSÃO ESTÁVEL (release oficial, sem sufixo beta/rc/preview/alpha):
   → Use MCP de documentação (Context7 ou equivalente) para docs oficiais
   → Confiável, prioridade alta

   VERSÃO BETA / RC / PREVIEW:
   → Clone repositório oficial via MCP de repositórios (GitHub MCP ou equivalente)
   → Analise o código-fonte no clone local
   → Docs oficiais podem estar desatualizados — prefira o código

   VERSÃO BLEEDING EDGE (branch main, sem tag):
   → Clone o repo e leia localmente via MCP de filesystem
   → Não confie em docs — leia implementação real

   LIB INTERNA / PRIVADA:
   → Use MCP de filesystem para ler código-fonte local
   → Se houver docs internas, priorize

   PROBLEMA ESPECÍFICO / BUG:
   → Use MCP de repositórios para buscar issues abertas/fechadas
   → Busque workarounds conhecidos

3. Registre a decisão em learning/knowledge_router.json para reutilizar:
   {
     "resolved": {
       "{pacote}@{versão}": {
         "source": "context7 | github_clone | filesystem",
         "note": "razão da escolha"
       }
     }
   }
```

### Fallback

Se nenhum MCP estiver disponível para a fonte ideal:
1. Use o conhecimento interno da AI
2. Informe o usuário que a resposta pode não refletir a versão exata
3. Sugira configurar o MCP apropriado

---

## 7. TEST GATES — Testes Obrigatórios

### Regra principal

**NENHUMA task é considerada DONE sem seus testes obrigatórios passando.**

### Matriz de testes por tipo de task

| Tipo de task | Unit | Integração | Performance | RPA (Playwright) | Security Check |
|-------------|------|-----------|-------------|------------------|---------------|
| backend | ✅ obrigatório | ✅ obrigatório | ○ recomendado | — | ✅ obrigatório |
| frontend | ✅ obrigatório | ○ recomendado | ○ recomendado | ✅ obrigatório | ✅ obrigatório |
| database | ○ recomendado | ✅ obrigatório | ✅ obrigatório | — | ✅ obrigatório |
| devops/infra | — | ✅ obrigatório | ○ recomendado | — | ✅ obrigatório |
| docs | — | — | — | — | — |

### Padrões por tipo de teste

**Unit tests**: Cobrir happy path + edge cases. Mocks para dependências externas.
Nomes descritivos: `test_should_{ação}_when_{condição}`.

**Integration tests**: Testar com dependências reais (banco, APIs). Cleanup entre testes.

**Performance tests**: Definir baseline. Testar sob carga esperada. Identificar gargalos.

**RPA / E2E (Playwright)**: Page Object Model. Seletores via `data-testid`.
Screenshots em falha. Consultar `.scaffold/skills/rpa_playwright.md`.

**Security check**: Executar checklist inline. Consultar `.scaffold/checklists/security_inline.md`.

### Cobertura mínima

- Global: 80%
- Lógica de negócio: 90%
- Endpoints/Controllers: 70%

---

## 8. SECURITY — Duas Camadas

### 7.1 Security Check Inline (a cada task que gera código)

Após implementar, ANTES de marcar como done, verificar:

```
CHECKLIST INLINE DE SEGURANÇA:
- [ ] Inputs validados e sanitizados
- [ ] Queries parametrizadas (NUNCA concatenação de strings)
- [ ] Output encoding (prevenção XSS)
- [ ] Auth/AuthZ em todos os endpoints que precisam
- [ ] Sem secrets hardcoded (senhas, tokens, chaves)
- [ ] CORS configurado corretamente
- [ ] Rate limiting considerado
- [ ] Logs sem dados sensíveis (senhas, tokens, PII)
- [ ] Headers de segurança configurados
- [ ] Dependências sem vulnerabilidades conhecidas
```

Se QUALQUER item falhar: **corrigir ANTES de marcar task como done**.
Se houve trade-off de segurança: registrar em DECISIONS_LOG.md com justificativa.

### 7.2 Security Audit Completo (ao final de cada sprint/marco)

```
AUDIT DE SEGURANÇA POR SPRINT:

1. OWASP Top 10 (2021) — Checklist completo
   Consultar: .scaffold/checklists/security_audit.md

2. SAST — Análise estática do código
   Ferramentas sugeridas por stack:
   - Python: bandit, semgrep
   - Node/TS: npm audit, eslint-plugin-security, semgrep
   - .NET: dotnet security-scan, semgrep
   - Go: gosec, semgrep
   - Genérico: semgrep (sempre disponível)

3. DAST — Testes dinâmicos contra endpoints (se aplicável)
   - OWASP ZAP ou nikto

4. Dependency Check
   - npm audit / pip-audit / dotnet list --vulnerable / cargo audit

5. Gerar relatório em {docs_dir}/security/audit_sprint_N.md
```

---

## 9. APRENDIZAGEM — Sistema de Lições e Perfis Evolutivos

### 8.1 Armazenamento

Lições são armazenadas em DOIS formatos:
- `learning/lessons/_index.json` — Estruturado, para a AI consumir
- `learning/lessons/LESSONS.md` — Legível, para o usuário revisar

Perfis de agentes em DOIS formatos:
- `learning/agents/{agente}.json` — Dados + métricas
- `learning/agents/{agente}.md` — Legível + editável pelo usuário

### 8.2 Quando extrair lições

Após CADA task, analisar:

| Sinal | Como detectar | Severidade |
|-------|--------------|-----------|
| Task precisou de retry | Falhou e precisou reexecutar | warning |
| Diff desproporcional | Muito código para escopo simples (heurística) | warning |
| Refatoração imediata | Task de refactor logo após implementação | warning → enforce |
| Mesmo erro > 2 vezes | Padrão de erro recorrente | critical |
| Feedback 👎 do usuário | Usuário deu negativo | critical |
| Feedback 👍 do usuário | Usuário deu positivo | info (reforço) |
| Tempo excessivo | Task demorou > 2x a média do projeto | info |

### 8.3 Formato de uma lição

```json
{
  "id": "lesson_001",
  "timestamp": "2026-02-06T...",
  "category": "code_quality | architecture | framework | performance | security | pattern",
  "severity": "info | warning | critical",
  "context": "Quando o agente coder implementa endpoints complexos...",
  "lesson": "Preferir composição sobre herança. Métodos < 20 linhas.",
  "source": { "task_id": "...", "agent": "...", "signal": "retry" },
  "tags": ["complexity", "simplicity"],
  "weight": 1.0,
  "applied_count": 0
}
```

### 8.4 Perfil evolutivo do agente

Quando uma lição impacta um agente específico, atualizar seu perfil:

**Traits** (injetados no prompt do agente):
- `enforce`: SEMPRE injetar, não negociável
- `warn`: Injetar se cabe no budget
- `info`: Injetar só se sobrar espaço

**Seção Pinned**: Editada manualmente pelo usuário. NUNCA sobrescrever.
Se `learning/agents/{agente}.md` contém `## Pinned`, preservar integralmente.

**Métricas**: tasks_completed, retries, refactoring_rounds, avg_quality

### 8.5 Decay (perda de peso)

```
Lição criada                    → peso 1.0
Após 5 execuções sem aplicar    → peso 0.8
Após 10 execuções sem aplicar   → peso 0.5
Após 20 execuções sem aplicar   → peso 0.2 (arquivada)

EXCEÇÕES (sem decay, peso permanente):
- Severity "critical"
- Seção "Pinned" do agente (editada pelo usuário)
- Originada de feedback 👎 explícito
```

### 8.6 Atualização dos arquivos legíveis

Após qualquer modificação no sistema de aprendizagem, regenerar:

**`learning/lessons/LESSONS.md`**:
```markdown
# Lições Aprendidas — {projeto}

## Critical
- [code_quality] {descrição} (desde: {data})
- ...

## Warnings
- [architecture] {descrição} (peso: {peso})
- ...

## Info
- ...

_Atualizado: {timestamp} | Total: {N} lições | Arquivadas: {M}_
```

**`learning/agents/{agente}.md`**:
```markdown
# Perfil: {agente}

## Traits Ativos
- 🔴 ENFORCE: {descrição} (motivo: ...)
- 🟡 WARN: {descrição} (motivo: ...)

## Pinned (editado manualmente — NÃO sobrescrever)
- {conteúdo do usuário, se existir}

## Lições
1. {lição}
2. {lição}

## Métricas
| Tasks | Retries | Refatorações | Qualidade |
|-------|---------|-------------|-----------|
| {N}   | {N}     | {N}         | {N}/5     |

_Atualizado: {timestamp} | Versão do perfil: {N}_
```

---

## 10. FEEDBACK — Coleta e Integração

### Quando coletar

- Ao final de cada sprint/marco: perguntar sobre cada task concluída
- Quando o usuário pedir explicitamente ("feedback", "review", "avaliar")

### Formato

Para cada task, perguntar:
- **👍 Bom** ou **👎 Ruim**
- Comentário opcional: texto livre

### Registro

Salvar em `learning/feedback/entries.jsonl`:
```json
{"task_id": "...", "agent": "...", "rating": "up|down", "comment": "...", "timestamp": "..."}
```

### Integração

```
Se 👎:
  → Identificar causa provável (perguntar ao usuário se não for óbvio)
  → Adicionar lição em learning/lessons/ com severity "critical"
  → Atualizar trait do agente para "enforce" ou "warn"
  → Garantir que seção "Pinned" do agente NÃO é modificada

Se 👍:
  → Reforçar comportamento positivo (registrar como "info")
  → Aumentar peso das lições que foram aplicadas nessa task
```

---

## 11. DIÁRIO DE BORDO E SINCRONIZAÇÃO

### 11.1 Logbook (Diário de Bordo)

Registro cronológico, incremental e **append-only** de tudo que acontece.
Fonte de verdade temporal para auditoria, debug e post-mortems.

**Localização**: `{docs_dir}/logbook/YYYY-MM-DD-<demand-slug>.md`

**Estrutura do arquivo:**

```markdown
# 📓 Diário de Bordo — <Nome da Demanda>

| Campo | Valor |
|-------|-------|
| Data | YYYY-MM-DD |
| Demanda | <descrição curta> |
| Impacto | baixo / médio / alto |
| Agentes | <lista> |
| Status | em andamento / concluído / rollback |

---

## Timeline

[HH:MM:SS] <etapa> | <agente> | <ação> | <resultado emoji> | <detalhes mínimos>
```

**Formato de entrada** (telegráfico, 1 linha por evento):
```
[14:32:10] Análise   | Orq     | Demanda: criar endpoint /users    | impacto: médio
[14:32:45] Consenso  | Cod,Rev | Aprovado                          | ✅
[14:33:00] Implement | Coder   | Controller + Service + Migration  | ✅ 47s
[14:33:50] TestGate  | Tester  | 12 unit + 4 integ                 | ✅ 100%
[14:34:10] Security  | Sec     | Inline check passed               | ✅
[14:34:20] DocSync   | Orq     | CURRENT_STATE.md, DECISIONS_LOG   | ✅
[14:35:00] ERRO      | Tester  | Teste de concorrência falhou      | ❌
[14:36:30] Fix       | Coder   | Mutex adicionado no /transfer     | ✅ 90s
[14:37:00] Retest    | Tester  | Todos passando                    | ✅
```

**Regras:**
1. Criar arquivo no início de CADA demanda
2. Append-only: NUNCA editar entradas passadas
3. Timestamps obrigatórios em cada entrada
4. Registrar: análise, consenso, execução, testes, erros, rollbacks, doc sync
5. Cada ciclo de monitoramento relevante gera uma entrada
6. Ao final: sumário com duração total, artefatos gerados, docs atualizados

### 11.2 Sincronização de Documentos Pós-Etapa

```
⚠️ REGRA CRÍTICA: Ao concluir QUALQUER etapa significativa,
os documentos de contexto DEVEM ser atualizados ANTES de prosseguir.
Documentos defasados = dívida técnica. Tratar com mesma urgência que bugs.
NÃO iniciar próxima etapa sem sync completo.
```

**Triggers de sincronização:**

| Evento | Documentos a atualizar |
|--------|----------------------|
| Task concluída | CURRENT_STATE.md |
| Decisão arquitetural | ARCHITECTURE.md + DECISIONS_LOG.md |
| Sprint/marco concluído | CURRENT_STATE.md + LESSONS.md |
| Erro/incidente | DECISIONS_LOG.md (o que aconteceu + resolução) |
| Mudança de convenção | CONVENTIONS.md |
| Security audit | Security report + CURRENT_STATE.md |

**Protocolo:**
```
1. Identificar quais documentos foram impactados
2. Para cada documento:
   ├─ Ler estado atual
   ├─ Identificar seção a atualizar
   ├─ Adicionar/modificar com data e referência à demanda
   └─ Salvar
3. Registrar no logbook: "[HH:MM:SS] DocSync | Orq | <docs atualizados> | ✅"
4. Confirmar sync antes de prosseguir
```

---

## 12. EXECUÇÃO — Fluxo por Task

### Pipeline completo de cada task

```
┌─ LOGBOOK ──────────────────────────────────────────────────────┐
│  Registrar início da task no diário de bordo                     │
│  [HH:MM:SS] Início | Orq | Task: {id} | Agente: {agente}       │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─ PRE-TASK ──────────────────────────────────────────────────────┐
│                                                                  │
│  1. Ler skill relevante em .scaffold/skills/                     │
│  2. Ler regras invioláveis do domínio (seção 14)                 │
│  3. Ler perfil base do agente em .scaffold/agents/               │
│  4. Ler perfil evolutivo em learning/agents/ (se existir)        │
│  5. Ler docs de contexto: PROJECT_BRIEF + CURRENT_STATE +        │
│     CONVENTIONS + ARCHITECTURE (conforme tabela do agente)       │
│  6. Consultar knowledge router para fonte de docs certa          │
│  7. Montar prompt com aprendizagem (max 2000 tokens de lições):  │
│     Prioridade: enforce → critical → pinned → warn → por peso   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─ CONSENSO ─────────────────────────────────────────────────────┐
│  Agentes relevantes avaliam (formato compacto da seção 2):       │
│  Se TODOS aprovam → prosseguir                                   │
│  Se CONDICIONA → resolver condição primeiro                      │
│  Se BLOQUEIA → não executar, reportar                            │
│  Registrar no logbook: [HH:MM:SS] Consenso | {agentes} | ✅/❌  │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─ EXECUÇÃO ─────────────────────────────────────────────────────┐
│  Executar a task como o agente designado                         │
│  Seguir instruções do perfil + skills + contexto injetado        │
│                                                                  │
│  Se comando longo (> 30s):                                       │
│  → Background + monitoramento ativo                              │
│  → Report por ciclo: [MON-C<N>] <elapsed>s | <status> | <alerta>│
│  → Cada ciclo relevante → entrada no logbook                     │
│                                                                  │
│  Verificar regras invioláveis do domínio durante execução.       │
│  Se alguma seria violada → PARAR e reportar.                     │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─ SECURITY CHECK INLINE ────────────────────────────────────────┐
│  Se a task gerou código: executar checklist da seção 8.1         │
│  Se algum item falhou: corrigir ANTES de prosseguir              │
│  Registrar no logbook: [HH:MM:SS] Security | Sec | ✅/❌        │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─ TEST GATE ────────────────────────────────────────────────────┐
│  Executar testes obrigatórios conforme matriz da seção 7         │
│  Task NÃO é done até todos os testes obrigatórios passarem      │
│  Registrar no logbook: [HH:MM:SS] TestGate | Tester | ✅/❌     │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─ VALIDAÇÃO PÓS-EXECUÇÃO ──────────────────────────────────────┐
│  1. O entregue corresponde ao pedido?                            │
│  2. Testes passam?                                               │
│  3. Regras invioláveis respeitadas?                              │
│  4. Efeitos colaterais?                                          │
│  5. Idempotente? (re-executar não causa divergência)             │
│  Se algo falhou → corrigir ANTES de prosseguir                   │
└──────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─ POST-TASK ────────────────────────────────────────────────────┐
│                                                                  │
│  1. Sincronizar documentos (protocolo seção 11.2)                │
│  2. Registrar decisões em DECISIONS_LOG.md (se houve)            │
│  3. Analisar resultado:                                          │
│     - Houve retries? Diff grande? Erro recorrente?               │
│  4. Extrair lições se houve problema                             │
│  5. Atualizar perfil do agente se necessário                     │
│  6. Atualizar learning/lessons/LESSONS.md                        │
│  7. Registrar no logbook: [HH:MM:SS] Done | Orq | Task {id} | ✅│
│  8. Verificar pressão de contexto:                               │
│     - ≥ 60%: compactar (resumir histórico, preservar essencial)  │
│     - ≥ 78%: checkpoint + regenerar sessão                       │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### Ao final de cada sprint/marco

1. Executar **Security Audit Completo** (seção 7.2)
2. Coletar **Feedback** do usuário (seção 9)
3. Atualizar **CURRENT_STATE.md** com resumo do sprint
4. Gerar relatório do sprint

### Ao final do workflow completo

1. Atualizar todos os docs de contexto com estado final
2. Gerar relatório final:
   - Tasks executadas / falhadas
   - Cobertura de testes
   - Issues de segurança encontrados/resolvidos
   - Lições aprendidas neste ciclo
3. Perguntar ao usuário se quer dar feedback final

---

## 13. GESTÃO DE CONTEXTO — Compactação e Continuidade

### Monitoramento

A cada task, estime o uso da janela de contexto:

```
< 60%:  Normal — continue
≥ 60%:  COMPACTAR
        → Resumir histórico da sessão
        → Preservar: docs de contexto, lições, estado atual
        → Descartar: conversas intermediárias, logs verbosos

≥ 78%:  CHECKPOINT + REGENERAR
        → Salvar estado completo em CURRENT_STATE.md
        → Garantir que learning/ está atualizado
        → Informar: "Contexto crítico. Recomendo iniciar nova sessão.
          O estado está salvo — na próxima sessão, leia CURRENT_STATE.md
          para continuar de onde parou."
```

### Continuidade entre sessões

Na próxima sessão, o AI deve:
1. Ler este documento (bootstrap detecta que já foi feito)
2. Ler CURRENT_STATE.md → entender onde parou
3. Ler learning/ → carregar lições e perfis
4. Continuar do ponto exato, sem retrabalho

---

## 14. REGRAS INVIOLÁVEIS POR DOMÍNIO

Cada domínio de trabalho define **regras que NUNCA podem ser quebradas**.
Ficam na skill do domínio em `.scaffold/skills/{dominio}.md` na seção `## Regras Invioláveis`.

### Protocolo de enforcement

```
ANTES de cada task:
1. Identificar domínio da task (backend, frontend, devops, database, etc.)
2. Ler .scaffold/skills/{dominio}.md
3. Localizar seção "## Regras Invioláveis"
4. Manter essas regras em mente durante toda a execução

DURANTE a execução:
5. Se qualquer regra seria violada → PARAR imediatamente
6. Reportar: qual regra, por que seria violada, alternativa proposta
7. Só prosseguir após resolução

APÓS a execução:
8. Validar que NENHUMA regra foi violada
9. Se foi → corrigir ANTES de marcar task como done
```

### Exemplos de regras por domínio

Cada skill define as suas. Estes são exemplos — as regras reais ficam nas skills:

```
Backend:
- Nunca endpoint sem autenticação (exceto explicitamente público)
- Nunca query sem parametrização
- Nunca resposta sem tratamento de erro padronizado
- Nunca expor stack trace em produção

Frontend:
- Nunca componente sem data-testid para testes RPA
- Nunca estado global sem justificativa documentada
- Nunca deploy sem testes Playwright passando
- Nunca input sem validação client-side + server-side

DevOps/Terraform:
- Nunca apply sem plan revisado
- Todo ajuste codificado no IaC (nada manual)
- Idempotência: plan pós-apply DEVE retornar "No changes"
- Nunca travar em comando longo (background + monitoramento)

Database:
- Nunca migration destrutiva sem backup verificado
- Nunca schema change sem migration versionada
- Nunca query em campo de busca sem índice
- Nunca expor dados sensíveis em logs

Security:
- Nunca secret hardcoded no código
- Nunca dependência com CVE conhecida sem mitigação
- Nunca bypass de auth "temporário"
- Nunca log com PII sem mascaramento
```

Projetos podem adicionar regras específicas no perfil das skills ou em CONVENTIONS.md.

---

## REFERÊNCIAS — Arquivos de Suporte

Todos em `.scaffold/`:

```
.scaffold/
├── skills/                        ← Ler antes de executar por domínio
│   ├── database_design.md
│   ├── api_patterns.md
│   ├── frontend_patterns.md
│   ├── cli_patterns.md
│   ├── data_pipeline.md
│   ├── testing_strategy.md
│   ├── security_baseline.md
│   ├── rpa_playwright.md
│   └── documentation.md
│
├── templates/                     ← Usar ao criar docs de contexto
│   ├── PROJECT_BRIEF.template.md
│   ├── ARCHITECTURE.template.md
│   ├── CONVENTIONS.template.md
│   ├── CURRENT_STATE.template.md
│   └── DECISIONS_LOG.template.md
│
├── checklists/                    ← Usar nos pontos indicados
│   ├── security_inline.md         ← Seção 7.1
│   ├── security_audit.md          ← Seção 7.2
│   ├── test_gate.md               ← Seção 6
│   └── code_review.md             ← Usado pelo agente reviewer
│
└── agents/                        ← Perfis base dos agentes
    ├── architect.md
    ├── coder.md
    ├── backend_coder.md
    ├── frontend_coder.md
    ├── tester.md
    ├── reviewer.md
    ├── security.md
    ├── docs.md
    └── devops.md
```

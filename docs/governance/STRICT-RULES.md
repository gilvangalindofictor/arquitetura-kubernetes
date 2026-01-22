# Regras Rígidas de Governança - Anti-Alucinação

> **Versão**: 1.0
> **Data de Criação**: 2026-01-22
> **Status**: ✅ ATIVO - OBRIGATÓRIO
> **Aplicação**: TODAS as IAs (GitHub Copilot, Claude, ChatGPT, etc.)

---

## 🚨 PRINCÍPIO FUNDAMENTAL

**NUNCA CRIE DOCUMENTOS SEM APROVAÇÃO EXPLÍCITA DO USUÁRIO**

Toda criação de arquivo, especialmente documentos markdown, DEVE ser precedida de:
1. Justificativa clara
2. Localização exata proposta
3. Aprovação explícita do usuário

---

## 📁 ESTRUTURA OFICIAL DO PROJETO

### Hierarquia de Diretórios APROVADA

```
Kubernetes/
├── README.md                       # ✅ ÚNICO README raiz
├── PROJECT-CONTEXT.md              # ✅ Contexto consolidado
├── ARCHITECTURE-DIAGRAMS.md        # ✅ Diagramas centralizados
│
├── SAD/                            # ✅ Decisões Sistêmicas
│   └── docs/
│       ├── sad.md                  # ✅ ÚNICO SAD
│       ├── sad-freeze-record.md    # ✅ ÚNICO freeze record
│       ├── adrs/                   # ✅ ADRs sistêmicos numerados (adr-XXX-)
│       └── architecture/           # ✅ Contratos e herança
│
├── docs/                           # ✅ Governança Central
│   ├── context/                    # ✅ Contexto do projeto
│   ├── adr/                        # ✅ ADRs de governança
│   ├── plan/                       # ✅ Planos de execução
│   │   ├── execution-plan.md       # ✅ ÚNICO plano de execução
│   │   ├── aws-execution/          # ✅ Planos específicos AWS
│   │   └── quickstart/             # ✅ Guias rápidos
│   ├── logs/                       # ✅ Logs de progresso
│   │   └── log-de-progresso.md     # ✅ ÚNICO log central
│   ├── hooks/                      # ✅ Hooks de validação
│   ├── agents/                     # ✅ Definições de agentes
│   ├── skills/                     # ✅ Skills para IA
│   ├── prompts/                    # ✅ Prompts especializados
│   ├── mcp/                        # ✅ MCP tools
│   └── governance/                 # ✅ Governança (ESTE ARQUIVO)
│
├── platform-provisioning/          # ✅ Provisioning cloud-specific
│   ├── aws/                        # ✅ Terraform AWS
│   ├── azure/                      # ✅ Terraform Azure
│   └── gcp/                        # ⏳ Terraform GCP (futuro)
│
├── domains/                        # ✅ Domínios da plataforma
│   └── {domain-name}/
│       ├── README.md               # ✅ ÚNICO README por domínio
│       ├── docs/
│       │   ├── adr/                # ✅ ADRs locais numerados
│       │   ├── VALIDATION-REPORT.md # ✅ ÚNICO validation report
│       │   ├── instrumentation/    # ✅ Guias de instrumentação
│       │   └── runbooks/           # ✅ Runbooks operacionais
│       ├── infra/
│       │   ├── terraform/          # ✅ IaC cloud-agnostic
│       │   ├── helm/               # ✅ Helm charts
│       │   └── validation/         # ✅ Scripts de validação
│       └── local-dev/              # ✅ Docker Compose local
│
└── ai-contexts/                    # ✅ Contextos para IA
    └── copilot-context.md          # ✅ ÚNICO contexto Copilot
```

---

## 🚫 PROIBIÇÕES ABSOLUTAS

### 1. ❌ NUNCA CRIAR ESTES ARQUIVOS/DIRETÓRIOS

```yaml
PROIBIDO:
  # Reports duplicados ou temporários
  - "**/REPORT-*.md"
  - "**/report-*.md"
  - "**/temp-*.md"
  - "**/draft-*.md"
  - "**/analysis-*.md"
  - "**/summary-*.md"
  - "**/notes-*.md"

  # READMEs duplicados
  - "docs/README.md"              # Só existe na raiz
  - "SAD/README.md"               # Só existe sad.md
  - "**/README-*.md"

  # Logs duplicados
  - "docs/logs/changelog.md"      # Só log-de-progresso.md
  - "docs/logs/history.md"
  - "**/activity-log.md"

  # Contextos duplicados
  - "ai-contexts/claude-context.md"
  - "ai-contexts/chatgpt-context.md"
  - ".claude/context.md"

  # Diretórios temporários
  - "tmp/"
  - "temp/"
  - "scratch/"
  - "drafts/"
  - "backup/"

  # Validations duplicadas
  - "**/validation-*.md"           # Só VALIDATION-REPORT.md
  - "**/check-*.md"
  - "**/audit-*.md"

  # Plans duplicados
  - "**/plan-*.md"                 # Só execution-plan.md
  - "**/roadmap-*.md"
```

### 2. ❌ NUNCA DUPLICAR DOCUMENTOS EXISTENTES

Se o documento JÁ EXISTE, **ATUALIZE-O**. Não crie:
- `README-v2.md` → Atualize `README.md`
- `execution-plan-new.md` → Atualize `execution-plan.md`
- `sad-updated.md` → Atualize `sad.md` (se descongelado)
- `log-de-progresso-2026.md` → Adicione entrada em `log-de-progresso.md`

### 3. ❌ NUNCA CRIAR DIRETÓRIOS FORA DO PADRÃO

Diretórios APROVADOS são os listados na estrutura oficial. Qualquer outro REQUER aprovação explícita.

**Exemplo de PROIBIDO**:
```
❌ domains/observability/reports/
❌ docs/analysis/
❌ SAD/proposals/
❌ platform-provisioning/templates/
❌ docs/meetings/
```

---

## ✅ REGRAS DE CRIAÇÃO DE DOCUMENTOS

### Quando PODE criar documentos

#### A. ADRs (Architecture Decision Records)

**Localização permitida**:
- `/SAD/docs/adrs/` → ADRs sistêmicos (afetam múltiplos domínios)
- `/docs/adr/` → ADRs de governança
- `/domains/{domain}/docs/adr/` → ADRs locais do domínio

**Nomenclatura obrigatória**:
```
adr-XXX-{titulo-kebab-case}.md

Onde:
- XXX = número sequencial de 3 dígitos (001, 002, 003...)
- titulo-kebab-case = título descritivo em kebab-case

Exemplos CORRETOS:
✅ adr-001-estrutura-inicial.md
✅ adr-022-escolha-banco-dados.md

Exemplos ERRADOS:
❌ ADR-Banco-de-Dados.md
❌ adr-banco.md
❌ decision-001.md
```

**Processo obrigatório**:
1. Verificar último número de ADR no diretório
2. Incrementar +1
3. Criar com template padrão
4. Registrar no índice (se houver)
5. Atualizar SAD se sistêmico

#### B. Validation Reports

**Localização permitida**:
- `/domains/{domain}/docs/VALIDATION-REPORT.md` → ✅ ÚNICO por domínio

**Regras**:
- ❌ NUNCA criar `VALIDATION-REPORT-v2.md`
- ❌ NUNCA criar `validation-2026-01-22.md`
- ✅ SEMPRE atualizar o existente adicionando nova seção

**Template de nova validação**:
```markdown
## Validação #{numero} — YYYY-MM-DD

### Contexto
{por que validar agora}

### Resultado
{resultado da validação}

### Ações Tomadas
{o que foi feito}

---
```

#### C. Documentação de Domínio

**Documentos ÚNICOS permitidos por domínio**:
```
domains/{domain}/
├── README.md                    # ✅ ÚNICO - Visão geral do domínio
├── docs/
│   └── VALIDATION-REPORT.md     # ✅ ÚNICO - Histórico de validações
```

**Documentos MÚLTIPLOS permitidos**:
```
domains/{domain}/docs/
├── adr/                         # ✅ Múltiplos ADRs numerados
│   ├── adr-001-*.md
│   ├── adr-002-*.md
│   └── ...
├── instrumentation/             # ✅ Guias de instrumentação
│   ├── python.md
│   ├── nodejs.md
│   └── ...
└── runbooks/                    # ✅ Runbooks operacionais
    ├── troubleshooting.md
    ├── deployment.md
    └── ...
```

#### D. Planos de Execução

**Localização ÚNICA**:
- `/docs/plan/execution-plan.md` → ✅ ÚNICO plano central

**Planos específicos permitidos** (em subpastas):
```
docs/plan/
├── execution-plan.md            # ✅ Plano central
├── aws-execution/               # ✅ Planos específicos AWS
│   ├── 01-*.md
│   ├── 02-*.md
│   └── ...
└── quickstart/                  # ✅ Guias rápidos
    └── README.md
```

---

## 🔍 CHECKLIST ANTES DE CRIAR QUALQUER DOCUMENTO

### Perguntas Obrigatórias

Antes de criar QUALQUER arquivo `.md`, responda:

1. **Este documento JÁ EXISTE?**
   - ✅ SIM → **PARE!** Atualize o existente
   - ❌ NÃO → Continue

2. **Este documento está na lista PROIBIDA?**
   - ✅ SIM → **PARE!** Não crie
   - ❌ NÃO → Continue

3. **A localização está na estrutura APROVADA?**
   - ✅ SIM → Continue
   - ❌ NÃO → **PARE!** Peça aprovação ao usuário

4. **Há um documento similar que pode ser atualizado?**
   - ✅ SIM → **PARE!** Atualize o existente
   - ❌ NÃO → Continue

5. **A nomenclatura segue o padrão?**
   - ✅ SIM → Continue
   - ❌ NÃO → **PARE!** Corrija antes

6. **O usuário aprovou explicitamente?**
   - ✅ SIM → OK, pode criar
   - ❌ NÃO → **PARE!** Peça aprovação

---

## 📋 WORKFLOW DE CRIAÇÃO DE DOCUMENTO

### Fluxo Obrigatório

```yaml
1. IDENTIFICAR_NECESSIDADE:
   - Por que preciso criar este documento?
   - Qual informação ele contém?

2. VERIFICAR_EXISTENTE:
   - Existe documento similar?
   - Posso atualizar ao invés de criar?

3. VALIDAR_LOCALIZAÇÃO:
   - O diretório está aprovado?
   - A nomenclatura está correta?

4. SOLICITAR_APROVAÇÃO:
   prompt: |
     Identifico a necessidade de criar:
     - Arquivo: {caminho/completo/arquivo.md}
     - Motivo: {justificativa clara}
     - Conteúdo: {resumo do que terá}

     Posso prosseguir?

5. AGUARDAR_CONFIRMAÇÃO:
   - ✅ APROVADO → Criar
   - ❌ REJEITADO → Buscar alternativa

6. CRIAR_DOCUMENTO:
   - Seguir template apropriado
   - Preencher metadados
   - Adicionar ao índice se necessário

7. REGISTRAR_CRIAÇÃO:
   - Adicionar entrada em log-de-progresso.md
   - Atualizar contextos se relevante
```

---

## 🛡️ VALIDAÇÕES AUTOMÁTICAS

### Hook de Pre-Commit

Verificações que DEVEM ser implementadas:

```bash
#!/bin/bash
# .git/hooks/pre-commit-doc-validation

# 1. Verificar documentos duplicados
DUPLICATES=(
    "README-*.md"
    "*-report-*.md"
    "validation-*.md"
    "plan-*.md"
)

# 2. Verificar diretórios proibidos
FORBIDDEN_DIRS=(
    "tmp/"
    "temp/"
    "drafts/"
    "backup/"
)

# 3. Verificar nomenclatura de ADRs
find . -name "adr-*.md" | grep -v "adr-[0-9]\{3\}-"

# 4. Verificar READMEs fora de lugar
find . -name "README.md" | grep -v -E "(^./README.md$|domains/.*/README.md$|platform-provisioning/.*/README.md$)"

# Se alguma regra falhar, bloquear commit
```

---

## 📊 DOCUMENTOS PERMITIDOS - RESUMO

### Documentos ÚNICOS (1 por escopo)

| Documento | Localização | Escopo |
|-----------|-------------|--------|
| **README.md** | `/` | ✅ Raiz do projeto |
| **README.md** | `/domains/{domain}/` | ✅ 1 por domínio |
| **README.md** | `/platform-provisioning/{cloud}/` | ✅ 1 por cloud |
| **PROJECT-CONTEXT.md** | `/` | ✅ Global |
| **sad.md** | `/SAD/docs/` | ✅ Global |
| **sad-freeze-record.md** | `/SAD/docs/` | ✅ Global |
| **execution-plan.md** | `/docs/plan/` | ✅ Global |
| **log-de-progresso.md** | `/docs/logs/` | ✅ Global |
| **copilot-context.md** | `/ai-contexts/` | ✅ Global |
| **VALIDATION-REPORT.md** | `/domains/{domain}/docs/` | ✅ 1 por domínio |

### Documentos MÚLTIPLOS (seguindo padrões)

| Tipo | Padrão | Localização | Regra |
|------|--------|-------------|-------|
| **ADRs Sistêmicos** | `adr-XXX-*.md` | `/SAD/docs/adrs/` | Numeração sequencial |
| **ADRs de Governança** | `adr-XXX-*.md` | `/docs/adr/` | Numeração sequencial |
| **ADRs de Domínio** | `adr-XXX-*.md` | `/domains/{domain}/docs/adr/` | Numeração sequencial |
| **Agentes** | `{nome-agente}.md` | `/docs/agents/` | Nome descritivo |
| **Skills** | `{nome-skill}.md` | `/docs/skills/` | Nome descritivo |
| **Prompts** | `{nome-prompt}.md` | `/docs/prompts/` | Nome descritivo |
| **Runbooks** | `{nome-runbook}.md` | `/domains/{domain}/docs/runbooks/` | Nome descritivo |
| **Guias Instrumentação** | `{linguagem}.md` | `/domains/{domain}/docs/instrumentation/` | Por linguagem |

---

## 🚨 PENALIDADES POR VIOLAÇÃO

### Violações que invalidam o trabalho

Se a IA criar qualquer dos seguintes sem aprovação:

1. ❌ Documento duplicado → **REVERTER IMEDIATAMENTE**
2. ❌ Documento em localização proibida → **REVERTER IMEDIATAMENTE**
3. ❌ Diretório não aprovado → **REVERTER IMEDIATAMENTE**
4. ❌ Nome fora do padrão → **REVERTER IMEDIATAMENTE**

### Processo de reversão

```bash
# 1. Identificar arquivo violador
git status

# 2. Remover do staging
git reset HEAD {arquivo-violador}

# 3. Deletar arquivo
rm {arquivo-violador}

# 4. Documentar no log-de-progresso.md
# Adicionar entrada explicando a violação e reversão
```

---

## ✅ EXCEÇÕES PERMITIDAS

### Casos onde novas estruturas podem ser criadas

1. **Novo Domínio** (após aprovação explícita)
   - Seguir template de domínio existente
   - Criar estrutura padrão completa

2. **Nova Cloud em platform-provisioning** (após aprovação)
   - Seguir template de cloud existente (aws/azure)

3. **Novo tipo de documentação** (após aprovação)
   - Justificar necessidade
   - Propor localização
   - Definir nomenclatura
   - Atualizar ESTE documento (STRICT-RULES.md)

---

## 📝 TEMPLATES OBRIGATÓRIOS

### Template: ADR

```markdown
# ADR-XXX: {Título da Decisão}

> **Status**: Proposto | Aceito | Rejeitado | Deprecated | Substituído
> **Data**: YYYY-MM-DD
> **Decisores**: {Lista de pessoas/papéis}
> **Contexto SAD**: {se aplicável, mencionar conformidade com SAD}

## Contexto

{Descrição do problema que levou a esta decisão}

## Decisão

{Descrição da decisão tomada}

## Consequências

### Positivas
- {Benefício 1}
- {Benefício 2}

### Negativas
- {Trade-off 1}
- {Trade-off 2}

## Alternativas Consideradas

1. **{Alternativa 1}**
   - Prós: ...
   - Contras: ...
   - Por que rejeitada: ...

## Referências

- {Link/documento relevante 1}
- {Link/documento relevante 2}
```

### Template: Validation Report (Nova Entrada)

```markdown
## Validação #{numero} — YYYY-MM-DD

### Contexto

{Por que esta validação foi necessária agora}

### Escopo

- Versão SAD validada: v{X.Y}
- ADRs verificados: {lista}
- Componentes afetados: {lista}

### Resultado

- ✅ Conformidade: {lista de itens conformes}
- ⚠️ Gaps: {lista de gaps encontrados}
- ❌ Violações: {lista de violações}

### Ações Tomadas

1. {Ação 1}
2. {Ação 2}

### Status Final

{APROVADO | APROVADO COM RESSALVAS | REPROVADO}

---
```

---

## 🔄 MANUTENÇÃO DESTE DOCUMENTO

### Quando atualizar STRICT-RULES.md

1. Nova estrutura aprovada
2. Novo padrão de nomenclatura definido
3. Nova exceção identificada
4. Regra se mostrou impraticável (com justificativa)

### Processo de atualização

1. Propor mudança com justificativa
2. Obter aprovação do usuário
3. Atualizar documento
4. Incrementar versão
5. Registrar em log-de-progresso.md
6. Comunicar aos contextos de IA

---

## 📚 REFERÊNCIAS

- [Post-Activity Hook](../hooks/post-activity-validation.md)
- [SAD](../../SAD/docs/sad.md)
- [Execution Plan](../plan/execution-plan.md)
- [Log de Progresso](../logs/log-de-progresso.md)

---

**Última Atualização**: 2026-01-22
**Versão**: 1.0
**Status**: ✅ ATIVO - CUMPRIMENTO OBRIGATÓRIO

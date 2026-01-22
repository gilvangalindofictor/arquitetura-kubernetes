# Guia de Treinamento - Governança Documental

> **Data**: 2026-01-22
> **Versão**: 1.0
> **Público-Alvo**: Equipe de desenvolvimento, DevOps, Arquitetos, IAs
> **Duração Estimada**: 45 minutos
> **Status**: ✅ ATIVO

---

## 🎯 Objetivos do Treinamento

Ao final deste treinamento, você será capaz de:

1. ✅ Compreender a importância da governança documental
2. ✅ Aplicar o checklist de 6 perguntas antes de criar documentos
3. ✅ Identificar violações das regras de governança
4. ✅ Utilizar corretamente os templates padronizados
5. ✅ Entender o workflow de aprovação

---

## 📚 Módulo 1: Por Que Governança Documental?

### 1.1 Problemas Sem Governança

**Cenário Real - Antes da Governança:**

```
/projeto
├── README.md
├── README-v2.md              ❌ Duplicação
├── README-new.md             ❌ Duplicação
├── report-2026-01-15.md      ❌ Report temporário
├── report-2026-01-20.md      ❌ Report temporário
├── analysis-final.md         ❌ Report temporário
├── tmp/
│   └── draft-plan.md         ❌ Diretório proibido
├── validation-test.md        ❌ Nomenclatura incorreta
└── validation-prod.md        ❌ Nomenclatura incorreta
```

**Problemas Identificados:**
- 🔴 **Proliferação descontrolada**: 8 documentos desnecessários
- 🔴 **Confusão**: Qual README é o oficial?
- 🔴 **Inconsistência**: Validations com nomes diferentes
- 🔴 **Desperdício**: Tempo procurando a versão correta

### 1.2 Benefícios da Governança

**Cenário Ideal - Com Governança:**

```
/projeto
├── README.md                              ✅ Único na raiz
├── docs/
│   ├── governance/
│   │   ├── STRICT-RULES.md               ✅ Regras centrais
│   │   └── EXECUTIVE-SUMMARY.md          ✅ Sumário executivo
│   ├── logs/
│   │   └── log-de-progresso.md           ✅ Único log global
│   └── plan/
│       └── execution-plan.md             ✅ Único plano
└── domains/
    └── platform-core/
        └── docs/
            └── VALIDATION-REPORT.md      ✅ 1 por domínio
```

**Benefícios:**
- ✅ **Clareza**: Um único documento para cada propósito
- ✅ **Rastreabilidade**: Histórico completo em log único
- ✅ **Eficiência**: Encontrar informações rapidamente
- ✅ **Qualidade**: Templates padronizados garantem consistência

---

## 📋 Módulo 2: Checklist Obrigatório (6 Perguntas)

### Passo a Passo Prático

Antes de criar **QUALQUER** arquivo `.md`, execute este checklist:

#### ❓ Pergunta 1: Este documento JÁ EXISTE?

**Como verificar:**
```bash
# Buscar por nome de arquivo
find . -name "execution-plan.md" -not -path "./.git/*"

# Buscar por conteúdo similar
grep -r "Plano de Execução" . --include="*.md"
```

**Decisão:**
- ✅ **SIM** (documento existe) → **PARE! ATUALIZE O EXISTENTE**
- ❌ **NÃO** (não existe) → Continue para Pergunta 2

**Exemplo Prático:**

```bash
# Situação: Você quer criar "execution-plan-v2.md"
$ find . -name "execution-plan*.md"
./docs/plan/execution-plan.md    # ❌ JÁ EXISTE!

# AÇÃO CORRETA: Atualizar docs/plan/execution-plan.md
# AÇÃO ERRADA: Criar execution-plan-v2.md
```

---

#### ❓ Pergunta 2: Está na Lista PROIBIDA?

**Lista de Proibições Absolutas:**

| Padrão Proibido | Motivo | Alternativa Correta |
|-----------------|--------|---------------------|
| `README-v2.md` | Duplicação | Atualizar `README.md` |
| `report-*.md` | Temporário | Usar `VALIDATION-REPORT.md` |
| `REPORT-*.md` | Temporário | Usar `VALIDATION-REPORT.md` |
| `analysis-*.md` | Temporário | Adicionar ao log ou VALIDATION-REPORT |
| `validation-*.md` | Nomenclatura | Usar `VALIDATION-REPORT.md` |
| `changelog.md` | Duplicação | Usar `log-de-progresso.md` |
| `tmp/` (diretório) | Temporário | Não criar |
| `drafts/` (diretório) | Temporário | Não criar |

**Decisão:**
- ✅ **SIM** (está proibido) → **PARE! NÃO CRIE**
- ❌ **NÃO** (não está proibido) → Continue para Pergunta 3

**Exemplo Prático:**

```bash
# Situação: Você quer criar "report-platform-2026-01.md"
# Verificar: "report-*.md" está na lista proibida?
# Resposta: SIM ❌

# AÇÃO CORRETA: Atualizar domains/{domain}/docs/VALIDATION-REPORT.md
# AÇÃO ERRADA: Criar report-platform-2026-01.md
```

---

#### ❓ Pergunta 3: Localização Está APROVADA?

**Estrutura de Diretórios Oficial:**

```
/
├── SAD/docs/                    ✅ Documentos do SAD
├── domains/{domain}/docs/       ✅ Documentos por domínio
├── docs/
│   ├── governance/              ✅ Governança
│   ├── logs/                    ✅ Logs centralizados
│   ├── plan/                    ✅ Planejamento
│   └── hooks/                   ✅ Hooks e automações
├── ai-contexts/                 ✅ Contextos de IA
└── platform-provisioning/       ✅ IaC e provisionamento
```

**Localizações PROIBIDAS:**
- ❌ Raiz do projeto (exceto `README.md`)
- ❌ `tmp/`, `temp/`, `drafts/`, `backup/`
- ❌ Dentro de `.git/` (exceto hooks)

**Decisão:**
- ✅ **SIM** (localização aprovada) → Continue para Pergunta 4
- ❌ **NÃO** (não aprovada) → **PARE! PEÇA APROVAÇÃO**

**Exemplo Prático:**

```bash
# Situação: Você quer criar "docs/temp/notes.md"
# Verificar: "docs/temp/" está aprovado?
# Resposta: NÃO ❌ (temp/ é proibido)

# AÇÃO CORRETA: Pedir aprovação ao arquiteto ou usar docs/logs/
# AÇÃO ERRADA: Criar em docs/temp/
```

---

#### ❓ Pergunta 4: Há Documento SIMILAR?

**Como verificar similaridade:**

```bash
# Buscar por título similar
grep -r "Validação de Domínio" . --include="*.md"

# Buscar por tipo de documento
find . -name "*validation*.md" -not -path "./.git/*"

# Listar todos os ADRs
find . -path "*/adr/*.md"
```

**Decisão:**
- ✅ **SIM** (há similar) → **PARE! ATUALIZE O SIMILAR**
- ❌ **NÃO** (não há similar) → Continue para Pergunta 5

**Exemplo Prático:**

```bash
# Situação: Você quer criar "platform-core-validation.md"
$ find . -name "*validation*.md"
./domains/platform-core/docs/VALIDATION-REPORT.md    # ❌ JÁ EXISTE SIMILAR!

# AÇÃO CORRETA: Atualizar VALIDATION-REPORT.md existente
# AÇÃO ERRADA: Criar platform-core-validation.md
```

---

#### ❓ Pergunta 5: Nomenclatura Está CORRETA?

**Regras de Nomenclatura por Tipo:**

| Tipo de Documento | Padrão Correto | Exemplo |
|-------------------|----------------|---------|
| **README** | `README.md` | `README.md` (1 por escopo) |
| **ADR** | `adr-XXX-titulo.md` | `adr-022-banco-dados.md` |
| **Validation Report** | `VALIDATION-REPORT.md` | `VALIDATION-REPORT.md` |
| **Log** | `log-de-progresso.md` | `log-de-progresso.md` (único) |
| **Plano** | `execution-plan.md` | `execution-plan.md` (único) |
| **Agente** | `{nome}.md` | `gestor.md`, `arquiteto.md` |
| **Skill** | `{nome}.md` | `terraform.md`, `kubernetes.md` |

**Decisão:**
- ✅ **SIM** (nomenclatura correta) → Continue para Pergunta 6
- ❌ **NÃO** (incorreta) → **PARE! CORRIJA**

**Exemplo Prático:**

```bash
# Situação: Você quer criar "adr-22-database.md"
# Verificar: Segue padrão "adr-XXX-titulo.md"?
# Resposta: NÃO ❌ (falta zero à esquerda)

# AÇÃO CORRETA: Renomear para "adr-022-database.md"
# AÇÃO ERRADA: Criar com "adr-22-database.md"
```

---

#### ❓ Pergunta 6: Usuário APROVOU Explicitamente?

**Workflow de Aprovação:**

1. **Identificou necessidade** de novo documento
2. **Passou pelas 5 perguntas anteriores**
3. **Apresente ao usuário/arquiteto:**
   - Justificativa clara
   - Localização proposta
   - Nome proposto
   - Conteúdo planejado

4. **Aguarde aprovação EXPLÍCITA**

**Decisão:**
- ✅ **SIM** (aprovado) → **OK, PODE CRIAR**
- ❌ **NÃO** (não aprovado) → **PARE! PEÇA APROVAÇÃO**

**Exemplo de Solicitação de Aprovação:**

```markdown
**Solicitação de Criação de Documento**

**Justificativa**: Decisão arquitetural sobre escolha do Vault precisa ser documentada

**Localização proposta**: /domains/secrets-management/docs/adr/adr-002-vault-architecture.md

**Nome proposto**: adr-002-vault-architecture.md

**Conteúdo planejado**:
- Contexto da decisão
- Opções avaliadas (Vault vs ESO)
- Decisão tomada e justificativa
- Consequências

**Aprovação necessária**: Sim/Não?
```

---

## 🚫 Módulo 3: Identificando Violações

### 3.1 Exercício Prático 1: Encontre as Violações

**Cenário:**

```
Desenvolvedor criou os seguintes arquivos:
1. /tmp/draft-plan.md
2. /docs/reports/report-2026-01-22.md
3. /domains/security/docs/validation-kyverno.md
4. /SAD/docs/adr/adr-5-networking.md
5. /docs/plan/execution-plan-new.md
```

**Questão**: Quantas e quais são as violações?

<details>
<summary>✅ Resposta (clique para revelar)</summary>

**5 violações identificadas:**

1. `/tmp/draft-plan.md`
   - ❌ Diretório `tmp/` é proibido
   - ✅ Solução: Usar `docs/plan/` ou não criar

2. `/docs/reports/report-2026-01-22.md`
   - ❌ Padrão `report-*.md` é proibido
   - ✅ Solução: Usar `VALIDATION-REPORT.md` ou adicionar ao log

3. `/domains/security/docs/validation-kyverno.md`
   - ❌ Nomenclatura incorreta (deve ser `VALIDATION-REPORT.md`)
   - ✅ Solução: Renomear para `VALIDATION-REPORT.md`

4. `/SAD/docs/adr/adr-5-networking.md`
   - ❌ Nomenclatura incorreta (falta zeros: deve ser `adr-005-...`)
   - ✅ Solução: Renomear para `adr-005-networking.md`

5. `/docs/plan/execution-plan-new.md`
   - ❌ Documento único duplicado (execution-plan.md já existe)
   - ✅ Solução: Atualizar `execution-plan.md` existente
</details>

### 3.2 Exercício Prático 2: Decisão Correta

**Cenário**: Você precisa documentar uma análise de performance do domínio observability.

**Pergunta**: Qual a ação correta?

**Opções:**
- A) Criar `/tmp/performance-analysis.md`
- B) Criar `/docs/reports/observability-performance-2026-01.md`
- C) Atualizar `/domains/observability/docs/VALIDATION-REPORT.md`
- D) Criar `/domains/observability/docs/performance-report.md`

<details>
<summary>✅ Resposta (clique para revelar)</summary>

**Resposta Correta: C) Atualizar `/domains/observability/docs/VALIDATION-REPORT.md`**

**Justificativa:**
- ✅ VALIDATION-REPORT.md é o documento padrão para análises de domínio
- ✅ Evita criação de reports temporários
- ✅ Mantém histórico consolidado
- ✅ Segue padrão de nomenclatura

**Por que as outras estão erradas:**
- A) ❌ Diretório `tmp/` é proibido
- B) ❌ Padrão `*-2026-01.md` (report temporário) é proibido
- D) ❌ Nomenclatura incorreta (deve ser `VALIDATION-REPORT.md`)
</details>

---

## 📝 Módulo 4: Templates Padronizados

### 4.1 Template: ADR (Architecture Decision Record)

**Localização**: `/domains/{domain}/docs/adr/adr-XXX-titulo.md`

**Estrutura Obrigatória:**

```markdown
# ADR-XXX: Título da Decisão

**Status**: Proposto | Aprovado | Substituído | Rejeitado
**Data**: YYYY-MM-DD
**Decisores**: Nome1, Nome2
**Consultor**: Nome (se aplicável)

---

## Contexto

[Descreva o contexto e o problema que motivou a decisão]

## Decisão

[Descreva a decisão tomada de forma clara e concisa]

## Opções Consideradas

### Opção 1: [Nome]
- ✅ Prós: ...
- ❌ Contras: ...

### Opção 2: [Nome]
- ✅ Prós: ...
- ❌ Contras: ...

## Consequências

### Positivas
- ...

### Negativas
- ...

### Neutras
- ...

## Conformidade com SAD

- [x] Conforme ADR-XXX
- [x] Conforme ADR-YYY

## Links

- [SAD](../../../SAD/docs/sad.md)
- [ADR relacionado](./adr-YYY-titulo.md)
```

### 4.2 Template: VALIDATION-REPORT

**Localização**: `/domains/{domain}/docs/VALIDATION-REPORT.md`

**Estrutura Obrigatória:**

```markdown
# Validation Report - {Domain Name}

> **Data**: YYYY-MM-DD
> **Versão**: X.Y
> **Status**: ✅ APROVADO | ⚠️ COM GAPS | ❌ REPROVADO

---

## 📊 Resumo Executivo

| Métrica | Valor |
|---------|-------|
| Conformidade Geral | XX% |
| Gaps Bloqueantes | X |
| Gaps Não-Bloqueantes | X |
| ADRs Validados | X/Y |

## ✅ Validações Aprovadas

### ADR-XXX: [Título]
- ✅ Validação 1
- ✅ Validação 2

## ⚠️ Gaps Identificados

### Gap 1: [Descrição]
- **Severidade**: Bloqueante | Não-Bloqueante
- **ADR Relacionado**: ADR-XXX
- **Plano de Remediação**: ...
- **Prazo**: Sprint+X

## 📈 Métricas Detalhadas

[Tabelas e gráficos de conformidade]

## 🔗 Próximos Passos

- [ ] Ação 1
- [ ] Ação 2
```

---

## 🛠️ Módulo 5: Ferramentas e Automações

### 5.1 Pre-Commit Hook

O projeto possui um hook Git que valida automaticamente antes do commit:

**Localização**: `.git/hooks/pre-commit`

**O que valida:**
1. ✅ Arquivos proibidos
2. ✅ Diretórios proibidos
3. ✅ Documentos únicos duplicados
4. ✅ Nomenclatura de ADRs
5. ✅ Nomenclatura de VALIDATION-REPORTs
6. ✅ Estrutura de diretórios

**Como funciona:**

```bash
# Ao tentar commitar arquivo violado:
$ git add tmp/draft.md
$ git commit -m "Adicionar rascunho"

🔍 Executando validação de governança documental...
❌ VIOLAÇÃO: Arquivo em diretório proibido: tmp/draft.md
   Diretório: tmp/
   Consulte: docs/governance/STRICT-RULES.md

╔═══════════════════════════════════════════════════════════╗
║  ❌ COMMIT BLOQUEADO - 1 VIOLAÇÃO(ÕES) DETECTADA(S)      ║
╚═══════════════════════════════════════════════════════════╝
```

### 5.2 Comandos Úteis

**Verificar conformidade manualmente:**

```bash
# Listar todos os .md no projeto
find . -name "*.md" -not -path "./.git/*" | sort

# Encontrar possíveis duplicações de README
find . -name "README*.md"

# Listar ADRs e verificar nomenclatura
find . -path "*/adr/*.md" | grep -v "adr-[0-9]\{3\}-"

# Buscar reports temporários
find . -name "report-*.md" -o -name "REPORT-*.md"

# Verificar estrutura de domínios
ls -la domains/*/docs/VALIDATION-REPORT.md
```

---

## 📊 Módulo 6: Quiz de Certificação

### Teste Seu Conhecimento

**Questão 1**: Você precisa criar uma decisão arquitetural para o domínio `cicd-platform` sobre escolha entre Jenkins e GitLab. Qual o caminho correto do arquivo?

<details>
<summary>✅ Resposta</summary>

`/domains/cicd-platform/docs/adr/adr-002-escolha-ci-cd.md`

**Justificativa:**
- Localização: `/domains/cicd-platform/docs/adr/`
- Nomenclatura: `adr-002-` (próximo número sequencial)
- Título descritivo: `escolha-ci-cd`
</details>

---

**Questão 2**: Ao tentar commitar `report-final-2026.md`, o hook bloqueou. Por quê?

<details>
<summary>✅ Resposta</summary>

Padrão `report-*.md` está na lista de proibições absolutas.

**Motivo**: Reports temporários são proibidos para evitar proliferação.

**Solução Correta**: Atualizar `VALIDATION-REPORT.md` do domínio relevante ou adicionar ao `log-de-progresso.md`.
</details>

---

**Questão 3**: Quantos arquivos `README.md` podem existir no projeto?

<details>
<summary>✅ Resposta</summary>

**N + 1**, onde N = número de domínios

**Explicação:**
- 1 `README.md` na raiz (único global)
- 1 `README.md` por domínio em `/domains/{domain}/README.md`

**Exemplo com 6 domínios**: 7 READMEs no total (1 raiz + 6 domínios)
</details>

---

**Questão 4**: Você encontrou um arquivo `validation-test.md`. O que fazer?

<details>
<summary>✅ Resposta</summary>

**Ações:**

1. ✅ Verificar se é duplicação de `VALIDATION-REPORT.md`
2. ✅ Se for duplicação:
   - Consolidar conteúdo em `VALIDATION-REPORT.md`
   - Deletar `validation-test.md`
3. ✅ Se for novo conteúdo:
   - Renomear para `VALIDATION-REPORT.md`
   - Mover para localização correta: `/domains/{domain}/docs/`

**Justificativa**: Nomenclatura `validation-*.md` é proibida, apenas `VALIDATION-REPORT.md` é permitido.
</details>

---

## 🎓 Certificação de Conclusão

### Critérios de Aprovação

Para ser certificado neste treinamento, você deve:

- [ ] Assistir/ler todos os 6 módulos
- [ ] Acertar pelo menos 3/4 questões do quiz
- [ ] Completar os 2 exercícios práticos
- [ ] Compreender e aplicar o checklist de 6 perguntas

### Próximos Passos

Após conclusão do treinamento:

1. ✅ Aplicar o checklist em todas as criações de documentos
2. ✅ Consultar [STRICT-RULES.md](STRICT-RULES.md) em caso de dúvida
3. ✅ Usar os templates padronizados
4. ✅ Reportar sugestões de melhoria ao arquiteto

---

## 📚 Referências

- [STRICT-RULES.md](STRICT-RULES.md) - Regras completas (400+ linhas)
- [EXECUTIVE-SUMMARY.md](EXECUTIVE-SUMMARY.md) - Sumário executivo da governança
- [Copilot Context](../../ai-contexts/copilot-context.md) - Seção 12
- [Post-Activity Hook](../hooks/post-activity-validation.md) - Validação automática
- [Log de Progresso](../logs/log-de-progresso.md) - Histórico de implementação

---

## 🔄 Histórico de Versões

| Versão | Data | Mudanças |
|--------|------|----------|
| 1.0 | 2026-01-22 | Criação inicial do guia de treinamento |

---

**Última Atualização**: 2026-01-22
**Autor**: System Architect
**Aprovação**: Equipe de Governança
**Status**: ✅ ATIVO

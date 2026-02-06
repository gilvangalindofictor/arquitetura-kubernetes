# README - Learning System

## Estrutura

```
docs/learning/
├── lessons/                      # Lições aprendidas
│   ├── _index.json               # Estruturado para AI consumir
│   └── lessons.md                # Legível para usuário revisar
│
├── agents/                       # Perfis evolutivos dos agentes
│   └── {agente}.md               # Um arquivo por agente (criado quando necessário)
│
├── feedback/                     # Feedback do usuário
│   └── entries.jsonl             # JSON Lines com ratings e comentários
│
└── knowledge_router.json         # Mapeamento de fontes de documentação
```

## Como Funciona

### 1. Extração de Lições

Após CADA task, o sistema analisa se houve:
- Retry necessário
- Diff desproporcional
- Refatoração imediata
- Erro recorrente
- Feedback do usuário

Se detectado, uma lição é extraída e armazenada em `lessons/_index.json` e `lessons/lessons.md`.

### 2. Perfis Evolutivos de Agentes

Quando uma lição impacta um agente específico, o perfil do agente é atualizado em `agents/{agente}.md`.

**Estrutura do perfil**:
```markdown
# Perfil: {agente}

## Traits Ativos
- 🔴 ENFORCE: {descrição} (sempre aplicado)
- 🟡 WARN: {descrição} (aplicado quando relevante)

## Pinned (editado manualmente — NÃO sobrescrever)
- {conteúdo do usuário}

## Lições
1. {lição aplicável a este agente}

## Métricas
| Tasks | Retries | Refatorações | Qualidade |
| ----- | ------- | ------------ | --------- |
| N     | N       | N            | N/5       |
```

### 3. Feedback do Usuário

O usuário pode dar feedback sobre tasks concluídas:
- 👍 Bom: Reforça comportamento positivo
- 👎 Ruim: Cria lição CRITICAL imediatamente

Feedback é coletado ao final de sprints ou quando solicitado explicitamente.

### 4. Knowledge Router

Mapeia dependências do projeto para as melhores fontes de documentação:

```json
{
  "resolved": {
    "terraform@1.6.6": {
      "source": "context7",
      "note": "Versão estável, docs oficiais ok"
    },
    "helm@3.13.3-beta": {
      "source": "github_clone",
      "note": "Beta version, clone repo para código real"
    }
  }
}
```

## Decay de Lições

Lições perdem peso se não forem aplicadas:
- Após 5 execuções sem usar: peso 0.8
- Após 10 execuções sem usar: peso 0.5
- Após 20 execuções sem usar: peso 0.2 (arquivada)

**Exceções (peso permanente)**:
- Severity "critical"
- Seção "Pinned" do agente
- Originada de feedback negativo

## Uso pelo Agente AI

Antes de executar uma task como agente X:

1. Ler `lessons/_index.json` ou `lessons/lessons.md`
2. Ler `agents/{agente}.md` (perfil evolutivo)
3. Injetar no prompt:
   - Todas CRITICAL e ENFORCE
   - WARN se cabe no budget
   - INFO se sobra espaço

4. Durante execução, aplicar as lições relevantes
5. Após execução, incrementar `applied_count` das lições usadas

## Edição Manual

**Usuário pode editar**:
- ✅ Seção `## Pinned` em `agents/{agente}.md`
- ✅ Adicionar lições manualmente em `lessons/_index.json`
- ✅ Ajustar severity de lições existentes

**Usuário NÃO deve editar**:
- ❌ Métricas dos agentes (auto-calculadas)
- ❌ Estrutura JSON de `_index.json` (pode quebrar parsing)

**Ao editar Pinned**:
```markdown
## Pinned (editado manualmente — NÃO sobrescrever)

### Terraform Sempre Com Plan

Antes de qualquer `terraform apply`, SEMPRE rodar `terraform plan` e apresentar ao usuário.
NUNCA aplicar sem aprovação explícita.

**Motivo**: Evitar aplicação acidental de mudanças destrutivas
**Relevância**: Todas tasks de infrastructure
```

## Comandos Úteis

**Ver total de lições**:
```bash
jq '.meta.total_lessons' docs/learning/lessons/_index.json
```

**Ver lições CRITICAL**:
```bash
jq '.lessons[] | select(.severity == "critical")' docs/learning/lessons/_index.json
```

**Ver feedback negativo**:
```bash
grep '"rating": "down"' docs/learning/feedback/entries.jsonl
```

---

_Sistema de aprendizagem do Scaffold Kit v1.0_

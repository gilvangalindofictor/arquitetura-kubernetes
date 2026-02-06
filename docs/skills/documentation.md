# Skill: Documentation

## Princípios

1. **Documentation as Code**: Versionado, revisável, testável
2. **Single Source of Truth**: Um lugar para cada informação
3. **Always Updated**: Docs atualizados junto com código
4. **Searchable**: Fácil de buscar (Markdown + Git grep)

## Hierarchy

```
docs/
├── context/            # Estado e decisões (alta prioridade)
├── adr/                # Architecture Decision Records
├── logbook/            # Diários de bordo (append-only)
├── plan/               # Planejamento e roadmaps
├── agents/             # Perfis de agentes AI
├── skills/             # Skills por domínio
├── checklists/         # Checklists de qualidade
├── templates/          # Templates de documentos
├── learning/           # Sistema de aprendizagem
└── tests/              # Organização de testes
```

## Document Types

### 1. Context Documents

| Doc              | Owner          | When Update          | Priority |
| ---------------- | -------------- | -------------------- | -------- |
| project_brief.md | User           | Requirements change  | 1        |
| architecture.md  | AI (architect) | After arch decisions | 2        |
| conventions.md   | User + AI      | Setup + changes      | 3        |
| current_state.md | AI (auto)      | After EACH task      | 4        |
| decisions.md     | AI (auto)      | After decisions      | 5        |

### 2. ADRs (Architecture Decision Records)

**When to create**:
- Significant architectural decisions
- Choice between multiple valid options
- Important trade-offs

**Format** (simplified):
```markdown
# ADR-XXX: Title

**Date**: YYYY-MM-DD
**Status**: Accepted / Superseded / Deprecated

## Context
[Why this decision needed]

## Decision
[What was decided]

## Consequences
- ✅ Benefit 1
- ⚠️ Trade-off 1
```

### 3. Logbooks

**Purpose**: Temporal audit trail

**When**: After complex/multi-step tasks

**Format**: See `docs/templates/` or existing logbooks

### 4. Module READMEs

Every Terraform module MUST have:
```markdown
# Module: {name}

## Description

## Usage
\```hcl
module "example" {
  source = "./modules/{name}"
  ...
}
\```

## Inputs
| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | -------- |

## Outputs
| Name | Description |
| ---- | ----------- |
```

## Update Triggers

| Event                  | Update                                    |
| ---------------------- | ----------------------------------------- |
| Task completed         | current_state.md                          |
| Architectural decision | architecture.md + decisions.md            |
| Convention changed     | conventions.md                            |
| Sprint completed       | current_state.md summary                  |
| Error/incident         | decisions.md (what happened + resolution) |
| Security audit         | Security report + current_state.md        |

## Sync Protocol

```
1. Identify impacted docs
2. For each doc:
   ├─ Read current state
   ├─ Identify section to update
   ├─ Add/modify with date and reference
   └─ Save
3. Register in logbook: "[HH:MM:SS] DocSync | Docs | <list> | ✅"
4. Confirm sync before proceeding
```

## Regras

1. **NEVER modify `project_brief.md` automatically** (user responsibility)
2. **ALWAYS sync docs after significant tasks**
3. **Docs out-of-date = technical debt** (same urgency as bugs)

---

_Skill v1.0 - Documentation management_

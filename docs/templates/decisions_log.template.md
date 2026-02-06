# Decisions Log Template

> **Responsabilidade**: AI (atualizado automaticamente após decisões)
> **Quando atualizar**: Após decisões significativas (arquiteturais, técnicas, trade-offs)
> **Prioridade de leitura**: 5

---

## Sobre Este Documento

Este é um log cronológico de decisões técnicas e arquiteturais tomadas durante o projeto.

**Diferença vs ADR**:
- **ADR** (Architecture Decision Record): Documento formal, imutável, para decisões arquiteturais críticas
- **Decisions Log**: Log evolutivo, menos formal, para todas as decisões significativas

**Quando registrar aqui**:
- Escolha de tecnologia/biblioteca
- Trade-offs de design
- Mudança de abordagem
- Decisão que impacta múltiplos componentes
- Accept de vulnerabilidade/risco
- Workaround temporário significativo

---

## Formato de Entrada

Cada decisão registrada segue o formato:

```markdown
### [YYYY-MM-DD] [Categoria] Título da Decisão

**Contexto**: [Por que essa decisão foi necessária]

**Opções Consideradas**:
1. [Opção 1]: [Pros / Cons]
2. [Opção 2]: [Pros / Cons]
3. [Opção 3]: [Pros / Cons]

**Decisão**: [O que foi decidido]

**Justificativa**: [Por que essa opção]

**Consequências**:
- ✅ [Benefício 1]
- ✅ [Benefício 2]
- ⚠️ [Trade-off 1]
- ⚠️ [Trade-off 2]

**Impacto**:
- Componentes afetados: [Lista]
- Dívida técnica: [Se aplicável]
- Ação futura: [Se há plano de revisitar]

**Decisor**: [Agente AI / Usuário / Ambos]

**Relacionado**: [ADR-XXX / Issue #YYY / Task ZZZ]
```

**Categorias**: `architecture`, `technology`, `security`, `performance`, `cost`, `process`, `infrastructure`

---

## Decisões

<!-- Adicionar novas decisões no TOPO (ordem cronológica reversa) -->

---

### [2026-02-06] [infrastructure] Vault Unsealing via Lambda com PostgreSQL público

**Contexto**: Vault precisa de unsealing após restart, mas está em subnet privada sem acesso direto ao PostgreSQL (também privado).

**Opções Consideradas**:
1. **PostgreSQL público temporário**: Mover PostgreSQL para subnet pública até implementar VPC endpoints
   - ✅ Solução rápida (horas)
   - ❌ Expõe banco temporariamente
   - ⚠️ Requer security group restritivo

2. **VPC Endpoints imediatamente**: Criar VPC endpoints para Secrets Manager
   - ✅ Solução definitiva
   - ❌ Leva dias (FinOps Lambda depende)
   - ❌ Complexidade adicional agora

3. **Vault em subnet pública**: Mover Vault para subnet com NAT Gateway
   - ❌ Expõe Vault (pior que PostgreSQL)
   - ❌ Contra boas práticas

**Decisão**: PostgreSQL em subnet pública TEMPORARIAMENTE com security group restritivo permitindo apenas Lambda e EKS nodes.

**Justificativa**:
- Desbloqueia progresso imediato (Marco 3 em andamento)
- Risco mitigado por security group (não totalmente público)
- VPC endpoints virá no próximo sprint (já planejado)

**Consequências**:
- ✅ Vault consegue unseal automaticamente
- ✅ GitLab/Harbor/Keycloak conseguem conectar
- ⚠️ PostgreSQL temporariamente em subnet pública (mitigado por SG)
- ⚠️ Dívida técnica: migrar para privado após VPC endpoints

**Impacto**:
- Componentes afetados: Vault, PostgreSQL, FinOps Lambda
- Dívida técnica: Migração para subnet privada (Marco 4)
- Ação futura: Implementar VPC endpoints e migrar PostgreSQL

**Decisor**: Consenso (architect + devops + security)

**Relacionado**: Logbook 2026-02-06, Task Marco3-Vault-ESO

---

### [2026-01-28] [architecture] Managed PostgreSQL vs CloudNativePG Operator

**Contexto**: Decisão sobre como provisionar PostgreSQL para GitLab/Harbor no EKS.

**Opções Consideradas**:
1. **AWS RDS PostgreSQL (Managed)**:
   - ✅ Fully managed, backups automáticos
   - ✅ Multi-AZ alta disponibilidade
   - ❌ Vendor lock-in
   - ❌ Mais caro

2. **CloudNativePG Operator (Cloud-agnostic)**:
   - ✅ Cloud-agnostic, portável
   - ✅ Controle total
   - ❌ Mais complexo de operar
   - ❌ Responsabilidade de backups/HA

3. **PostgreSQL Stateful Set direto**:
   - ❌ Muito manual, sem operador
   - ❌ Alta complexidade operacional

**Decisão**: AWS RDS PostgreSQL para MVP (Marco 0-3), migrar para CloudNativePG na convergência cloud-agnostic.

**Justificativa**:
- MVP prioriza velocidade (8 semanas)
- RDS reduz complexidade operacional inicial
- Migração para operator é factível mais tarde (dados portáveis)

**Consequências**:
- ✅ Deploy mais rápido do MVP
- ✅ Menor overhead operacional inicial
- ⚠️ Custo $X/mês maior que operator
- ⚠️ Vendor lock-in temporário

**Impacto**:
- Componentes afetados: GitLab, Harbor, Keycloak (todos usam PostgreSQL)
- Dívida técnica: Migração para CloudNativePG (Convergence Roadmap)
- Ação futura: Marco 6+ (pós-MVP)

**Decisor**: Architect (aprovado por CTO)

**Relacionado**: ADR-021 (Kubernetes Operator Strategy), docs/plan/convergence-roadmap.md

---

<!-- Template para próxima entrada -->

### [YYYY-MM-DD] [categoria] Título

**Contexto**:

**Opções Consideradas**:
1.
2.
3.

**Decisão**:

**Justificativa**:

**Consequências**:
- ✅
- ⚠️

**Impacto**:
- Componentes afetados:
- Dívida técnica:
- Ação futura:

**Decisor**:

**Relacionado**:

---

## Índice por Categoria

<!-- Auto-gerado ou manual -->

### Architecture
- [2026-01-28] Managed PostgreSQL vs CloudNativePG Operator

### Infrastructure
- [2026-02-06] Vault Unsealing via Lambda com PostgreSQL público

### [Outra Categoria]
- [Data] Título

---

## Decisões por Review (Críticas)

Decisões que devem ser revisitadas em marcos específicos:

| Decisão            | Marco de Review | Status     |
| ------------------ | --------------- | ---------- |
| PostgreSQL público | Marco 4         | ⏸️ Pendente |
| RDS vs Operator    | Marco 6         | ⏸️ Pendente |

---

_Atualizado automaticamente | Última entrada: [Data] por [Agente]_

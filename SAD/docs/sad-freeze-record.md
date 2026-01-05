# Registro de Congelamento do SAD (Software Architecture Document)

> Este arquivo registra todos os congelamentos do SAD, garantindo rastreabilidade de decisões arquiteturais sistêmicas.

---

## Status Atual
**STATUS**: ✅ CONGELADO - Freeze #3 (v1.2)

O SAD foi descongelado (v1.1), atualizado com ADR-021 (Escolha do Orquestrador de Containers - Kubernetes), documentando decisão fundamental que estava implícita, e recongelado como v1.2.

**Mudanças principais v1.1 → v1.2**:
- ADR-021 criado (Escolha do Orquestrador de Containers - Kubernetes)
- Decisão fundamental documentada explicitamente (estava implícita)
- Justificativa: Kubernetes vs Docker Swarm, Nomad, AWS ECS, Cloud Run, Container Apps
- Validação: Kubernetes é o ÚNICO que atende ADR-003 (cloud-agnostic) + ecossistema maduro

**Histórico de Freezes**:
- Freeze #1: SAD v1.0 (2025-12-30)
- Freeze #2: SAD v1.1 (2026-01-05) - ADR-020, diretrizes práticas
- Freeze #3: SAD v1.2 (2026-01-05) - ADR-021, decisão de orquestrador

---

## Template para Registro de Freeze

```markdown
## Freeze #N — YYYY-MM-DD

### Contexto
{{por que congelar neste momento}}

### SAD Version
{{versão do SAD sendo congelada}}

### ADRs Sistêmicos Incluídos
- ADR-00X: {{título}}
- ADR-00Y: {{título}}

### Decisões Principais
1. {{decisão 1}}
2. {{decisão 2}}

### Regras de Herança Definidas
{{link para inheritance-rules.md}}

### Contratos Entre Domínios
{{link para domain-contracts.md}}

### Validações Realizadas
- [ ] Contexto completo
- [ ] ADRs sistêmicos criados
- [ ] Bounded Contexts definidos
- [ ] Contratos documentados
- [ ] Regras de herança definidas
- [ ] Architect Guardian validou
- [ ] Usuário aprovou explicitamente

### Aprovações
- [ ] Usuário: {{nome}}
- [ ] Architect Guardian: Validado
- [ ] Data de Aprovação: {{data}}

### Impacto
{{quais domínios são afetados}}

### Próximos Passos Após Freeze
1. {{próximo passo}}
2. {{próximo passo}}

---
```

---

## Freeze #3 — 2026-01-05

### Contexto
Usuário identificou lacuna: decisão de usar Kubernetes como orquestrador estava implícita, mas não documentada formalmente. Alternativas (Docker Swarm, Nomad, ECS, Cloud Run) não foram consideradas explicitamente em ADR.

### SAD Version
**v1.2** (atualização de v1.1)

### ADRs Sistêmicos Incluídos
Total: **13 ADRs**

Novos:
- ADR-021: Escolha do Orquestrador de Containers (Kubernetes) ✅

Mantidos (v1.0-v1.1):
- ADR-003 a ADR-020

### Decisões Principais
1. **Orquestrador Escolhido**: Kubernetes
2. **Alternativas Consideradas**: Docker Swarm, Nomad, AWS ECS, Cloud Run, Azure Container Apps
3. **Justificativa**: Kubernetes é o ÚNICO que atende ADR-003 (cloud-agnostic) + ecossistema maduro
4. **Validação**: Matriz de decisão com 8 critérios ponderados - K8s venceu com 542/630 pontos
5. **Trade-offs Aceitos**: Complexidade operacional, custo de control plane, curva de aprendizado
6. **Trade-offs Rejeitados**: Simplicidade (Swarm/Nomad), vendor lock-in (ECS/Cloud Run)

### Regras de Herança e Contratos
Mantidos de v1.0

### Validações Realizadas
- [x] Contexto completo
- [x] ADR-021 criado com alternativas documentadas
- [x] Justificativa detalhada (matriz de decisão, validação com requisitos)
- [x] Trade-offs documentados
- [x] Architect Guardian validou
- [x] Usuário aprovou explicitamente

### Aprovações
- [x] Usuário: Aprovado
- [x] Architect Guardian: Validado
- [x] Data de Aprovação: 2026-01-05

### Impacto
**Todos os domínios afetados** (decisão fundamental)
- Domínios assumem Kubernetes como plataforma base
- IaC usa apenas Kubernetes APIs nativas
- Alternativas (Swarm, Nomad, ECS) descartadas

### Próximos Passos Após Freeze
1. ✅ Atualizar README, copilot-context com decisão explícita
2. ✅ Atualizar logs de progresso
3. Continuar FASE 2: Criação dos domínios (2.2 platform-core)

---

## Freeze #2 — 2026-01-05

### Contexto
Validação do domínio observability contra SAD v1.0 revelou necessidade de esclarecer escopo de implementação cloud-agnostic. SAD foi descongelado, atualizado com diretrizes práticas e re-validação foi realizada.

### SAD Version
**v1.1** (atualização de v1.0)

### ADRs Sistêmicos Incluídos
Total: **12 ADRs**

Novos:
- ADR-020: Provisionamento de Clusters e Escopo de Domínios ✅

Atualizados:
- ADR-003: Cloud-Agnostic e Portabilidade (v1.1)
- ADR-004: IaC e GitOps (v1.1)

Mantidos (v1.0):
- ADR-005 a ADR-019

### Decisões Principais
1. **Separação de Responsabilidades**: Clusters provisionados EXTERNAMENTE aos domínios
2. **Escopo de Domínios**: Apenas recursos Kubernetes nativos
3. **Storage Classes**: Parametrização obrigatória
4. **Object Storage**: S3-compatible como padrão
5. **Terraform nos Domínios**: Apenas providers K8s

### Regras de Herança e Contratos
Mantidos de v1.0

### Validações Realizadas
- [x] ADR-020 criado
- [x] ADR-003 e ADR-004 atualizados
- [x] Domínio observability re-validado
- [x] Architect Guardian validou
- [x] Usuário aprovou

### Aprovações
- [x] Usuário: Gilvan Galindo (CTO)
- [x] Architect Guardian: Validado ✅
- [x] Data: 2026-01-05

### Impacto
- **observability**: APROVADO com plano de refatoração
- **Novos domínios**: Seguem ADR-020 desde o início

### Próximos Passos
1. Continuar FASE 2 (criação de domínios)
2. Criar `/platform-provisioning` estrutura
3. Template de domínio cloud-agnostic

---

## Freeze #1 — 2025-12-30

## Regras de Freeze

### Quando Congelar
- Ao completar FASE 1 (primeira vez)
- Ao fazer mudanças arquiteturais significativas que exigem novo freeze

### O que Significa "Congelado"
- ✅ Decisões sistêmicas são finais
- ✅ Domínios devem seguir obrigatoriamente
- ✅ Mudanças exigem novo ADR + aprovação + novo freeze
- ❌ Não significa "imutável" - significa "controlado"

### Como Descongelar (se necessário)
1. Criar ADR justificando mudança
2. Propor novas decisões sistêmicas
3. Atualizar SAD
4. Validar com Architect Guardian
5. Obter aprovação explícita do usuário
6. Novo freeze com incremento de versão

---

## Histórico de Freezes

## Freeze #1 — 2025-12-30

### Contexto
Re-validação após correções das lacunas identificadas: ADR-019 FinOps criado, storage classes integradas em ADR-008, inheritance-rules.md atualizado.

### SAD Version
v1.0 - FASE 1 Completa

### ADRs Sistêmicos Incluídos
- ADR-003: Cloud Agnostic
- ADR-004: IaC e GitOps
- ADR-005: Segurança Sistêmica
- ADR-006: Observabilidade Transversal
- ADR-007: Service Mesh
- ADR-008: Escalabilidade e Performance (incluindo storage classes)
- ADR-013: Disaster Recovery
- ADR-014: Compliance Regulatória
- ADR-015: Multi-Tenancy
- ADR-016: Escalabilidade Vertical
- ADR-017: Integrações Externas
- ADR-018: Treinamento e Capacitação
- ADR-019: FinOps e Otimização de Custos

### Decisões Principais
1. Cloud-agnostic com Kubernetes como base
2. IaC/GitOps obrigatório para todos os domínios
3. Segurança transversal com RBAC, encryption, service mesh
4. Observabilidade com OpenTelemetry e golden signals
5. Escalabilidade horizontal/vertical com storage classes otimizadas
6. FinOps integrado desde o início com cost allocation, monitoring, budgeting

### Regras de Herança Definidas
[SAD/docs/architecture/inheritance-rules.md](SAD/docs/architecture/inheritance-rules.md)

### Contratos Entre Domínios
[SAD/docs/architecture/domain-contracts.md](SAD/docs/architecture/domain-contracts.md)

### Validações Realizadas
- [x] Contexto completo
- [x] ADRs sistêmicos criados
- [x] Bounded Contexts definidos
- [x] Contratos documentados
- [x] Regras de herança definidas
- [x] Architect Guardian validou
- [x] Usuário aprovou explicitamente

### Aprovações
- [x] Usuário: Gilvan Galindo
- [x] Architect Guardian: Validado
- [x] Data de Aprovação: 2025-12-30

### Impacto
Todos os domínios devem herdar as regras definidas. Mudanças exigem novo ADR.

### Próximos Passos Após Freeze
1. Iniciar desenvolvimento dos domínios conforme inheritance rules
2. Implementar IaC/GitOps pipelines
3. Configurar observabilidade transversal
4. Executar testes de carga por domínio

---

*(Vazio - aguardando FASE 1)*

---

## Próximo Freeze Esperado

**Freeze #1** - Após completar FASE 1 (Concepção do SAD)

Checklist para Freeze #1:
- [ ] `/SAD/docs/sad.md` criado
- [ ] ADRs sistêmicos criados (cloud-agnostic, IaC, segurança, observabilidade, GitOps)
- [ ] `/SAD/docs/architecture/inheritance-rules.md` criado
- [ ] `/SAD/docs/architecture/domain-contracts.md` criado
- [ ] Architect Guardian validou
- [ ] Usuário aprovou

Data Estimada: A definir

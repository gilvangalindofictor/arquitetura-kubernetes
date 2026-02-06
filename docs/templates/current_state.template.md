# Current State Template

> **Responsabilidade**: AI (atualizado automaticamente após cada task)
> **Quando atualizar**: Após CADA task que modifica código/infra
> **Prioridade de leitura**: 4

---

## Status Geral

**Última Atualização**: YYYY-MM-DD HH:MM

**Estado do Projeto**: [Planejamento / Desenvolvimento / Staging / Produção]

**Marco Atual**: [Marco X - Nome]

**Progresso Geral**: [X%] ██████████░░░░░░░░░░ 50%

---

## Marcos

| Marco   | Status         | Progresso | Completado em |
| ------- | -------------- | --------- | ------------- |
| Marco 0 | ✅ Completo     | 100%      | YYYY-MM-DD    |
| Marco 1 | ✅ Completo     | 100%      | YYYY-MM-DD    |
| Marco 2 | 🚧 Em andamento | 67%       | —             |
| Marco 3 | ⏸️ Pendente     | 0%        | —             |

**Legenda**: ✅ Completo | 🚧 Em andamento | ⏸️ Pendente | ⚠️ Bloqueado

---

## Tasks em Andamento

**Sprint/Marco Atual**: [Nome]

| Task     | Responsável (Agente) | Status          | Bloqueios            |
| -------- | -------------------- | --------------- | -------------------- |
| [Task 1] | backend_coder        | 🚧 80%           | —                    |
| [Task 2] | devops               | ⏸️ Pendente deps | Aguarda Task 1       |
| [Task 3] | security             | ⚠️ Bloqueado     | CVE em dependência X |

---

## Componentes

### Infraestrutura

| Componente  | Status        | Versão | Ambiente | Notas                |
| ----------- | ------------- | ------ | -------- | -------------------- |
| EKS Cluster | ✅ Operacional | 1.28   | Staging  | 3 nodes m5.large     |
| VPC         | ✅ Operacional | —      | Staging  | 10.0.0.0/16          |
| PostgreSQL  | ✅ Operacional | 15.4   | Staging  | RDS db.t3.medium     |
| Vault       | ⚠️ Parcial     | 1.15.0 | Staging  | Unsealing manual     |
| Keycloak    | 🚧 Deploy      | 23.0.0 | Staging  | Integrando com Vault |

**Legenda**: ✅ Operacional | 🚧 Em deploy | ⏸️ Planejado | ⚠️ Com issues | ❌ Inoperante

---

### Aplicações

| Aplicação  | Status        | Versão | Ambiente | Réplicas | Notas              |
| ---------- | ------------- | ------ | -------- | -------- | ------------------ |
| GitLab     | ✅ Operacional | 16.7.0 | Staging  | 1        | Postgres externo   |
| Harbor     | ✅ Operacional | 2.9.1  | Staging  | 1        | Registry funcional |
| Prometheus | ✅ Operacional | 2.48.0 | Staging  | 1        | Métricas ok        |
| Grafana    | ✅ Operacional | 10.2.0 | Staging  | 1        | Dashboards ok      |
| Loki       | ✅ Operacional | 2.9.3  | Staging  | 1        | Logs agregados     |

---

## Observabilidade

**Stack de Monitoring**:
- ✅ Prometheus: metrics coleta ok
- ✅ Grafana: dashboards principais disponíveis
- ✅ Loki: logs centralizados
- ✅ Tempo: traces habilitados
- ⏸️ Alertmanager: configuração pendente

**Dashboards Disponíveis**:
- Cluster Overview: [URL]
- Application Metrics: [URL]
- Cost Analysis: [URL]

**Alertas Configurados**: [N] alertas ativos

---

## Testes

**Última Execução**: YYYY-MM-DD HH:MM

| Tipo        | Total | Passed | Failed | Cobertura |
| ----------- | ----- | ------ | ------ | --------- |
| Unit        | [N]   | [N]    | [N]    | [X]%      |
| Integration | [N]   | [N]    | [N]    | —         |
| E2E         | [N]   | [N]    | [N]    | —         |
| Performance | [N]   | [N]    | [N]    | —         |

**Issues Conhecidos**:
- [Issue 1]: [Descrição breve]
- [Issue 2]: [Descrição breve]

---

## Dependências Externas

| Dependência | Versão | Status | Última Verificação |
| ----------- | ------ | ------ | ------------------ |
| Terraform   | 1.6.6  | ✅ Ok   | YYYY-MM-DD         |
| Helm        | 3.13.3 | ✅ Ok   | YYYY-MM-DD         |
| kubectl     | 1.28.x | ✅ Ok   | YYYY-MM-DD         |
| [Tool X]    | [Ver]  | ✅ Ok   | YYYY-MM-DD         |

**Vulnerabilidades Conhecidas**: [N] HIGH, [M] MEDIUM

---

## Segurança

**Última Audit**: YYYY-MM-DD

**Findings**:
- HIGH: [N] (resolvidos: [X])
- MEDIUM: [N] (resolvidos: [X])
- LOW: [N] (resolvidos: [X])

**Pendências Críticas**:
- [ ] [Vulnerability 1] - [Prazo]
- [ ] [Vulnerability 2] - [Prazo]

**Status Compliance**:
- OWASP Top 10: [X/10] ✅
- CIS Benchmarks: [X%]
- [Outro framework]: [Status]

---

## Configuração e Secrets

**Secrets Management**: [Vault / AWS Secrets Manager / etc.]

**Secrets Migrados para Vault**: [X/Y] ([Z%])

**Configurações por Ambiente**:

| Config        | Staging     | Production | Gerenciado por |
| ------------- | ----------- | ---------- | -------------- |
| DB Host       | RDS Staging | RDS Prod   | Terraform      |
| API Keys      | Vault       | Vault      | ESO            |
| Feature Flags | ConfigMap   | ConfigMap  | Git            |

---

## Custos

**Última Análise**: YYYY-MM-DD

**Custo Atual (mensal)**:
- Staging: $[X] USD
- Production: $[Y] USD (projetado)
- Total: $[Z] USD

**Maiores Custos**:
1. [Recurso 1]: $[X] ([Y%])
2. [Recurso 2]: $[X] ([Y%])
3. [Recurso 3]: $[X] ([Y%])

**Otimizações Implementadas**:
- ✅ [Otimização 1]: economia de $[X]/mês
- ✅ [Otimização 2]: economia de $[X]/mês

**Próximas Otimizações**:
- [ ] [Otimização 3]: projeção $[X]/mês

---

## Dívida Técnica

**Top 5 Items**:

1. **[Nome da Dívida 1]** - Severidade: [HIGH/MEDIUM/LOW]
   - **Impacto**: [Descrição]
   - **Esforço**: [S/M/L]
   - **Plano**: [Quando será resolvida]

2. **[Nome da Dívida 2]** - Severidade: [HIGH/MEDIUM/LOW]
   - **Impacto**: [Descrição]
   - **Esforço**: [S/M/L]
   - **Plano**: [Quando será resolvida]

[...]

---

## Próximos Passos

**Sprint/Marco Próximo**: [Nome]

**Tasks Planejadas**:
- [ ] [Task 1] - [Agente responsável]
- [ ] [Task 2] - [Agente responsável]
- [ ] [Task 3] - [Agente responsável]

**Dependências Críticas**:
- [Dependência 1]: [O que precisa acontecer]
- [Dependência 2]: [O que precisa acontecer]

**Riscos Identificados**:
- ⚠️ [Risco 1]: [Mitigação planejada]
- ⚠️ [Risco 2]: [Mitigação planejada]

---

## Mudanças Recentes

### [YYYY-MM-DD]
- ✅ [Task concluída 1]
- ✅ [Task concluída 2]
- 🐛 [Bug fix 1]

### [YYYY-MM-DD]
- ✅ [Task concluída 3]
- ⚠️ [Issue identificado]

[Manter últimas 2 semanas]

---

## Notas

[Qualquer informação adicional relevante sobre o estado atual]

---

_Auto-atualizado pelo sistema de scaffold | Última task: [Task ID] por [Agente] em YYYY-MM-DD HH:MM_

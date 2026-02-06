# 📋 Demandas em Aberto — Plataforma Kubernetes

> **Data**: 2026-02-06
> **Fonte**: Análise de documentos de contexto (current_state.md, gap analysis, risks.md)
> **Status Marco Atual**: Marco 3 ✅ Completo | Marco 4 em planejamento

---

## 🎯 VISÃO GERAL

### Status Atual
- **Marcos 0-3**: ✅ 100% completos (~14 dias trabalho, $700/mês)
- **Marco 4**: 🚧 Gap analysis completo, implementação pendente
- **Dívida Técnica**: 5 items identificados (2 HIGH, 2 MEDIUM, 1 LOW)

### Próximo Marco: Marco 4 — CI/CD Completa
**Objetivo**: GitLab CI/CD + ArgoCD + SonarQube + Keycloak SSO
**Duração Estimada**: 13-17h (2-3 dias úteis)
**Custo Adicional**: +$100/mês
**ROI**: $6.600/ano economia vs SaaS

---

## 🔴 DEMANDAS CRÍTICAS (Bloqueantes)

### GAP-001: Keycloak SSO Platform Deploy
**Prioridade**: 🔴 CRÍTICA — BLOQUEANTE para Marco 4
**Status**: Módulo NÃO EXISTE
**Duração**: 4-6h
**Custo**: +$35/mês

**Descrição**:
Implementar Keycloak como plataforma SSO centralizada para toda a plataforma (ArgoCD, SonarQube, GitLab, Grafana).

**Requisitos**:
- PostgreSQL DB `keycloak` (bootstrap no RDS)
- Keycloak HA 2 replicas
- OIDC clients: argocd, sonarqube, gitlab, grafana
- Realm master + groups (argocd-admins, developers, platform-admins)

**Entregáveis**:
- [ ] Módulo Terraform `modules/keycloak/`
  - [ ] main.tf (namespace + helm release)
  - [ ] variables.tf
  - [ ] outputs.tf
  - [ ] values.yaml.tpl (HA config, PostgreSQL external, OIDC)
  - [ ] manifests/external-secret-db.yaml
  - [ ] README.md
- [ ] Script bootstrap PostgreSQL database
- [ ] Configuração inicial Keycloak (realm, groups, clients)
- [ ] Integração main.tf (module call + outputs)
- [ ] Validação (pods running, admin UI, OIDC token endpoint)
- [ ] ADR-046: Keycloak SSO Platform Strategy
- [ ] Logbook: `2026-02-0X-keycloak-deployment.md`
- [ ] Atualizar: PROJECT-CONTEXT.md, architecture.md, current_state.md

**Dependências**:
- PostgreSQL RDS operacional (✅ já existe)
- Vault + ESO operacional (✅ já existe)

**Bloqueios**:
- ArgoCD deploy (GAP-003)
- SonarQube deploy (GAP-004)
- GitLab OAuth integration (GAP-005)

---

### GAP-002: GitLab Components Failures Fix
**Prioridade**: 🔴 CRÍTICA — BLOQUEANTE para CI/CD
**Status**: Componentes em CrashLoop/Pending
**Duração**: 2-4h
**Custo**: $0 (já provisionado)

**Descrição**:
Corrigir falhas nos componentes GitLab que impedem funcionamento da pipeline CI/CD.

**Problemas Identificados**:
- ❌ `gitlab-gitlab-runner`: CrashLoopBackOff (107 restarts)
- ❌ `gitlab-kas`: CrashLoopBackOff (86 restarts)
- ❌ `gitlab-gitaly`: Pending (PVC issue)
- ❌ `gitlab-sidekiq`: Init:Error (85 failures)
- ✅ `gitlab-webservice`: Running (2/2) — OK
- ✅ `gitlab-gitlab-shell`: Running (2/2) — OK
- ✅ `gitlab-registry`: Running (2/2) — OK

**Root Causes**:
- Gitaly: PVC Pending (RWO + scheduling conflict)
- Runner: CrashLoop (RBAC/network policies)
- KAS: CrashLoop (K8s API auth)
- Sidekiq: Init Error (Redis/DB migration issue)

**Entregáveis**:
- [ ] Troubleshoot gitaly PVC (verificar storage class, node affinity)
- [ ] Fix gitlab-runner RBAC/network (ServiceAccount, Role, NetworkPolicy)
- [ ] Fix gitlab-kas K8s API auth (IRSA/token)
- [ ] Fix sidekiq init (Redis connection, DB migration)
- [ ] Validação (todos pods Running 100%)
- [ ] Logbook: `2026-02-0X-gitlab-components-fix.md`

**Dependências**: Nenhuma (pode iniciar imediatamente)

**Bloqueios**: GitLab CI/CD Integration (GAP-005)

---

## 🟡 DEMANDAS ALTAS (Não-bloqueantes)

### GAP-003: ArgoCD Deploy
**Prioridade**: 🟡 ALTA
**Status**: Módulo TF criado (scaffold), não deployado
**Duração**: 2h
**Custo**: +$15/mês

**Descrição**:
Deploy ArgoCD como plataforma GitOps.

**Pré-requisito**: GAP-001 (Keycloak) concluído

**Entregáveis**:
- [ ] Completar módulo `modules/argocd/` (✅ scaffold existe)
  - [ ] Configurar Keycloak OIDC (client ID, secret via ExternalSecret)
  - [ ] AppProjects CRDs (plataforma, aplicacoes)
  - [ ] RBAC policies (argocd-admins group)
- [ ] Integração main.tf
- [ ] Validation (UI acessível, login OIDC, sync app teste)
- [ ] Atualizar ADR-034: ArgoCD ApplicationSets (adicionar OIDC Keycloak)
- [ ] Logbook: `2026-02-0X-argocd-deployment.md`

---

### GAP-004: SonarQube Deploy
**Prioridade**: 🟡 ALTA
**Status**: Módulo TF criado (scaffold), não deployado
**Duração**: 2h
**Custo**: +$50/mês

**Descrição**:
Deploy SonarQube Community Edition para análise de código.

**Entregáveis**:
- [ ] Completar módulo `modules/sonarqube/` (✅ scaffold + bootstrap script existem)
  - [ ] Executar bootstrap database (✅ script pronto)
  - [ ] ExternalSecret credentials (username, password, DB config)
  - [ ] Persistent storage (PVC 20Gi)
- [ ] Integração main.tf
- [ ] Validation (UI acessível, DB connection, quality gates)
- [ ] Atualizar ADR-035: SonarQube Code Quality (adicionar PostgreSQL RDS)
- [ ] Logbook: `2026-02-0X-sonarqube-deployment.md`

---

### GAP-005: GitLab CI/CD Integration
**Prioridade**: 🟡 ALTA
**Status**: Não implementado
**Duração**: 3h
**Custo**: $0

**Descrição**:
Integrar GitLab CI/CD com SonarQube e Harbor (pipeline completa).

**Pré-requisito**: GAP-002 (GitLab fix) + GAP-004 (SonarQube) concluídos

**Entregáveis**:
- [ ] GitLab Runner functional (RBAC namespace-scoped)
- [ ] CI/CD variables configured:
  - [ ] Harbor registry (HARBOR_URL, HARBOR_USER, HARBOR_PASSWORD)
  - [ ] SonarQube (SONAR_HOST_URL, SONAR_TOKEN)
- [ ] .gitlab-ci.yml templates (build, test, scan, deploy):
  - [ ] Build: Docker build + push to Harbor
  - [ ] Test: Unit tests
  - [ ] Scan: SonarQube analysis
  - [ ] Deploy: ArgoCD sync (opcional)
- [ ] End-to-end pipeline validation (commit → build → scan → deploy)
- [ ] Logbook: `2026-02-0X-gitlab-ci-integration.md`

---

## 🟢 DEMANDAS BAIXAS (Melhorias)

### GAP-006: ApplicationSets GitOps Patterns
**Prioridade**: 🟢 BAIXA
**Duração**: 2h
**Custo**: $0

**Descrição**: Implementar ApplicationSets para GitOps patterns (Git generator, auto-sync, pruning).

---

### GAP-007: Network Policies Marco 4
**Prioridade**: 🟢 BAIXA
**Duração**: 1h
**Custo**: $0

**Descrição**: Network Policies para ArgoCD, SonarQube, Keycloak (hardening).

---

### GAP-008: Monitoring & Dashboards Marco 4
**Prioridade**: 🟢 BAIXA
**Duração**: 1h
**Custo**: $0

**Descrição**: Grafana dashboards para ArgoCD sync status, SonarQube metrics, Keycloak usage.

---

## 🔧 DÍVIDA TÉCNICA

### DT-001: PostgreSQL em Subnet Pública (Temporário)
**Severidade**: 🔴 HIGH
**Impacto**: Exposição de banco (mitigado por SG restritivo)
**Esforço**: M (depende de VPC endpoints funcionais)
**Plano**: Migrar para subnet privada quando Vault 100% estável

**Tarefas**:
- [ ] Validar Vault unsealing após VPC Endpoints (ADR-046)
- [ ] Criar subnet privada para data tier
- [ ] Migrar PostgreSQL RDS para subnet privada
- [ ] Atualizar security groups
- [ ] Validar GitLab/Harbor/Keycloak connectivity
- [ ] Logbook: `2026-02-0X-postgresql-private-subnet-migration.md`

---

### DT-002: Secrets Hardcoded (Harbor, GitLab)
**Severidade**: 🔴 HIGH
**Impacto**: Secrets em Kubernetes Secrets não criptografados em rest
**Esforço**: S (migração via ESO)
**Plano**: Marco 4, após Vault 100% estável

**Tarefas**:
- [ ] Migrar Harbor secrets para Vault + ESO
  - [ ] Admin password
  - [ ] PostgreSQL credentials
  - [ ] S3 credentials (IRSA)
- [ ] Migrar GitLab secrets para Vault + ESO
  - [ ] Root password
  - [ ] PostgreSQL credentials
  - [ ] Rails secrets
- [ ] Validar aplicações após migração
- [ ] Remover Kubernetes Secrets manuais
- [ ] Logbook: `2026-02-0X-secrets-vault-migration.md`

---

### DT-003: Sem Testes Automatizados (IaC)
**Severidade**: 🟡 MEDIUM
**Impacto**: Risco de regressão em mudanças Terraform
**Esforço**: M (setup Terratest + CI)
**Plano**: Marco 4+

**Tarefas**:
- [ ] Setup Terratest (Go)
- [ ] Testes integration para módulos críticos:
  - [ ] modules/keycloak
  - [ ] modules/argocd
  - [ ] modules/sonarqube
  - [ ] modules/vault
- [ ] CI integration (GitHub Actions / GitLab CI)
- [ ] Test coverage report
- [ ] Logbook: `2026-02-0X-terratest-implementation.md`

---

### DT-004: RDS Single-AZ (Staging)
**Severidade**: 🟢 LOW (staging only)
**Impacto**: Sem HA em staging (aceitável)
**Esforço**: S (flag Multi-AZ)
**Plano**: Production será Multi-AZ desde o início

**Nota**: Aceito para staging (redução de custo $30/mês). Production terá Multi-AZ obrigatório.

---

### DT-005: Alertas Básicos (Observability)
**Severidade**: 🟡 MEDIUM
**Impacto**: Possível falha sem notificação rápida
**Esforço**: M (definir alertas + routing)
**Plano**: Marco 5 (observability completa)

**Tarefas**:
- [ ] Definir alertas críticos:
  - [ ] Disk space < 20%
  - [ ] Memory pressure
  - [ ] Certificate expiration < 30 days
  - [ ] Database connection pool > 80%
  - [ ] Pod restarts > 5 em 10min
- [ ] Configurar Alertmanager routing (Slack/Email)
- [ ] Runbooks para cada alerta
- [ ] Logbook: `2026-02-0X-alerting-configuration.md`

---

## ⚠️ RISCOS ATIVOS

Ver `docs/context/risks.md` para matriz completa. Riscos críticos monitorados:

- **R-010**: Secrets leak em Git (🟢 mitigado)
- **R-003**: Network Policies bloqueiam tráfego (🟢 mitigado)
- **R-030**: Missing VPC Endpoints (✅ RESOLVIDO ADR-046)

---

## 📅 ROADMAP DE IMPLEMENTAÇÃO SUGERIDO

### Sprint 1: Pre-Requisites (CRÍTICO) — 6-10h
**Ordem de execução**:
1. ✅ Bootstrap scaffold kit (concluído 2026-02-06)
2. 🔴 GAP-001: Keycloak Deploy (4-6h) ← **PRÓXIMA DEMANDA**
3. 🔴 GAP-002: GitLab Components Fix (2-4h) — pode ser paralelo

**Output Sprint 1**:
- Keycloak SSO operacional
- GitLab 100% funcional
- Fundações para Marco 4

---

### Sprint 2: Core CI/CD Components — 4h
**Ordem de execução**:
1. 🟡 GAP-003: ArgoCD Deploy (2h) — depende GAP-001
2. 🟡 GAP-004: SonarQube Deploy (2h) — pode ser paralelo

**Output Sprint 2**:
- ArgoCD GitOps operacional
- SonarQube quality gates funcionais

---

### Sprint 3: Pipeline Integration — 3h
**Ordem de execução**:
1. 🟡 GAP-005: GitLab CI/CD Integration (3h) — depende GAP-002 + GAP-004

**Output Sprint 3**:
- Pipeline CI/CD end-to-end funcional
- Marco 4 COMPLETO

---

### Sprint 4: Hardening (OPCIONAL) — 4h
**Ordem de execução**:
1. 🟢 GAP-006: ApplicationSets (2h)
2. 🟢 GAP-007: Network Policies (1h)
3. 🟢 GAP-008: Monitoring Dashboards (1h)

**Output Sprint 4**:
- Hardening completo
- Observability aprimorada

---

### Sprint 5+: Dívida Técnica & Otimizações
1. DT-001: PostgreSQL subnet privada (4h)
2. DT-002: Secrets migration Vault (3h)
3. DT-003: Terratest implementation (8h)
4. DT-005: Alerting configuration (4h)

---

## 📊 PRIORIZAÇÃO RECOMENDADA

### Ação Imediata (Hoje/Amanhã)
1. **GAP-001: Keycloak** — Bloqueante crítico
2. **GAP-002: GitLab Fix** — Bloqueante crítico

### Próxima Semana
3. **GAP-003: ArgoCD** — Alta prioridade
4. **GAP-004: SonarQube** — Alta prioridade
5. **GAP-005: GitLab CI/CD** — Alta prioridade

### Próximo Sprint (Semana +2)
6. DT-002: Secrets migration
7. DT-001: PostgreSQL private subnet
8. GAP-006/007/008: Hardening

### Backlog (Sem prazo)
9. DT-003: Terratest
10. DT-005: Alerting completo

---

## 💰 CUSTO ESTIMADO TOTAL

| Item | Custo/Mês | Status |
|------|-----------|--------|
| **Marco 0-3 (Atual)** | $700 | ✅ Operacional |
| GAP-001: Keycloak | +$35 | ⏸️ Pendente |
| GAP-003: ArgoCD | +$15 | ⏸️ Pendente |
| GAP-004: SonarQube | +$50 | ⏸️ Pendente |
| GAP-002/005/006/007/008 | $0 | ⏸️ Pendente |
| **Marco 4 TOTAL** | **+$100** | |
| **PLATAFORMA COMPLETA** | **~$800/mês** | Marco 0-4 |

**ROI Marco 4**: $6.600/ano economia vs SaaS

---

## 📚 REFERÊNCIAS

- [current_state.md](docs/context/current_state.md) — Estado atual detalhado
- [Gap Analysis](docs/logbook/2026-02-05-marco4-gap-analysis.md) — Análise completa Marco 4
- [Pre-Planning Sprint+1](docs/logbook/2026-02-05-pre-planejamento-sprint-plus-1.md) — Artefatos preparados
- [risks.md](docs/context/risks.md) — Matriz de riscos
- [project_brief.md](docs/context/project_brief.md) — Visão do projeto

---

_Última atualização: 2026-02-06 | Fonte: Análise de contexto automatizada_

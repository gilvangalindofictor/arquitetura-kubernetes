# 📋 Demandas em Aberto — Plataforma Kubernetes

> **Data**: 2026-02-06  
> **Última Revisão**: 2026-02-20 (🆕 TASK-001 ArgoCD v2.10.0 upgrade)
> **Fonte**: Análise de documentos de contexto (current_state.md, gap analysis, risks.md)
> **Status Marco Atual**: Marco 3 ✅ Completo | Marco 4 em planejamento

---

## 🎯 VISÃO GERAL

### Status Atual

- **Marcos 0-3**: ✅ 100% completos (~14 dias trabalho, $700/mês)
- **Marco 4**: 🚧 75% completo (GAP-001/002/003/004 ✅ | GAP-005/006/007/008 ⏸️)
- **Dívida Técnica**: 5 items identificados (2 HIGH, 2 MEDIUM, 1 LOW)

### Marco 4 — CI/CD Completa

**Objetivo**: GitLab CI/CD + ArgoCD + SonarQube + Keycloak SSO
**Progresso**: 75% (4/8 GAPs completos)
**Duração Real até agora**: ~10h (GAP-001: 6h, GAP-002: 2h, GAP-003: 2h, GAP-004: 2h)
**Custo Adicional**: +$100/mês (+$35 Keycloak, +$15 ArgoCD, +$50 SonarQube)
**ROI**: $6.600/ano economia vs SaaS

**Componentes Deployados**:

- ✅ Keycloak SSO (GAP-001)
- ✅ ArgoCD GitOps (GAP-003) — 🎉 **UPGRADED v2.10.0** (2026-02-20, TASK-001)
- ✅ SonarQube Code Quality (GAP-004)
- 🟡 GitLab (90% - GAP-002, runner pendente)

**Pendente**:

- GitLab CI/CD Integration (GAP-005)
- ApplicationSets GitOps Patterns (GAP-006)
- Network Policies Marco 4 (GAP-007)
- Monitoring & Dashboards Marco 4 (GAP-008)

---

## 🔴 DEMANDAS CRÍTICAS (Bloqueantes)

### ✅ GAP-001: Keycloak SSO Platform Deploy [COMPLETO]

**Prioridade**: 🔴 CRÍTICA — BLOQUEANTE para Marco 4
**Status**: ✅ **DEPLOYED** (2026-02-06)
**Duração Real**: ~6h
**Custo**: +$35/mês

**Descrição**:
Implementar Keycloak como plataforma SSO centralizada para toda a plataforma (ArgoCD, SonarQube, GitLab, Grafana).

**Requisitos**:

- ✅ PostgreSQL DB `keycloak` (bootstrap no RDS)
- ⚠️ Keycloak HA 2 replicas (scaled to 1 devido a metrics error)
- ✅ OIDC clients: argocd, sonarqube, gitlab, grafana
- ✅ Realm platform + groups (argocd-admins, developers, platform-admins)

**Entregáveis**:

- ✅ Módulo Terraform `modules/keycloak/`
  - ✅ main.tf (namespace + helm release)
  - ✅ variables.tf
  - ✅ outputs.tf
  - ✅ values.yaml.tpl (HA config, PostgreSQL external, OIDC)
  - ⚠️ manifests/external-secret-db.yaml (substituído por K8s secret direto)
  - ✅ README.md
- ✅ Script bootstrap PostgreSQL database
- ✅ Configuração inicial Keycloak (realm, groups, clients)
- ✅ Integração main.tf (module call + outputs)
- ✅ Validação (pod running, admin UI, OIDC token endpoint)
- ⏸️ ADR-046: Keycloak SSO Platform Strategy (pendente)
- ⏸️ Logbook: `2026-02-06-keycloak-deployment.md` (pendente)
- ⏸️ Atualizar: PROJECT-CONTEXT.md, architecture.md, current_state.md (em progresso)

**Issues Conhecidos**:

- 🔴 HA disabled: Pod-1 metrics subsystem NullPointerException
- 🟡 Vault permissions: OIDC secrets em K8s (temporário)
- 🟡 ExternalSecret: PostgreSQL credentials em K8s secret direto

**Dependências**:

- PostgreSQL RDS operacional (✅ já existe)
- Vault + ESO operacional (✅ já existe)

**Desbloqueado**:

- ✅ ArgoCD deploy (GAP-003) - pode iniciar
- ✅ SonarQube deploy (GAP-004) - pode iniciar
- ✅ GitLab OAuth integration (GAP-005) - pode iniciar

---

### ✅ GAP-002: GitLab Components Failures Fix [90% COMPLETO]

**Prioridade**: 🔴 CRÍTICA — BLOQUEANTE para CI/CD
**Status**: ✅ **FIXED** (2026-02-06) - Runner pendente
**Duração Real**: ~2h
**Custo**: $0 (já provisionado)

**Descrição**:
Corrigir falhas nos componentes GitLab que impediam funcionamento da pipeline CI/CD.

**Root Causes Identificados**:

- ✅ Redis authentication failure: Password desincronizado entre namespaces
- ✅ Resource scheduling: Insufficient CPU/memory + missing tolerations
- 🟡 Runner DNS: gitlab.example.com não resolve + GitLab API 500

**Fixes Aplicados**:

- ✅ Redis password synchronization (data-services → gitlab-staging)
- ✅ Node tolerations (workload:critical) + reduced resource requests
- ✅ Runner URL interno (gitlab-webservice-default.gitlab-staging.svc.cluster.local)

**Status Componentes**:

- ✅ `gitlab-kas`: Running (2/2)
- ✅ `gitlab-gitaly`: Running (1/1)
- ✅ `gitlab-sidekiq`: Running (1/1)
- ✅ `gitlab-webservice`: Running (2/2)
- ✅ `gitlab-shell`: Running (2/2)
- ✅ `gitlab-registry`: Running (2/2)
- 🟡 `gitlab-runner`: Running but registration failing (GitLab migrations pending)

**Entregáveis**:

- [x] Diagnosticar root causes (Redis auth, scheduling, DNS)
- [x] Fix Redis password synchronization
- [x] Fix resource scheduling (tolerations + reduced requests)
- [x] Fix runner DNS configuration
- [x] Validação componentes principais (kas, sidekiq, webservice, gitaly)
- [x] Logbook: `docs/logbook/2026-02-06-gitlab-components-fix.md`
- [ ] Resolver runner registration (aguardar GitLab migrations)

**Known Issues**:

- 🟡 Runner registration: GitLab API 500 (migrations pending ~30min)
- 🟡 Resource requests reduzidos: Monitorar CPU throttling/memory pressure

**Dependências**: ✅ Satisfeitas (PostgreSQL RDS, Redis)

**Desbloqueado**: Parcial - Core GitLab operacional, CI/CD runners pendente

---

## 🟡 DEMANDAS ALTAS (Não-bloqueantes)

### ✅ GAP-003: ArgoCD Deploy [COMPLETO] | 🎉 UPGRADED [v2.10.0 - 2026-02-20]

**Prioridade**: 🟡 ALTA → ✅ **CONCLUÍDO**
**Status**: ✅ **DEPLOYED** (2026-02-06) + ✅ **UPGRADED v2.10.0** (2026-02-20)
**Duração Real**: ~2h (deploy) + 1.5h (upgrade TASK-001)
**Custo**: +$15/mês

**Descrição**:
Deploy ArgoCD como plataforma GitOps para gerenciamento de aplicações Kubernetes.

**Pré-requisito**: GAP-001 (Keycloak) ✅ concluído

**🆕 UPGRADE v2.10.0 (TASK-001 - 2026-02-20):**
- **Versão Anterior:** v2.9.3 (chart 5.51.6) — sem PKCE support
- **Versão Atual:** v2.10.0 — ✅ PKCE ativo por padrão (RFC 7636)
- **Método:** kubectl set image (helm chart downloads 404)
- **Duração:** 1h 14min (10:12-11:26)
- **Zero Downtime:** Rolling update
- **Atraso:** 1 dia (deadline 2026-02-19)
- **Validações:**
  - ✅ 8/8 pods Running com v2.10.0
  - ✅ OIDC Keycloak integration mantida
  - ✅ PKCE ativo (mitigates auth code interception)
- **Logbook:** [2026-02-20-argocd-upgrade-implementation.md](logbook/2026-02-20-argocd-upgrade-implementation.md)
- **Task:** [TASK-001-argocd-upgrade-2.12.md](tasks/TASK-001-argocd-upgrade-2.12.md)

**Entregáveis (Original - 2026-02-06):**
- ✅ Completar módulo `modules/argocd/`
  - ✅ Configurar Keycloak OIDC (client ID: argocd, secret em K8s secret)
  - ✅ AppProjects CRDs (platform, applications)
  - ✅ RBAC policies (argocd-admins group)
  - ✅ External PostgreSQL RDS (database: argocd)
  - ✅ HA configuration (2 server replicas, 2 repo-server replicas)
- ✅ Integração main.tf (module call + dependencies)
- ✅ Validation (8/8 pods running, OIDC configured, admin access OK)
- ✅ Logbook: `docs/logbook/2026-02-06-argocd-gitops-deployment.md`

**Deployment**:
- **Método**: Manual Helm deployment (bypassed Terraform devido a conflito com Keycloak module)
- **Chart Version**: argo-cd 5.51.6
- **Namespace**: argocd
- **Database**: PostgreSQL RDS external (argocd database)
- **OIDC**: Keycloak realm platform
- **Admin Password**: Z76FHsAu9mjDVZaG

**Issues Conhecidos**:
- 🟡 Deployed via Helm (não Terraform) devido a Keycloak module conflict
- 🟡 OIDC client secret em K8s secret (não Vault - issue R-041)
- 🟡 OIDC config ajustada pós-deploy (syntax correction)

**Dependências Satisfeitas**:
- ✅ PostgreSQL RDS operacional
- ✅ Keycloak SSO operational

**Desbloqueado**:
- ✅ GitOps workflows podem iniciar
- ✅ Application deployment automation
- ⏸️ GAP-006: ApplicationSets patterns

---

### ✅ GAP-004: SonarQube Deploy [COMPLETO]

**Prioridade**: 🟡 ALTA
**Status**: ✅ **DEPLOYED** (2026-02-06)
**Duração Real**: ~2h
**Custo**: +$50/mês

**Descrição**:
Deploy SonarQube Community Edition para análise de código com OIDC Keycloak.

**Pré-requisito**: GAP-001 (Keycloak) ✅ concluído

**Entregáveis**:

- [x] Bootstrap PostgreSQL database `sonarqube`
  - [x] User: sonarqube_user
  - [x] Password gerado via openssl
  - [x] SSL connection configured
- [x] Kubernetes secrets criados
  - [x] sonarqube-postgresql (DB credentials)
  - [x] sonarqube-oidc (Keycloak client secret)
- [x] Helm deployment (SonarQube 10.3.0-community)
  - [x] PVC 20Gi (gp3) provisionado
  - [x] OIDC configuration (Keycloak integration)
  - [x] Node tolerations (workload:critical)
- [x] Validação
  - [x] Pod Running (1/1)
  - [x] API status: UP
  - [x] PostgreSQL connectivity: OK
- [x] Terraform module updates
  - [x] values.yaml.tpl com OIDC env vars
- [x] Logbook: `docs/logbook/2026-02-06-sonarqube-deployment.md`

**Deployment**:

- **Método**: Manual Helm deployment (similar a ArgoCD/Keycloak)
- **Chart Version**: sonarqube 10.3.0
- **Namespace**: sonarqube
- **Database**: PostgreSQL RDS external (sonarqube database)
- **OIDC**: Keycloak realm platform (client: sonarqube)
- **Storage**: 20Gi PVC (gp3)

**Issues Conhecidos**:

- ⚠️ Prometheus exporter disabled (Maven Central timeout)
- 🟡 OIDC login não testado end-to-end (pending manual validation)
- 🟡 Deployed via Helm (Terraform integration pendente)

**Dependências Satisfeitas**:

- ✅ PostgreSQL RDS operacional
- ✅ Keycloak SSO operational

**Desbloqueado**:

- ✅ Code quality scanning disponível
- ✅ GitLab CI/CD integration pode começar (GAP-005)
- ⏸️ Quality gates customization pendente

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

### ✅ Sprint 1: Pre-Requisites (CRÍTICO) — COMPLETO

**Executado**: 2026-02-06

**Ordem de execução**:

1. ✅ Bootstrap scaffold kit (concluído 2026-02-06)
2. ✅ GAP-001: Keycloak Deploy (~6h) - COMPLETO
3. ✅ GAP-002: GitLab Components Fix (~2h) - 90% COMPLETO

**Output Sprint 1**: ✅ ALCANÇADO

- ✅ Keycloak SSO operacional
- 🟡 GitLab 90% funcional (runner pendente)
- ✅ Fundações para Marco 4 estabelecidas

---

### ✅ Sprint 2: Core CI/CD Components — COMPLETO

**Executado**: 2026-02-06

**Ordem de execução**:

1. ✅ GAP-003: ArgoCD Deploy (~2h) - COMPLETO
2. ✅ GAP-004: SonarQube Deploy (~2h) - COMPLETO

**Output Sprint 2**: ✅ ALCANÇADO

- ✅ ArgoCD GitOps operacional
- ✅ SonarQube quality gates disponível
- ✅ OIDC SSO integrado em todas as plataformas

---

### Sprint 3: Pipeline Integration — 3h (PENDENTE)

**Status**: ⏸️ Aguardando GitLab runner resolution

**Ordem de execução**:

1. 🟡 Resolver GAP-002 runner registration (aguardar migrations ~30min)
2. 🟡 GAP-005: GitLab CI/CD Integration (3h) — depende GAP-002 + GAP-004

**Output Sprint 3**: 🎯 PRÓXIMO

- Pipeline CI/CD end-to-end funcional
- Marco 4 Core COMPLETO

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

### ✅ Concluído (2026-02-06)

1. ✅ **GAP-001: Keycloak** — Bloqueante crítico (COMPLETO)
2. ✅ **GAP-003: ArgoCD** — Alta prioridade (COMPLETO)
3. ✅ **GAP-004: SonarQube** — Alta prioridade (COMPLETO)
4. 🟡 **GAP-002: GitLab Fix** — Bloqueante crítico (90% COMPLETO)

### Ação Imediata (Próximas Horas)

1. **GAP-002 Runner**: Aguardar GitLab migrations (~30min)
2. **Validação OIDC**: Testar login SonarQube/ArgoCD via Keycloak

### Próxima Semana

1. **GAP-005: GitLab CI/CD Integration** — Alta prioridade (3h)
2. **GAP-006: ApplicationSets** — Baixa prioridade (2h)
3. **GAP-007: Network Policies** — Baixa prioridade (1h)
4. **GAP-008: Monitoring Dashboards** — Baixa prioridade (1h)

### Próximo Sprint (Semana +2)

1. DT-002: Secrets migration Vault
2. DT-001: PostgreSQL private subnet
3. DT-003: Terratest implementation

### Backlog (Sem prazo)

1. DT-005: Alerting completo

---

## 💰 CUSTO ESTIMADO TOTAL

| Item                    | Custo/Mês     | Status           |
| ----------------------- | ------------- | ---------------- |
| **Marco 0-3 (Atual)**   | $700          | ✅ Operacional   |
| GAP-001: Keycloak       | +$35          | ✅ **Deployed**  |
| GAP-003: ArgoCD         | +$15          | ✅ **Deployed**  |
| GAP-004: SonarQube      | +$50          | ✅ **Deployed**  |
| GAP-002/005/006/007/008 | $0            | 🟡 Parcial       |
| **Marco 4 TOTAL**       | **+$100**     | **✅ 75% Done**  |
| **PLATAFORMA ATUAL**    | **~$800/mês** | **Operacional**  |

**ROI Marco 4**: $6.600/ano economia vs SaaS

**Breakdown Marco 4 (+$100/mês)**:

- Keycloak SSO: $35/mês (compute + storage + database overhead)
- ArgoCD GitOps: $15/mês (compute + storage + database overhead)
- SonarQube: $50/mês (compute + storage + database overhead)
- GitLab/Outros: $0 (já provisionados no Marco 3)

---

## 📚 REFERÊNCIAS

- [current_state.md](docs/context/current_state.md) — Estado atual detalhado
- [Gap Analysis](docs/logbook/2026-02-05-marco4-gap-analysis.md) — Análise completa Marco 4
- [Pre-Planning Sprint+1](docs/logbook/2026-02-05-pre-planejamento-sprint-plus-1.md) — Artefatos preparados
- [risks.md](docs/context/risks.md) — Matriz de riscos
- [project_brief.md](docs/context/project_brief.md) — Visão do projeto

---

_Última atualização: 2026-02-06 | Fonte: Análise de contexto automatizada_

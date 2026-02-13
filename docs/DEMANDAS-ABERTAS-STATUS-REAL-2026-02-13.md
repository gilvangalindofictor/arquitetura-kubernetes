# Demandas Abertas - Status Real Auditado (2026-02-13)

**Data da Auditoria:** 2026-02-13 15:00 BRT
**Executor:** Orquestrador DevOps
**Método:** Verificação real cluster K8s + documentos + logs

---

## 🔴 CRÍTICO - Ação Imediata Necessária

### 1. 🚨 **SonarQube EBS Volume Perdido** (NOVO - Descoberto hoje)
- **Status:** 🔴 BROKEN (EBS volume deletado)
- **Root Cause:** Volume `vol-04fcd44f4ac758f9b` não existe mais na AWS
- **Sintoma:** Pod stuck em `Init:0/2` por 1h (FailedAttachVolume)
- **Impacto:** SonarQube inoperante, dados perdidos
- **Tempo Estimado:** 1-2h (recreate PVC + restore database)
- **Prioridade:** URGENTE
- **Arquivo:** Novo problema não documentado
- **Ação:**
  1. Delete PVC atual (bound to inexistente volume)
  2. Recreate PVC (novo EBS volume gp3 será criado)
  3. Restore database do RDS (schema existe)
  4. Reiniciar pod SonarQube
  5. Reconfigurar admin/settings

---

### 2. **Data Services - Decisões Pendentes** (Deadline: Esta Semana)
- **Status:** ⏳ AGUARDANDO DECISÃO CTO
- **Impacto:** Compliance risk (backup gap Redis/RabbitMQ)
- **Tempo:** 2-3 semanas se Velero aprovado
- **Sub-tarefas:**
  - [ ] CTO DECISION: Implementar Velero vs. Aceitar gap
  - [ ] Criar ADR PostgreSQL RDS vs K8s Operator
  - [ ] Atualizar VERSION-CONTROL.md (Spotahome vs OT-Container-Kit)
  - [ ] Documentar estratégia backup final
- **Arquivo:** [STAGING-ANALYSIS-FINDINGS.md](domains/data-services/docs/STAGING-ANALYSIS-FINDINGS.md)

---

### 3. **Keycloak - Persistir Terraform Changes** (30min)
- **Status:** ⚠️ HOTFIX APLICADO, TF DRIFT
- **Contexto:** Startup resilience fix aplicado via K8s patch (2026-02-13)
- **Impacto:** Changes serão perdidos em próximo `terraform apply`
- **Ação:**
  - [ ] Run `terraform apply` em `environments/staging`
  - [ ] Validar keycloak-0 startup após apply
  - [ ] Considerar aplicar pattern em produção
- **Arquivo:** [2026-02-13-keycloak-startup-fix.md](docs/logbook/2026-02-13-keycloak-startup-fix.md)

---

## ⚠️ ALTA PRIORIDADE - Gaps Não Implementados

### 4. **GAP-005: GitLab CI/CD Integration** (3h)
- **Status:** ❌ NÃO INICIADO
- **Dependências:** ✅ GAP-002 resolvido, ✅ GAP-004 resolvido (mas quebrado)
- **Bloqueio:** Runner requer authentication token (GitLab 17.x workflow)
- **Sub-tarefas:**
  - [ ] Acessar GitLab Admin UI (port-forward)
  - [ ] Criar authentication token (Admin → CI/CD → Runners)
  - [ ] Atualizar secret `gitlab-gitlab-runner-secret`
  - [ ] Configurar CI/CD variables (Harbor, SonarQube)
  - [ ] Criar `.gitlab-ci.yml` templates (build, test, scan, deploy)
  - [ ] Runner RBAC least-privilege
  - [ ] Validação pipeline end-to-end
- **Arquivo:** [PROJECT-CONTEXT.md](PROJECT-CONTEXT.md#L602-L606)

---

### 5. **GAP-006: ApplicationSets GitOps Patterns** (2h) - OPCIONAL
- **Status:** ❌ NÃO INICIADO
- **Prioridade:** 🟢 BAIXA (hardening, não bloqueante)
- **Descrição:** Patterns avançados ArgoCD ApplicationSets
- **Arquivo:** [PROJECT-CONTEXT.md](PROJECT-CONTEXT.md#L609)

---

### 6. **GAP-008: Monitoring & Dashboards Marco 4** (1h) - OPCIONAL
- **Status:** ❌ NÃO INICIADO
- **Prioridade:** 🟢 BAIXA (pós-deploy enhancement)
- **Descrição:** Dashboards específicos Marco 4 (GitLab, SonarQube, ArgoCD)
- **Arquivo:** [PROJECT-CONTEXT.md](PROJECT-CONTEXT.md#L611)

---

## ✅ RESOLVIDO - Atualizar Documentação

### 7. ✅ **GAP-002: GitLab Components Fix** (RESOLVIDO 2026-02-13)
- **Status:** ✅ 95% COMPLETO
- **Resolução:** DNS fix aplicado, todos componentes Running
- **Componentes:**
  - ✅ Gitaly: Running (2026-02-06)
  - ✅ KAS: Running (2026-02-06)
  - ✅ Sidekiq: Running (2026-02-06)
  - ✅ Webservice: Running (2026-02-06)
  - ✅ Runner DNS: Fixed (2026-02-13)
  - ⏸️ Runner Registration: Diferido para GAP-005
- **Ação:** ✅ PROJECT-CONTEXT.md atualizado
- **Arquivo:** [2026-02-13-gitlab-runner-dns-fix.md](docs/logbook/2026-02-13-gitlab-runner-dns-fix.md)

---

### 8. ✅ **GAP-003: ArgoCD Deploy** (RESOLVIDO 2026-02-06)
- **Status:** ✅ 100% COMPLETO
- **Deployment:** ArgoCD v5.51.6 (v2.9.3), 8 pods Running
- **Features:**
  - ✅ PostgreSQL RDS integration
  - ✅ OIDC Keycloak integration
  - ✅ RBAC (argocd-admins group)
  - ✅ AppProjects (platform, applications)
  - ✅ HA (2 replicas server/repo-server)
- **Ação:** ✅ Nenhuma - documentação OK
- **Arquivo:** [2026-02-06-argocd-gitops-deployment.md](docs/logbook/2026-02-06-argocd-gitops-deployment.md)

---

### 9. ⚠️ **GAP-004: SonarQube Deploy** (RESOLVIDO 2026-02-06, QUEBRADO 2026-02-13)
- **Status Original:** ✅ 100% COMPLETO (2026-02-06)
- **Status Atual:** 🔴 BROKEN (EBS volume deletado hoje)
- **Deployment:** SonarQube 10.3.0, Helm chart deployed
- **Problema:** Ver item #1 (SonarQube EBS Volume Perdido)
- **Ação:** 🚨 Recuperação urgente necessária
- **Arquivo:** [2026-02-06-sonarqube-deployment.md](docs/logbook/2026-02-06-sonarqube-deployment.md)

---

### 10. ✅ **GAP-007: Tempo OTLP Integration** (RESOLVIDO 2026-02-10)
- **Status:** ✅ 100% COMPLETO
- **Features:**
  - ✅ OTLP receivers 4317/4318 ativos
  - ✅ Replication factor fix (RF=2)
  - ✅ Trace generator operacional
  - ✅ Helm REV 6 estável
- **Ação:** ✅ Nenhuma - documentação OK
- **Arquivo:** [2026-02-10-gap007-tempo-otlp.md](docs/logbook/2026-02-10-gap007-tempo-otlp.md)

---

## 🟡 MÉDIA PRIORIDADE - Investigação & Manutenção

### 11. **Investigação de Versões Data Services** (6-8h)
- **Status:** ⏸️ PLANEJADO
- **Sub-tarefas:**
  - [ ] Redis 6.2.6 → 7.2 evaluation (breaking changes)
  - [ ] RabbitMQ 3.13 → 4.1 evaluation (compatibility)
  - [ ] Spotahome Operator 3.3.0 → 4.x upgrade path
- **Responsável:** DevOps
- **Deadline:** Esta/Próxima semana
- **Arquivo:** [STAGING-ANALYSIS-FINDINGS.md](domains/data-services/docs/STAGING-ANALYSIS-FINDINGS.md#L168-L176)

---

### 12. **Observability - Sprint 3 Finalização** (2h)
- **Status:** ⏸️ PENDENTE
- **Sub-tarefas:**
  - [ ] Configurar derived fields Loki → Tempo (30min)
  - [ ] Validar metrics generator exemplars (1h)
  - [ ] Documentar runbooks troubleshooting (30min)
- **Arquivo:** [current_state.md](docs/context/current_state.md#L62-L65)

---

## 🟢 BAIXA PRIORIDADE - Hardening (Sprint+1)

### 13. **Remediação de Gaps (Sprint+1)** (15-20h)
- **Status:** ⏸️ DIFERIDO
- **Sub-tarefas:**
  - [ ] RBAC Granular (4 domínios)
  - [ ] Network Policies (6 domínios)
  - [ ] Velero Credentials → Vault
  - [ ] HPA/VPA (após 2 semanas métricas)
- **Arquivo:** [PROJECT-CONTEXT.md](PROJECT-CONTEXT.md#L613-L617)

---

### 14. **Quickstart - Itens Diferidos** (Não Bloqueante Staging)
- **Status:** ⏸️ DIFERIDO MVP
- **Sub-tarefas:**
  - [ ] ALB WAF OWASP rules (economia quickstart)
  - [ ] IP allowlist ALB (staging interno)
  - [ ] DR Drill executado (não obrigatório staging)
- **Arquivo:** [QUICKSTART-RECONCILIATION-2026-02-12.md](docs/infrastructure/QUICKSTART-RECONCILIATION-2026-02-12.md#L189-L205)

---

## 📝 DOCUMENTAÇÃO PENDENTE

### 15. **TODOs de Documentação** (2-3h)
- [ ] Comentar outputs.tf quebrados (staging/prod)
- [ ] Integrar verificação ao vivo em STAGING-ANALYSIS-FINDINGS.md
- [ ] Fix Terraform module outputs (postgresql, redis)
- **Prioridade:** 🟢 BAIXA (não bloqueante)

---

## 📊 RESUMO EXECUTIVO

### Status Consolidado

| Categoria | Quantidade | Tempo Estimado | Status |
|-----------|-----------|----------------|--------|
| 🔴 **CRÍTICO** | 3 tarefas | 4-8h + decisão CTO | 🚨 Ação imediata |
| ⚠️ **ALTA** | 3 tarefas | 6h | ⏸️ Aguardando |
| ✅ **RESOLVIDO** | 4 tarefas | - | ✅ Documentar |
| 🟡 **MÉDIA** | 2 tarefas | 8-10h | ⏸️ Planejado |
| 🟢 **BAIXA** | 3 tarefas | 17-23h | ⏸️ Diferido |

**Total:** 15 demandas | **Novos Problemas:** 1 (SonarQube) | **Resolvidos Hoje:** 1 (GAP-002)

---

## 🎯 RECOMENDAÇÃO DE AÇÃO IMEDIATA

### Esta Tarde (2026-02-13)
1. 🚨 **SonarQube Recovery** (1-2h) - URGENTE
2. ✅ **Commit GAP-002 resolution** (5min)
3. ⚠️ **Keycloak Terraform apply** (30min)

### Esta Semana
4. ✅ **Decisão CTO sobre Velero** (reunião)
5. ⚠️ **GAP-005: GitLab CI/CD** (3h)
6. 📝 **Documentar ADRs pendentes** (2h)

### Próximas 2 Semanas
7. 🟡 **Investigação versões data services** (6-8h)
8. 🟡 **Observability finalização** (2h)
9. 🟢 **Hardening opcional** (conforme demanda)

---

## 🔄 DISCREPÂNCIAS CORRIGIDAS

### Documentos Atualizados
1. ✅ PROJECT-CONTEXT.md - GAP-002 marcado resolvido
2. ✅ DEMANDAS-ABERTAS-STATUS-REAL-2026-02-13.md - Este arquivo (novo)
3. ⏳ MEMORY.md - Atualizar padrão SonarQube volume recovery

### Descobertas Importantes
- ✅ **GAP-003 (ArgoCD):** COMPLETO em 2026-02-06 (não estava na lista)
- ✅ **GAP-004 (SonarQube):** COMPLETO em 2026-02-06, mas QUEBRADO hoje
- ✅ **GAP-007 (Tempo OTLP):** COMPLETO em 2026-02-10 (não estava listado)
- 🔴 **SonarQube EBS Volume:** NOVO PROBLEMA descoberto hoje (crítico)

---

**Próximo Review:** 2026-02-14 (após SonarQube recovery)
**Responsável:** Orquestrador DevOps
**Aprovação:** Aguardando user review

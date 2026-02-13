# Demandas Abertas - Status Real Auditado (2026-02-13)

**Data da Auditoria:** 2026-02-13 15:00 BRT (atualizado 18:00 BRT)
**Executor:** Orquestrador DevOps
**Método:** Cross-check AWS real + K8s real + documentação

**⚠️ ATUALIZAÇÃO 18:00 BRT:** Revalidação AWS/K8s completa identificou:
- ✅ 4 itens JÁ FEITOS (não documentados): +R$ 3.744/ano
- 🔴 2 problemas NOVOS descobertos: GitLab KAS/Runner quebrados
- 📊 Savings total ATUALIZADO: R$ 34.752,80/ano (vs R$ 31.200,80 anterior)

**✅ ATUALIZAÇÃO 16:04 BRT - FinOps P0 COMPLETO:**
- ✅ nginx-test ALB deletion confirmada (6 ALBs ativos)
- ✅ echo-server ALB deletion confirmada (namespace absent)
- ✅ Orphan detector Lambda functional (0 orphans found)
- 📊 Savings P0: R$ 2.920/ano
- 📊 **TOTAL ACUMULADO: R$ 37.172,80/ano** (59% roadmap)

**Referências:**
- [REVALIDACAO-AWS-K8S-2026-02-13.md](REVALIDACAO-AWS-K8S-2026-02-13.md)
- [2026-02-13-finops-p0-execution.md](docs/logbook/2026-02-13-finops-p0-execution.md)

---

## 🔴 CRÍTICO - Ação Imediata Necessária

### 1. ✅ **SonarQube EBS Volume Perdido** (RESOLVIDO 2026-02-13 14:10 BRT)
- **Status Original:** 🔴 BROKEN (EBS volume deletado)
- **Status Atual:** ✅ **RECUPERADO** (1h15min recovery time)
- **Root Cause:** Volume `vol-04fcd44f4ac758f9b` deletado durante cleanup orphan resources
- **Solução Aplicada:**
  1. ✅ PVC/PV recreados (novo volume gp3 20GB: `pvc-aa3c540a-5119-4017-88e6-9114755059ee`)
  2. ✅ ExternalName service criado (`postgresql-external` → RDS endpoint)
  3. ✅ Liveness probe ajustado (8min tolerance para first boot)
  4. ✅ Pod status: **1/1 Running** (SonarQube operational)
  5. ✅ UI acessível (HTTP 200 confirmado)
- **Data Loss:** Filesystem only (database schema preservado)
- **Logbook:** [2026-02-13-sonarqube-volume-recovery.md](docs/logbook/2026-02-13-sonarqube-volume-recovery.md)

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

### 3. ⚠️ **GitLab KAS/Runner - Parcialmente Resolvido** (2026-02-13 18:00-18:30 BRT)
- **Status:** ✅ **KAS RESOLVIDO** | ⚠️ **Runner bloqueado (cluster capacity)**
- **Problema 1:** ✅ GitLab KAS - **RESOLVIDO**
  - Erro original: `lookup rfrm-redis.data-services.svc.cluster.local: no such host`
  - Fix aplicado: 6 ConfigMaps atualizados (`rfrm-redis` → `redis`)
  - Status atual: **2/2 Running** (gitlab-kas-6b5dc5cb7c-kq99c, gitlab-kas-6b5dc5cb7c-s296f)
- **Problema 2:** ⚠️ GitLab Runner - **BLOQUEADO**
  - Status: 0/1 CrashLoop (registration 500 error)
  - Bloqueio: Webservice rollout stuck (insufficient CPU/Memory cluster)
  - Runner tentativa: 14/30 (aguardando webservice restart)
  - ETA: 1-2h (após scale cluster OU runner atingir 30 tentativas)
- **Root Cause:** Redis operator migration (2026-02-13) esqueceu atualizar GitLab ConfigMaps
  - Service antigo: `rfrm-redis.data-services.svc.cluster.local` (SpotaHome - deletado)
  - Service atual: `redis.data-services.svc.cluster.local` (OT-Container-Kit)
- **Fixes Aplicados:**
  1. ✅ 6 ConfigMaps atualizados via kubectl patch
  2. ✅ Redis RDB persist fix (chown 999:999 /data)
  3. ✅ GitLab deployments restarted
  4. ⚠️ Webservice rollout bloqueado (cluster capacity)
- **Impacto Atual:**
  - ✅ GitLab Agent for Kubernetes (KAS) **ONLINE** (2/2 Running)
  - ⚠️ GitLab CI/CD offline (runner aguardando webservice)
  - ⚠️ GAP-005 bloqueado até runner recovery
- **Próxima Ação:**
  - Scale cluster (add 1 worker) OU aguardar runner 30 tentativas
- **Arquivo:** [gitlab-redis-dns-troubleshooting.md](logbook/2026-02-13-gitlab-redis-dns-troubleshooting.md)

---

### 4. ✅ **Keycloak - Terraform State Verified** (RESOLVIDO 2026-02-13 18:45 BRT)
- **Status Original:** ⚠️ HOTFIX APLICADO, TF DRIFT
- **Status Atual:** ✅ **SINCRONIZADO** (zero drift confirmado)
- **Contexto:** Hotfix aplicado 2026-02-13: initContainer wait-for-db, startupProbe 60 failures, health-enabled
- **Verificação:**
  - ✅ Terraform plan shows zero changes (keycloak module)
  - ✅ Pod status: 1/1 Running, 0 restarts, 4h uptime
  - ✅ All 3 hotfixes confirmed active
  - ✅ Health endpoints returning HTTP 200
- **Conclusão:** Fixes JÁ estavam persistidos no Terraform desde 2026-02-13 apply
- **Arquivo:** [2026-02-13-keycloak-startup-fix.md](docs/logbook/2026-02-13-keycloak-startup-fix.md)

---

## ⚠️ ALTA PRIORIDADE - Gaps Não Implementados

### 5. **GAP-005: GitLab CI/CD Integration** (3h)
- **Status:** ⏸️ BLOQUEADO por GitLab KAS/Runner crashes (item #3)
- **Dependências:**
  - ✅ GAP-002 resolvido
  - ✅ GAP-004 resolvido
  - 🔴 **BLOQUEIO:** GitLab Runner crashloop + KAS offline (fix item #3 primeiro)
- **Bloqueio Original:** Runner requer authentication token (GitLab 17.x workflow)
- **Bloqueio Descoberto:** Runner registration retorna 500 (webservice internal error por Redis DNS)
- **Sub-tarefas (após fix item #3):**
  - [ ] ✅ Fix GitLab Redis DNS (item #3)
  - [ ] Validar Runner auto-recovery
  - [ ] Se persistir 500: investigar webservice logs
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

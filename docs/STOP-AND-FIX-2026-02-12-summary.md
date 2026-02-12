# 🛑 STOP-AND-FIX Summary — 2026-02-12

**Duração**: 2h30min (14:47 - 17:17 BRT)
**Objetivo Original**: GitLab OIDC Integration (Task#1 Quickstart MVP)
**Resultado**: Incompleto (fresh deploy parcial, GitLab não functional)

---

## 🎯 Problemas Raiz Identificados e Resolvidos

### 1. EBS Volumes Orphan (Cleanup 2026-02-11)
- **Causa**: Cleanup de volumes orphan deletou volumes ainda referenciados por PVCs
- **Impacto**: Gitaly + Redis PVCs corrompidos → pods ContainerCreating infinito
- **Fix**: Scale StatefulSet→0, delete PVC, recreate com volume novo
- **Lição**: Sempre validar PVC usage antes de deletar volumes (kubectl get pvc -A -o yaml | grep volumeName)

### 2. Redis Password Mismatch (PVC Wipe)
- **Causa**: PVC delete reset Redis data → password armazenado perdido
- **Impacto**: GitLab pods não conseguem conectar ao Redis
- **Workaround Temporário**: Copy secret cross-namespace
- **Fix Definitivo**: Fresh deploy com secrets gerenciados pelo Terraform

### 3. Cluster Sem Capacidade (Workloads Órfãos)
- **Causa**: Namespaces órfãos (gitlab, harbor-system, keycloak) com pods 15h ocupando CPU/mem
- **Impacto**: Insufficient CPU (5 nodes), Insufficient Memory (2 nodes), Too many pods (2 nodes)
- **Fix**: Delete namespaces órfãos → liberou 40-60% recursos
- **Lição**: Implementar cleanup automático de namespaces Terminating >1h

### 4. Secrets Cross-Namespace
- **Causa**: Módulo GitLab espera secrets em `gitlab-staging`, mas foram criados em `data-services`
- **Impacto**: Pods Init:0/X aguardando secrets mount
- **Workaround**: Copy secrets manualmente
- **Fix Definitivo**: Ajustar módulo Terraform para criar secrets no namespace correto

### 5. Secret OIDC Missing
- **Causa**: Módulo Keycloak não foi aplicado (TF apply com -target apenas gitlab/redis/rabbitmq)
- **Impacto**: Webservice Init:0/3 aguardando `gitlab-oidc-keycloak` secret
- **Workaround**: Create placeholder secret
- **Fix Definitivo**: Apply full Terraform (incluir módulo keycloak_staging)

### 6. Migrations Wait-For-Deps Timeout
- **Causa**: Migrations esperando PostgreSQL/Redis, mas connection fail (ainda investigando)
- **Impacto**: CrashLoopBackOff → bloqueia webservice deployment
- **Status**: NÃO RESOLVIDO
- **Próximos Passos**: Verificar PostgreSQL RDS connectivity, Redis auth, network policies

---

## 📊 Estado Atual do Cluster

### Pods GitLab (gitlab-staging)

| Component       | Status         | Ready | Restarts | Detalhes                              |
| --------------- | -------------- | ----- | -------- | ------------------------------------- |
| gitaly          | ✅ Running     | 1/1   | 0        | PVC novo functional                   |
| kas             | ✅ Running     | 2/2   | 0        | HA pods ambos UP                      |
| registry        | ✅ Running     | 2/2   | 0        | HA pods ambos UP                      |
| shell           | ✅ Running     | 2/2   | 0        | SSH gateway functional                |
| exporter        | ✅ Running     | 1/1   | 0        | Metrics export OK                     |
| migrations      | ❌ CrashLoop   | 0/1   | 3        | wait-for-deps timeout                 |
| webservice      | ⚠️ Init:0/3    | 0/2   | 0        | Aguardando migrations completar       |
| sidekiq         | ⚠️ Init:0/3    | 0/1   | 0        | Aguardando migrations completar       |
| runner          | ⚠️ Running     | 0/1   | 9        | Aguardando webservice para se registrar |

**Bloqueador**: Migrations CrashLoop impede webservice/sidekiq init

### Data Services (data-services)

| Component | Status      | Ready | Replicas | Detalhes                 |
| --------- | ----------- | ----- | -------- | ------------------------ |
| Redis     | ✅ Running  | 5/5   | 1+3+1    | Master + Sentinels + Repl |
| RabbitMQ  | ✅ Running  | 1/1   | 1        | Staging single-node      |

### Recursos Deletados

| Namespace          | Motivo                            | Age  |
| ------------------ | --------------------------------- | ---- |
| gitlab             | Órfão (Helm travado REV 4)        | 15h  |
| harbor-system      | Órfão (CrashLoop sem uso)         | 15h  |
| keycloak           | Órfão (CrashLoop DB issue)        | 15h  |
| data-services-prod | Request usuário (limpar staging)  | 2d   |

---

## 🔧 Terraform Apply Result

**Comando**: `terraform apply -target=module.gitlab_staging -target=module.redis_staging -target=module.rabbitmq_staging`
**Exit Code**: 1 (AWS credentials expired durante apply)
**Duração**: 20min
**Recursos Criados**: 24/26 (parcial success)

### Recursos OK

- ✅ Namespace data-services
- ✅ Namespace gitlab-staging
- ✅ Redis Operator + StatefulSet
- ✅ RabbitMQ Operator + StatefulSet
- ✅ GitLab Helm release (parcial - pods não completaram init)
- ✅ Secrets redis-password, gitlab-postgresql-password (em data-services)

### Recursos Missing

- ❌ Secret gitlab-oidc-keycloak (módulo keycloak_staging não aplicado)
- ❌ Keycloak deployment (módulo não incluído no -target)
- ❌ Harbor deployment (namespace deletado, módulo não reaplicado)

---

## 📚 Lições Aprendidas

### 1. Fresh Deploy ≠ Solução Rápida
- **Problema**: Fresh deploy pareceu mais rápido que fix pontual
- **Realidade**: 2h30min sem completar, múltiplos bloqueadores cascata
- **Lição**: Fresh deploy staging aceitável, mas requer ALL módulos (não -target)

### 2. PVC Delete Catastrophic
- **Problema**: Deletar PVC parece cleanup inocente
- **Realidade**: Perde dados persistentes (Redis auth, Gitaly repos)
- **Lição**: SEMPRE backup antes PVC delete, ou snapshot EBS volume

### 3. Orphan Resources Cascade
- **Problema**: Cleanup de volumes orphan (2026-02-11) pareceu seguro
- **Realidade**: Volumes "orphan" ainda tinham PVCs ativos (não detectados)
- **Lição**: Validar `kubectl get pvc -A -o yaml | grep <volume-id>` ANTES de deletar

### 4. Cluster Capacity Invisible
- **Problema**: Pods Pending sem erro claro
- **Realidade**: Workloads órfãos 15h ocupando recursos
- **Lição**: Implementar alertas capacity + cleanup automático NS Terminating >1h

### 5. Cross-Namespace Secrets Frágil
- **Problema**: Módulos criando secrets em namespace errado
- **Realidade**: Terraform module design inconsistent
- **Lição**: Enforcar secret creation no mesmo namespace do consumer

### 6. -target Apply Perigoso
- **Problema**: -target gitlab_staging sem keycloak_staging
- **Realidade**: Dependencies não satisfeitas (OIDC secret missing)
- **Lição**: Evitar -target, ou mapear TODAS dependencies manualmente

---

## 🚀 Próximos Passos (Próxima Sessão)

### Opção A: Completar Fresh Deploy (2-3h)

**Approach**: Completar o deploy iniciado

1. **Resolver Migrations Dependency**
   - Verificar PostgreSQL RDS connectivity (DNS, SG, IAM)
   - Verificar Redis auth (password correct?)
   - Check network policies (allow gitlab-staging → data-services)
   - Logs detalhados: `kubectl logs migrations -c dependencies`

2. **Apply Keycloak Module**
   ```bash
   terraform apply -target=module.keycloak_staging
   ```
   - Cria secret gitlab-oidc-keycloak correto
   - Deploy Keycloak pods

3. **Validar GitLab E2E**
   - Migrations complete → webservice Running
   - Runner se registra → pipeline test OK
   - OIDC login (após Keycloak UP)

**Pros**: Resolve TODOS problemas definitivamente
**Cons**: Ainda pode levar 2-3h, risco de novos bloqueadores

### Opção B: Abort Fresh Deploy + Fix Incremental (1-2h)

**Approach**: Deletar gitlab-staging novamente, usar ambiente pré-existente

1. **Cleanup Fresh Deploy Incompleto**
   ```bash
   kubectl delete namespace gitlab-staging data-services --wait=true
   ```

2. **Restaurar Ambiente Anterior (se backup existe)**
   - Ou: Re-deploy apenas GitLab via Helm direto (bypass Terraform)
   - Helm install gitlab com values corretos (sem OIDC primeiro)

3. **OIDC Incremental**
   - Deploy Keycloak standalone
   - Configure OIDC no GitLab via Helm values
   - Test E2E

**Pros**: Menor risco, rollback fácil
**Cons**: Não resolve root causes, pode ter mesmos problemas

### Opção C: Postergar GitLab, Focar Node Upgrade + E2E App (6h)

**Approach**: Pular Task#1 (GitLab OIDC), focar Tasks críticas MVP

1. **Task#2**: Node Groups v1.34 (1h30min) ← Não bloqueante, pode executar
2. **Task#3**: E2E Smoke Test App (3h) ← Requer GitLab CI/CD → BLOQUEADO
3. **Task#4**: FinOps Dashboards (2h) ← Não bloqueante, pode executar
4. **Task#5**: FinOps Automation (1h) ← Não bloqueante, pode executar

**Pros**: Avança MVP (Tasks 2,4,5), economiza tempo
**Cons**: Task#3 (crítica) bloqueada sem GitLab

---

## 🎯 Recomendação

**Opção A (Completar Fresh Deploy)** se:
- Objetivo é resolver TODOS problemas definitivamente
- Disponível 3-4h contínuas
- Prioridade em GitLab functional

**Opção C (Postergar GitLab)** se:
- Quickstart MVP precisa avançar rápido (75% → 85%)
- GitLab OIDC pode ser Fase 2
- Tasks 2,4,5 desbloqueiam valor (Node upgrade, FinOps dashboards)

---

## 📂 Arquivos Atualizados

- ✅ `docs/logbook/2026-02-12-quickstart-mvp-completion.md` - Timeline completa STOP-AND-FIX
- ✅ `docs/STOP-AND-FIX-2026-02-12-summary.md` (este arquivo) - Resumo executivo
- ⏸️ `docs/STATUS-2026-02-12.md` - Pendente atualização (estado cluster mudou)

---

**Documentado**: 2026-02-12 17:20 BRT
**Próxima Sessão**: TBD (aguardando decisão abordagem)

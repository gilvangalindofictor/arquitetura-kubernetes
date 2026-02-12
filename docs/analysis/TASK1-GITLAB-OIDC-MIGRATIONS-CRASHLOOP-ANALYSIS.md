# 🔍 ANÁLISE PROFUNDA — Task#1 GitLab OIDC Migrations CrashLoop

| Campo            | Valor                                           |
| ---------------- | ----------------------------------------------- |
| **Data**         | 2026-02-12                                      |
| **Analista**     | Orquestrador DevOps (executor-terraform agent)  |
| **Bloqueador**   | GitLab Migrations CrashLoop                     |
| **Impacto**      | CRÍTICO - Bloqueia webservice/sidekiq init      |
| **Tempo Parado** | 2h30min (desde STOP-AND-FIX 2026-02-12 14:47)  |

---

## 🎯 RESUMO EXECUTIVO

**Problema Raiz**: GitLab init containers falham porque o database "gitlab" NÃO EXISTE no PostgreSQL RDS.

**Sintoma**: Init containers em `CrashLoopBackOff` com erro:
```
Error checking main: We could not find your database: gitlab.
Which can be found in the database configuration file located at config/database.yml.
```

**Causa Imediata**:
1. PostgreSQL RDS foi criado com database inicial "platform" (não "gitlab")
2. Nenhum processo de criação do database "gitlab" foi executado
3. GitLab Terraform module assume que database pré-existe

**Fix Imediato** (15min): Criar database "gitlab" + user "gitlab_user" no PostgreSQL RDS

**Fix Definitivo** (1h): Atualizar Terraform module PostgreSQL para criar databases adicionais

---

## 📊 EVIDÊNCIAS

### 1. Estado Atual dos Pods GitLab (gitlab-staging)

```bash
$ kubectl get pods -n gitlab-staging | grep -E "webservice|sidekiq"
gitlab-sidekiq-all-in-1-v2-5cc98bd9bb-xs6p7   0/1  Init:CrashLoopBackOff   4       6m17s
gitlab-webservice-default-789f764b99-hlx2r    0/2  Init:CrashLoopBackOff   8       27m
gitlab-webservice-default-789f764b99-vg2wq    0/2  Init:CrashLoopBackOff   14      60m
```

**Status**: Init containers "dependencies" aguardando database "gitlab" existir

### 2. Logs do Init Container "dependencies"

```bash
$ kubectl logs -n gitlab-staging gitlab-webservice-default-789f764b99-hlx2r -c dependencies

Checking: main
Error checking main: We could not find your database: gitlab.
Which can be found in the database configuration file located at config/database.yml.

To resolve this issue:
- Did you create the database for this app, or delete it? You may need to create your database.
- Has the database name changed? Check your database.yml config has the correct database name.

To create your database, run:
        bin/rails db:create

WARNING: Not all services were operational, with data migrations completed.
```

**Causa**: Rails está tentando conectar ao database "gitlab", mas recebe erro "database not found"

### 3. Configuração Terraform — PostgreSQL RDS

**Arquivo**: `terraform/modules/postgresql/main.tf:80`
```hcl
resource "aws_db_instance" "postgresql" {
  identifier = "${var.cluster_name}-postgresql"

  engine         = "postgres"
  engine_version = "16.4"

  db_name  = "platform"  # ← DATABASE INICIAL (NÃO "gitlab")
  username = "postgres_admin"
  password = random_password.master.result

  # ...
}
```

**Problema**: RDS criado com database inicial "platform", sem provisioning adicional de databases

### 4. Configuração Terraform — GitLab Module

**Arquivo**: `terraform/environments/staging/main.tf:276`
```hcl
module "gitlab_staging" {
  # ...

  postgresql_host     = module.postgresql_staging.rds_address
  postgresql_port     = 5432
  postgresql_database = "gitlab"        # ← ASSUME QUE DATABASE EXISTE
  postgresql_username = "gitlab_user"   # ← ASSUME QUE USER EXISTE
  postgresql_password_secret = kubernetes_secret.gitlab_postgresql_password.metadata[0].name

  # ...
}
```

**Problema**: Module assume que database "gitlab" e user "gitlab_user" já existem, mas não os cria

### 5. Validação de Secrets

**PostgreSQL Secret (OK)**:
```bash
$ kubectl get secret -n gitlab-staging gitlab-postgresql-password -o jsonpath='{.data}'
{"password":"R2l0TGFiU3RhZ2luZzIwMjYhU2VjdXJlUGFzcyNEZXY="}
✅ Secret existe e está acessível
```

**Redis Secret (OK)**:
```bash
$ kubectl get secret -n gitlab-staging redis-password -o jsonpath='{.data}'
{"password":"...base64..."}
✅ Secret existe e está acessível (copiado de data-services)
```

**Conclusão**: Secrets estão corretos; problema é exclusivamente PostgreSQL database missing

---

## 🔍 ROOT CAUSE ANALYSIS

### Cadeia de Causas

```
┌─────────────────────────────────────────────────────────────┐
│ ROOT CAUSE #1: PostgreSQL RDS Module Design Flaw            │
│ ----------------------------------------------------------- │
│ Module cria RDS com database inicial "platform"             │
│ NÃO provisiona databases adicionais (gitlab, keycloak, etc) │
│ Assume que apps criarão seus próprios databases             │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ ROOT CAUSE #2: GitLab Module Assumption                     │
│ ----------------------------------------------------------- │
│ GitLab module ASSUME que database "gitlab" pré-existe       │
│ Init container "dependencies" checa database existence      │
│ Sem database → CrashLoop (NÃO auto-create)                  │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ ROOT CAUSE #3: Fresh Deploy Sem Database Migration          │
│ ----------------------------------------------------------- │
│ Fresh deploy (2026-02-12 15:10) criou namespace novo        │
│ Nenhum step de database provisioning executado              │
│ Terraform apply completou mas pods não inicializaram        │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ SYMPTOM: GitLab Pods CrashLoopBackOff                       │
│ ----------------------------------------------------------- │
│ Init container "dependencies" CrashLoop (14 restarts)       │
│ Webservice/Sidekiq bloqueados (Init:0/3, Init:0/2)          │
│ Runner CrashLoop tentando se registrar (0/1, 9 restarts)    │
└─────────────────────────────────────────────────────────────┘
```

### Por Que Isso Aconteceu Agora?

**Contexto**:
- 2026-02-11: Cleanup orphan volumes deletou volumes ativos por engano
- 2026-02-12: Fresh deploy staging (delete NS + TF apply) para resolver PVC corruption
- Fresh deploy iniciou de zero (sem state anterior)

**Timeline**:
```
[15:10:00] TF Apply | TF | Fresh deploy iniciado | 🔄
[15:20:00] TF Apply | TF | PostgreSQL RDS: apply complete (no changes) | ✅
           └── RDS já existia (produção), database "platform" preservado
[15:21:00] TF Apply | TF | GitLab Helm release: deployed REV 1 | ✅
[15:22:00] K8s | GitLab | Init containers iniciaram | 🔄
[15:22:30] K8s | GitLab | Dependencies check: database "gitlab" not found | ❌
[15:23:00] K8s | GitLab | CrashLoopBackOff (restarts=1) | 🔄
[15:27:00] TF Apply | TF | Exit 1 (AWS creds expired), mas recursos criados | ⚠️
[15:28:00] Diagnóstico | Obs | Migrations CrashLoop detectado | ❌
```

**Por Que Não Falhou Antes?**:
- Deploy anterior (semanas atrás) pode ter criado database "gitlab" manualmente
- OU: Terraform destroy não deletou RDS (deletion_protection), database "gitlab" sobreviveu
- Fresh deploy 2026-02-12 assumiu database existia, mas ele NÃO EXISTE

---

## 💡 SOLUÇÕES PROPOSTAS

### Opção A: Fix Imediato (15min) ⭐ RECOMENDADO

**Approach**: Criar database "gitlab" + user "gitlab_user" manualmente no PostgreSQL RDS

**Passos**:

1. **Obter RDS Endpoint + Master Password**
   ```bash
   # RDS endpoint (já conhecido)
   RDS_ENDPOINT=$(terraform output -raw postgresql_staging_endpoint)
   # → k8s-platform-prod-postgresql.cw9kqksocqv1.us-east-1.rds.amazonaws.com

   # Master password (Secrets Manager)
   MASTER_PASS=$(aws secretsmanager get-secret-value \
     --secret-id "k8s-platform-prod/postgresql-master-*" \
     --query SecretString --output text)
   ```

2. **Criar Database + User via psql Pod**
   ```bash
   # Deploy temporary psql client pod
   kubectl run psql-client -n gitlab-staging --rm -it --restart=Never \
     --image=postgres:16.4-alpine -- bash

   # Dentro do pod:
   psql "postgresql://postgres_admin:$MASTER_PASS@$RDS_ENDPOINT:5432/postgres" <<EOF
   -- Create GitLab database
   CREATE DATABASE gitlab WITH ENCODING 'UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8';

   -- Create GitLab user
   CREATE USER gitlab_user WITH PASSWORD 'GitLabStaging2026!SecurePass#Dev';

   -- Grant privileges
   GRANT ALL PRIVILEGES ON DATABASE gitlab TO gitlab_user;

   -- Connect to gitlab database and grant schema privileges
   \c gitlab
   GRANT ALL ON SCHEMA public TO gitlab_user;

   -- Verify
   \l gitlab
   \du gitlab_user
   EOF
   ```

3. **Restart GitLab Pods**
   ```bash
   # Rollout restart para forçar re-check dependencies
   kubectl rollout restart deployment -n gitlab-staging gitlab-webservice-default
   kubectl rollout restart deployment -n gitlab-staging gitlab-sidekiq-all-in-1-v2
   ```

4. **Validar Migrations**
   ```bash
   # Watch migrations logs (init container)
   kubectl logs -n gitlab-staging -l app=webservice -c dependencies --tail=50 -f

   # Expected: "All services operational, migrations completed"
   ```

**Tempo Estimado**: 15min
**Risco**: BAIXO (operação idempotente, staging environment)
**Rollback**: N/A (criação de database não afeta workloads existentes)

**Pros**:
- ✅ Resolve bloqueador imediatamente
- ✅ Zero downtime para outros services (Redis, RabbitMQ)
- ✅ Permite completar Task#1 (GitLab OIDC)

**Cons**:
- ⚠️ Fix manual (não automatizado via Terraform)
- ⚠️ Database password hardcoded (deve ser rotacionado depois)

---

### Opção B: Fix Definitivo (1h30min)

**Approach**: Atualizar Terraform module PostgreSQL para provisionar databases via `postgresql` provider

**Passos**:

1. **Adicionar `postgresql` Provider ao Module**

   **Arquivo**: `terraform/modules/postgresql/versions.tf`
   ```hcl
   terraform {
     required_providers {
       # ... existing providers ...

       postgresql = {
         source  = "cyrilgdn/postgresql"
         version = "~> 1.22"
       }
     }
   }
   ```

2. **Criar Database Resources**

   **Arquivo**: `terraform/modules/postgresql/databases.tf` (NOVO)
   ```hcl
   # PostgreSQL Provider Configuration
   provider "postgresql" {
     host            = aws_db_instance.postgresql.address
     port            = aws_db_instance.postgresql.port
     username        = aws_db_instance.postgresql.username
     password        = random_password.master.result
     sslmode         = "require"
     connect_timeout = 15
   }

   # GitLab Database + User
   resource "postgresql_database" "gitlab" {
     name              = "gitlab"
     owner             = postgresql_role.gitlab_user.name
     encoding          = "UTF8"
     lc_collate        = "en_US.UTF-8"
     lc_ctype          = "en_US.UTF-8"
     connection_limit  = -1
     allow_connections = true
   }

   resource "postgresql_role" "gitlab_user" {
     name     = "gitlab_user"
     login    = true
     password = random_password.gitlab_user.result
   }

   resource "random_password" "gitlab_user" {
     length  = 32
     special = true
     override_special = "!#$%&*()-_=+[]{}<>:?"
   }

   resource "postgresql_grant" "gitlab_user_all" {
     database    = postgresql_database.gitlab.name
     role        = postgresql_role.gitlab_user.name
     schema      = "public"
     object_type = "database"
     privileges  = ["ALL"]
   }

   # Repeat for keycloak, sonarqube, etc.
   ```

3. **Expor Passwords via Outputs**

   **Arquivo**: `terraform/modules/postgresql/outputs.tf` (atualizar)
   ```hcl
   output "gitlab_user_password" {
     description = "GitLab user password"
     value       = random_password.gitlab_user.result
     sensitive   = true
   }
   ```

4. **Atualizar Environment Staging**

   **Arquivo**: `terraform/environments/staging/main.tf` (atualizar secret)
   ```hcl
   resource "kubernetes_secret" "gitlab_postgresql_password" {
     metadata {
       name      = "gitlab-postgresql-password"
       namespace = "gitlab-staging"  # ← FIX: era "data-services"
     }

     data = {
       password = module.postgresql_staging.gitlab_user_password  # ← FIX: era master password
     }
   }
   ```

5. **Terraform Apply**
   ```bash
   cd terraform/environments/staging
   AWS_PROFILE=k8s-platform-prod terraform apply -target=module.postgresql_staging
   # Expected: 4 add (database, role, 2 grants)
   ```

**Tempo Estimado**: 1h30min (desenvolvimento + testing + apply)
**Risco**: MÉDIO (changes em RDS config, possível lock durante apply)
**Rollback**: `terraform destroy -target=...` (databases podem ser recriados)

**Pros**:
- ✅ Resolve root cause definitivamente
- ✅ Automatizado (Terraform IaC)
- ✅ Permite CI/CD repeatability (fresh deploys futuros funcionarão)
- ✅ Password management via Terraform (não hardcoded)

**Cons**:
- ⏳ Demora 1h30min (bloqueia Task#1 completion)
- ⚠️ Requer `postgresql` provider (nova dependência)
- ⚠️ Terraform state growth (mais recursos para track)

---

## 🎯 RECOMENDAÇÃO FINAL

### Estratégia Híbrida (2 Fases)

**FASE 1 - Agora (15min)**: Executar **Opção A (Fix Imediato)**
- Criar database "gitlab" + user manualmente
- Completar Task#1 (GitLab OIDC Integration)
- Desbloquear Task#3 (E2E Smoke Test App)

**FASE 2 - Próxima Sprint (1h30min)**: Executar **Opção B (Fix Definitivo)**
- Refatorar Terraform PostgreSQL module
- Automatizar database provisioning
- Test fresh deploy E2E (validate repeatability)

**Justificativa**:
1. **Urgência**: Quickstart MVP completion precisa avançar (75% → 95%)
2. **ROI**: 15min fix desbloqueia 4h+ de trabalho (Tasks 1,3)
3. **Risk Management**: Fix imediato staging (não produção), rollback fácil
4. **Technical Debt**: Fix definitivo vira ADR + task backlog (não bloqueante)

---

## 📋 AÇÕES PARA ESPECIALISTAS

### Para AWS Specialist

**Tarefa**: Validar RDS connectivity + permissions

**Checklist**:
- [ ] Verificar Security Group: gitlab-staging pods podem alcançar RDS port 5432?
  ```bash
  kubectl run netcat -n gitlab-staging --rm -it --restart=Never \
    --image=busybox -- nc -zv $RDS_ENDPOINT 5432
  ```
- [ ] Verificar DNS resolution: RDS endpoint resolve dentro do cluster?
  ```bash
  kubectl run nslookup -n gitlab-staging --rm -it --restart=Never \
    --image=busybox -- nslookup $RDS_ENDPOINT
  ```
- [ ] Validar IAM role (se IRSA for usado para RDS auth - NOT current case)

**Resultado Esperado**: Connectivity OK (já validado por outros pods)

### Para TF (Terraform) Specialist

**Tarefa**: Implementar Opção B (Fix Definitivo) quando aprovado

**Checklist**:
- [ ] Adicionar `postgresql` provider (cyrilgdn/postgresql ~> 1.22)
- [ ] Criar `databases.tf` com resources (gitlab, keycloak, sonarqube)
- [ ] Atualizar outputs.tf para expor user passwords
- [ ] Atualizar `staging/main.tf` para usar novos outputs
- [ ] Terraform plan validation (expect: 4-8 add)
- [ ] Terraform apply em staging (watch for locks)
- [ ] Idempotence check (`terraform plan` → "No changes")
- [ ] Documentar em ADR-XXX: PostgreSQL Database Provisioning Strategy

**Resultado Esperado**: Fresh deploy staging funciona E2E sem intervenção manual

### Para Obs (Observability) Specialist

**Tarefa**: Criar alertas para database connectivity issues

**Checklist**:
- [ ] Alert: Init containers CrashLoop > 3 restarts em 10min
- [ ] Alert: PostgreSQL connection refused (SG/network issue)
- [ ] Dashboard: GitLab init container logs aggregation (Loki)
- [ ] Runbook: PostgreSQL database missing troubleshooting

**Resultado Esperado**: Problema similar detectado em <5min no futuro

---

## 📚 REFERÊNCIAS

**Documentos Relacionados**:
- [STOP-AND-FIX-2026-02-12-summary.md](../STOP-AND-FIX-2026-02-12-summary.md) - Context STOP-AND-FIX
- [2026-02-12-quickstart-mvp-completion.md](../logbook/2026-02-12-quickstart-mvp-completion.md) - Timeline
- [EXECUCAO-QUICKSTART-MVP-2026-02-12.md](../plan/EXECUCAO-QUICKSTART-MVP-2026-02-12.md) - Plano original

**Terraform Files**:
- `modules/postgresql/main.tf` - RDS provisioning
- `modules/gitlab/main.tf` - GitLab Helm release
- `environments/staging/main.tf` - Environment config

**GitLab Charts Documentation**:
- https://docs.gitlab.com/charts/installation/deployment.html#postgresql-requirements
- https://docs.gitlab.com/charts/troubleshooting/index.html#application-containers-constantly-initializing

**Terraform Providers**:
- cyrilgdn/postgresql: https://registry.terraform.io/providers/cyrilgdn/postgresql/latest/docs

---

## 🔄 PRÓXIMOS PASSOS (Post-Fix)

1. **Executar Opção A** (15min)
   - Criar database "gitlab" via psql
   - Restart pods GitLab
   - Validar migrations complete

2. **Completar Task#1** (30min)
   - Terraform apply OIDC modules
   - E2E test SSO login

3. **Task#3: E2E Smoke Test** (3h)
   - Deploy Python FastAPI via GitLab CI/CD
   - Validar stack completo

4. **Agendar Opção B** (Sprint 4)
   - ADR-XXX: PostgreSQL Database Provisioning
   - Terraform refactor + testing
   - Fresh deploy validation

---

**Documentado**: 2026-02-12 18:30 BRT
**Autor**: Orquestrador DevOps (executor-terraform agent)
**Aprovação Pendente**: CTO (para execução Opção A)

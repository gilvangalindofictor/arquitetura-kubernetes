# 📋 Plano de Deprecação: terraform/envs/marco3

| Campo | Valor |
|-------|-------|
| Data criação | 2026-02-03 |
| Status | Aguardando apply GitLab staging |
| Risco | ⚠️ Médio (recursos em produção) |
| Aprovação | Requer validação manual |

---

## 🎯 Objetivo

Deprecar completamente `terraform/envs/marco3/` após migração bem-sucedida para `terraform/environments/staging/`.

---

## 📦 Recursos Gerenciados por Marco3

Baseado em `envs/marco3/main.tf`:

### 1. PostgreSQL RDS
- Instance class: `var.postgresql_instance_class`
- Storage: `var.postgresql_allocated_storage`
- Module: `./modules/postgresql`

### 2. Redis (Spotahome Operator)
- Replicas: `var.redis_replicas`
- PVC size: `var.redis_pvc_size`
- Module: `./modules/redis`

### 3. RabbitMQ (Cluster Operator)
- Replicas: `var.rabbitmq_replicas`
- PVC size: `var.rabbitmq_pvc_size`
- Module: `./modules/rabbitmq`

### 4. S3 Buckets
- GitLab artifacts bucket
- GitLab uploads bucket
- Module: `./modules/s3-buckets`

### 5. GitLab (Helm)
- Edition: CE
- Version: 8.7.0
- Replicas: 2 webservice, 2 runners
- Namespace: `gitlab` (provavelmente)
- Module: `./modules/gitlab`

### 6. Kubernetes Secrets
- `gitlab-postgresql-password` (🚨 hardcoded)

---

## ⚠️ PRÉ-REQUISITOS CRÍTICOS

**ANTES de executar destroy em marco3, GARANTIR:**

1. ✅ GitLab staging deployed e funcional
   - Pods Running em `gitlab-staging` namespace
   - Health checks passando
   - Acesso web OK
   - Runners registrados

2. ✅ Data services staging operacionais
   - PostgreSQL RDS: disponível
   - Redis: master/replica Running
   - RabbitMQ: cluster healthy
   - S3 buckets: criados e acessíveis

3. ✅ Aplicações migradas (se houver)
   - Nenhuma app apontando para GitLab marco3
   - Nenhuma app consumindo data services marco3

4. ✅ Backup de dados críticos
   - PostgreSQL: snapshot RDS
   - GitLab repos: backup incremental
   - S3: versionamento ativado

---

## 🔄 PROCEDIMENTO DE DESTROY

### Fase 1: Validação Pré-Destroy

```bash
cd platform-provisioning/aws/kubernetes/terraform/envs/marco3

# 1. Verificar state atual
terraform state list

# 2. Verificar recursos ativos
terraform show

# 3. Identificar dependências
# - Verificar se algum recurso fora do TF depende dos recursos marco3
# - Checar network policies, ingress rules, etc
```

### Fase 2: Destroy Parcial (Opção Segura)

**Destruir APENAS recursos não-stateful primeiro:**

```bash
# 1. Remover GitLab Helm release
terraform destroy -target=module.gitlab

# 2. Aguardar conclusão e validar
kubectl get pods -n gitlab

# 3. Remover secrets K8s
terraform destroy -target=kubernetes_secret.gitlab_postgresql_password

# 4. Validar que staging GitLab ainda funciona
```

### Fase 3: Destroy Data Services (CRÍTICO)

**⚠️ ATENÇÃO: Perda de dados permanente se não houver backup**

```bash
# 1. Criar snapshots finais
aws rds create-db-snapshot \
  --db-instance-identifier <marco3-rds-id> \
  --db-snapshot-identifier marco3-final-snapshot-$(date +%Y%m%d)

# 2. Backup S3 buckets (se necessário)
aws s3 sync s3://<marco3-artifacts-bucket> s3://<backup-bucket>/marco3-backup/

# 3. Destroy Redis (stateful)
terraform destroy -target=module.redis

# 4. Destroy RabbitMQ (stateful)
terraform destroy -target=module.rabbitmq

# 5. Destroy PostgreSQL RDS (stateful - LAST)
terraform destroy -target=module.postgresql

# 6. Destroy S3 buckets (se vazios)
terraform destroy -target=module.s3_buckets
```

### Fase 4: Destroy Completo

```bash
# Destruir tudo restante
terraform destroy

# Confirmar state vazio
terraform state list  # deve retornar vazio
```

### Fase 5: Limpeza

```bash
# 1. Remover diretório local
cd ../../../../
rm -rf platform-provisioning/aws/kubernetes/terraform/envs/

# 2. Arquivar state no S3 (NÃO deletar)
# State permanece em: s3://terraform-state-marco0-891377105802/marco3/terraform.tfstate
# Manter para auditoria e possível recovery

# 3. Tag state como deprecated
aws s3api put-object-tagging \
  --bucket terraform-state-marco0-891377105802 \
  --key marco3/terraform.tfstate \
  --tagging 'TagSet=[{Key=Status,Value=deprecated},{Key=DeprecatedDate,Value=2026-02-03}]'
```

---

## 🛡️ ROLLBACK PLAN

Se problemas críticos após destroy:

### Cenário 1: GitLab staging não funciona

```bash
# 1. Re-deploy marco3 GitLab
cd platform-provisioning/aws/kubernetes/terraform/envs/marco3
terraform init
terraform apply -target=module.gitlab

# 2. Aguardar pods Running
kubectl get pods -n gitlab -w
```

### Cenário 2: Perda de dados (pior caso)

```bash
# 1. Restore RDS snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier marco3-restored \
  --db-snapshot-identifier marco3-final-snapshot-YYYYMMDD

# 2. Restore S3 de backup
aws s3 sync s3://<backup-bucket>/marco3-backup/ s3://<marco3-artifacts-bucket>/

# 3. Recreate infra via terraform apply
terraform apply
```

---

## 📊 CHECKLIST DE APROVAÇÃO

**Aprovar destroy APENAS se:**

- [ ] GitLab staging: pods Running > 5min
- [ ] GitLab staging: health check `/health` retorna 200
- [ ] PostgreSQL staging: connection test OK
- [ ] Redis staging: ping test OK
- [ ] RabbitMQ staging: management UI acessível
- [ ] S3 staging: buckets criados, políticas corretas
- [ ] Backup RDS: snapshot criado e validado
- [ ] Backup S3: dados críticos copiados
- [ ] Nenhuma aplicação consumindo marco3 resources
- [ ] Aprovação: DevOps Lead + Security

---

## 📅 TIMELINE PROPOSTA

| Dia | Ação | Responsável |
|-----|------|-------------|
| D+0 (2026-02-03) | Apply GitLab staging | DevOps |
| D+1 | Validar deploy completo (24h uptime) | DevOps + QA |
| D+2 | Criar backups finais marco3 | DevOps |
| D+3 | Destroy fase 1 (GitLab helm) | DevOps |
| D+4 | Validar staging stable (48h sem marco3 GitLab) | DevOps |
| D+7 | Destroy fase 3 (data services) | DevOps + DBA |
| D+8 | Destroy completo + limpeza | DevOps |

**Total: ~8 dias para deprecação segura**

---

## 🔗 Referências

- [ADR-027 Deprecação envs/marco3](./decisions.md#adr-027)
- [Logbook Migração GitLab](../logbook/2026-02-03-gitlab-migration-envs-to-environments.md)
- State S3: `s3://terraform-state-marco0-891377105802/marco3/terraform.tfstate`
- Staging Plan: `environments/staging/staging-gitlab.tfplan`

---

## ⚠️ AVISOS FINAIS

1. **NÃO execute destroy sem aprovação formal**
2. **NÃO delete state S3 (manter para auditoria)**
3. **SEMPRE crie snapshots antes de destroy data services**
4. **VALIDE backups antes de prosseguir**
5. **TESTE rollback plan antes de D+0**

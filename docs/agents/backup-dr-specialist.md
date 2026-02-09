# 💾 Agente Backup & Disaster Recovery Specialist

**Função:** Estratégias de backup, RTO/RPO, testes de restore, DR runbooks
**Expertise:** Velero, Snapshots (EBS, RDS), RTO/RPO, PITR, Cross-Region Replication

---

## 🎯 Responsabilidades

1. **Backup Strategy**
   - Velero para K8s resources (deployments, configmaps, PVCs)
   - EBS snapshots (automated via DLM - Data Lifecycle Manager)
   - RDS automated backups + manual snapshots
   - Retention policies (staging: 7d, prod: 30d)

2. **Disaster Recovery**
   - RTO (Recovery Time Objective): tempo máximo para restaurar
   - RPO (Recovery Point Objective): perda de dados tolerada
   - Cross-region replication (prod only)
   - DR runbooks (step-by-step recovery procedures)

3. **Restore Testing**
   - Testes de restore mensais (não confiar em backups não testados)
   - Validação de integridade (checksums, data consistency)
   - Restore parcial (namespace, PVC específico)
   - Restore completo (cluster inteiro)

4. **Compliance & Auditoria**
   - Backup logs (quem, quando, o quê)
   - Retention compliance (LGPD, SOC2, ISO27001)
   - Encryption at rest (KMS para snapshots)

5. **Validação Pré e Pós Execução**
   - PRE: Backup schedule definido para novos workloads
   - POST: Validar backups executados, restore testado

---

## 📋 Checklist PRE-HOOK Backup/DR

- [ ] Velero schedule criado para namespace do workload
- [ ] PVCs têm snapshot class configurada (gp3-snapshot)
- [ ] RDS automated backups habilitados (retention ≥ 7 dias)
- [ ] Backup location configurado (S3 bucket com versioning)
- [ ] RTO/RPO definidos e documentados (decisions.md)
- [ ] KMS encryption habilitado para snapshots

---

## 📋 Checklist POST-HOOK Backup/DR

- [ ] Velero backup executado com sucesso (velero backup get)
- [ ] EBS snapshots criados (aws ec2 describe-snapshots)
- [ ] RDS snapshot manual criado (aws rds describe-db-snapshots)
- [ ] Restore test passou (velero restore create --from-backup)
- [ ] Backup logs auditados (CloudTrail events)
- [ ] DR runbook atualizado com novo workload

---

## 🔍 Análise Backup/DR STAGING

### Estado Atual (Validar/Criar)

| Componente | Backup Strategy | Status | RTO | RPO |
|------------|----------------|--------|-----|-----|
| **K8s Resources** | ❌ Velero ausente | 🔴 CRÍTICO | N/A | N/A |
| **PostgreSQL (RDS)** | ⚠️ Auto-backup 7d | 🟡 BÁSICO | 2h | 24h |
| **Redis (PVC)** | ❌ Sem snapshot | 🔴 CRÍTICO | N/A | N/A |
| **RabbitMQ (PVC)** | ❌ Sem snapshot | 🔴 CRÍTICO | N/A | N/A |
| **GitLab (PVC)** | ❌ Sem snapshot | 🔴 CRÍTICO | N/A | N/A |
| **Harbor (PVC)** | ❌ Sem snapshot | 🔴 CRÍTICO | N/A | N/A |

### Gaps Críticos Identificados

#### 1. Velero Ausente (BLOQUEADOR para DR)

**Impacto:**
- Sem backup de K8s resources (deployments, secrets, configmaps)
- Desastre = rebuild manual (RTO dias, não horas)
- Compliance fail (sem evidência de backups)

**Ação Obrigatória:**

```bash
# 1. Deploy Velero via Helm
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --set configuration.provider=aws \
  --set configuration.backupStorageLocation.bucket=k8s-velero-backups-staging \
  --set configuration.backupStorageLocation.config.region=us-east-1 \
  --set configuration.volumeSnapshotLocation.config.region=us-east-1 \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.9.0 \
  --set serviceAccount.server.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::ACCOUNT:role/velero-role

# 2. Criar backup schedule (diário 2am UTC)
velero schedule create staging-daily \
  --schedule="0 2 * * *" \
  --ttl 168h0m0s \
  --include-namespaces gitlab,redis,rabbitmq,harbor

# 3. Primeiro backup manual (validar)
velero backup create staging-initial --wait
velero backup describe staging-initial
```

#### 2. PVC Snapshots Ausentes

**Problema:** PVCs stateful (Redis, RabbitMQ, GitLab) sem snapshot policy

**Solução:**

```yaml
# StorageClass com snapshot support
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-snapshot
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
  kmsKeyId: arn:aws:kms:us-east-1:ACCOUNT:key/KEY_ID
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
---
# VolumeSnapshotClass
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: ebs-snapshot-class
driver: ebs.csi.aws.com
deletionPolicy: Retain
parameters:
  tagSpecification_1: "Name=daily-snapshot"
```

**DLM Policy (Automated Snapshots via AWS):**

```hcl
# terraform - DLM lifecycle policy
resource "aws_dlm_lifecycle_policy" "staging_snapshots" {
  description        = "Staging PVC daily snapshots"
  execution_role_arn = aws_iam_role.dlm_role.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    schedule {
      name = "Daily snapshots"

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"]  # UTC
      }

      retain_rule {
        count = 7
      }

      tags_to_add = {
        SnapshotType = "DLM-automated"
        Environment  = "staging"
      }

      copy_tags = true
    }

    target_tags = {
      Environment = "staging"
      Backup      = "true"
    }
  }
}
```

#### 3. RDS Backup Não Testado

**Problema:** Auto-backup habilitado, mas NUNCA testou restore

**Solução:**

```bash
# Restore test mensal (criar read-replica temporária)
# 1. Criar snapshot manual
aws rds create-db-snapshot \
  --db-instance-identifier staging-postgresql \
  --db-snapshot-identifier staging-test-restore-$(date +%Y%m%d)

# 2. Restaurar em instância temporária
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier staging-postgresql-restore-test \
  --db-snapshot-identifier staging-test-restore-$(date +%Y%m%d) \
  --db-instance-class db.t3.small \
  --no-publicly-accessible

# 3. Validar dados (sample queries)
psql -h <endpoint> -U postgres -d gitlab -c "SELECT COUNT(*) FROM users;"

# 4. Destruir após validação
aws rds delete-db-instance \
  --db-instance-identifier staging-postgresql-restore-test \
  --skip-final-snapshot
```

---

## 📊 RTO/RPO Targets (Staging)

| Workload | RTO | RPO | Backup Frequency | Retention |
|----------|-----|-----|------------------|-----------|
| **GitLab** | 4h | 24h | Velero diário + PVC snapshot diário | 7d |
| **PostgreSQL** | 2h | 24h | RDS auto-backup diário | 7d |
| **Redis** | 1h | 1h | PVC snapshot 6x/dia | 2d |
| **RabbitMQ** | 2h | 4h | PVC snapshot 2x/dia | 3d |
| **Harbor** | 4h | 24h | Velero diário + PVC snapshot diário | 7d |

**Rationale (Staging):**
- RTO/RPO mais relaxados que prod (custo vs criticidade)
- Snapshots frequentes para stateful críticos (Redis cache = low RPO)
- Retention curto (7d) suficiente para staging

---

## 📖 DR Runbook (Staging - Disaster Completo)

### Cenário: Cluster K8s perdido (AZ failure, acidental delete)

**Pré-requisitos:**
- Velero backups em S3 (fora do cluster)
- RDS snapshots disponíveis
- EBS snapshots dos PVCs

**Procedimento:**

```bash
# 1. Provisionar novo cluster EKS (Terraform)
cd terraform/environments/staging
terraform apply -target=module.eks

# 2. Instalar Velero no novo cluster
helm install velero vmware-tanzu/velero [...]  # mesmo comando deploy inicial

# 3. Restaurar último backup
velero restore create staging-disaster-recovery \
  --from-backup staging-daily-20260209020000 \
  --wait

# 4. Validar recursos restaurados
kubectl get all -n gitlab
kubectl get pvc -A

# 5. Restaurar RDS (se necessário - geralmente RDS sobrevive)
# RDS não está no cluster, então apenas reconfigurar endpoint se mudou

# 6. Validação funcional
# - GitLab UI acessível
# - Login funcional
# - Sample CI job executa

# 7. Atualizar DNS (se cluster endpoint mudou)
# Route53 update (manual ou Terraform)

# 8. Declarar RTO atingido
# Registrar tempo total no logbook
```

**RTO Esperado:** 3-4 horas (provisionamento EKS ~20 min + restore ~30 min + validação ~1h)

---

## 🔄 Integração com AML

Durante execução via AML, Backup/DR Specialist monitora:

```bash
# Ciclo AML - Verificações Adicionais
├─ Velero backup status: velero backup get | grep InProgress
├─ Snapshot creation: aws ec2 describe-snapshots --filters "Name=status,Values=pending"
├─ RDS backup: aws rds describe-db-snapshots --db-instance-id X
└─ S3 backup location: aws s3 ls s3://k8s-velero-backups-staging/ | tail -5
```

**Report AML Compacto:**
```
[AML-C12] 180s | DR | Velero backup: 85% (1.2GB/1.4GB) | EBS snapshots: 3/5 completed | ✅
```

---

## 💰 Custo Backup/DR (Staging)

| Item | Custo/mês |
|------|-----------|
| S3 Velero backups (50GB, Standard-IA) | ~$2.50 |
| EBS snapshots (100GB incremental) | ~$5.00 |
| RDS snapshots (included in RDS cost) | $0 |
| DLM automation | $0 |
| **Total** | **~$7.50/mês** |

**Custo vs Valor:**
- Rebuild manual cluster: 2 dias eng ($2,000 custo eng)
- DR com Velero: 4 horas ($400 custo eng)
- **Economia em 1 desastre:** $1,600 (ROI 213x)

---

## ⚠️ Decisão Final

🔴 **BLOQUEADOR CRÍTICO** - Staging SEM DR = risco inaceitável

**Ação Imediata (Marco 4):**
1. ✅ Deploy Velero (2h setup)
2. ✅ Configurar DLM snapshots (1h setup)
3. ✅ Primeiro restore test (2h validação)
4. ✅ Documentar DR runbook (1h)

**Total esforço:** 6 horas eng
**Prazo:** Antes de secrets migration (dependencies)

---

**Criado em:** 2026-02-09
**Próxima Revisão:** Pós-deploy Velero (validar primeiro backup + restore test)

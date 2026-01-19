# 06 - Backup e Disaster Recovery

> **Épicos H + J** | Estimativa: 34 person-hours | Sprint 3
> **Pré-requisitos**: Docs 01-05 concluídos

---

## Índice

1. [Visão Geral](#1-visão-geral)
2. [Estratégia de Backup](#2-estratégia-de-backup)
3. [Velero - Backup Kubernetes](#3-velero---backup-kubernetes)
4. [AWS Backup - RDS e EBS](#4-aws-backup---rds-e-ebs)
5. [GitLab Backup Nativo](#5-gitlab-backup-nativo)
6. [Disaster Recovery Plan](#6-disaster-recovery-plan)
7. [DR Drill - Procedimento de Teste](#7-dr-drill---procedimento-de-teste)
8. [Restore Procedures](#8-restore-procedures)
9. [Automação e Monitoramento](#9-automação-e-monitoramento)
10. [Checklist de Conclusão](#10-checklist-de-conclusão)

---

## 1. Visão Geral

### 1.1 Arquitetura de Backup

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         BACKUP ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐     │
│  │   KUBERNETES    │    │      AWS        │    │     GITLAB      │     │
│  │    RESOURCES    │    │    MANAGED      │    │     NATIVE      │     │
│  └────────┬────────┘    └────────┬────────┘    └────────┬────────┘     │
│           │                      │                      │               │
│           ▼                      ▼                      ▼               │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐     │
│  │     VELERO      │    │   AWS BACKUP    │    │  gitlab-backup  │     │
│  │  - Deployments  │    │  - RDS Snapshot │    │  - Repositories │     │
│  │  - ConfigMaps   │    │  - EBS Snapshot │    │  - Database     │     │
│  │  - Secrets      │    │                 │    │  - Uploads      │     │
│  │  - PVCs         │    │                 │    │  - CI Artifacts │     │
│  └────────┬────────┘    └────────┬────────┘    └────────┬────────┘     │
│           │                      │                      │               │
│           ▼                      ▼                      ▼               │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                         AWS S3                                   │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │   │
│  │  │velero-backup│  │ rds-snapshots│  │gitlab-backup│              │   │
│  │  │   bucket    │  │   (managed)  │  │   bucket    │              │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.2 RTO/RPO Definidos

| Componente | RPO | RTO | Método |
|------------|-----|-----|--------|
| **GitLab Repositories** | 1 hora | 4 horas | Velero + GitLab backup |
| **GitLab Database** | 15 min | 2 horas | RDS Automated + PITR |
| **Redis** | 1 hora | 1 hora | Velero PVC backup |
| **RabbitMQ** | 1 hora | 1 hora | Velero PVC backup |
| **Kubernetes Config** | 1 hora | 1 hora | Velero |
| **Observability Data** | 24 horas | 4 horas | S3 lifecycle |

### 1.3 Retenção de Backups

| Tipo | Retenção | Frequência |
|------|----------|------------|
| Velero - Hourly | 24 horas | A cada hora |
| Velero - Daily | 7 dias | Diário 2:00 AM |
| Velero - Weekly | 4 semanas | Domingo 3:00 AM |
| RDS Snapshot | 7 dias | Automático AWS |
| GitLab Backup | 7 dias | Diário 4:00 AM |

---

## 2. Estratégia de Backup

### 2.1 Componentes e Responsabilidades

```
┌──────────────────────────────────────────────────────────────┐
│                    BACKUP MATRIX                              │
├──────────────────┬───────────────┬───────────────────────────┤
│ Componente       │ Ferramenta    │ O que é backupeado        │
├──────────────────┼───────────────┼───────────────────────────┤
│ K8s Resources    │ Velero        │ Deployments, Services,    │
│                  │               │ ConfigMaps, Secrets, CRDs │
├──────────────────┼───────────────┼───────────────────────────┤
│ PVCs (EBS)       │ Velero +      │ Gitaly data, Redis AOF,   │
│                  │ AWS Snapshots │ RabbitMQ data             │
├──────────────────┼───────────────┼───────────────────────────┤
│ RDS PostgreSQL   │ AWS Backup    │ GitLab database           │
│                  │ + Snapshots   │ (PITR enabled)            │
├──────────────────┼───────────────┼───────────────────────────┤
│ GitLab Data      │ gitlab-backup │ Repos, uploads, LFS,      │
│                  │ rake task     │ CI artifacts              │
├──────────────────┼───────────────┼───────────────────────────┤
│ S3 Buckets       │ S3 Versioning │ Loki logs, Tempo traces,  │
│                  │ + Replication │ GitLab artifacts          │
└──────────────────┴───────────────┴───────────────────────────┘
```

---

## 3. Velero - Backup Kubernetes

### 3.1 Criar S3 Bucket para Velero

**Console AWS** → **S3** → **Create bucket**

1. **Bucket name**: `k8s-platform-velero-backups`
2. **Region**: `us-east-1`
3. **Object Ownership**: ACLs disabled
4. **Block Public Access**: Todas as opções marcadas
5. **Versioning**: Enable
6. **Encryption**: SSE-S3

**Lifecycle Rule:**
- Rule name: `cleanup-old-backups`
- Filter: Apply to all objects
- Transitions:
  - Standard-IA after 30 days
  - Glacier after 90 days
- Expiration: 365 days

### 3.2 Criar IAM Policy para Velero

```bash
# velero-policy.json
cat > velero-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeVolumes",
                "ec2:DescribeSnapshots",
                "ec2:CreateTags",
                "ec2:CreateVolume",
                "ec2:CreateSnapshot",
                "ec2:DeleteSnapshot"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:PutObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts"
            ],
            "Resource": "arn:aws:s3:::k8s-platform-velero-backups/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": "arn:aws:s3:::k8s-platform-velero-backups"
        }
    ]
}
EOF

aws iam create-policy \
  --policy-name VeleroBackupPolicy \
  --policy-document file://velero-policy.json
```

### 3.3 Criar IRSA para Velero

```bash
eksctl create iamserviceaccount \
  --cluster=k8s-platform-cluster \
  --namespace=velero \
  --name=velero \
  --attach-policy-arn=arn:aws:iam::ACCOUNT_ID:policy/VeleroBackupPolicy \
  --approve
```

### 3.4 Instalar Velero

```bash
# Adicionar repo
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

# Criar namespace
kubectl create namespace velero

# Criar values.yaml
cat > velero-values.yaml << 'EOF'
configuration:
  backupStorageLocation:
    - name: default
      provider: aws
      bucket: k8s-platform-velero-backups
      config:
        region: us-east-1

  volumeSnapshotLocation:
    - name: default
      provider: aws
      config:
        region: us-east-1

  defaultBackupStorageLocation: default
  defaultVolumeSnapshotLocations: aws:default

initContainers:
  - name: velero-plugin-for-aws
    image: velero/velero-plugin-for-aws:v1.9.0
    imagePullPolicy: IfNotPresent
    volumeMounts:
      - mountPath: /target
        name: plugins

serviceAccount:
  server:
    create: false
    name: velero
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/velero-irsa-role

credentials:
  useSecret: false

deployNodeAgent: true
nodeAgent:
  podVolumePath: /var/lib/kubelet/pods
  privileged: true
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 1000m
    memory: 512Mi

metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    namespace: observability

schedules:
  hourly-backup:
    disabled: false
    schedule: "0 * * * *"
    template:
      ttl: "24h"
      includedNamespaces:
        - gitlab
        - data-services
      snapshotVolumes: true
      storageLocation: default
      volumeSnapshotLocations:
        - default

  daily-backup:
    disabled: false
    schedule: "0 2 * * *"
    template:
      ttl: "168h"  # 7 dias
      includedNamespaces:
        - gitlab
        - data-services
        - observability
        - cert-manager
      snapshotVolumes: true
      storageLocation: default

  weekly-backup:
    disabled: false
    schedule: "0 3 * * 0"
    template:
      ttl: "720h"  # 30 dias
      includedNamespaces:
        - "*"
      snapshotVolumes: true
      storageLocation: default
EOF

# Instalar
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --values velero-values.yaml

# Verificar
kubectl get pods -n velero
kubectl get backupstoragelocations -n velero
```

### 3.5 Instalar CLI Velero

```bash
# Linux
wget https://github.com/vmware-tanzu/velero/releases/download/v1.13.0/velero-v1.13.0-linux-amd64.tar.gz
tar -xvf velero-v1.13.0-linux-amd64.tar.gz
sudo mv velero-v1.13.0-linux-amd64/velero /usr/local/bin/

# Verificar
velero version
```

### 3.6 Criar Backup Manual

```bash
# Backup completo
velero backup create full-backup-$(date +%Y%m%d) \
  --include-namespaces gitlab,data-services,observability \
  --snapshot-volumes \
  --wait

# Backup apenas GitLab
velero backup create gitlab-backup-$(date +%Y%m%d-%H%M) \
  --include-namespaces gitlab \
  --snapshot-volumes \
  --wait

# Verificar backup
velero backup describe gitlab-backup-$(date +%Y%m%d-%H%M)
velero backup logs gitlab-backup-$(date +%Y%m%d-%H%M)

# Listar backups
velero backup get
```

### 3.7 Backup com Labels Específicos

```bash
# Backup apenas de recursos com label específico
velero backup create critical-apps-backup \
  --selector app.kubernetes.io/part-of=gitlab \
  --snapshot-volumes

# Backup excluindo secrets (útil para compliance)
velero backup create config-only-backup \
  --include-namespaces gitlab \
  --exclude-resources secrets
```

---

## 4. AWS Backup - RDS e EBS

### 4.1 Criar Backup Vault

**Console AWS** → **AWS Backup** → **Backup vaults** → **Create backup vault**

1. **Backup vault name**: `k8s-platform-vault`
2. **Encryption key**: Criar nova KMS key ou usar default
3. **Tags**:
   - `Environment`: `production`
   - `Project`: `k8s-platform`

### 4.2 Criar Backup Plan

**Console AWS** → **AWS Backup** → **Backup plans** → **Create backup plan**

1. **Start options**: Build a new plan
2. **Backup plan name**: `k8s-platform-backup-plan`

**Backup rule 1 - Daily:**
- Rule name: `daily-rds-backup`
- Backup vault: `k8s-platform-vault`
- Backup frequency: Daily
- Backup window: Start 02:00, Complete within 8 hours
- Lifecycle:
  - Transition to cold storage: 30 days
  - Expire: 90 days
- Copy to another Region: (opcional) `us-west-2`

**Backup rule 2 - Hourly (para PITR):**
- Rule name: `hourly-snapshot`
- Backup frequency: Hourly
- Retention: 24 hours
- Enable continuous backup: Yes (para PITR)

### 4.3 Assign Resources

**Resource assignment name**: `k8s-platform-resources`

**IAM role**: Create new role ou usar `AWSBackupDefaultServiceRole`

**Resource selection**:
- Define resource selection: Include specific resource types
- Select resource types:
  - RDS
  - EBS
- Resource ID:
  - RDS: `k8s-platform-gitlab-db`
  - EBS: Tag `kubernetes.io/cluster/k8s-platform-cluster` = `owned`

### 4.4 Habilitar PITR no RDS

**Console AWS** → **RDS** → **Databases** → Selecionar `k8s-platform-gitlab-db`

1. **Modify**
2. **Backup**:
   - Backup retention period: 7 days
   - Backup window: 03:00-04:00 UTC
   - ✅ Enable automated backups
   - ✅ Copy tags to snapshots

3. **Apply immediately**

### 4.5 Script de Verificação AWS Backup

```bash
#!/bin/bash
# check-aws-backups.sh

echo "=== Backup Vaults ==="
aws backup list-backup-vaults --query 'BackupVaultList[*].[BackupVaultName,NumberOfRecoveryPoints]' --output table

echo ""
echo "=== Backup Plans ==="
aws backup list-backup-plans --query 'BackupPlansList[*].[BackupPlanName,BackupPlanId]' --output table

echo ""
echo "=== Recovery Points (últimas 24h) ==="
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name k8s-platform-vault \
  --by-created-after $(date -d '24 hours ago' --iso-8601=seconds) \
  --query 'RecoveryPoints[*].[ResourceType,CreationDate,Status]' \
  --output table

echo ""
echo "=== RDS Snapshots ==="
aws rds describe-db-snapshots \
  --db-instance-identifier k8s-platform-gitlab-db \
  --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime,Status]' \
  --output table
```

---

## 5. GitLab Backup Nativo

### 5.1 Configurar GitLab Backup para S3

Atualizar `gitlab-values.yaml` (do Doc 02):

```yaml
global:
  appConfig:
    backups:
      bucket: k8s-platform-gitlab-backups
      tmpBucket: k8s-platform-gitlab-tmp

    object_store:
      enabled: true
      connection:
        secret: gitlab-rails-storage
        key: connection

gitlab:
  toolbox:
    backups:
      cron:
        enabled: true
        schedule: "0 4 * * *"  # 4:00 AM diário
        extraArgs: "--skip builds,artifacts"  # Opcional: pular grandes arquivos
      objectStorage:
        backend: s3
        config:
          secret: gitlab-rails-storage
          key: config
```

### 5.2 Criar Secret de Storage

```yaml
# gitlab-storage-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-rails-storage
  namespace: gitlab
type: Opaque
stringData:
  connection: |
    provider: AWS
    region: us-east-1
    use_iam_profile: true
  config: |
    [default]
    bucket = k8s-platform-gitlab-backups
    region = us-east-1
```

```bash
kubectl apply -f gitlab-storage-secret.yaml
```

### 5.3 Executar Backup Manual

```bash
# Acessar toolbox pod
TOOLBOX_POD=$(kubectl get pods -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}')

# Executar backup completo
kubectl exec -it -n gitlab $TOOLBOX_POD -- backup-utility --skip builds,artifacts

# Listar backups
kubectl exec -it -n gitlab $TOOLBOX_POD -- ls -la /srv/gitlab/tmp/backups/

# Verificar backup no S3
aws s3 ls s3://k8s-platform-gitlab-backups/
```

### 5.4 Backup de Secrets do GitLab

```bash
# IMPORTANTE: Backup dos secrets (não incluídos no backup padrão)
kubectl get secret -n gitlab gitlab-rails-secret -o yaml > gitlab-rails-secret-backup.yaml
kubectl get secret -n gitlab gitlab-gitlab-shell-secret -o yaml > gitlab-shell-secret-backup.yaml
kubectl get secret -n gitlab gitlab-registry-secret -o yaml > gitlab-registry-secret-backup.yaml

# Encriptar e enviar para S3
tar -czvf gitlab-secrets-$(date +%Y%m%d).tar.gz gitlab-*-secret-backup.yaml
aws s3 cp gitlab-secrets-$(date +%Y%m%d).tar.gz s3://k8s-platform-gitlab-backups/secrets/

# Limpar arquivos locais
rm -f gitlab-*-secret-backup.yaml gitlab-secrets-*.tar.gz
```

---

## 6. Disaster Recovery Plan

### 6.1 Cenários de DR

```
┌─────────────────────────────────────────────────────────────────────┐
│                    DR SCENARIOS & RESPONSES                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  SCENARIO 1: Pod/Deployment Failure                                  │
│  ├─ Impact: Single service unavailable                              │
│  ├─ RTO: < 5 min (auto-healing)                                     │
│  └─ Action: Kubernetes auto-restart                                 │
│                                                                      │
│  SCENARIO 2: Node Failure                                            │
│  ├─ Impact: Multiple pods rescheduled                               │
│  ├─ RTO: < 10 min                                                   │
│  └─ Action: ASG replacement + pod reschedule                        │
│                                                                      │
│  SCENARIO 3: AZ Failure                                              │
│  ├─ Impact: 1/3 capacity lost                                       │
│  ├─ RTO: < 15 min                                                   │
│  └─ Action: Multi-AZ failover automático                            │
│                                                                      │
│  SCENARIO 4: Data Corruption                                         │
│  ├─ Impact: GitLab data inconsistent                                │
│  ├─ RTO: 2-4 horas                                                  │
│  └─ Action: Restore from Velero/RDS snapshot                        │
│                                                                      │
│  SCENARIO 5: Region Failure                                          │
│  ├─ Impact: Total outage                                            │
│  ├─ RTO: 4-8 horas                                                  │
│  └─ Action: Cross-region DR (se configurado)                        │
│                                                                      │
│  SCENARIO 6: Ransomware/Security Breach                              │
│  ├─ Impact: Cluster comprometido                                    │
│  ├─ RTO: 4-8 horas                                                  │
│  └─ Action: Isolate + rebuild from clean backup                     │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 6.2 Runbook de DR

#### Cenário: Corrupção de Dados GitLab

```
RUNBOOK: GITLAB DATA CORRUPTION RECOVERY
========================================

TRIGGER:
- Usuários reportam dados faltando
- Erros de integridade no banco
- CI/CD pipelines com comportamento errático

ASSESSMENT (10 min):
1. [ ] Verificar logs do GitLab: kubectl logs -n gitlab -l app=webservice --tail=100
2. [ ] Verificar status do RDS no Console AWS
3. [ ] Verificar último backup válido: velero backup get
4. [ ] Comunicar stakeholders - canal #incident

CONTAINMENT (5 min):
1. [ ] Scale down GitLab para evitar mais escrita:
       kubectl scale deployment -n gitlab gitlab-webservice --replicas=0
2. [ ] Criar snapshot atual (para análise posterior):
       velero backup create pre-restore-$(date +%Y%m%d-%H%M) --include-namespaces gitlab

RECOVERY:
Opção A - Restore Velero (K8s resources + PVC):
1. [ ] Identificar backup: velero backup describe <backup-name>
2. [ ] Restore: velero restore create --from-backup <backup-name>
3. [ ] Aguardar: velero restore describe <restore-name>

Opção B - Restore RDS PITR:
1. [ ] Console AWS → RDS → Restore to point in time
2. [ ] Selecionar timestamp anterior ao problema
3. [ ] Criar nova instância: k8s-platform-gitlab-db-restored
4. [ ] Atualizar connection string no GitLab

VALIDATION (30 min):
1. [ ] Scale up GitLab: kubectl scale deployment -n gitlab gitlab-webservice --replicas=2
2. [ ] Testar login: curl -I https://gitlab.seudominio.com.br
3. [ ] Verificar repositórios: criar branch de teste
4. [ ] Verificar CI/CD: trigger pipeline de teste

POST-INCIDENT:
1. [ ] Documentar timeline no incident report
2. [ ] Root cause analysis
3. [ ] Atualizar runbook se necessário
```

### 6.3 Contatos de Emergência

```yaml
# dr-contacts.yaml (armazenar em local seguro, não no cluster)
emergency_contacts:
  - role: Platform Lead
    name: "[Nome]"
    phone: "+55 11 9xxxx-xxxx"
    email: "platform-lead@empresa.com"

  - role: DBA
    name: "[Nome]"
    phone: "+55 11 9xxxx-xxxx"
    email: "dba@empresa.com"

  - role: AWS Support
    case_url: "https://console.aws.amazon.com/support/home"
    tier: "Business Support"

escalation_path:
  - level: 1
    time: "0-15 min"
    contact: "Platform Lead"
  - level: 2
    time: "15-30 min"
    contact: "Engineering Manager"
  - level: 3
    time: "30+ min"
    contact: "CTO + AWS Support"
```

---

## 7. DR Drill - Procedimento de Teste

### 7.1 Plano de DR Drill Trimestral

```
DR DRILL CHECKLIST
==================
Frequência: Trimestral
Duração: 4 horas (janela de manutenção)
Participantes: Platform Team + DBA + QA

PRÉ-DRILL (1 dia antes):
[ ] Comunicar janela de manutenção
[ ] Verificar backups recentes disponíveis
[ ] Preparar ambiente de teste isolado
[ ] Documentar estado atual (baseline)

DRILL EXECUTION:

Fase 1 - Velero Restore (1h)
[ ] Criar namespace de teste: kubectl create ns dr-test
[ ] Restore parcial: velero restore create dr-test-restore \
      --from-backup <latest-backup> \
      --namespace-mappings gitlab:dr-test-gitlab
[ ] Verificar recursos restaurados
[ ] Validar PVCs e dados
[ ] Cleanup: kubectl delete ns dr-test-gitlab

Fase 2 - RDS PITR (1h)
[ ] Criar restore point-in-time para nova instância
[ ] Aguardar instância available (~20 min)
[ ] Conectar e validar dados
[ ] Deletar instância de teste

Fase 3 - GitLab Full Restore (1.5h)
[ ] Criar namespace limpo: kubectl create ns gitlab-restore-test
[ ] Deploy GitLab mínimo (sem dados)
[ ] Restore do backup: backup-utility --restore
[ ] Validar repositórios e CI/CD
[ ] Cleanup completo

Fase 4 - Documentação (30 min)
[ ] Registrar tempos de cada fase
[ ] Documentar problemas encontrados
[ ] Atualizar runbooks
[ ] Calcular RTO real vs target

POST-DRILL:
[ ] Relatório para stakeholders
[ ] Action items para melhorias
[ ] Atualizar DR plan se necessário
```

### 7.2 Script de DR Drill Automatizado

```bash
#!/bin/bash
# dr-drill.sh
# Executar em ambiente de teste apenas!

set -e

DRILL_ID="dr-drill-$(date +%Y%m%d-%H%M)"
BACKUP_NAME="${1:-$(velero backup get -o json | jq -r '.items[-1].metadata.name')}"
TEST_NS="dr-test-${DRILL_ID}"

echo "=== DR DRILL: $DRILL_ID ==="
echo "Using backup: $BACKUP_NAME"
echo ""

# Fase 1: Velero Restore
echo "=== FASE 1: Velero Restore ==="
START_TIME=$(date +%s)

kubectl create namespace $TEST_NS

velero restore create $DRILL_ID \
  --from-backup $BACKUP_NAME \
  --include-namespaces gitlab \
  --namespace-mappings gitlab:$TEST_NS \
  --wait

END_TIME=$(date +%s)
VELERO_TIME=$((END_TIME - START_TIME))
echo "Velero restore completed in ${VELERO_TIME}s"

# Verificar recursos
echo ""
echo "=== Recursos Restaurados ==="
kubectl get all -n $TEST_NS

# Verificar PVCs
echo ""
echo "=== PVCs ==="
kubectl get pvc -n $TEST_NS

# Fase 2: Validação de Dados
echo ""
echo "=== FASE 2: Validação ==="

# Verificar se pods estão rodando
kubectl wait --for=condition=Ready pods -l app=webservice -n $TEST_NS --timeout=300s || echo "WARN: Pods not ready"

# Cleanup
echo ""
echo "=== CLEANUP ==="
read -p "Deletar namespace de teste $TEST_NS? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl delete namespace $TEST_NS
    velero restore delete $DRILL_ID --confirm
fi

echo ""
echo "=== DR DRILL SUMMARY ==="
echo "Drill ID: $DRILL_ID"
echo "Backup Used: $BACKUP_NAME"
echo "Velero Restore Time: ${VELERO_TIME}s"
echo "Status: COMPLETED"
```

### 7.3 Métricas de DR

```yaml
# prometheus-rules/dr-metrics.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: dr-alerts
  namespace: observability
spec:
  groups:
    - name: disaster-recovery
      rules:
        - alert: VeleroBackupFailed
          expr: |
            increase(velero_backup_failure_total[1h]) > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Velero backup failed"
            description: "Backup {{ $labels.schedule }} failed. Check velero logs."

        - alert: VeleroBackupMissing
          expr: |
            time() - velero_backup_last_successful_timestamp > 7200
          for: 30m
          labels:
            severity: warning
          annotations:
            summary: "No successful Velero backup in 2 hours"

        - alert: RDSBackupMissing
          expr: |
            aws_rds_backup_retention_period_days < 7
          for: 1h
          labels:
            severity: warning
          annotations:
            summary: "RDS backup retention below 7 days"

        - record: dr:backup:age_hours
          expr: (time() - velero_backup_last_successful_timestamp) / 3600

        - record: dr:rpo:compliance
          expr: |
            (time() - velero_backup_last_successful_timestamp) < 3600
```

---

## 8. Restore Procedures

### 8.1 Restore Velero - Namespace Completo

```bash
# Listar backups disponíveis
velero backup get

# Descrever backup específico
velero backup describe daily-backup-20240115

# Restore completo do namespace gitlab
velero restore create gitlab-restore-$(date +%Y%m%d) \
  --from-backup daily-backup-20240115 \
  --include-namespaces gitlab \
  --restore-volumes=true \
  --wait

# Verificar status
velero restore describe gitlab-restore-$(date +%Y%m%d)

# Verificar logs se houver erros
velero restore logs gitlab-restore-$(date +%Y%m%d)
```

### 8.2 Restore Velero - Recurso Específico

```bash
# Restore apenas de um deployment específico
velero restore create webservice-restore \
  --from-backup daily-backup-20240115 \
  --include-namespaces gitlab \
  --include-resources deployments \
  --selector app=webservice

# Restore de ConfigMaps e Secrets apenas
velero restore create config-restore \
  --from-backup daily-backup-20240115 \
  --include-namespaces gitlab \
  --include-resources configmaps,secrets
```

### 8.3 Restore RDS - Point-in-Time

**Console AWS** → **RDS** → **Databases** → Selecionar DB → **Actions** → **Restore to point in time**

1. **Restore time**: Custom date and time
2. **Date**: Selecionar data
3. **Time (UTC)**: Selecionar hora antes do incidente
4. **DB instance identifier**: `k8s-platform-gitlab-db-restored`
5. **DB instance class**: Mesmo do original
6. **VPC**: Mesmo do original
7. **Subnet group**: Mesmo do original
8. **Security group**: Mesmo do original

**Após restore:**
```bash
# Atualizar endpoint no Kubernetes
NEW_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-gitlab-db-restored \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# Atualizar secret
kubectl create secret generic gitlab-postgresql-password \
  --from-literal=postgresql-password='SuaSenhaAqui' \
  --from-literal=postgresql-host=$NEW_ENDPOINT \
  --namespace gitlab \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart GitLab para pegar novo endpoint
kubectl rollout restart deployment -n gitlab gitlab-webservice
kubectl rollout restart deployment -n gitlab gitlab-sidekiq
```

### 8.4 Restore GitLab Backup Nativo

```bash
# Obter toolbox pod
TOOLBOX_POD=$(kubectl get pods -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}')

# Listar backups disponíveis
kubectl exec -n gitlab $TOOLBOX_POD -- ls -la /srv/gitlab/tmp/backups/

# Ou listar do S3
aws s3 ls s3://k8s-platform-gitlab-backups/

# Download do backup do S3 (se necessário)
kubectl exec -n gitlab $TOOLBOX_POD -- \
  aws s3 cp s3://k8s-platform-gitlab-backups/1705320000_2024_01_15_16.7.0_gitlab_backup.tar \
  /srv/gitlab/tmp/backups/

# IMPORTANTE: Escalar para 0 antes do restore
kubectl scale deployment -n gitlab gitlab-webservice --replicas=0
kubectl scale deployment -n gitlab gitlab-sidekiq --replicas=0

# Executar restore
kubectl exec -it -n gitlab $TOOLBOX_POD -- \
  backup-utility --restore -t 1705320000_2024_01_15_16.7.0

# Restaurar secrets (se necessário)
kubectl apply -f gitlab-rails-secret-backup.yaml

# Escalar de volta
kubectl scale deployment -n gitlab gitlab-webservice --replicas=2
kubectl scale deployment -n gitlab gitlab-sidekiq --replicas=2

# Verificar
kubectl exec -n gitlab $TOOLBOX_POD -- gitlab-rake gitlab:check
```

### 8.5 Restore de EBS Snapshot

```bash
# Listar snapshots
aws ec2 describe-snapshots \
  --owner-ids self \
  --filters "Name=tag:kubernetes.io/cluster/k8s-platform-cluster,Values=owned" \
  --query 'Snapshots[*].[SnapshotId,StartTime,VolumeSize,Description]' \
  --output table

# Criar volume do snapshot
aws ec2 create-volume \
  --availability-zone us-east-1a \
  --snapshot-id snap-0123456789abcdef0 \
  --volume-type gp3 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=restored-gitaly-data}]'

# Criar PV apontando para o volume
cat > restored-pv.yaml << EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: restored-gitaly-pv
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: gp3
  awsElasticBlockStore:
    volumeID: vol-0123456789abcdef0
    fsType: ext4
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: topology.kubernetes.io/zone
              operator: In
              values:
                - us-east-1a
EOF

kubectl apply -f restored-pv.yaml
```

---

## 9. Automação e Monitoramento

### 9.1 CronJob de Verificação de Backups

```yaml
# backup-verification-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-verification
  namespace: velero
spec:
  schedule: "0 6 * * *"  # 6:00 AM diário
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: velero
          containers:
            - name: verify
              image: bitnami/kubectl:latest
              command:
                - /bin/bash
                - -c
                - |
                  # Verificar último backup
                  LAST_BACKUP=$(velero backup get -o json | jq -r '.items | sort_by(.metadata.creationTimestamp) | last | .metadata.name')
                  LAST_STATUS=$(velero backup get $LAST_BACKUP -o json | jq -r '.status.phase')

                  if [ "$LAST_STATUS" != "Completed" ]; then
                    echo "ALERT: Last backup $LAST_BACKUP status is $LAST_STATUS"
                    exit 1
                  fi

                  # Verificar idade do backup
                  LAST_TIME=$(velero backup get $LAST_BACKUP -o json | jq -r '.metadata.creationTimestamp')
                  AGE_HOURS=$(( ($(date +%s) - $(date -d "$LAST_TIME" +%s)) / 3600 ))

                  if [ $AGE_HOURS -gt 2 ]; then
                    echo "ALERT: Last backup is $AGE_HOURS hours old"
                    exit 1
                  fi

                  echo "OK: Backup $LAST_BACKUP completed $AGE_HOURS hours ago"
          restartPolicy: OnFailure
```

### 9.2 Dashboard Grafana para Backups

```json
{
  "dashboard": {
    "title": "Backup & DR Status",
    "panels": [
      {
        "title": "Last Successful Backup Age",
        "type": "stat",
        "targets": [
          {
            "expr": "dr:backup:age_hours",
            "legendFormat": "Hours since last backup"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "thresholds": {
              "steps": [
                {"color": "green", "value": 0},
                {"color": "yellow", "value": 1},
                {"color": "red", "value": 2}
              ]
            },
            "unit": "h"
          }
        }
      },
      {
        "title": "Backup Success Rate (7d)",
        "type": "gauge",
        "targets": [
          {
            "expr": "sum(increase(velero_backup_success_total[7d])) / (sum(increase(velero_backup_success_total[7d])) + sum(increase(velero_backup_failure_total[7d]))) * 100"
          }
        ]
      },
      {
        "title": "Backup History",
        "type": "table",
        "targets": [
          {
            "expr": "velero_backup_last_successful_timestamp",
            "format": "table"
          }
        ]
      },
      {
        "title": "RDS Snapshots",
        "type": "stat",
        "datasource": "CloudWatch",
        "targets": [
          {
            "namespace": "AWS/RDS",
            "metricName": "SnapshotStorageUsed",
            "dimensions": {
              "DBInstanceIdentifier": "k8s-platform-gitlab-db"
            }
          }
        ]
      }
    ]
  }
}
```

### 9.3 Alertas SNS para Falha de Backup

**Console AWS** → **SNS** → **Create topic**

1. **Topic name**: `k8s-backup-alerts`
2. **Type**: Standard
3. **Create subscription**:
   - Protocol: Email
   - Endpoint: `devops-team@empresa.com`

**EventBridge Rule:**

**Console AWS** → **EventBridge** → **Rules** → **Create rule**

1. **Name**: `backup-failure-alert`
2. **Event pattern**:
```json
{
  "source": ["aws.backup"],
  "detail-type": ["Backup Job State Change"],
  "detail": {
    "state": ["FAILED", "ABORTED"]
  }
}
```
3. **Target**: SNS topic `k8s-backup-alerts`

---

## 10. Checklist de Conclusão

### 10.1 Definition of Done - Épicos H + J

| Item | Critério | Status |
|------|----------|--------|
| **Velero** | Instalado e configurado com S3 | ☐ |
| **Velero Schedules** | Hourly, Daily, Weekly configurados | ☐ |
| **AWS Backup** | Vault e Plan criados | ☐ |
| **RDS Backup** | Automated backups + PITR habilitado | ☐ |
| **GitLab Backup** | CronJob nativo configurado | ☐ |
| **GitLab Secrets** | Backup separado dos secrets | ☐ |
| **DR Plan** | Documentado com runbooks | ☐ |
| **DR Drill** | Executado e documentado | ☐ |
| **Restore Tested** | Velero + RDS restore validados | ☐ |
| **Monitoring** | Alertas de backup configurados | ☐ |
| **Dashboard** | Grafana dashboard de backup | ☐ |

### 10.2 Comandos de Verificação Final

```bash
# Velero
velero backup get
velero schedule get
velero backup-location get

# AWS Backup
aws backup list-backup-jobs --by-state COMPLETED --max-results 5

# RDS
aws rds describe-db-instances \
  --db-instance-identifier k8s-platform-gitlab-db \
  --query 'DBInstances[0].{BackupRetention:BackupRetentionPeriod,LatestRestorableTime:LatestRestorableTime}'

# GitLab backup CronJob
kubectl get cronjobs -n gitlab

# Alertas
kubectl get prometheusrules -n observability | grep -i backup
```

### 10.3 Próximos Passos

- **Doc 07**: [FinOps e Automação](./07-finops-automacao.md) - Cost management, Start/Stop automation, Budgets

---

## Referências

- [Velero Documentation](https://velero.io/docs/)
- [AWS Backup Documentation](https://docs.aws.amazon.com/aws-backup/)
- [GitLab Backup & Restore](https://docs.gitlab.com/ee/raketasks/backup_restore.html)
- [RDS Point-in-Time Recovery](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIT.html)
- [EKS Best Practices - Backup](https://aws.github.io/aws-eks-best-practices/reliability/docs/datamanagement/)

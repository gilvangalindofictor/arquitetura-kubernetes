# Estratégia de Backup - Data Services Domain (STAGING Environment)

> **Status**: REVISÃO NECESSÁRIA - Estratégia para STAGING pode ser aliviada
> **Data**: 2026-02-11
> **Ambiente**: 🟡 STAGING
> **Nota**: Uma estratégia de backup mais robusta será necessária para Production

---

## ℹ️ SITUAÇÃO ATUAL EM STAGING

A documentação menciona **Velero 5.2.0**, mas **NÃO FOI IMPLEMENTADO** em STAGING (deliberado):
- ❌ Nenhum namespace velero
- ❌ Nenhuma Helm release
- ❌ Nenhuma CRD velero
- ❌ Nenhum S3 bucket com padrão k8s-platform-*-velero

🚨 **QUESTÃO CRÍTICA**: Como está sendo feito backup dos dados em produção?

---

## 📊 Componentes de Backup Encontrados

### 1. AWS RDS Snapshots (PostgreSQL)

**Componente**: k8s-platform-prod-postgresql (RDS)

```yaml
Tipo: AWS RDS Automated Snapshots
Versão: PostgreSQL 16.4
Retenção: TBD (verificar console AWS)
Frequência: Automática (horária ou diária)
Restore Target: Create new RDS instance
RPO (Recovery Point Objective): < 1 dia
RTO (Recovery Time Objective): 15-30 minutos
```

**Status Atual**: ✅ Provavelmente configurado (padrão AWS)
**Validação Necessária**: Confirmar retention policy no AWS console

### 2. S3 Buckets para Snapshots

**Componente**: k8s-platform-prod-vault-snapshots-891377105802

```yaml
Nome: k8s-platform-prod-vault-snapshots
Propósito: Snapshots do Vault (Secrets Management)
Tipo: S3 Storage
Linked: Backup de configurações, credenciais
RPO: Configurável no Vault
```

**Status Atual**: ✅ Encontrado e ativo
**Validação Necessária**: Verificar se inclui dados de aplicação

### 3. Redis Backup Strategy

**Componente**: SpotaHome Redis Operator v3.3.0 (data-services/redis)

```yaml
Tipo: Redis Persistence (RDB + AOF)
Storage: K8s PVC (EBS backed)
Backup: TBD
```

**PROBLEMA**:
- Documentação não especifica backup de Redis
- Redis RedisFailover com 3 replicas (HA, não backup)
- Persistência depende de PVC → se perder node + PVC = perda de dados

**Risco**: CRÍTICO se não houver backup

### 4. RabbitMQ Backup Strategy

**Componente**: RabbitMQ Cluster Operator v2.19.0 (data-services/rabbitmq)

```yaml
Tipo: RabbitMQ Cluster (3 nodes by default)
Data: Queue + Definitions
Backup: TBD
```

**PROBLEMA**:
- Documentação não especifica backup de RabbitMQ
- 3 nodes redundantes (HA, não backup)
- Definitions em etcd, não em persistente storage

**Risco**: CRÍTICO se não houver backup

### 5. Observability Data (Not Critical)

```yaml
Loki: S3 bucket (k8s-platform-loki)
  → Logs apenas, recriável
Tempo: S3 bucket (k8s-platform-tempo)
  → Traces apenas, recriável
Prometheus: local storage (não visto em S3)
  → Métricas apenas, recriável
```

---

## 🔍 GAPS IDENTIFICADOS

| Componente     | Backup Esperado              | Backup Real    | Gap       | Risk   |
| -------------- | ---------------------------- | -------------- | --------- | ------ |
| **PostgreSQL** | RDS snapshots                | RDS snapshots  | ✅ OK      | 🟢 Low  |
| **Redis**      | Velero OR RDB snapshots      | ❓ Unknown      | ❌ CRÍTICO | 🔴 High |
| **RabbitMQ**   | Velero OR definitions export | ❓ Unknown      | ❌ CRÍTICO | 🔴 High |
| **Vault**      | S3 snapshots                 | S3 snapshots ✅ | ✅ OK      | 🟢 Low  |

---

## 🛠️ OPÇÕES DE RESOLUÇÃO

### Opção A: Implementar Velero (Documentação Original)

**Pros**:
- ✅ Solution única e centralizada
- ✅ Consistent com documentação
- ✅ Support para multi-cluster disaster recovery
- ✅ Granular restore (namespaces específicos)
- ✅ Cronjob scheduling built-in
- ✅ Best practice da indústria

**Cons**:
- ❌ Overhead adicional (Pod, controlador, webhooks)
- ❌ Complexidade operacional (CRD, Schedules, Restore)
- ❌ Curva de aprendizado
- ❌ Requer storage class compatible
- ❌ Pode impactar performance durante backups

**Estimated Effort**: 1-2 semanas (incluindo testing)

**Action Items**:
1. Create Velero namespace
2. Install Velero chart
3. Configure S3 bucket (k8s-platform-velero-backups)
4. Test backup + restore on staging
5. Configure schedules (daily backups)
6. Create runbooks

---

### Opção B: Estratégia Híbrida (Recomendado)

**Componentes**:
```
PostgreSQL  → AWS RDS automated snapshots ✅
Redis       → Manual RDB exports (cron) + S3
RabbitMQ    → Definitions export (cron) + etcd backup
Vault       → S3 snapshots ✅ (já existe)
```

**Pros**:
- ✅ Simples de implementar
- ✅ Leverages managed AWS services existentes
- ✅ Menor overhead
- ✅ Menor cost
- ✅ Menor complexidade

**Cons**:
- ❌ Não centralizado (múltiplas estratégias)
- ❌ Requer scripting customizado
- ❌ Monitoring mais complexo
- ❌ Não é "best practice"
- ❌ Requer atualização da documentação

**Estimated Effort**: 2-3 dias (para implementar scripts)

**Action Items**:
```bash
# 1. Redis RDB export
kubectl exec -n data-services <redis-pod> -- redis-cli BGSAVE
kubectl cp data-services/<redis-pod>:/data/dump.rdb ./backup/redis-$(date +%Y%m%d).rdb
aws s3 cp ./backup/redis-*.rdb s3://k8s-platform-backups/redis/

# 2. RabbitMQ definitions export
kubectl exec -n data-services <rabbitmq-pod> -- \
  rabbitmqctl export_definitions /tmp/definitions.json
kubectl cp data-services/<rabbitmq-pod>:/tmp/definitions.json ./backup/
aws s3 cp ./backup/definitions.json s3://k8s-platform-backups/rabbitmq/

# 3. Schedule via CronJob (K8s)
kubectl apply -f backup-cronjobs.yaml
```

---

### Opção C: Vendor-Specific Backups

**Componentes**:
```
PostgreSQL  → AWS RDS snapshots (managed)
Redis       → Replicação + failover (vendedor)
RabbitMQ    → Queue mirroring (vendedor)
Vault       → AWS S3 snapshots
```

**Pros**:
- ✅ Simples (cada serviço cuida de si)
- ✅ Menor mantenabilidade
- ✅ Melhor performance (sem overhead)

**Cons**:
- ❌ Não é true disaster recovery
- ❌ HA não é backup (não protege contra corrupção)
- ❌ Risco de perda de dados
- ❌ Não passa compliance requirements

**Estimated Effort**: 0 (já implementado)
**⚠️ NÃO RECOMENDADO** para produção

---

## 🎯 RECOMENDAÇÃO

**OPÇÃO RECOMENDADA: B (Híbrida) → Transição para A (Velero)**

### Curto Prazo (Esta semana - 2 semanas)

Implementar **Opção B** para ter ALGO em lugar de NADA:

```bash
# Criar namespace de backup
kubectl create namespace backup-system

# Criar scripts de backup
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: redis-backup
  namespace: backup-system
spec:
  schedule: "0 2 * * *"  # 2am daily
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: backup-service
          containers:
          - name: redis-backup
            image: redis:6.2.6
            command:
            - /bin/sh
            - -c
            - |
              redis-cli -h redis.data-services BGSAVE
              sleep 10
              kubectl cp data-services/redis-pod:/data/dump.rdb /tmp/redis-backup.rdb
              aws s3 cp /tmp/redis-backup.rdb s3://k8s-platform-prod-backups/redis/$(date +%Y%m%d-%H%M%S).rdb
          restartPolicy: OnFailure
EOF
```

### Médio Prazo (Próximo mês)

Implementar **Opção A** (Velero):
1. Staging environment testing
2. Load testing (impact analysis)
3. Production deployment
4. Monitoring setup
5. Runbook development

### Documentação

- [ ] Criar BACKUP-STRATEGY-CURRENT.md (o que está implementado agora)
- [ ] Criar BACKUP-MIGRATION-PLAN.md (como ir de B para A)
- [ ] Criar DISASTER-RECOVERY-RUNBOOK.md (como restaurar)
- [ ] Definir SLA de RPO/RTO

---

## 📋 Pré-requisitos de Implementação

### Para Velero

```bash
# S3 bucket
aws s3 mb s3://k8s-platform-prod-velero-backups-891377105802

# IAM Role
aws iam create-role --role-name velero-role \
  --assume-role-policy-document file://trust-policy.json

# IAM Policy
aws iam put-role-policy --role-name velero-role \
  --policy-name velero-policy \
  --policy-document file://policy.json

# ServiceAccount + IRSA
kubectl create serviceaccount velero -n velero
```

### Para Hybrid

```bash
# S3 buckets
aws s3 mb s3://k8s-platform-prod-backups-891377105802
aws s3api put-bucket-versioning \
  --bucket k8s-platform-prod-backups-891377105802 \
  --versioning-configuration Status=Enabled

# ServiceAccount com permissões S3
```

---

## 📊 RPO/RTO TARGETS

| Componente    | Data Type      | RPO (Max Age) | RTO (Max Downtime) | Criticidade  |
| ------------- | -------------- | ------------- | ------------------ | ------------ |
| PostgreSQL    | Application DB | 1 dia         | 30 min             | 🔴 CRÍTICO    |
| Redis         | Cache          | 1 hora        | 15 min             | 🟡 IMPORTANTE |
| RabbitMQ      | Message Queue  | 6 horas       | 30 min             | 🟡 IMPORTANTE |
| Vault         | Secrets        | 1 dia         | 15 min             | 🔴 CRÍTICO    |
| Observability | Logs/Metrics   | 7 dias        | 24 horas           | 🟢 BAIXO      |

---

## 🚨 AÇÕES IMEDIATAS (BLOQUEAR PRODUÇÃO)

| Item | Action                                        | Owner         | Deadline    |
| ---- | --------------------------------------------- | ------------- | ----------- |
| 1    | Verificar RDS backup retention no console AWS | DBA           | Hoje        |
| 2    | Verificar Redis/RabbitMQ backup strategy      | DevOps        | Hoje        |
| 3    | Criar incident se não houver backup           | Platform Lead | Hoje        |
| 4    | Escolher entre Opção A, B, ou C               | Architecture  | Amanhã      |
| 5    | Iniciar implementation                        | Platform Team | Esta semana |

---

**PRÓXIMA REVISÃO**: 2026-02-18 (quando Opção A/B for definida)
**OWNER**: Platform Team + Security
**ESCALATION**: CTO (se nenhuma backup strategy em 48 horas)

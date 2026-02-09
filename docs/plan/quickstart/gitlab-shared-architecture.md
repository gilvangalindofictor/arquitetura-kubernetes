# GitLab: Arquitetura de Instância Compartilhada com Migração Progressiva

**Documento:** Estratégia técnica de GitLab compartilhado entre ambientes
**Data:** 2026-02-09
**Status:** ✅ Aprovado

---

## 📋 Visão Geral

Este documento detalha a estratégia de **GitLab como instância única compartilhada** entre ambientes, com migração progressiva dos recursos de backend de **Staging** (Momento A) para **Produção** (Momento B).

### Decisão Estratégica

Ao invés de deployar múltiplas instâncias do GitLab (uma por ambiente), optamos por:

- ✅ **Uma única instância GitLab** deployada no namespace `cicd-gitlab`
- ✅ **Migração progressiva de backends**: Staging → Produção
- ✅ **Isolamento lógico**: Via branches, projetos, grupos e runners

---

## 🎯 Momento A - Fase Inicial (Validação)

### Objetivo

Validar a plataforma GitLab com **recursos de staging** (menor custo, risco reduzido).

### Arquitetura

```text
┌─────────────────────────────────────────────────────────┐
│ Namespace: cicd-gitlab (ÚNICO)                          │
│                                                         │
│  ┌─────────────────────────────────────────────────┐  │
│  │ GitLab CE (Helm Chart)                          │  │
│  │ ├── webservice (Deployment)                     │  │
│  │ ├── sidekiq (Deployment)                        │  │
│  │ ├── gitaly (StatefulSet)                        │  │
│  │ └── registry (Deployment)                       │  │
│  └─────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─────────────────────────────────────────────────┐  │
│  │ GitLab Runners (Helm Chart - separado)         │  │
│  │ ├── Runner Pool: staging-runners (2 replicas)  │  │
│  │ └── Runner Pool: generic-runners (2 replicas)  │  │
│  └─────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                      ↓ Conecta a ↓
┌─────────────────────────────────────────────────────────┐
│ Recursos de Backend: STAGING                            │
│                                                         │
│  ┌──────────────────────────────────────────────────┐ │
│  │ PostgreSQL RDS                                   │ │
│  │ - Instância: staging-gitlab-db                   │ │
│  │ - Tipo: db.t3.small Multi-AZ                     │ │
│  │ - Database: gitlabhq_production                  │ │
│  └──────────────────────────────────────────────────┘ │
│                                                         │
│  ┌──────────────────────────────────────────────────┐ │
│  │ Redis (Spotahome Operator)                       │ │
│  │ - Nome: staging-redis                            │ │
│  │ - Tipo: Single instance (1 master)               │ │
│  │ - Uso: Cache + sessions + job queue             │ │
│  └──────────────────────────────────────────────────┘ │
│                                                         │
│  ┌──────────────────────────────────────────────────┐ │
│  │ RabbitMQ (RabbitMQ Operator)                     │ │
│  │ - Nome: staging-rabbitmq                         │ │
│  │ - Tipo: Single instance                          │ │
│  │ - Uso: Async jobs + webhooks                     │ │
│  └──────────────────────────────────────────────────┘ │
│                                                         │
│  ┌──────────────────────────────────────────────────┐ │
│  │ S3 (Object Storage)                              │ │
│  │ - Bucket: staging-gitlab-artifacts               │ │
│  │ - Uso: Artifacts, uploads, LFS, packages         │ │
│  └──────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Configuração Helm Values (Momento A)

```yaml
# values-momento-a.yaml
global:
  edition: ce
  hosts:
    domain: gitlab.example.com

  # Conexão com PostgreSQL RDS Staging
  psql:
    host: staging-gitlab-db.xxxxxxxxx.us-east-1.rds.amazonaws.com
    port: 5432
    database: gitlabhq_production
    username: gitlab
    password:
      secret: gitlab-postgresql-secret
      key: password

  # Conexão com Redis Staging
  redis:
    host: staging-redis-master.default.svc.cluster.local
    port: 6379
    password:
      enabled: true
      secret: staging-redis-secret
      key: password

  # Object Storage - S3 Staging
  appConfig:
    object_store:
      enabled: true
      connection:
        secret: gitlab-s3-staging-secret
        key: connection
    lfs:
      enabled: true
      bucket: staging-gitlab-artifacts
    artifacts:
      enabled: true
      bucket: staging-gitlab-artifacts
    uploads:
      enabled: true
      bucket: staging-gitlab-artifacts
    packages:
      enabled: true
      bucket: staging-gitlab-artifacts

# Desabilitar subcharts (usamos serviços externos)
postgresql:
  install: false
redis:
  install: false
```

### Características do Momento A

| Aspecto | Configuração |
|---------|-------------|
| **Custo Mensal** | ~R$ 1.200 (recursos staging) |
| **Disponibilidade** | 8h/dia útil (automação start/stop) |
| **RTO** | 15 minutos (cold start) |
| **RPO** | 24 horas (snapshots diários) |
| **Capacidade** | 10-20 usuários, 50 repos, 100 pipelines/dia |
| **Uso recomendado** | Validação, testes, homologação |

---

## 🚀 Momento B - Fase Produção (Após Validação)

### Objetivo

Migrar GitLab para **recursos de produção** (alta disponibilidade, performance, 24/7).

### Arquitetura

```text
┌─────────────────────────────────────────────────────────┐
│ Namespace: cicd-gitlab (MESMA instância)                │
│                                                         │
│  ┌─────────────────────────────────────────────────┐  │
│  │ GitLab CE (Helm Chart) - SEM MUDANÇAS          │  │
│  │ ├── webservice (Deployment)                     │  │
│  │ ├── sidekiq (Deployment)                        │  │
│  │ ├── gitaly (StatefulSet)                        │  │
│  │ └── registry (Deployment)                       │  │
│  └─────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─────────────────────────────────────────────────┐  │
│  │ GitLab Runners (Reconfigurados)                 │  │
│  │ ├── Runner Pool: prod-runners (4 replicas) ✅   │  │
│  │ ├── Runner Pool: staging-runners (2 replicas)  │  │
│  │ └── Runner Pool: generic-runners (2 replicas)  │  │
│  └─────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                      ↓ Conecta a ↓
┌─────────────────────────────────────────────────────────┐
│ Recursos de Backend: PRODUÇÃO ✅ MIGRADO                │
│                                                         │
│  ┌──────────────────────────────────────────────────┐ │
│  │ PostgreSQL RDS                                   │ │
│  │ - Instância: prod-gitlab-db ✅                   │ │
│  │ - Tipo: db.t3.medium Multi-AZ ✅                 │ │
│  │ - Backup: Snapshots automáticos + PITR          │ │
│  │ - Retenção: 30 dias                              │ │
│  └──────────────────────────────────────────────────┘ │
│                                                         │
│  ┌──────────────────────────────────────────────────┐ │
│  │ Redis (Spotahome Operator) ✅                    │ │
│  │ - Nome: prod-redis                               │ │
│  │ - Tipo: HA (master-replica + sentinel) ✅        │ │
│  │ - Replicas: 1 master + 2 slaves + 3 sentinels   │ │
│  │ - Persistência: PVC + snapshots                  │ │
│  └──────────────────────────────────────────────────┘ │
│                                                         │
│  ┌──────────────────────────────────────────────────┐ │
│  │ RabbitMQ (RabbitMQ Operator) ✅                  │ │
│  │ - Nome: prod-rabbitmq                            │ │
│  │ - Tipo: Cluster (3 nodes) ✅                     │ │
│  │ - Quorum Queues: Habilitado                      │ │
│  │ - Replicação: 3x (HA completa)                   │ │
│  └──────────────────────────────────────────────────┘ │
│                                                         │
│  ┌──────────────────────────────────────────────────┐ │
│  │ S3 (Object Storage) ✅                           │ │
│  │ - Bucket: prod-gitlab-artifacts                  │ │
│  │ - Versionamento: Habilitado                      │ │
│  │ - Replicação: Cross-region (opcional)            │ │
│  └──────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### Configuração Helm Values (Momento B)

```yaml
# values-momento-b.yaml (APENAS AS MUDANÇAS)
global:
  # Conexão com PostgreSQL RDS Produção ✅
  psql:
    host: prod-gitlab-db.xxxxxxxxx.us-east-1.rds.amazonaws.com
    # Resto igual, apenas muda o host e secret
    password:
      secret: gitlab-postgresql-prod-secret

  # Conexão com Redis Produção HA ✅
  redis:
    host: prod-redis-master.default.svc.cluster.local
    sentinels:
      - host: prod-redis-sentinel-0.default.svc.cluster.local
        port: 26379
      - host: prod-redis-sentinel-1.default.svc.cluster.local
        port: 26379
      - host: prod-redis-sentinel-2.default.svc.cluster.local
        port: 26379
    password:
      secret: prod-redis-secret

  # Object Storage - S3 Produção ✅
  appConfig:
    object_store:
      connection:
        secret: gitlab-s3-prod-secret
    lfs:
      bucket: prod-gitlab-artifacts
    artifacts:
      bucket: prod-gitlab-artifacts
    uploads:
      bucket: prod-gitlab-artifacts
    packages:
      bucket: prod-gitlab-artifacts
```

### Características do Momento B

| Aspecto | Configuração |
|---------|-------------|
| **Custo Mensal** | ~R$ 2.800 (recursos produção) |
| **Disponibilidade** | 24/7 (99.9% SLA) |
| **RTO** | < 5 minutos (HA automático) |
| **RPO** | < 1 hora (PITR + backups frequentes) |
| **Capacidade** | 100+ usuários, 500+ repos, 1000+ pipelines/dia |
| **Uso recomendado** | Produção, critical workloads |

---

## 🔄 Estratégia de Migração (A → B)

### Pré-requisitos

- ✅ GitLab operacional no Momento A (validado por 2-4 semanas)
- ✅ Recursos de produção provisionados (RDS, Redis HA, RabbitMQ cluster)
- ✅ Backup completo realizado e validado
- ✅ Janela de manutenção agendada (recomendado: fora de horário comercial)

### Passos da Migração

#### 1. Backup Completo (Momento A)

```bash
# Criar backup completo do GitLab
kubectl exec -n cicd-gitlab deploy/gitlab-webservice -- \
  gitlab-backup create SKIP=registry,uploads

# Backup do PostgreSQL RDS
aws rds create-db-snapshot \
  --db-instance-identifier staging-gitlab-db \
  --db-snapshot-identifier gitlab-migration-snapshot-$(date +%Y%m%d)

# Backup do Redis
kubectl exec -n default redis-master-0 -- \
  redis-cli BGSAVE

# Copiar dados do S3 staging → prod
aws s3 sync s3://staging-gitlab-artifacts s3://prod-gitlab-artifacts \
  --delete
```

#### 2. Provisionar Recursos de Produção

```bash
# RDS Produção (via Terraform)
cd platform-provisioning/aws/kubernetes/terraform/modules/rds/
terraform apply -target=aws_db_instance.gitlab_prod

# Redis HA (via Operator)
kubectl apply -f - <<EOF
apiVersion: databases.spotahome.com/v1
kind: RedisFailover
metadata:
  name: prod-redis
spec:
  sentinel:
    replicas: 3
  redis:
    replicas: 3
    resources:
      requests:
        cpu: 100m
        memory: 512Mi
      limits:
        cpu: 500m
        memory: 2Gi
EOF

# RabbitMQ Cluster (via Operator)
kubectl apply -f - <<EOF
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: prod-rabbitmq
spec:
  replicas: 3
  persistence:
    storageClassName: gp3
    storage: 20Gi
EOF
```

#### 3. Migrar Dados

```bash
# Migrar PostgreSQL (staging → prod)
# 1. Dump do staging
pg_dump -h staging-gitlab-db.xxx.rds.amazonaws.com \
  -U gitlab gitlabhq_production > gitlab-staging.sql

# 2. Restore no prod
psql -h prod-gitlab-db.xxx.rds.amazonaws.com \
  -U gitlab gitlabhq_production < gitlab-staging.sql

# Sincronizar Redis (se necessário)
# Dados do Redis são cache/sessões, podem ser recriados

# Sincronizar RabbitMQ
# Exportar definições (exchanges, queues)
rabbitmqctl export_definitions staging-rabbitmq-definitions.json
rabbitmqctl import_definitions staging-rabbitmq-definitions.json \
  --node prod-rabbitmq
```

#### 4. Atualizar Configuração GitLab

```bash
# Criar novo values file com backends de produção
cd /path/to/helm/values/
cp values-momento-a.yaml values-momento-b.yaml

# Editar values-momento-b.yaml:
# - global.psql.host → prod-gitlab-db...
# - global.redis.host → prod-redis-master...
# - global.appConfig.object_store.*.bucket → prod-gitlab-artifacts
```

#### 5. Rollout GitLab (Zero Downtime)

```bash
# Atualizar secrets com credenciais de produção
kubectl create secret generic gitlab-postgresql-prod-secret \
  -n cicd-gitlab \
  --from-literal=password=PROD_DB_PASSWORD

kubectl create secret generic prod-redis-secret \
  -n cicd-gitlab \
  --from-literal=password=PROD_REDIS_PASSWORD

# Helm upgrade com novos values (rolling update)
helm upgrade gitlab gitlab/gitlab \
  -n cicd-gitlab \
  -f values-momento-b.yaml \
  --timeout 15m \
  --wait

# Aguardar rollout completo
kubectl rollout status deployment/gitlab-webservice -n cicd-gitlab
kubectl rollout status deployment/gitlab-sidekiq -n cicd-gitlab
```

#### 6. Validação Pós-Migração

```bash
# Verificar conectividade
kubectl exec -n cicd-gitlab deploy/gitlab-webservice -- \
  gitlab-rake gitlab:env:info

# Testar banco de dados
kubectl exec -n cicd-gitlab deploy/gitlab-webservice -- \
  gitlab-rails dbconsole -p

# Verificar Redis
kubectl exec -n cicd-gitlab deploy/gitlab-webservice -- \
  redis-cli -h prod-redis-master ping

# Smoke tests
# 1. Login no GitLab
# 2. Criar projeto de teste
# 3. Executar pipeline
# 4. Verificar artifacts
```

#### 7. Descomissionar Recursos Staging (Opcional)

```bash
# Parar recursos staging (economia de custos)
aws rds stop-db-instance --db-instance-identifier staging-gitlab-db

kubectl scale statefulset staging-redis-master --replicas=0
kubectl scale deployment staging-rabbitmq --replicas=0

# Ou deletar completamente
terraform destroy -target=aws_db_instance.gitlab_staging
kubectl delete redisfailover staging-redis
kubectl delete rabbitmqcluster staging-rabbitmq
```

---

## 📊 Comparativo: Instância Única vs Múltiplas Instâncias

### Arquitetura: Instância Única (ADOTADA)

| Aspecto | Detalhes |
|---------|----------|
| **Instâncias GitLab** | 1 (compartilhada) |
| **Namespaces** | 1 (`cicd-gitlab`) |
| **Recursos Computacionais** | 1x webservice, 1x sidekiq, 1x gitaly |
| **Custo GitLab App** | ~R$ 800/mês (1 instância) |
| **Custo Backends (Momento A)** | ~R$ 400/mês (staging) |
| **Custo Backends (Momento B)** | ~R$ 2.000/mês (produção) |
| **Gestão** | Simplificada (1 instância para administrar) |
| **Migração** | Via configuração (sem downtime) |

**Total Momento A**: ~R$ 1.200/mês
**Total Momento B**: ~R$ 2.800/mês

### Arquitetura: Múltiplas Instâncias (ALTERNATIVA NÃO ESCOLHIDA)

| Aspecto | Detalhes |
|---------|----------|
| **Instâncias GitLab** | 2 (staging + prod) |
| **Namespaces** | 2 (`cicd-gitlab-staging`, `cicd-gitlab-prod`) |
| **Recursos Computacionais** | 2x webservice, 2x sidekiq, 2x gitaly |
| **Custo GitLab App** | ~R$ 1.600/mês (2 instâncias) |
| **Custo Backends (Staging)** | ~R$ 400/mês |
| **Custo Backends (Prod)** | ~R$ 2.000/mês |
| **Gestão** | Complexa (2 instâncias, sincronização manual) |
| **Migração** | Via export/import (com downtime) |

**Total**: ~R$ 4.000/mês

### Economia com Instância Única

```text
Momento A (validação): R$ 1.200/mês
Momento B (produção):  R$ 2.800/mês

vs

Múltiplas Instâncias:  R$ 4.000/mês

Economia no Momento B: R$ 1.200/mês (30% de redução)
Economia anual:        R$ 14.400/ano
```

---

## ✅ Benefícios da Abordagem Adotada

### 1. Economia de Custos

- ✅ Uma única instância GitLab (50% menos recursos computacionais)
- ✅ Migração progressiva (não paga por recursos prod enquanto valida)
- ✅ Redução de ~30% no custo final

### 2. Gestão Simplificada

- ✅ Apenas um GitLab para administrar
- ✅ Usuários, grupos, permissões centralizados
- ✅ Configuração única (single source of truth)
- ✅ Backup e DR simplificados

### 3. Migração Sem Downtime

- ✅ Troca de backend via Helm upgrade (rolling update)
- ✅ Zero downtime para usuários
- ✅ Rollback fácil (helm rollback)

### 4. Validação Segura

- ✅ Iniciar com recursos staging (menor risco)
- ✅ Validar por 2-4 semanas antes de escalar
- ✅ Migração apenas quando plataforma estiver madura

### 5. Isolamento Lógico Suficiente

- ✅ **Projetos e Grupos**: Separação por namespace GitLab (não K8s)
- ✅ **Branches**: `main` (prod), `staging`, `develop`
- ✅ **Runners**: Pools dedicados por ambiente (tags)
- ✅ **CI/CD Variables**: Scoped por branch/environment

---

## 🔐 Estratégias de Isolamento Lógico

### 1. Organização de Projetos

```text
GitLab Root
├── group: platform-team
│   ├── project: infrastructure (prod)
│   └── project: infrastructure-staging
├── group: data-team
│   ├── project: etl-hatch (prod)
│   └── project: etl-hatch-staging
└── group: integration-team
    ├── project: ipaas (prod)
    └── project: ipaas-staging
```

### 2. Runners com Tags

```yaml
# Runner Pool: Produção
runners:
  - name: prod-runner-1
    tags: [prod, production, deploy-prod]
    runUntagged: false

# Runner Pool: Staging
runners:
  - name: staging-runner-1
    tags: [staging, homolog, deploy-staging]
    runUntagged: false

# Runner Pool: Generic
runners:
  - name: generic-runner-1
    tags: [build, test, scan]
    runUntagged: true
```

### 3. CI/CD Variables Scoped

```yaml
# .gitlab-ci.yml
variables:
  DATABASE_URL: "$DATABASE_URL"  # Scoped per environment

deploy-staging:
  stage: deploy
  tags: [staging]
  environment:
    name: staging
  variables:
    DATABASE_URL: "postgres://staging-db:5432/app"
  script:
    - helm upgrade --install app ./chart

deploy-prod:
  stage: deploy
  tags: [prod]
  environment:
    name: production
  variables:
    DATABASE_URL: "postgres://prod-db:5432/app"
  script:
    - helm upgrade --install app ./chart
  when: manual  # Require approval
```

---

## 📖 Referências

### Documentação do Projeto

- [README Principal](../../../README.md) - Visão geral da plataforma
- [Quickstart README](README.md) - Plano de implementação
- [Cenários Explicados](cenarios-explicados.md) - Estratégias de custo

### Helm Charts

- [GitLab Helm Chart](https://docs.gitlab.com/charts/)
- [GitLab Runner Helm Chart](https://docs.gitlab.com/runner/install/kubernetes.html)

### Operators

- [Spotahome Redis Operator](https://github.com/spotahome/redis-operator)
- [RabbitMQ Cluster Operator](https://github.com/rabbitmq/cluster-operator)

---

**Última atualização**: 2026-02-09
**Status**: ✅ Aprovado para Implementação
**Responsável**: Equipe Platform Engineering

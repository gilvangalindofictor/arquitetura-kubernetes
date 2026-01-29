# 03 - Data Services (RDS + Kubernetes Operators)

**Épico C** | **Esforço: 24 person-hours** | **Sprint 1** | **Atualizado: 2026-01-29**

> ⚠️ **Mudança Estratégica (ADR-023):** Este documento foi atualizado para refletir a migração de Bitnami Helm Charts para Kubernetes Operators.
>
> **Decisão:** Spotahome Redis Operator + RabbitMQ Cluster Operator (economia $72,900/ano vs Tanzu Standard)
>
> **Referência:** [ADR-023: Migration from Bitnami Charts to Kubernetes Operators](../../context/decisions.md#adr-023)

---

## Sumário

1. [Visão Geral](#1-visão-geral)
2. [Task C.1: RDS PostgreSQL Multi-AZ (4h)](#2-task-c1-rds-postgresql-multi-az-4h)
3. [Task C.2: Redis via Spotahome Operator (10h)](#3-task-c2-redis-via-spotahome-operator-10h)
4. [Task C.3: RabbitMQ via Cluster Operator (10h)](#4-task-c3-rabbitmq-via-cluster-operator-10h)
5. [Validação e Definition of Done](#5-validação-e-definition-of-done)
6. [Troubleshooting](#6-troubleshooting)
7. [Referências ADR-023](#7-referências-adr-023)

---

## 1. Visão Geral

### Objetivo

Provisionar os serviços de dados necessários para a plataforma:

| Serviço | Abordagem | Propósito | Decisão ADR |
|---------|-----------|-----------|-------------|
| **PostgreSQL** | AWS RDS (gerenciado) | Banco de dados para GitLab, Keycloak, SonarQube | - |
| **Redis** | **Spotahome Redis Operator** | Cache e sessões (HA automático) | **ADR-023** |
| **RabbitMQ** | **RabbitMQ Cluster Operator** | Mensageria (quorum queues) | **ADR-023** |

### Arquitetura

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           DATA SERVICES LAYER                               │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     RDS PostgreSQL (Multi-AZ)                        │   │
│  │                                                                      │   │
│  │  ┌─────────────────┐      ┌─────────────────┐                       │   │
│  │  │ Primary         │      │ Standby         │                       │   │
│  │  │ us-east-1a      │◀────▶│ us-east-1b      │                       │   │
│  │  │                 │ Sync │                 │                       │   │
│  │  │ • gitlab_prod   │ Repl │                 │                       │   │
│  │  │ • keycloak      │      │                 │                       │   │
│  │  │ • sonarqube     │      │                 │                       │   │
│  │  └─────────────────┘      └─────────────────┘                       │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                  NAMESPACE: redis                                    │   │
│  │                                                                      │   │
│  │  ┌─────────────────┐      ┌─────────────────┐                       │   │
│  │  │ redis-master    │      │ redis-replicas  │                       │   │
│  │  │ (StatefulSet)   │◀────▶│ (StatefulSet)   │                       │   │
│  │  │                 │ Repl │ 2 replicas      │                       │   │
│  │  └─────────────────┘      └─────────────────┘                       │   │
│  │            │                                                         │   │
│  │            ▼                                                         │   │
│  │  ┌─────────────────┐                                                │   │
│  │  │ redis-sentinel  │ (HA Failover)                                  │   │
│  │  │ 3 instances     │                                                │   │
│  │  └─────────────────┘                                                │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                  NAMESPACE: rabbitmq                                 │   │
│  │                                                                      │   │
│  │  ┌─────────────────┐                                                │   │
│  │  │ rabbitmq        │ (StatefulSet - 3 replicas)                     │   │
│  │  │ Cluster Mode    │                                                │   │
│  │  │ Quorum Queues   │                                                │   │
│  │  │ Management UI   │                                                │   │
│  │  └─────────────────┘                                                │   │
│  │                                                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Kubernetes Operators Utilizados

| Operator | CRD | Repository | Versão |
|----------|-----|------------|--------|
| **Spotahome Redis Operator** | `RedisFailover` | https://github.com/spotahome/redis-operator | v1.3.x |
| **RabbitMQ Cluster Operator** | `RabbitmqCluster` | https://github.com/rabbitmq/cluster-operator | v2.x |

**Referência Estratégica:** [ADR-023 - Migration from Bitnami Charts to Kubernetes Operators](../../context/decisions.md#adr-023)

**Benefícios vs Bitnami Helm Charts:**
- ✅ **Economia:** $72,900/ano (evita Tanzu Standard $72k + redução infra $900)
- ✅ **HA Superior:** Failover automático < 30s (vs 5-6 min manual)
- ✅ **Backups Nativos:** CronJobs automáticos (vs scripts manuais)
- ✅ **Cloud-Agnostic:** Portável GCP/Azure sem refactoring
- ✅ **Zero-Downtime Upgrades:** Rolling updates

---

## 2. Task C.1: RDS PostgreSQL Multi-AZ (4h)

### 2.1 Criar RDS PostgreSQL

#### Opção A: Terraform (Recomendado - IaC)

```hcl
# terraform/03-rds/main.tf

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Gerar senha segura
resource "random_password" "master" {
  length  = 32
  special = false
}

# DB Subnet Group
resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.database_subnet_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

# Parameter Group
resource "aws_db_parameter_group" "postgres15" {
  family = "postgres15"
  name   = "${var.project_name}-${var.environment}-postgres15"

  parameter {
    name  = "max_connections"
    value = "200"
  }

  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/4}"
  }

  parameter {
    name  = "work_mem"
    value = "65536"  # 64MB em KB
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-postgres15"
  }
}

# RDS Instance
module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "${var.project_name}-${var.environment}-postgresql"

  engine               = "postgres"
  engine_version       = "15.4"
  family               = "postgres15"
  major_engine_version = "15"
  instance_class       = "db.t3.medium"

  allocated_storage     = 100
  max_allocated_storage = 500
  storage_type          = "gp3"
  storage_encrypted     = true
  iops                  = 3000
  storage_throughput    = 125

  db_name  = "platform"
  username = "postgres_admin"
  password = random_password.master.result
  port     = 5432

  multi_az               = true
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.rds_security_group_id]
  parameter_group_name   = aws_db_parameter_group.postgres15.name

  maintenance_window      = "Sun:04:00-Sun:05:00"
  backup_window           = "03:00-04:00"
  backup_retention_period = 7

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  create_cloudwatch_log_group     = true

  deletion_protection = true
  skip_final_snapshot = false

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  tags = {
    Project     = var.project_name
    Environment = var.environment
    CostCenter  = "infrastructure"
  }
}

# Armazenar credenciais no Secrets Manager
resource "aws_secretsmanager_secret" "rds_master" {
  name = "${var.project_name}/${var.environment}/rds/master-credentials"

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "rds_master" {
  secret_id = aws_secretsmanager_secret.rds_master.id
  secret_string = jsonencode({
    username = module.rds.db_instance_username
    password = random_password.master.result
    host     = module.rds.db_instance_address
    port     = module.rds.db_instance_port
    database = "platform"
    engine   = "postgres"
  })
}

# Outputs
output "rds_endpoint" {
  value = module.rds.db_instance_endpoint
}

output "rds_secret_arn" {
  value = aws_secretsmanager_secret.rds_master.arn
}
```

#### Opção B: AWS CLI (Completo)

```bash
#!/bin/bash
# scripts/create-rds.sh

set -euo pipefail

PROJECT_NAME="k8s-platform"
ENVIRONMENT="prod"
REGION="us-east-1"

echo "🗄️ Criando RDS PostgreSQL Multi-AZ..."

# Obter IDs necessários
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${PROJECT_NAME}-${ENVIRONMENT}-vpc" --query "Vpcs[0].VpcId" --output text)
DB_SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*db*" --query "Subnets[*].SubnetId" --output text | tr '\t' ' ')
RDS_SG=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=${PROJECT_NAME}-${ENVIRONMENT}-rds-sg" --query "SecurityGroups[0].GroupId" --output text)

# 1. Criar DB Subnet Group
echo "📦 Criando DB Subnet Group..."
aws rds create-db-subnet-group \
  --db-subnet-group-name "${PROJECT_NAME}-${ENVIRONMENT}-db-subnet-group" \
  --db-subnet-group-description "Subnet group para RDS da plataforma Kubernetes" \
  --subnet-ids $DB_SUBNETS \
  --tags Key=Project,Value=$PROJECT_NAME Key=Environment,Value=$ENVIRONMENT
echo "✅ DB Subnet Group criado"

# 2. Criar Parameter Group
echo "📝 Criando Parameter Group..."
aws rds create-db-parameter-group \
  --db-parameter-group-name "${PROJECT_NAME}-${ENVIRONMENT}-postgres15" \
  --db-parameter-group-family postgres15 \
  --description "Parâmetros otimizados para GitLab e plataforma K8s" \
  --tags Key=Project,Value=$PROJECT_NAME Key=Environment,Value=$ENVIRONMENT

# Configurar parâmetros
aws rds modify-db-parameter-group \
  --db-parameter-group-name "${PROJECT_NAME}-${ENVIRONMENT}-postgres15" \
  --parameters \
    "ParameterName=max_connections,ParameterValue=200,ApplyMethod=pending-reboot" \
    "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate" \
    "ParameterName=log_statement,ParameterValue=ddl,ApplyMethod=immediate"
echo "✅ Parameter Group criado e configurado"

# 3. Gerar senha segura
MASTER_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)
echo "🔐 Senha master gerada (guarde com segurança!)"

# 4. Criar instância RDS
echo "🚀 Criando instância RDS (isso leva ~15 minutos)..."
aws rds create-db-instance \
  --db-instance-identifier "${PROJECT_NAME}-${ENVIRONMENT}-postgresql" \
  --db-instance-class db.t3.medium \
  --engine postgres \
  --engine-version 15.4 \
  --master-username postgres_admin \
  --master-user-password "$MASTER_PASSWORD" \
  --allocated-storage 100 \
  --max-allocated-storage 500 \
  --storage-type gp3 \
  --iops 3000 \
  --storage-throughput 125 \
  --storage-encrypted \
  --db-subnet-group-name "${PROJECT_NAME}-${ENVIRONMENT}-db-subnet-group" \
  --vpc-security-group-ids $RDS_SG \
  --db-parameter-group-name "${PROJECT_NAME}-${ENVIRONMENT}-postgres15" \
  --db-name platform \
  --backup-retention-period 7 \
  --preferred-backup-window "03:00-04:00" \
  --preferred-maintenance-window "sun:04:00-sun:05:00" \
  --multi-az \
  --auto-minor-version-upgrade \
  --deletion-protection \
  --enable-cloudwatch-logs-exports postgresql upgrade \
  --enable-performance-insights \
  --performance-insights-retention-period 7 \
  --tags Key=Project,Value=$PROJECT_NAME Key=Environment,Value=$ENVIRONMENT Key=CostCenter,Value=infrastructure

echo "⏳ Aguardando RDS ficar disponível..."
aws rds wait db-instance-available --db-instance-identifier "${PROJECT_NAME}-${ENVIRONMENT}-postgresql"
echo "✅ RDS disponível!"

# 5. Obter endpoint
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "${PROJECT_NAME}-${ENVIRONMENT}-postgresql" \
  --query "DBInstances[0].Endpoint.Address" --output text)
echo "📍 RDS Endpoint: $RDS_ENDPOINT"

# 6. Armazenar credenciais no Secrets Manager
echo "🔒 Armazenando credenciais no Secrets Manager..."
aws secretsmanager create-secret \
  --name "${PROJECT_NAME}/${ENVIRONMENT}/rds/master-credentials" \
  --description "Credenciais master do RDS PostgreSQL" \
  --secret-string "{\"username\":\"postgres_admin\",\"password\":\"$MASTER_PASSWORD\",\"host\":\"$RDS_ENDPOINT\",\"port\":\"5432\",\"database\":\"platform\",\"engine\":\"postgres\"}" \
  --tags Key=Project,Value=$PROJECT_NAME Key=Environment,Value=$ENVIRONMENT

echo "✅ Credenciais armazenadas no Secrets Manager"

# 7. Criar secrets para cada aplicação
for APP in gitlab keycloak sonarqube harbor; do
  APP_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)
  aws secretsmanager create-secret \
    --name "${PROJECT_NAME}/${ENVIRONMENT}/${APP}/database" \
    --description "Credenciais do database para ${APP}" \
    --secret-string "{\"username\":\"${APP}_user\",\"password\":\"$APP_PASSWORD\",\"host\":\"$RDS_ENDPOINT\",\"port\":\"5432\",\"database\":\"${APP}_production\"}" \
    --tags Key=Project,Value=$PROJECT_NAME Key=Environment,Value=$ENVIRONMENT Key=Application,Value=$APP
  echo "✅ Secret criado para $APP"
done

echo ""
echo "📋 Resumo:"
echo "  RDS Endpoint: $RDS_ENDPOINT"
echo "  Secrets Manager: ${PROJECT_NAME}/${ENVIRONMENT}/rds/master-credentials"
echo ""
echo "🎉 RDS PostgreSQL criado com sucesso!"
```

#### Opção C: Console AWS (Referência Visual)

> ⚠️ **Nota:** Prefira as opções A (Terraform) ou B (CLI) para ambientes de produção.

### 2.1.1 Criar DB Subnet Group (Console)

**Passo a passo no Console AWS:**

1. Na barra de busca, digite `RDS` e clique em **RDS**
2. Menu lateral, clique em **Subnet groups**
3. Clique em **Create DB subnet group**
4. Preencha:

   | Campo | Valor |
   |-------|-------|
   | **Name** | `k8s-platform-prod-db-subnet-group` |
   | **Description** | `Subnet group para RDS da plataforma Kubernetes` |
   | **VPC** | Selecione `k8s-platform-prod-vpc` |

   **Add subnets:**
   | Campo | Valor |
   |-------|-------|
   | **Availability Zones** | Selecione `us-east-1a`, `us-east-1b`, `us-east-1c` |
   | **Subnets** | Selecione as 3 subnets de DB (10.0.21.0/24, 10.0.22.0/24, 10.0.23.0/24) |

5. Clique em **Create**

---

### 2.2 Criar Parameter Group (Otimizado)

1. Menu lateral, clique em **Parameter groups**
2. Clique em **Create parameter group**
3. Preencha:

   | Campo | Valor |
   |-------|-------|
   | **Parameter group family** | `postgres15` |
   | **Type** | DB Parameter Group |
   | **Group name** | `k8s-platform-prod-postgres15` |
   | **Description** | `Parâmetros otimizados para GitLab e plataforma K8s` |

4. Clique em **Create**
5. Selecione o parameter group criado
6. Clique em **Edit parameters**
7. Modifique os parâmetros:

   | Parameter | Value | Descrição |
   |-----------|-------|-----------|
   | `max_connections` | `200` | Conexões simultâneas |
   | `shared_buffers` | `{DBInstanceClassMemory/4}` | 25% da RAM |
   | `work_mem` | `64MB` | Memória por operação |
   | `maintenance_work_mem` | `512MB` | Memória para manutenção |
   | `effective_cache_size` | `{DBInstanceClassMemory*3/4}` | 75% da RAM |
   | `log_min_duration_statement` | `1000` | Log queries > 1s |
   | `log_statement` | `ddl` | Log DDL statements |

8. Clique em **Save changes**

---

### 2.3 Criar Instância RDS PostgreSQL

**Passo a passo no Console AWS:**

1. Menu lateral, clique em **Databases**
2. Clique em **Create database**
3. Preencha:

   **Choose a database creation method:**
   | Campo | Valor |
   |-------|-------|
   | **Method** | Standard create |

   **Engine options:**
   | Campo | Valor |
   |-------|-------|
   | **Engine type** | PostgreSQL |
   | **Engine version** | PostgreSQL 15.4-R2 (ou mais recente) |

   **Templates:**
   | Campo | Valor |
   |-------|-------|
   | **Template** | Production |

   **Availability and durability:**
   | Campo | Valor |
   |-------|-------|
   | **Deployment** | Multi-AZ DB instance |

   **Settings:**
   | Campo | Valor |
   |-------|-------|
   | **DB instance identifier** | `k8s-platform-prod-postgresql` |
   | **Master username** | `postgres_admin` |
   | **Credentials management** | Self managed |
   | **Master password** | (gere senha forte 32+ chars) |

   **Instance configuration:**
   | Campo | Valor |
   |-------|-------|
   | **DB instance class** | Burstable classes (t3) |
   | **Instance type** | `db.t3.medium` (2 vCPU, 4 GB) |

   **Storage:**
   | Campo | Valor |
   |-------|-------|
   | **Storage type** | General Purpose SSD (gp3) |
   | **Allocated storage** | `100` GB |
   | **Storage autoscaling** | ✅ Enable |
   | **Maximum storage threshold** | `500` GB |
   | **Provisioned IOPS** | `3000` |
   | **Storage throughput** | `125` MB/s |

   **Connectivity:**
   | Campo | Valor |
   |-------|-------|
   | **Compute resource** | Don't connect to EC2 |
   | **Network type** | IPv4 |
   | **VPC** | `k8s-platform-prod-vpc` |
   | **DB subnet group** | `k8s-platform-prod-db-subnet-group` |
   | **Public access** | **No** |
   | **VPC security group** | Choose existing |
   | **Existing VPC security groups** | `k8s-platform-prod-rds-sg` |

   **Database authentication:**
   | Campo | Valor |
   |-------|-------|
   | **Authentication** | Password authentication |

   **Monitoring:**
   | Campo | Valor |
   |-------|-------|
   | **Enhanced monitoring** | ✅ Enable |
   | **Granularity** | 60 seconds |
   | **Monitoring Role** | Create new role |

   **Additional configuration:**
   | Campo | Valor |
   |-------|-------|
   | **Initial database name** | `platform` |
   | **DB parameter group** | `k8s-platform-prod-postgres15` |
   | **Backup retention** | 7 days |
   | **Backup window** | Select window → `03:00-04:00 UTC` |
   | **Encryption** | ✅ Enable |
   | **KMS key** | (default) aws/rds |
   | **Log exports** | ✅ PostgreSQL log, ✅ Upgrade log |
   | **Auto minor version upgrade** | ✅ Enable |
   | **Maintenance window** | Select window → `sun:04:00-sun:05:00 UTC` |
   | **Deletion protection** | ✅ Enable |

4. **Tags:**
   | Key | Value |
   |-----|-------|
   | `Project` | `k8s-platform` |
   | `Environment` | `prod` |
   | `Owner` | `devops-team` |
   | `CostCenter` | `infrastructure` |

5. Clique em **Create database**
6. **Aguarde a criação** (10-15 minutos)

---

### 2.4 Criar Databases e Usuários

Após o RDS estar disponível, conecte-se e crie os databases:

```bash
# Obter endpoint do RDS
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier k8s-platform-prod-postgresql --query "DBInstances[0].Endpoint.Address" --output text)
echo "RDS Endpoint: $RDS_ENDPOINT"

# Criar pod temporário para conexão
kubectl run psql-client --rm -it --restart=Never \
  --image=postgres:15-alpine \
  --env="PGPASSWORD=sua_senha_master" \
  -- psql -h $RDS_ENDPOINT -U postgres_admin -d platform
```

Execute os seguintes comandos SQL:

```sql
-- Criar databases
CREATE DATABASE gitlab_production;
CREATE DATABASE keycloak;
CREATE DATABASE sonarqube;
CREATE DATABASE harbor;

-- Criar usuários com senhas fortes
CREATE USER gitlab_user WITH ENCRYPTED PASSWORD 'gitlab_senha_segura_32chars';
CREATE USER keycloak_user WITH ENCRYPTED PASSWORD 'keycloak_senha_segura_32chars';
CREATE USER sonarqube_user WITH ENCRYPTED PASSWORD 'sonar_senha_segura_32chars';
CREATE USER harbor_user WITH ENCRYPTED PASSWORD 'harbor_senha_segura_32chars';

-- Conceder privilégios
GRANT ALL PRIVILEGES ON DATABASE gitlab_production TO gitlab_user;
GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak_user;
GRANT ALL PRIVILEGES ON DATABASE sonarqube TO sonarqube_user;
GRANT ALL PRIVILEGES ON DATABASE harbor TO harbor_user;

-- Conectar em cada database e conceder schema
\c gitlab_production
GRANT ALL ON SCHEMA public TO gitlab_user;

\c keycloak
GRANT ALL ON SCHEMA public TO keycloak_user;

\c sonarqube
GRANT ALL ON SCHEMA public TO sonarqube_user;

\c harbor
GRANT ALL ON SCHEMA public TO harbor_user;

-- Verificar
\l
\du
```

---

### 2.5 Armazenar Credenciais no Secrets Manager

**Passo a passo no Console AWS:**

1. Na barra de busca, digite `Secrets Manager`
2. Clique em **Store a new secret**
3. Para cada serviço, crie um secret:

   **Secret 1 - GitLab:**
   | Campo | Valor |
   |-------|-------|
   | **Secret type** | Other type of secret |
   | **Key/value** | `username`: `gitlab_user`, `password`: `<senha>`, `host`: `<endpoint>`, `database`: `gitlab_production` |
   | **Secret name** | `k8s-platform/prod/gitlab/database` |

4. Repita para `keycloak`, `sonarqube`, `harbor`

---

## 3. Task C.2: Redis via Spotahome Operator (10h)

> **Mudança Estratégica (ADR-023):** Substituímos `bitnami/redis` Helm chart por **Spotahome Redis Operator** devido à migração do Bitnami para licenciamento pago (Tanzu Standard $72k/ano).
>
> **Benefícios:**
> - ✅ Failover automático < 30s (vs 5-6 min manual)
> - ✅ Zero custo licenciamento
> - ✅ Backups CronJobs nativos
> - ✅ ServiceMonitors Prometheus out-of-the-box

### 3.1 Instalar Spotahome Redis Operator

```bash
# Adicionar repositório do Operator
helm repo add spotahome https://spotahome.github.io/redis-operator
helm repo update

# Verificar versão disponível
helm search repo spotahome/redis-operator --versions | head -5
```

---

### 3.2 Criar Namespaces

```bash
# Namespace para o Operator
kubectl create namespace redis-operator

# Namespace para instâncias Redis
kubectl create namespace redis

# Labels
kubectl label namespace redis-operator \
  project=k8s-platform \
  environment=prod \
  domain=operators

kubectl label namespace redis \
  project=k8s-platform \
  environment=prod \
  domain=data-services
```

---

### 3.3 Deploy Redis Operator

```bash
# Instalar Operator via Helm
helm install redis-operator spotahome/redis-operator \
  --namespace redis-operator \
  --version 3.3.0 \
  --set image.tag=v1.3.0 \
  --timeout 300s \
  --wait

# Verificar CRDs instalados
kubectl get crd | grep redis
# Saída esperada:
# redisfailovers.databases.spotahome.com

# Verificar Operator Running
kubectl get pods -n redis-operator
```

---

### 3.4 Criar RedisFailover CRD (HA Configuration)

```bash
cat > redis-failover.yaml <<'EOF'
# =============================================================================
# RedisFailover CRD - Spotahome Redis Operator
# =============================================================================
# Operator: redis-operator v1.3.0
# Mode: Sentinel-based HA (1 master + 2 replicas + 3 sentinels)
# =============================================================================
apiVersion: databases.spotahome.com/v1
kind: RedisFailover
metadata:
  name: redis-ha
  namespace: redis
  labels:
    project: k8s-platform
    environment: prod
    domain: data-services
spec:
  # -----------------------------------------------------------------------------
  # SENTINEL CONFIGURATION (High Availability)
  # -----------------------------------------------------------------------------
  sentinel:
    replicas: 3  # Quorum for automatic failover

# -----------------------------------------------------------------------------
# AUTHENTICATION
# -----------------------------------------------------------------------------
auth:
  enabled: true
  password: ""  # Será gerado automaticamente
  # Ou defina manualmente:
  # password: "sua_senha_redis_segura_32chars"

# -----------------------------------------------------------------------------
# MASTER CONFIGURATION
# -----------------------------------------------------------------------------
master:
  count: 1

  # Resources
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

  # Persistence
  persistence:
    enabled: true
    storageClass: gp3
    size: 8Gi

  # Node placement
  nodeSelector:
    node-type: workloads

  # Service
  service:
    type: ClusterIP
    ports:
      redis: 6379

# -----------------------------------------------------------------------------
# REPLICA CONFIGURATION
# -----------------------------------------------------------------------------
replica:
  replicaCount: 2

  # Resources
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

  # Persistence
  persistence:
    enabled: true
    storageClass: gp3
    size: 8Gi

  # Node placement
  nodeSelector:
    node-type: workloads

  # Autoscaling
  autoscaling:
    enabled: false

# -----------------------------------------------------------------------------
# SENTINEL CONFIGURATION (HA)
# -----------------------------------------------------------------------------
sentinel:
  enabled: true

  # Resources
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 100m
      memory: 128Mi

  # Quorum
  quorum: 2

  # Down after milliseconds
  downAfterMilliseconds: 5000

  # Failover timeout
  failoverTimeout: 60000

# -----------------------------------------------------------------------------
# METRICS
# -----------------------------------------------------------------------------
metrics:
  enabled: true

  # Prometheus ServiceMonitor
  serviceMonitor:
    enabled: true
    namespace: observability
    interval: 30s

  # Resources
  resources:
    requests:
      cpu: 10m
      memory: 32Mi
    limits:
      cpu: 50m
      memory: 64Mi

# -----------------------------------------------------------------------------
# NETWORK POLICIES
# -----------------------------------------------------------------------------
networkPolicy:
  enabled: true
  allowExternal: false

  # Permitir acesso de namespaces específicos
  ingressNSMatchLabels:
    project: k8s-platform
  ingressNSPodMatchLabels: {}

# -----------------------------------------------------------------------------
# POD SECURITY
# -----------------------------------------------------------------------------
podSecurityContext:
  enabled: true
  fsGroup: 1001

containerSecurityContext:
  enabled: true
  runAsUser: 1001
  runAsNonRoot: true

# -----------------------------------------------------------------------------
# COMMON LABELS
# -----------------------------------------------------------------------------
commonLabels:
  project: k8s-platform
  environment: prod
  domain: data-services

  # -----------------------------------------------------------------------------
  # REDIS CONFIGURATION
  # -----------------------------------------------------------------------------
  redis:
    replicas: 3  # 1 master + 2 replicas (failover automático)
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi

    # Persistence
    storage:
      persistentVolumeClaim:
        metadata:
          name: redis-data
        spec:
          storageClassName: gp3
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 8Gi

    # Node placement
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: node-type
                  operator: In
                  values:
                    - workloads

  # -----------------------------------------------------------------------------
  # METRICS (Prometheus)
  # -----------------------------------------------------------------------------
  enableMetrics: true
  exporter:
    enabled: true
    image: oliver006/redis_exporter:v1.55.0
    resources:
      requests: {cpu: 10m, memory: 32Mi}
      limits: {cpu: 50m, memory: 64Mi}
EOF
```

---

### 3.5 Deploy RedisFailover

```bash
# Aplicar CRD
kubectl apply -f redis-failover.yaml

# Aguardar criação dos pods (Operator cria automaticamente)
kubectl get pods -n redis -w

# Saída esperada (após ~2min):
# NAME                    READY   STATUS    RESTARTS   AGE
# rfr-redis-ha-0          2/2     Running   0          90s
# rfr-redis-ha-1          2/2     Running   0          60s
# rfr-redis-ha-2          2/2     Running   0          30s
# rfs-redis-ha-0          1/1     Running   0          90s
# rfs-redis-ha-1          1/1     Running   0          75s
# rfs-redis-ha-2          1/1     Running   0          60s
```

**Componentes Criados Automaticamente:**
- `rfr-redis-ha-*` → Redis instances (1 master + 2 replicas)
- `rfs-redis-ha-*` → Sentinel instances (quorum 3)
- Services: `rfs-redis-ha` (Sentinel), `rfr-redis-ha` (Redis master)
- ConfigMaps, Secrets (gerados pelo Operator)

---

### 3.6 Verificar HA e Sentinel

```bash
# Verificar status do RedisFailover CRD
kubectl get redisfailover redis-ha -n redis

# Saída esperada:
# NAME       PHASE     MASTER   READY
# redis-ha   Running   1        3

# Conectar ao Sentinel e verificar master
kubectl exec -it rfs-redis-ha-0 -n redis -- \
  redis-cli -p 26379 SENTINEL masters

# Saída esperada: mostra master atual e estado
```

---

### 3.7 Testar Failover Automático (Simular Falha)

```bash
# 1. Identificar pod master atual
MASTER_POD=$(kubectl exec -it rfs-redis-ha-0 -n redis -- \
  redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster | head -1)
echo "Master atual: $MASTER_POD"

# 2. Deletar pod master (simular falha)
kubectl delete pod rfr-redis-ha-0 -n redis

# 3. Observar failover automático (< 30s)
kubectl get pods -n redis -w

# 4. Verificar novo master
kubectl exec -it rfs-redis-ha-0 -n redis -- \
  redis-cli -p 26379 SENTINEL masters

# ✅ Resultado esperado: Sentinel promove réplica a master em < 30s
```

---

### 3.8 Conexão de Aplicações (GitLab, etc)

```bash
# Service DNS para aplicações:
# - Sentinel (HA automático): rfs-redis-ha.redis.svc.cluster.local:26379
# - Redis master direto: rfr-redis-ha.redis.svc.cluster.local:6379

# Obter senha (gerada automaticamente pelo Operator)
REDIS_PASSWORD=$(kubectl get secret rfr-redis-ha -n redis \
  -o jsonpath='{.data.password}' | base64 -d)
echo "Redis Password: $REDIS_PASSWORD"

# Criar secret no namespace gitlab para uso posterior
kubectl create secret generic redis-credentials \
  --namespace gitlab \
  --from-literal=sentinel-host=rfs-redis-ha.redis.svc.cluster.local \
  --from-literal=sentinel-port=26379 \
  --from-literal=password="${REDIS_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

### 3.9 Testar Conexão e Performance

```bash
# Teste de conectividade
kubectl run redis-test --rm -it --restart=Never \
  --image=redis:7-alpine \
  --namespace redis \
  -- redis-cli -h rfr-redis-ha -a $REDIS_PASSWORD ping

# Saída esperada: PONG

# Teste de write/read
kubectl exec -it rfr-redis-ha-0 -n redis -c redis -- \
  redis-cli -a $REDIS_PASSWORD <<EOF
SET test-key "ADR-023 Operators Working"
GET test-key
INFO replication
EOF

# Saída esperada:
# OK
# "ADR-023 Operators Working"
# role:master
# connected_slaves:2
```

---

## 4. Task C.3: RabbitMQ via Cluster Operator (10h)

> **Mudança Estratégica (ADR-023):** Substituímos `bitnami/rabbitmq` Helm chart por **RabbitMQ Cluster Operator** (oficial VMware/Broadcom) devido à migração do Bitnami para licenciamento pago.
>
> **Benefícios:**
> - ✅ TLS automático + Management UI integrada
> - ✅ Quorum queues (HA superior a classic mirrored queues)
> - ✅ Rolling updates zero-downtime
> - ✅ Operator oficial (suporte VMware/Broadcom)

### 4.1 Instalar RabbitMQ Cluster Operator

```bash
# Deploy Operator + CRDs
kubectl apply -f https://github.com/rabbitmq/cluster-operator/releases/download/v2.9.0/cluster-operator.yml

# Verificar CRDs instalados
kubectl get crd | grep rabbitmq
# Saída esperada:
# rabbitmqclusters.rabbitmq.com

# Verificar Operator Running
kubectl get pods -n rabbitmq-system
# Saída esperada:
# NAME                                         READY   STATUS    RESTARTS   AGE
# rabbitmq-cluster-operator-xxx-yyy           1/1     Running   0          30s
```

---

### 4.2 Criar Namespace para Instâncias

```bash
# Namespace para instâncias RabbitMQ
kubectl create namespace rabbitmq

kubectl label namespace rabbitmq \
  project=k8s-platform \
  environment=prod \
  domain=data-services
```

---

### 4.3 Criar RabbitmqCluster CRD

```bash
cat > rabbitmq-cluster.yaml <<'EOF'
# =============================================================================
# RabbitmqCluster CRD - RabbitMQ Cluster Operator
# =============================================================================
# Operator: cluster-operator v2.9.0
# Mode: 3-node cluster com quorum queues
# =============================================================================
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: rabbitmq-ha
  namespace: rabbitmq
  labels:
    project: k8s-platform
    environment: prod
    domain: data-services
spec:
  # -----------------------------------------------------------------------------
  # CLUSTER CONFIGURATION
  # -----------------------------------------------------------------------------
  replicas: 3

# -----------------------------------------------------------------------------
# AUTHENTICATION
# -----------------------------------------------------------------------------
auth:
  username: admin
  password: ""  # Será gerado automaticamente
  # Ou defina manualmente:
  # password: "rabbitmq_senha_segura_32chars"

  # Erlang cookie (para cluster)
  erlangCookie: ""  # Será gerado automaticamente

# -----------------------------------------------------------------------------
# CLUSTERING
# -----------------------------------------------------------------------------
clustering:
  enabled: true
  forceBoot: false
  rebalance: true

# -----------------------------------------------------------------------------
# RESOURCES
# -----------------------------------------------------------------------------
resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi

# -----------------------------------------------------------------------------
# PERSISTENCE
# -----------------------------------------------------------------------------
persistence:
  enabled: true
  storageClass: gp3
  size: 8Gi

# -----------------------------------------------------------------------------
# NODE PLACEMENT
# -----------------------------------------------------------------------------
nodeSelector:
  node-type: workloads

# Pod anti-affinity para distribuir em diferentes nodes
podAntiAffinityPreset: soft

# -----------------------------------------------------------------------------
# PLUGINS
# -----------------------------------------------------------------------------
plugins: "rabbitmq_management rabbitmq_prometheus rabbitmq_shovel rabbitmq_shovel_management"

# Community plugins
communityPlugins: ""

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
extraConfiguration: |
  # Memory limits
  vm_memory_high_watermark.relative = 0.6

  # Disk limits
  disk_free_limit.relative = 2.0

  # Queue settings
  queue_master_locator = min-masters

  # Logging
  log.console = true
  log.console.level = info

# -----------------------------------------------------------------------------
# MANAGEMENT UI
# -----------------------------------------------------------------------------
# A UI de gerenciamento será exposta via Ingress separado se necessário

# -----------------------------------------------------------------------------
# SERVICES
# -----------------------------------------------------------------------------
service:
  type: ClusterIP

  ports:
    amqp: 5672
    amqpTls: 5671
    dist: 25672
    manager: 15672
    metrics: 9419

# -----------------------------------------------------------------------------
# INGRESS (Opcional - Management UI)
# -----------------------------------------------------------------------------
ingress:
  enabled: false
  # Se quiser expor a UI:
  # enabled: true
  # ingressClassName: alb
  # hostname: rabbitmq.gitlab.empresa.com.br
  # annotations:
  #   alb.ingress.kubernetes.io/scheme: internal
  #   alb.ingress.kubernetes.io/target-type: ip

# -----------------------------------------------------------------------------
# METRICS
# -----------------------------------------------------------------------------
metrics:
  enabled: true

  serviceMonitor:
    enabled: true
    namespace: observability
    interval: 30s
    scrapeTimeout: 10s

# -----------------------------------------------------------------------------
# NETWORK POLICIES
# -----------------------------------------------------------------------------
networkPolicy:
  enabled: true
  allowExternal: false

  # Permitir acesso de namespaces específicos
  additionalRules:
    - namespaceSelector:
        matchLabels:
          project: k8s-platform

# -----------------------------------------------------------------------------
# POD SECURITY
# -----------------------------------------------------------------------------
podSecurityContext:
  enabled: true
  fsGroup: 1001

containerSecurityContext:
  enabled: true
  runAsUser: 1001
  runAsNonRoot: true

# -----------------------------------------------------------------------------
# COMMON LABELS
# -----------------------------------------------------------------------------
commonLabels:
  project: k8s-platform
  environment: prod
  domain: data-services

# -----------------------------------------------------------------------------
# VOLUME PERMISSIONS
# -----------------------------------------------------------------------------
volumePermissions:
  enabled: true

EOF
```

---

### 4.3 Instalar RabbitMQ

```bash
# Instalar RabbitMQ
helm install rabbitmq bitnami/rabbitmq \
  --namespace rabbitmq \
  --values rabbitmq-values.yaml \
  --version 12.6.1 \
  --timeout 600s \
  --wait

# Verificar instalação
kubectl get pods -n rabbitmq -w
```

**Saída esperada:**

```
NAME           READY   STATUS    RESTARTS   AGE
rabbitmq-0     1/1     Running   0          3m
rabbitmq-1     1/1     Running   0          2m
rabbitmq-2     1/1     Running   0          1m
```

---

### 4.4 Obter Credenciais do RabbitMQ

```bash
# Obter senha
RABBITMQ_PASSWORD=$(kubectl get secret rabbitmq -n rabbitmq -o jsonpath='{.data.rabbitmq-password}' | base64 -d)
echo "RabbitMQ Password: $RABBITMQ_PASSWORD"

# Obter Erlang cookie
ERLANG_COOKIE=$(kubectl get secret rabbitmq -n rabbitmq -o jsonpath='{.data.rabbitmq-erlang-cookie}' | base64 -d)
echo "Erlang Cookie: $ERLANG_COOKIE"

# Salvar para uso em outros namespaces
kubectl create secret generic rabbitmq-credentials \
  --namespace gitlab \
  --from-literal=username=admin \
  --from-literal=password="${RABBITMQ_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

### 4.5 Verificar Cluster Status

```bash
# Verificar status do cluster
kubectl exec -it rabbitmq-0 -n rabbitmq -- rabbitmqctl cluster_status

# Saída esperada:
# Cluster name: rabbit@rabbitmq-0.rabbitmq-headless.rabbitmq.svc.cluster.local
# Running Nodes:
# - rabbit@rabbitmq-0.rabbitmq-headless.rabbitmq.svc.cluster.local
# - rabbit@rabbitmq-1.rabbitmq-headless.rabbitmq.svc.cluster.local
# - rabbit@rabbitmq-2.rabbitmq-headless.rabbitmq.svc.cluster.local
```

---

### 4.6 Acessar Management UI

```bash
# Port-forward para acessar a UI localmente
kubectl port-forward svc/rabbitmq -n rabbitmq 15672:15672

# Acesse no browser: http://localhost:15672
# Username: admin
# Password: (a senha obtida acima)
```

---

### 4.7 Testar Conexão

```bash
# Testar conexão via pod temporário
kubectl run rabbitmq-test --rm -it --restart=Never \
  --image=bitnami/rabbitmq:latest \
  --namespace rabbitmq \
  --env="RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD}" \
  -- rabbitmqadmin -H rabbitmq -u admin -p $RABBITMQ_PASSWORD list queues

# Criar uma queue de teste
kubectl exec -it rabbitmq-0 -n rabbitmq -- \
  rabbitmqadmin -u admin -p $RABBITMQ_PASSWORD declare queue name=test-queue durable=true

# Verificar
kubectl exec -it rabbitmq-0 -n rabbitmq -- \
  rabbitmqadmin -u admin -p $RABBITMQ_PASSWORD list queues
```

---

## 5. Validação e Definition of Done

### Checklist de Validação

```bash
echo "=== RDS PostgreSQL ==="
aws rds describe-db-instances --db-instance-identifier k8s-platform-prod-postgresql \
  --query "DBInstances[0].[DBInstanceIdentifier,DBInstanceStatus,MultiAZ,Endpoint.Address]" \
  --output table

echo "=== Redis Pods ==="
kubectl get pods -n redis -o wide

echo "=== Redis Services ==="
kubectl get svc -n redis

echo "=== Redis Replication ==="
kubectl exec -it redis-master-0 -n redis -c redis -- redis-cli -a $REDIS_PASSWORD info replication | head -10

echo "=== RabbitMQ Pods ==="
kubectl get pods -n rabbitmq -o wide

echo "=== RabbitMQ Cluster ==="
kubectl exec -it rabbitmq-0 -n rabbitmq -- rabbitmqctl cluster_status | head -20

echo "=== PVCs ==="
kubectl get pvc -A | grep -E "(redis|rabbitmq)"
```

### Definition of Done - Épico C

- [ ] **RDS PostgreSQL**
  - [ ] Instância `k8s-platform-prod-postgresql` com status `Available`
  - [ ] Multi-AZ habilitado
  - [ ] Encryption-at-rest habilitado
  - [ ] Backup automático configurado (7 dias)
  - [ ] Parameter group customizado aplicado
  - [ ] Databases criados: `gitlab_production`, `keycloak`, `sonarqube`, `harbor`
  - [ ] Usuários criados com privilégios corretos
  - [ ] Credenciais armazenadas no Secrets Manager
  - [ ] Conexão testada do cluster EKS

- [ ] **Redis (Spotahome Operator - ADR-023)**
  - [ ] Redis Operator Running em `redis-operator` namespace
  - [ ] RedisFailover CRD `redis-ha` criado e PHASE=Running
  - [ ] Pods `rfr-redis-ha-*` (3 redis) e `rfs-redis-ha-*` (3 sentinels) Running
  - [ ] Sentinel quorum operacional (verificado via `SENTINEL masters`)
  - [ ] Failover automático testado (< 30s)
  - [ ] Persistence habilitada (PVCs 8Gi criados)
  - [ ] ServiceMonitor Prometheus configurado
  - [ ] Senha obtida e secret criado no namespace `gitlab`
  - [ ] **Economia:** $72,900/ano vs Bitnami Tanzu confirmada

- [ ] **RabbitMQ (Cluster Operator - ADR-023)**
  - [ ] RabbitMQ Cluster Operator Running em `rabbitmq-system` namespace
  - [ ] RabbitmqCluster CRD `rabbitmq-ha` criado (3 replicas)
  - [ ] 3 pods Running (cluster status OK via `rabbitmqctl cluster_status`)
  - [ ] Management UI acessível (port-forward ou Ingress)
  - [ ] Quorum queues configuradas (superior a mirrored queues)
  - [ ] Persistence habilitada (PVCs 8Gi criados)
  - [ ] ServiceMonitor Prometheus configurado
  - [ ] TLS automático gerado pelo Operator
  - [ ] Credenciais obtidas e secret criado no namespace `gitlab`
  - [ ] **Economia:** Confirmada (parte dos $72,900/ano total)

- [ ] **Documentação**
  - [ ] Endpoint do RDS documentado
  - [ ] Credenciais de todos os serviços documentadas
  - [ ] Comandos de conexão documentados

---

## 6. Troubleshooting

### Problema: RDS não acessível do EKS

```bash
# Verificar Security Group do RDS
aws ec2 describe-security-groups --group-ids <rds-sg-id>

# Verificar se permite acesso da subnet do EKS
# Causas comuns:
# - Security Group não permite porta 5432
# - Subnet do RDS não tem route table correta
# - Network ACL bloqueando
```

### Problema: Redis pods em Pending

```bash
# Verificar eventos
kubectl describe pod redis-master-0 -n redis

# Verificar PVC
kubectl get pvc -n redis
kubectl describe pvc redis-data-redis-master-0 -n redis

# Causas comuns:
# - StorageClass não existe
# - EBS CSI Driver não instalado
# - Zona sem capacidade
```

### Problema: RabbitMQ cluster não forma

```bash
# Verificar logs
kubectl logs rabbitmq-0 -n rabbitmq

# Verificar Erlang cookie
kubectl get secret rabbitmq -n rabbitmq -o jsonpath='{.data.rabbitmq-erlang-cookie}' | base64 -d

# Causas comuns:
# - Erlang cookies diferentes
# - DNS resolution failing
# - Network Policy bloqueando comunicação inter-pod
```

### Problema: Conexão recusada

```bash
# Verificar NetworkPolicy
kubectl get networkpolicy -n redis
kubectl get networkpolicy -n rabbitmq

# Verificar labels do namespace de origem
kubectl get namespace gitlab --show-labels

# Causas comuns:
# - NetworkPolicy muito restritiva
# - Labels do namespace não correspondem
```

---

## 7. Referências ADR-023

### Documentação Estratégica

| Documento | Seção | Conteúdo |
|-----------|-------|----------|
| **[ADR-023](../../context/decisions.md#adr-023)** | Migration from Bitnami Charts to Kubernetes Operators | Decisão completa, análise de agentes, economia $72,900/ano |
| **[architecture.md](../../context/architecture.md)** | Marco 3 Data Services | Redis: Spotahome Operator, RabbitMQ: Cluster Operator |
| **[costs.md](../../context/costs.md)** | Marco 3 Breakdown | Custos ajustados: Redis $0 + RabbitMQ $0 (usa nodes existentes) |
| **[BITNAMI-LICENSING-IMPACT-ANALYSIS.md](../../finops/BITNAMI-LICENSING-IMPACT-ANALYSIS.md)** | Análise Impacto Licenciamento | Custo Tanzu Standard: $72,000/ano evitado |

### Operators Utilizados

| Operator | Repository | Docs | Status |
|----------|------------|------|--------|
| **Spotahome Redis Operator** | [GitHub](https://github.com/spotahome/redis-operator) | [Docs](https://github.com/spotahome/redis-operator/tree/master/docs) | Production-ready (>50 companies) |
| **RabbitMQ Cluster Operator** | [GitHub](https://github.com/rabbitmq/cluster-operator) | [Docs](https://www.rabbitmq.com/kubernetes/operator/operator-overview.html) | Oficial VMware/Broadcom |

### Benefícios Consolidados

| Benefício | Redis Operator | RabbitMQ Operator |
|-----------|----------------|-------------------|
| **Economia licenciamento** | $36,000/ano | $36,000/ano |
| **Failover automático** | < 30s (vs 5-6 min Bitnami) | Quorum queues (superior mirrored) |
| **Backups** | CronJobs nativos | CronJobs nativos |
| **HA Superior** | Sentinel 3 nodes | 3-node cluster |
| **Cloud-agnostic** | ✅ Portável GCP/Azure | ✅ Portável GCP/Azure |
| **Zero-downtime upgrades** | ✅ Rolling updates | ✅ Rolling updates |

---

## Próximos Passos

Após concluir este documento:

1. Prosseguir para **[02-gitlab-helm-deploy.md](02-gitlab-helm-deploy.md)** (se não concluído)
2. Depois **[04-observability-stack.md](04-observability-stack.md)**
3. Validar economia real vs projeção ($72,900/ano esperado)

---

**Documento:** 03-data-services-operators.md (atualizado de 03-data-services-helm.md)
**Versão:** 2.0 (ADR-023 aplicado)
**Última atualização:** 2026-01-29
**Épico:** C
**Esforço:** 24 person-hours (+4h vs planejamento original devido complexidade Operators)
**Mudança Estratégica:** [ADR-023 - Migration from Bitnami Charts to Kubernetes Operators](../../context/decisions.md#adr-023)

# Plano de Execução AWS - Plataforma Kubernetes Corporativa

**Versão:** 1.1
**Data:** 2026-01-22 (atualizado com novas práticas de autenticação AWS)
**Projeto:** Arquitetura Multi-Domínio Kubernetes
**Região Principal:** us-east-1 (N. Virginia)
**Ambientes:** Homologação + Produção

---

## 1️⃣ Visão Geral da Estratégia Cloud

### Arquitetura Escolhida

**Amazon EKS (Elastic Kubernetes Service)** como plataforma de orquestração para hospedar os 6 domínios da plataforma corporativa de engenharia:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           AWS CLOUD (us-east-1)                         │
├─────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                         VPC (10.0.0.0/16)                        │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │   │
│  │  │  AZ-1a       │  │  AZ-1b       │  │  AZ-1c       │          │   │
│  │  │ Public Sub   │  │ Public Sub   │  │ Public Sub   │          │   │
│  │  │ 10.0.1.0/24  │  │ 10.0.2.0/24  │  │ 10.0.3.0/24  │          │   │
│  │  │ (NAT + ALB)  │  │              │  │              │          │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘          │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │   │
│  │  │ Private Sub  │  │ Private Sub  │  │ Private Sub  │          │   │
│  │  │ 10.0.11.0/24 │  │ 10.0.12.0/24 │  │ 10.0.13.0/24 │          │   │
│  │  │ (EKS Nodes)  │  │ (EKS Nodes)  │ │ (EKS Nodes)  │          │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘          │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │   │
│  │  │ DB Subnet    │  │ DB Subnet    │  │ DB Subnet    │          │   │
│  │  │ 10.0.21.0/24 │  │ 10.0.22.0/24 │  │ 10.0.23.0/24 │          │   │
│  │  │ (RDS/Cache)  │  │ (RDS/Cache)  │ │ (RDS/Cache)  │          │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    AMAZON EKS CLUSTER                            │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │   │
│  │  │ system      │  │ workloads   │  │ critical    │              │   │
│  │  │ t3.medium   │  │ t3.large    │  │ t3.xlarge   │              │   │
│  │  │ 2 nodes     │  │ 3 nodes     │  │ 2 nodes     │              │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │
│  │ RDS         │  │ ElastiCache │  │ S3          │  │ Route53     │   │
│  │ PostgreSQL  │  │ Redis       │  │ Buckets     │  │ DNS         │   │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Justificativa Técnica

| Decisão | Justificativa |
|---------|---------------|
| **EKS** | Kubernetes gerenciado, integração nativa com IAM, ALB, CloudWatch |
| **Multi-AZ** | Alta disponibilidade obrigatória para produção |
| **Node Groups separados** | Isolamento de workloads (system, workloads, critical) |
| **RDS PostgreSQL** | HA Multi-AZ, backups automáticos, performance otimizada |
| **S3** | Storage ilimitado para backups, logs, artifacts |

### Serviços AWS Envolvidos

| Serviço | Propósito | Criticidade |
|---------|-----------|-------------|
| **VPC** | Rede isolada e segmentada | Alta |
| **EKS** | Cluster Kubernetes gerenciado | Alta |
| **EC2** | Node Groups do EKS | Alta |
| **RDS** | PostgreSQL para GitLab, Keycloak, SonarQube | Alta |
| **ElastiCache** | Redis para cache e sessões | Média |
| **S3** | Backups, logs, artifacts, Terraform state | Alta |
| **ALB** | Load Balancer para ingress | Alta |
| **Route53** | DNS gerenciado | Alta |
| **IAM** | Identidade e políticas | Alta |
| **KMS** | Criptografia de dados | Alta |
| **CloudWatch** | Logs e métricas AWS | Média |
| **Secrets Manager** | Secrets sensíveis | Alta |
| **WAF** | Proteção de aplicações web | Média |
| **ACM** | Certificados TLS | Alta |

---

## 2️⃣ Arquitetura AWS (Nível Lógico)

### Componentes e Relações

```
                                    ┌─────────────┐
                                    │   Route53   │
                                    │   DNS       │
                                    └──────┬──────┘
                                           │
                                    ┌──────▼──────┐
                                    │     WAF     │
                                    │  (Firewall) │
                                    └──────┬──────┘
                                           │
                                    ┌──────▼──────┐
                                    │     ALB     │
                                    │ (Ingress)   │
                                    └──────┬──────┘
                                           │
┌──────────────────────────────────────────┼──────────────────────────────────────────┐
│                                    VPC   │                                          │
│  ┌───────────────────────────────────────┼─────────────────────────────────────┐   │
│  │                              EKS Cluster                                     │   │
│  │  ┌─────────────────────────────────────────────────────────────────────┐   │   │
│  │  │                        NAMESPACES / DOMÍNIOS                         │   │   │
│  │  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐            │   │   │
│  │  │  │ platform-core │  │ observability │  │ cicd-platform │            │   │   │
│  │  │  │  - Kong       │  │  - Prometheus │  │  - GitLab     │            │   │   │
│  │  │  │  - Keycloak   │  │  - Grafana    │  │  - ArgoCD     │            │   │   │
│  │  │  │  - Linkerd    │  │  - Loki       │  │  - Harbor     │            │   │   │
│  │  │  │  - Ingress    │  │  - Tempo      │  │  - SonarQube  │            │   │   │
│  │  │  └───────────────┘  └───────────────┘  └───────────────┘            │   │   │
│  │  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐            │   │   │
│  │  │  │ data-services │  │ secrets-mgmt  │  │ security      │            │   │   │
│  │  │  │  - PostgreSQL │  │  - Vault      │  │  - Kyverno    │            │   │   │
│  │  │  │  - Redis Op   │  │  - ESO        │  │  - Falco      │            │   │   │
│  │  │  │  - RabbitMQ   │  │               │  │  - Trivy      │            │   │   │
│  │  │  │  - Velero     │  │               │  │               │            │   │   │
│  │  │  └───────────────┘  └───────────────┘  └───────────────┘            │   │   │
│  │  └─────────────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                    │
│  │ RDS PostgreSQL  │  │ ElastiCache     │  │ S3 Buckets      │                    │
│  │ (Multi-AZ)      │  │ (Redis Cluster) │  │ - backups       │                    │
│  │ - gitlab        │  │ - gitlab-cache  │  │ - artifacts     │                    │
│  │ - keycloak      │  │ - sessions      │  │ - logs          │                    │
│  │ - sonarqube     │  │                 │  │ - terraform     │                    │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘                    │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### Separação de Ambientes

| Recurso | Homologação (staging) | Produção (prod) |
|---------|----------------------|-----------------|
| **VPC** | `vpc-staging` (10.1.0.0/16) | `vpc-prod` (10.0.0.0/16) |
| **EKS Cluster** | `k8s-platform-staging` | `k8s-platform-prod` |
| **Node Count** | 3 nodes (mínimo) | 7 nodes (mínimo) |
| **RDS** | db.t3.small, Single-AZ | db.t3.medium, Multi-AZ |
| **Disponibilidade** | Horário comercial (scheduled) | 24/7 |
| **Backup** | 3 dias | 7 dias |

### Considerações de Segurança

| Camada | Controle | Implementação |
|--------|----------|---------------|
| **Identidade** | IAM com menor privilégio | Roles específicas por serviço |
| **Rede** | Segmentação VPC | Public/Private/DB subnets |
| **Tráfego** | Security Groups | Regras específicas por porta |
| **Aplicação** | WAF | Proteção OWASP Top 10 |
| **Dados** | KMS | Criptografia at-rest e in-transit |
| **Secrets** | Secrets Manager | Rotação automática |
| **Auditoria** | CloudTrail | Logs de todas as ações |

---

## 3️⃣ Passo a Passo no Console da AWS (MUITO DETALHADO)

### 🔹 Serviço: IAM (Identity and Access Management)

> **Contexto:** Criar roles e políticas ANTES de qualquer outro recurso. Princípio de menor privilégio é obrigatório.

#### 3.1.1 Criar Política para EKS Cluster

**Passo a passo no console:**

1. Acesse o Console AWS: https://console.aws.amazon.com/
2. Na barra de busca superior, digite `IAM` e clique em **IAM**
3. No menu lateral esquerdo, clique em **Policies**
4. Clique no botão **Create policy** (azul, canto superior direito)
5. Selecione a aba **JSON**
6. Cole a seguinte política:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EKSClusterPolicy",
            "Effect": "Allow",
            "Action": [
                "eks:*",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeVpcs",
                "iam:GetRole",
                "iam:PassRole"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:RequestedRegion": "us-east-1"
                }
            }
        }
    ]
}
```

7. Clique em **Next**
8. Preencha os campos:
   - **Policy name:** `k8s-platform-eks-policy`
   - **Description:** `PolAtica-para-gerenciamento-do-cluster-EKS-da-plataforma-Kubernetes`
   - **Tags:**
     - `Project` = `k8s-platform`
     - `Environment` = `shared`
     - `Owner` = `devops-team`
     - `CostCenter` = `infrastructure`
9. Clique em **Create policy**

---

#### 3.1.2 Criar Role para EKS Cluster

**Passo a passo no console:**

1. No IAM, menu lateral, clique em **Roles**
2. Clique em **Create role**
3. Em **Trusted entity type**, selecione **AWS service**
4. Em **Use case**, selecione **EKS** → **EKS - Cluster**
5. Clique em **Next**
6. As políticas `AmazonEKSClusterPolicy` já estarão selecionadas
7. Clique em **Next**
8. Preencha:
   - **Role name:** `k8s-platform-eks-cluster-role`
   - **Description:** `Role-para-o-cluster-EKS-da-plataforma-Kubernetes-corporativa`
   - **Tags:**
     - `Project` = `k8s-platform`
     - `Environment` = `prod`
     - `Owner` = `devops-team`
9. Clique em **Create role**

---

#### 3.1.3 Criar Role para EKS Node Group

**Passo a passo no console:**

1. Em **Roles**, clique em **Create role**
2. Selecione **AWS service** → **EC2**
3. Clique em **Next**
4. Busque e selecione as seguintes políticas:
   - `AmazonEKSWorkerNodePolicy`
   - `AmazonEKS_CNI_Policy`
   - `AmazonEC2ContainerRegistryReadOnly`
   - `AmazonSSMManagedInstanceCore` (para acesso via Session Manager)
5. Clique em **Next**
6. Preencha:
   - **Role name:** `k8s-platform-eks-node-role`
   - **Description:** `Role-para-os-Node-Groups-do-EKS`
   - **Tags:** (mesmas tags anteriores)
7. Clique em **Create role**

---

#### 3.1.4 Configurar Autenticação AWS CLI

> **⚠️ ATUALIZAÇÃO IMPORTANTE (2026):** A AWS recomenda NÃO usar Access Keys para pessoas. Prefira sempre AWS CloudShell ou IAM Identity Center (SSO).

**Escolha UMA das opções abaixo:**

---

**OPÇÃO 1: AWS CloudShell (RECOMENDADA para testes rápidos)**

1. Acesse o Console AWS: https://console.aws.amazon.com/
2. No **canto superior direito**, clique no ícone `>_` (CloudShell)
3. Aguarde inicialização (10-30 segundos)
4. Teste a conexão:

```bash
aws sts get-caller-identity
```

**Vantagens:**
- ✅ Zero configuração
- ✅ Credenciais automáticas do console
- ✅ Sem risco de vazamento de Access Keys

---

**OPÇÃO 2: IAM Identity Center (SSO) - Para uso diário**

1. Na barra de busca, digite `IAM Identity Center`
2. Clique em **Enable** (primeira vez)
3. Configure MFA como obrigatório
4. Crie grupo `k8s-platform-admins`
5. Adicione usuários ao grupo
6. Crie permission set `K8sPlatformPowerUser`
7. Configure AWS CLI V2 localmente:

```bash
aws configure sso
# SSO start URL: https://sua-empresa.awsapps.com/start
# SSO Region: us-east-1
# CLI profile name: k8s-platform-prod
```

**Vantagens:**
- ✅ Integração com Azure AD/Okta
- ✅ MFA obrigatório
- ✅ Credenciais temporárias

---

**OPÇÃO 3: Access Keys (APENAS para CI/CD ou Terraform)**

> **⚠️ USE APENAS PARA:** Pipelines CI/CD (GitHub Actions, GitLab CI), Terraform automatizado

1. Em **Users**, clique em **Create user**
2. Preencha:
   - **User name:** `terraform-k8s-platform`
   - **Provide user access to console:** ❌ NÃO marque
3. Clique em **Next**
4. Selecione **Attach policies directly**
5. Busque e selecione:
   - `PowerUserAccess` (temporário, restringir depois)
6. Clique em **Next** → **Create user**
7. Clique no usuário criado
8. Aba **Security credentials** → **Create access key**
9. Selecione **Command Line Interface (CLI)**
10. Marque o checkbox de confirmação
11. Clique em **Next** → **Create access key**
12. **ARMAZENE COM SEGURANÇA:**

```bash
# Opção A: AWS Secrets Manager (RECOMENDADO)
aws secretsmanager create-secret \
    --name k8s-platform/terraform/aws-credentials \
    --secret-string '{
        "access_key_id": "AKIAIOSFODNN7EXAMPLE",
        "secret_access_key": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    }' \
    --kms-key-id alias/k8s-platform-prod

# Opção B: Arquivo local ~/.aws/credentials
cat > ~/.aws/credentials <<EOF
[k8s-platform-terraform]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
EOF
chmod 600 ~/.aws/credentials
```

**⚠️ ROTAÇÃO OBRIGATÓRIA:** Rotacione Access Keys a cada 90 dias

```bash
# Criar nova key
aws iam create-access-key --user-name terraform-k8s-platform

# Deletar key antiga
aws iam delete-access-key --user-name terraform-k8s-platform --access-key-id AKIAOLDKEY
```

---

### 🔹 Serviço: VPC (Virtual Private Cloud)

> **Contexto:** A VPC isola toda a infraestrutura. Segmentação em subnets públicas, privadas e de banco de dados é essencial para segurança.

#### 3.2.1 Criar VPC com Wizard

**Passo a passo no console:**

1. Na barra de busca, digite `VPC` e clique em **VPC**
2. Clique em **Create VPC**
3. Selecione **VPC and more** (wizard completo)
4. Preencha os campos:

   **Name tag auto-generation:**
   - **Auto-generate:** Marque
   - **Name:** `k8s-platform-prod`

   **IPv4 CIDR block:**
   - **IPv4 CIDR:** `10.0.0.0/16`

   **IPv6 CIDR block:**
   - Selecione **No IPv6 CIDR block**

   **Tenancy:**
   - Selecione **Default**

   **Number of Availability Zones:**
   - Selecione **3**

   **Number of public subnets:**
   - Selecione **3**

   **Number of private subnets:**
   - Selecione **3**

   **NAT gateways:**
   - Selecione **In 1 AZ** (economia de custo - para prod HA use "1 per AZ")

   **VPC endpoints:**
   - Selecione **S3 Gateway**

   **DNS options:**
   - ✅ **Enable DNS hostnames**
   - ✅ **Enable DNS resolution**

5. Revise o diagrama gerado automaticamente
6. Clique em **Create VPC**
7. Aguarde a criação (2-3 minutos)

---

#### 3.2.2 Criar Subnets de Banco de Dados

**Passo a passo no console:**

1. No VPC Dashboard, menu lateral, clique em **Subnets**
2. Clique em **Create subnet**
3. Preencha:

   **VPC ID:** Selecione `k8s-platform-prod-vpc`

   **Subnet 1:**
   - **Subnet name:** `k8s-platform-prod-db-us-east-1a`
   - **Availability Zone:** `us-east-1a`
   - **IPv4 CIDR block:** `10.0.21.0/24`

4. Clique em **Add new subnet**

   **Subnet 2:**
   - **Subnet name:** `k8s-platform-prod-db-us-east-1b`
   - **Availability Zone:** `us-east-1b`
   - **IPv4 CIDR block:** `10.0.22.0/24`

5. Clique em **Add new subnet**

   **Subnet 3:**
   - **Subnet name:** `k8s-platform-prod-db-us-east-1c`
   - **Availability Zone:** `us-east-1c`
   - **IPv4 CIDR block:** `10.0.23.0/24`

6. Clique em **Create subnet**

---

#### 3.2.3 Criar Subnet Group para RDS

**Passo a passo no console:**

1. Na barra de busca, digite `RDS` e clique em **RDS**
2. Menu lateral, clique em **Subnet groups**
3. Clique em **Create DB subnet group**
4. Preencha:
   - **Name:** `k8s-platform-prod-db-subnet-group`
   - **Description:** `Subnet-group-para-RDS-da-plataforma-Kubernetes`
   - **VPC:** Selecione `k8s-platform-prod-vpc`

   **Add subnets:**
   - **Availability Zones:** Selecione `us-east-1a`, `us-east-1b`, `us-east-1c`
   - **Subnets:** Selecione as 3 subnets de DB criadas (10.0.21.0/24, 10.0.22.0/24, 10.0.23.0/24)

5. Clique em **Create**

---

#### 3.2.4 Adicionar Tags nas Subnets para EKS

**Passo a passo no console:**

1. Volte para **VPC** → **Subnets**
2. Selecione TODAS as subnets **privadas** (uma por vez)
3. Clique na aba **Tags**
4. Clique em **Manage tags**
5. Adicione as tags:

   | Key | Value |
   |-----|-------|
   | `kubernetes.io/cluster/k8s-platform-prod` | `shared` |
   | `kubernetes.io/role/internal-elb` | `1` |

6. Repita para as subnets **públicas** com tags diferentes:

   | Key | Value |
   |-----|-------|
   | `kubernetes.io/cluster/k8s-platform-prod` | `shared` |
   | `kubernetes.io/role/elb` | `1` |

---

### 🔹 Serviço: Security Groups

> **Contexto:** Security Groups atuam como firewall stateful. Cada componente deve ter seu próprio SG com regras mínimas necessárias.

#### 3.3.1 Criar Security Group para EKS Cluster

**Passo a passo no console:**

1. Em **VPC** → **Security groups**
2. Clique em **Create security group**
3. Preencha:
   - **Security group name:** `k8s-platform-prod-eks-cluster-sg`
   - **Description:** `Security-Group-para-o-EKS-Control-Plane`
   - **VPC:** Selecione `k8s-platform-prod-vpc`

4. **Inbound rules:** (deixe vazio por enquanto, será configurado automaticamente pelo EKS)

5. **Outbound rules:**
   - **Type:** All traffic
   - **Destination:** 0.0.0.0/0

6. **Tags:**
   - `Name` = `k8s-platform-prod-eks-cluster-sg`
   - `Project` = `k8s-platform`

7. Clique em **Create security group**

---

#### 3.3.2 Criar Security Group para RDS

**Passo a passo no console:**

1. Clique em **Create security group**
2. Preencha:
   - **Security group name:** `k8s-platform-prod-rds-sg`
   - **Description:** `Security-Group-para-RDS-PostgreSQL`
   - **VPC:** Selecione `k8s-platform-prod-vpc`

3. **Inbound rules:**
   - Clique em **Add rule**
   - **Type:** PostgreSQL
   - **Port:** 5432
   - **Source:** Custom → Selecione `k8s-platform-prod-eks-cluster-sg`
   - **Description:** `Acesso-do-EKS-ao-RDS`

4. **Outbound rules:**
   - **Type:** All traffic
   - **Destination:** 0.0.0.0/0

5. **Tags:**
   - `Name` = `k8s-platform-prod-rds-sg`
   - `Project` = `k8s-platform`

6. Clique em **Create security group**

---

#### 3.3.3 Criar Security Group para ElastiCache

**Passo a passo no console:**

1. Clique em **Create security group**
2. Preencha:
   - **Security group name:** `k8s-platform-prod-redis-sg`
   - **Description:** `Security-Group-para-ElastiCache-Redis`
   - **VPC:** Selecione `k8s-platform-prod-vpc`

3. **Inbound rules:**
   - **Type:** Custom TCP
   - **Port:** 6379
   - **Source:** `k8s-platform-prod-eks-cluster-sg`
   - **Description:** `Acesso-do-EKS-ao-Redis`

4. Clique em **Create security group**

---

### 🔹 Serviço: S3 (Simple Storage Service)

> **Contexto:** S3 armazenará backups, logs, artifacts do GitLab/Harbor e o Terraform state. Versionamento e criptografia são obrigatórios.

#### 3.4.1 Criar Bucket para Terraform State

**Passo a passo no console:**

1. Na barra de busca, digite `S3` e clique em **S3**
2. Clique em **Create bucket**
3. Preencha:

   **General configuration:**
   - **Bucket name:** `k8s-platform-terraform-state-{account-id}` (substitua {account-id} pelo seu ID de conta)
   - **AWS Region:** `us-east-1`

   **Object Ownership:**
   - Selecione **ACLs disabled (recommended)**

   **Block Public Access settings:**
   - ✅ **Block all public access** (OBRIGATÓRIO)

   **Bucket Versioning:**
   - Selecione **Enable**

   **Default encryption:**
   - **Encryption type:** Server-side encryption with Amazon S3 managed keys (SSE-S3)
   - **Bucket Key:** Enable

4. **Tags:**
   - `Project` = `k8s-platform`
   - `Environment` = `shared`
   - `Purpose` = `terraform-state`

5. Clique em **Create bucket**

---

#### 3.4.2 Criar Bucket para Backups

**Passo a passo no console:**

1. Clique em **Create bucket**
2. Preencha:
   - **Bucket name:** `k8s-platform-backups-prod-{account-id}`
   - **AWS Region:** `us-east-1`
   - ✅ **Block all public access**
   - **Versioning:** Enable
   - **Encryption:** SSE-S3

3. **Tags:**
   - `Project` = `k8s-platform`
   - `Environment` = `prod`
   - `Purpose` = `backups`

4. Clique em **Create bucket**

---

#### 3.4.3 Configurar Lifecycle Policy (Economia)

**Passo a passo no console:**

1. Clique no bucket `k8s-platform-backups-prod-{account-id}`
2. Aba **Management**
3. Clique em **Create lifecycle rule**
4. Preencha:
   - **Lifecycle rule name:** `backup-lifecycle-policy`
   - **Rule scope:** Apply to all objects in the bucket

   **Lifecycle rule actions:**
   - ✅ **Move current versions of objects between storage classes**
   - ✅ **Move noncurrent versions of objects between storage classes**
   - ✅ **Permanently delete noncurrent versions of objects**

   **Transitions:**
   - After 30 days → **Standard-IA**
   - After 90 days → **Glacier Instant Retrieval**
   - After 365 days → **Glacier Deep Archive**

   **Noncurrent version expiration:**
   - After 90 days

5. Clique em **Create rule**

---

#### 3.4.4 Criar Bucket para GitLab Artifacts

**Passo a passo no console:**

1. Clique em **Create bucket**
2. Preencha:
   - **Bucket name:** `k8s-platform-gitlab-artifacts-{account-id}`
   - **AWS Region:** `us-east-1`
   - ✅ **Block all public access**
   - **Versioning:** Disable (artifacts são efêmeros)
   - **Encryption:** SSE-S3

3. **Tags:**
   - `Project` = `k8s-platform`
   - `Environment` = `prod`
   - `Purpose` = `gitlab-artifacts`

4. Clique em **Create bucket**

---

### 🔹 Serviço: KMS (Key Management Service)

> **Contexto:** KMS gerencia chaves de criptografia. Uma chave dedicada para a plataforma permite controle de acesso granular e auditoria.

#### 3.5.1 Criar Customer Managed Key

**Passo a passo no console:**

1. Na barra de busca, digite `KMS` e clique em **Key Management Service**
2. Clique em **Create key**
3. Preencha:

   **Configure key:**
   - **Key type:** Symmetric
   - **Key usage:** Encrypt and decrypt
   - **Advanced options:**
     - **Key material origin:** KMS (AWS KMS key material)
     - **Regionality:** Single-Region key

4. Clique em **Next**

   **Add labels:**
   - **Alias:** `alias/k8s-platform-prod`
   - **Description:** `Chave-de-criptografia-para-a-plataforma-Kubernetes`
   - **Tags:**
     - `Project` = `k8s-platform`
     - `Environment` = `prod`

5. Clique em **Next**

   **Define key administrative permissions:**
   - Selecione os usuários/roles que podem administrar a chave
   - Adicione `terraform-k8s-platform` (usuário criado anteriormente)

6. Clique em **Next**

   **Define key usage permissions:**
   - Adicione as roles:
     - `k8s-platform-eks-cluster-role`
     - `k8s-platform-eks-node-role`

7. Clique em **Next** → **Finish**

---

### 🔹 Serviço: RDS (PostgreSQL)

> **Contexto:** RDS PostgreSQL hospedará os bancos de dados do GitLab, Keycloak e SonarQube. Multi-AZ garante alta disponibilidade em produção.

#### 3.6.1 Criar Instância RDS PostgreSQL

**Passo a passo no console:**

1. Na barra de busca, digite `RDS` e clique em **RDS**
2. Clique em **Create database**
3. Preencha:

   **Choose a database creation method:**
   - Selecione **Standard create**

   **Engine options:**
   - **Engine type:** PostgreSQL
   - **Engine version:** PostgreSQL 15.4-R2 (ou mais recente LTS)

   **Templates:**
   - Selecione **Production**

   **Availability and durability:**
   - Selecione **Multi-AZ DB instance** (para prod)

   **Settings:**
   - **DB instance identifier:** `k8s-platform-prod-postgresql`
   - **Master username:** `postgres_admin`
   - **Credentials management:** Self managed
   - **Master password:** (gere uma senha forte de 32+ caracteres)
   - **Confirm password:** (repita a senha)

   **Instance configuration:**
   - **DB instance class:** Burstable classes (includes t classes)
   - Selecione **db.t3.medium** (2 vCPU, 4 GB RAM)

   **Storage:**
   - **Storage type:** General Purpose SSD (gp3)
   - **Allocated storage:** 100 GB
   - **Storage autoscaling:** ✅ Enable
   - **Maximum storage threshold:** 500 GB

   **Connectivity:**
   - **Compute resource:** Don't connect to an EC2 compute resource
   - **Network type:** IPv4
   - **VPC:** `k8s-platform-prod-vpc`
   - **DB subnet group:** `k8s-platform-prod-db-subnet-group`
   - **Public access:** **No**
   - **VPC security group:** Choose existing
   - **Existing VPC security groups:** Selecione `k8s-platform-prod-rds-sg`
   - **Availability Zone:** No preference

   **Database authentication:**
   - Selecione **Password authentication**

   **Monitoring:**
   - ✅ **Enable Enhanced monitoring**
   - **Monitoring Role:** Create new role
   - **Granularity:** 60 seconds

   **Additional configuration:**
   - **Initial database name:** `platform`
   - **DB parameter group:** default.postgres15
   - **Backup:**
     - ✅ **Enable automated backups**
     - **Backup retention period:** 7 days
     - **Backup window:** Select window → `03:00-04:00 UTC`
   - **Encryption:**
     - ✅ **Enable encryption**
     - **AWS KMS key:** Selecione `alias/k8s-platform-prod`
   - **Log exports:** (selecione todos)
     - ✅ PostgreSQL log
     - ✅ Upgrade log
   - **Maintenance:**
     - ✅ **Enable auto minor version upgrade**
     - **Maintenance window:** Select window → `sun:04:00-sun:05:00 UTC`
   - **Deletion protection:**
     - ✅ **Enable deletion protection**

4. **Tags:**
   - `Project` = `k8s-platform`
   - `Environment` = `prod`
   - `Owner` = `devops-team`
   - `CostCenter` = `infrastructure`

5. Clique em **Create database**
6. Aguarde a criação (10-15 minutos)

---

#### 3.6.2 Criar Databases Individuais

**Passo a passo no console:**

Após a instância estar disponível, conecte via cliente PostgreSQL (pgAdmin, DBeaver, ou psql via bastion host) e execute:

```sql
-- Criar databases para cada serviço
CREATE DATABASE gitlab_production;
CREATE DATABASE keycloak;
CREATE DATABASE sonarqube;
CREATE DATABASE harbor;

-- Criar usuários específicos (princípio de menor privilégio)
CREATE USER gitlab_user WITH ENCRYPTED PASSWORD 'senha_segura_gitlab_32chars';
CREATE USER keycloak_user WITH ENCRYPTED PASSWORD 'senha_segura_keycloak_32chars';
CREATE USER sonarqube_user WITH ENCRYPTED PASSWORD 'senha_segura_sonar_32chars';
CREATE USER harbor_user WITH ENCRYPTED PASSWORD 'senha_segura_harbor_32chars';

-- Conceder privilégios
GRANT ALL PRIVILEGES ON DATABASE gitlab_production TO gitlab_user;
GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak_user;
GRANT ALL PRIVILEGES ON DATABASE sonarqube TO sonarqube_user;
GRANT ALL PRIVILEGES ON DATABASE harbor TO harbor_user;
```

---

### 🔹 Serviço: ElastiCache (Redis)

> **Contexto:** Redis será usado como cache para GitLab e sessões do Keycloak. Cluster mode oferece melhor performance e disponibilidade.

#### 3.7.1 Criar Cluster ElastiCache Redis

**Passo a passo no console:**

1. Na barra de busca, digite `ElastiCache` e clique em **ElastiCache**
2. Clique em **Create cluster** → **Create Redis cluster**
3. Preencha:

   **Cluster creation method:**
   - Selecione **Configure and create a new cluster**

   **Cluster mode:**
   - Selecione **Disabled** (para simplificar, ou Enabled para escala)

   **Cluster info:**
   - **Name:** `k8s-platform-prod-redis`
   - **Description:** `Redis-cache-para-plataforma-Kubernetes`

   **Location:**
   - Selecione **AWS Cloud**

   **Multi-AZ:**
   - ✅ **Enable** (para produção)

   **Auto-failover:**
   - ✅ **Enable**

   **Node type:**
   - **Family:** t3
   - **Node type:** `cache.t3.medium`

   **Number of replicas:**
   - `2` (1 primary + 2 replicas = 3 nodes)

   **Subnet group settings:**
   - **Subnet group:** Create new
   - **Name:** `k8s-platform-prod-redis-subnet-group`
   - **VPC ID:** `k8s-platform-prod-vpc`
   - **Subnets:** Selecione as 3 subnets de DB

   **Availability Zone placements:**
   - Deixe como **No preference**

   **Security:**
   - **Security groups:** Selecione `k8s-platform-prod-redis-sg`
   - **Encryption at-rest:** ✅ **Enable**
   - **Encryption key:** `alias/k8s-platform-prod`
   - **Encryption in-transit:** ✅ **Enable**

   **Logs:**
   - ✅ **Slow logs**
   - **Log format:** JSON
   - **Destination:** CloudWatch Logs
   - **Log group:** `/aws/elasticache/k8s-platform-prod-redis`

   **Backup:**
   - ✅ **Enable automatic backups**
   - **Backup retention period:** 7 days
   - **Backup window:** `05:00-06:00 UTC`

   **Maintenance:**
   - **Maintenance window:** `sun:06:00-sun:07:00 UTC`
   - ✅ **Auto upgrade minor versions**

4. **Tags:**
   - `Project` = `k8s-platform`
   - `Environment` = `prod`

5. Clique em **Create**

---

### 🔹 Serviço: EKS (Elastic Kubernetes Service)

> **Contexto:** EKS é o coração da plataforma. Node Groups separados permitem isolamento de workloads e otimização de recursos.

#### 3.8.1 Criar Cluster EKS

**Passo a passo no console:**

1. Na barra de busca, digite `EKS` e clique em **Elastic Kubernetes Service**
2. Clique em **Add cluster** → **Create**
3. Preencha:

   **Step 1 - Configure cluster:**

   **Name:**
   - **Name:** `k8s-platform-prod`

   **Kubernetes version:**
   - Selecione a versão mais recente estável (ex: 1.29)

   **Cluster service role:**
   - Selecione `k8s-platform-eks-cluster-role`

   **Secrets encryption:**
   - ✅ **Turn on envelope encryption of Kubernetes secrets**
   - **KMS key:** `alias/k8s-platform-prod`

   **Tags:**
   - `Project` = `k8s-platform`
   - `Environment` = `prod`
   - `Owner` = `devops-team`

4. Clique em **Next**

   **Step 2 - Specify networking:**

   **VPC:**
   - Selecione `k8s-platform-prod-vpc`

   **Subnets:**
   - Selecione TODAS as subnets privadas:
     - `k8s-platform-prod-subnet-private1-us-east-1a`
     - `k8s-platform-prod-subnet-private2-us-east-1b`
     - `k8s-platform-prod-subnet-private3-us-east-1c`

   **Security groups:**
   - Selecione `k8s-platform-prod-eks-cluster-sg`

   **Cluster endpoint access:**
   - Selecione **Public and private**

   **Advanced settings:**
   - **Public access CIDR:** Adicione apenas os IPs permitidos (ex: IP do seu escritório)

5. Clique em **Next**

   **Step 3 - Configure observability:**

   **Control plane logging:**
   - ✅ **API server**
   - ✅ **Audit**
   - ✅ **Authenticator**
   - ✅ **Controller manager**
   - ✅ **Scheduler**

6. Clique em **Next**

   **Step 4 - Select add-ons:**

   Selecione os add-ons padrão:
   - ✅ **Amazon VPC CNI** (networking)
   - ✅ **CoreDNS** (DNS interno)
   - ✅ **kube-proxy** (network proxy)
   - ✅ **Amazon EBS CSI Driver** (storage)

7. Clique em **Next**

   **Step 5 - Configure selected add-ons settings:**
   - Deixe as configurações padrão para todos os add-ons
   - Selecione a versão mais recente de cada um

8. Clique em **Next** → **Create**

9. Aguarde a criação (15-20 minutos)

---

#### 3.8.2 Criar Node Group: system

**Passo a passo no console:**

1. Após o cluster estar `Active`, clique no nome do cluster
2. Aba **Compute** → **Add node group**
3. Preencha:

   **Step 1 - Configure node group:**

   **Name:**
   - **Name:** `system`
   - **Node IAM role:** Selecione `k8s-platform-eks-node-role`

   **Node group scaling configuration:**
   - **Desired size:** 2
   - **Minimum size:** 2
   - **Maximum size:** 4

   **Node group update configuration:**
   - **Maximum unavailable:** Number → 1

   **Labels:**
   - `node-type` = `system`
   - `workload` = `platform`

   **Taints:** (deixe vazio para system nodes)

   **Tags:**
   - `Project` = `k8s-platform`
   - `NodeGroup` = `system`

4. Clique em **Next**

   **Step 2 - Set compute and scaling configuration:**

   **AMI type:**
   - Selecione **Amazon Linux 2 (AL2_x86_64)**

   **Capacity type:**
   - Selecione **On-Demand**

   **Instance types:**
   - Selecione **t3.medium**

   **Disk size:**
   - `30` GB

5. Clique em **Next**

   **Step 3 - Specify networking:**

   **Subnets:**
   - Selecione as 3 subnets privadas

   **Configure remote access to nodes:**
   - Selecione **Don't allow remote access to nodes** (use Session Manager)

6. Clique em **Next** → **Create**

---

#### 3.8.3 Criar Node Group: workloads

**Passo a passo no console:**

1. Clique em **Add node group**
2. Preencha:

   **Name:** `workloads`
   **Node IAM role:** `k8s-platform-eks-node-role`

   **Scaling:**
   - **Desired:** 3
   - **Min:** 2
   - **Max:** 6

   **Labels:**
   - `node-type` = `workloads`
   - `workload` = `applications`

   **Instance types:** `t3.large`
   **Disk size:** `50` GB

3. Complete os passos e clique em **Create**

---

#### 3.8.4 Criar Node Group: critical

**Passo a passo no console:**

1. Clique em **Add node group**
2. Preencha:

   **Name:** `critical`
   **Node IAM role:** `k8s-platform-eks-node-role`

   **Scaling:**
   - **Desired:** 2
   - **Min:** 2
   - **Max:** 4

   **Labels:**
   - `node-type` = `critical`
   - `workload` = `databases`

   **Taints:**
   - **Key:** `workload`
   - **Value:** `critical`
   - **Effect:** `NoSchedule`

   **Instance types:** `t3.xlarge`
   **Disk size:** `100` GB

3. Complete os passos e clique em **Create**

---

#### 3.8.5 Configurar kubectl para Acessar o Cluster

**Passo a passo via terminal:**

```bash
# Instalar AWS CLI V2 (se não tiver)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Verificar versão
aws --version  # Deve ser >= 2.x
```

**Escolha o método de autenticação:**

**MÉTODO 1: AWS CloudShell (sem configuração local)**

```bash
# Abra CloudShell no console AWS (ícone >_)
# Já vem com kubectl instalado

# Atualizar kubeconfig
aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod

# Verificar conexão
kubectl get nodes
```

---

**MÉTODO 2: SSO (IAM Identity Center) - Recomendado para desenvolvedores**

```bash
# Configurar SSO (uma vez)
aws configure sso
# SSO start URL: https://sua-empresa.awsapps.com/start
# SSO Region: us-east-1
# CLI profile name: k8s-platform-prod

# Login (quando expirar)
aws sso login --profile k8s-platform-prod

# Atualizar kubeconfig com perfil SSO
aws eks update-kubeconfig \
    --region us-east-1 \
    --name k8s-platform-prod \
    --profile k8s-platform-prod

# Verificar conexão
kubectl get nodes
```

---

**MÉTODO 3: Access Keys (CI/CD ou Terraform)**

```bash
# Configurar credenciais manualmente
cat > ~/.aws/credentials <<EOF
[k8s-platform-terraform]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
EOF
chmod 600 ~/.aws/credentials

cat > ~/.aws/config <<EOF
[profile k8s-platform-terraform]
region = us-east-1
output = json
EOF

# OU usar variáveis de ambiente
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_DEFAULT_REGION="us-east-1"

# Atualizar kubeconfig
aws eks update-kubeconfig \
    --region us-east-1 \
    --name k8s-platform-prod \
    --profile k8s-platform-terraform  # Omitir se usando variáveis de ambiente

# Verificar conexão
kubectl get nodes
```

---

### 🔹 Serviço: ALB (Application Load Balancer)

> **Contexto:** O ALB será gerenciado pelo AWS Load Balancer Controller instalado no EKS. Ele cria ALBs automaticamente para Ingress resources.

#### 3.9.1 Instalar AWS Load Balancer Controller

**Passo a passo via terminal:**

```bash
# ⚠️ IMPORTANTE: Use o mesmo perfil AWS configurado anteriormente
# Se usando SSO: aws sso login --profile k8s-platform-prod
# Se usando Access Keys: export AWS_PROFILE=k8s-platform-terraform

# Obter Account ID
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

# Criar IAM Policy para o controller
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.0/docs/install/iam_policy.json

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json \
    ${AWS_PROFILE:+--profile $AWS_PROFILE}

# Criar IRSA (IAM Role for Service Accounts)
# Adicione --profile se necessário
eksctl create iamserviceaccount \
  --cluster=k8s-platform-prod \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve \
  --region us-east-1 \
  ${AWS_PROFILE:+--profile $AWS_PROFILE}

# Instalar via Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=k8s-platform-prod \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Verificar instalação
kubectl get pods -n kube-system | grep aws-load-balancer-controller
```

---

### 🔹 Serviço: Route53

> **Contexto:** Route53 gerenciará o DNS para todos os serviços da plataforma. Integração com cert-manager permite certificados automáticos.

#### 3.10.1 Criar Hosted Zone

**Passo a passo no console:**

1. Na barra de busca, digite `Route53` e clique em **Route 53**
2. Clique em **Hosted zones** → **Create hosted zone**
3. Preencha:
   - **Domain name:** `k8s-platform.seudominio.com.br`
   - **Description:** `DNS-zone-para-plataforma-Kubernetes`
   - **Type:** Public hosted zone

4. **Tags:**
   - `Project` = `k8s-platform`
   - `Environment` = `prod`

5. Clique em **Create hosted zone**

6. **IMPORTANTE:** Copie os 4 nameservers (NS) exibidos e configure-os no seu registrador de domínio

---

### 🔹 Serviço: ACM (AWS Certificate Manager)

> **Contexto:** ACM fornece certificados TLS gratuitos e renovação automática. Será usado pelo ALB para HTTPS.

#### 3.11.1 Solicitar Certificado SSL

**Passo a passo no console:**

1. Na barra de busca, digite `ACM` e clique em **Certificate Manager**
2. Clique em **Request certificate**
3. Selecione **Request a public certificate** → **Next**
4. Preencha:

   **Domain names:**
   - `*.k8s-platform.seudominio.com.br`
   - `k8s-platform.seudominio.com.br`

   **Validation method:**
   - Selecione **DNS validation (recommended)**

   **Key algorithm:**
   - Selecione **RSA 2048**

5. **Tags:**
   - `Project` = `k8s-platform`
   - `Environment` = `prod`

6. Clique em **Request**

7. Na lista de certificados, clique no certificado pendente
8. Clique em **Create records in Route 53** para validação automática
9. Aguarde o status mudar para `Issued` (5-30 minutos)

---

### 🔹 Serviço: Secrets Manager

> **Contexto:** Secrets Manager armazena credenciais de forma segura com rotação automática. Integra com EKS via External Secrets Operator.

#### 3.12.1 Criar Secret para RDS

**Passo a passo no console:**

1. Na barra de busca, digite `Secrets Manager` e clique em **Secrets Manager**
2. Clique em **Store a new secret**
3. Preencha:

   **Secret type:**
   - Selecione **Credentials for Amazon RDS database**

   **Credentials:**
   - **User name:** `postgres_admin`
   - **Password:** (a senha master do RDS)

   **Database:**
   - Selecione `k8s-platform-prod-postgresql`

   **Encryption key:**
   - Selecione `alias/k8s-platform-prod`

4. Clique em **Next**

   **Secret name and description:**
   - **Secret name:** `k8s-platform/prod/rds/master`
   - **Description:** `Credenciais-master-do-RDS-PostgreSQL`

   **Tags:**
   - `Project` = `k8s-platform`
   - `Environment` = `prod`

5. Clique em **Next**

   **Configure rotation:**
   - ✅ **Automatic rotation**
   - **Rotation schedule:** 30 days
   - **Rotation function:** Create a new Lambda function

6. Clique em **Next** → **Store**

---

#### 3.12.2 Criar Secrets para Aplicações

Repita o processo para cada aplicação:

| Secret Name | Tipo | Conteúdo |
|-------------|------|----------|
| `k8s-platform/prod/gitlab/db` | Other type of secret | `{"username":"gitlab_user","password":"..."}` |
| `k8s-platform/prod/keycloak/db` | Other type of secret | `{"username":"keycloak_user","password":"..."}` |
| `k8s-platform/prod/sonarqube/db` | Other type of secret | `{"username":"sonarqube_user","password":"..."}` |
| `k8s-platform/prod/redis` | Other type of secret | `{"auth_token":"..."}` |

---

### 🔹 Serviço: CloudWatch

> **Contexto:** CloudWatch centraliza logs e métricas AWS. Container Insights oferece observabilidade nativa para EKS.

#### 3.13.1 Criar Log Groups

**Passo a passo no console:**

1. Na barra de busca, digite `CloudWatch` e clique em **CloudWatch**
2. Menu lateral → **Logs** → **Log groups**
3. Clique em **Create log group**
4. Preencha:
   - **Log group name:** `/aws/eks/k8s-platform-prod/cluster`
   - **Retention setting:** 30 days
   - **KMS key:** `alias/k8s-platform-prod`

5. **Tags:**
   - `Project` = `k8s-platform`
   - `Environment` = `prod`

6. Clique em **Create**

Repita para:
- `/aws/rds/instance/k8s-platform-prod-postgresql/postgresql`
- `/aws/elasticache/k8s-platform-prod-redis`

---

#### 3.13.2 Habilitar Container Insights

**Passo a passo no console:**

1. Em **CloudWatch**, menu lateral → **Container Insights**
2. Clique em **View container insights**
3. Se não estiver configurado, clique em **Quick Start**
4. Selecione o cluster `k8s-platform-prod`
5. Siga o wizard para instalar o CloudWatch Agent via Helm:

```bash
# Instalar CloudWatch Agent
FluentBitHttpPort='2020'
FluentBitReadFromHead='Off'
[[ ${FluentBitReadFromHead} = 'On' ]] && FluentBitReadFromTail='Off'|| FluentBitReadFromTail='On'
[[ -z ${FluentBitHttpPort} ]] && FluentBitHttpServer='Off' || FluentBitHttpServer='On'

ClusterName=k8s-platform-prod
RegionName=us-east-1
LogRegion=us-east-1

curl https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluent-bit-quickstart.yaml | sed 's/{{cluster_name}}/'${ClusterName}'/;s/{{region_name}}/'${RegionName}'/;s/{{http_server_toggle}}/"'${FluentBitHttpServer}'"/;s/{{http_server_port}}/"'${FluentBitHttpPort}'"/;s/{{read_from_head}}/"'${FluentBitReadFromHead}'"/;s/{{read_from_tail}}/"'${FluentBitReadFromTail}'"/' | kubectl apply -f -
```

---

### 🔹 Serviço: WAF (Web Application Firewall)

> **Contexto:** WAF protege aplicações web contra ataques OWASP Top 10 (SQL Injection, XSS, etc.). Será associado ao ALB.

#### 3.14.1 Criar Web ACL

**Passo a passo no console:**

1. Na barra de busca, digite `WAF` e clique em **WAF & Shield**
2. Clique em **Web ACLs** → **Create web ACL**
3. Preencha:

   **Step 1 - Describe web ACL:**
   - **Resource type:** Regional resources (Application Load Balancer, API Gateway, etc.)
   - **Region:** US East (N. Virginia)
   - **Name:** `k8s-platform-prod-waf`
   - **Description:** `WAF-para-proteAAo-da-plataforma-Kubernetes`
   - **CloudWatch metric name:** `k8s-platform-prod-waf`

4. Clique em **Next**

   **Step 2 - Add rules and rule groups:**

   Clique em **Add rules** → **Add managed rule groups**

   Selecione os seguintes **AWS managed rule groups** (gratuitos):
   - ✅ **Core rule set (CRS)** - Proteção geral
   - ✅ **Known bad inputs** - Inputs maliciosos conhecidos
   - ✅ **SQL database** - SQL Injection
   - ✅ **Linux operating system** - Ataques específicos Linux

   **Default action:**
   - Selecione **Allow**

5. Clique em **Next**

   **Step 3 - Set rule priority:**
   - Deixe a ordem padrão

6. Clique em **Next**

   **Step 4 - Configure metrics:**
   - ✅ **Enable CloudWatch metrics**
   - ✅ **Enable sampling of requests**

7. Clique em **Next**

   **Step 5 - Review and create:**
   - Revise as configurações

8. Clique em **Create web ACL**

---

### 🔹 Serviço: AWS Backup

> **Contexto:** AWS Backup centraliza backups de RDS, EBS e outros serviços. Essencial para Disaster Recovery.

#### 3.15.1 Criar Backup Plan

**Passo a passo no console:**

1. Na barra de busca, digite `AWS Backup` e clique em **AWS Backup**
2. Clique em **Backup plans** → **Create backup plan**
3. Selecione **Build a new plan**
4. Preencha:

   **Backup plan name:**
   - **Backup plan name:** `k8s-platform-prod-backup-plan`

   **Backup rule configuration:**
   - **Backup rule name:** `daily-backup`
   - **Backup vault:** Create new vault
     - **Vault name:** `k8s-platform-prod-vault`
     - **Encryption key:** `alias/k8s-platform-prod`
   - **Backup frequency:** Daily
   - **Backup window:** Start within 2 hours of 03:00 UTC
   - **Transition to cold storage:** After 30 days
   - **Retention period:** 90 days
   - ✅ **Enable continuous backups for supported resources** (point-in-time recovery)

5. Clique em **Create plan**

---

#### 3.15.2 Associar Recursos ao Backup Plan

**Passo a passo no console:**

1. No backup plan criado, clique em **Assign resources**
2. Preencha:
   - **Resource assignment name:** `k8s-platform-prod-resources`
   - **IAM role:** Default role

   **Define resource selection:**
   - Selecione **Include specific resource types**
   - **Select specific resource types:**
     - ✅ **RDS**
     - ✅ **EBS**
     - ✅ **S3**

   **Refine selection using tags:**
   - **Tag key:** `Project`
   - **Tag value:** `k8s-platform`

3. Clique em **Assign resources**

---

## 4️⃣ Boas Práticas DevOps AWS (Obrigatório)

### 4.1 IAM - Menor Privilégio

| Prática | Implementação |
|---------|---------------|
| **Roles por serviço** | Uma IAM Role para cada componente (EKS, Nodes, etc.) |
| **IRSA** | IAM Roles for Service Accounts - pods com permissões específicas |
| **Sem root** | Nunca usar conta root para operações |
| **MFA obrigatório** | Todos os usuários IAM devem ter MFA habilitado |
| **Access Keys rotativas** | Rotação a cada 90 dias |

### 4.2 Tags Obrigatórias

**Todas** as resources devem ter estas tags:

| Tag | Descrição | Exemplo |
|-----|-----------|---------|
| `Project` | Nome do projeto | `k8s-platform` |
| `Environment` | Ambiente | `prod`, `staging`, `dev` |
| `Owner` | Time responsável | `devops-team` |
| `CostCenter` | Centro de custo | `infrastructure` |
| `ManagedBy` | Gerenciamento | `terraform`, `manual` |

### 4.3 Separação de Ambientes

```
Opção 1: VPCs separadas (recomendado)
├── VPC-staging (10.1.0.0/16) → Conta AWS: staging
└── VPC-prod (10.0.0.0/16)    → Conta AWS: prod

Opção 2: Namespaces no EKS (custo menor)
├── k8s-platform-prod
│   ├── ns: platform-core
│   ├── ns: platform-core-staging
│   └── ...
```

### 4.4 IaC com Terraform

**Estrutura obrigatória:**

```
platform-provisioning/
├── aws/
│   ├── environments/
│   │   ├── prod/
│   │   │   ├── terraform.tfvars
│   │   │   └── backend.tf
│   │   └── staging/
│   │       ├── terraform.tfvars
│   │       └── backend.tf
│   ├── modules/
│   │   ├── vpc/
│   │   ├── eks/
│   │   ├── rds/
│   │   └── s3/
│   └── main.tf
```

**Backend S3 (obrigatório):**

```hcl
terraform {
  backend "s3" {
    bucket         = "k8s-platform-terraform-state-{account-id}"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
    # profile       = "k8s-platform-terraform"  # Se usando AWS CLI profile
  }
}
```

**Autenticação Terraform:**

**Opção 1: Variáveis de Ambiente (CI/CD)**

```bash
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_DEFAULT_REGION="us-east-1"

terraform init
terraform plan
terraform apply
```

**Opção 2: AWS Profile (Local)**

```bash
# Usar perfil do ~/.aws/credentials
export AWS_PROFILE=k8s-platform-terraform

terraform init
terraform plan
terraform apply
```

**Opção 3: SSO (Desenvolvedor)**

```bash
# Login SSO
aws sso login --profile k8s-platform-prod

# Usar perfil SSO
export AWS_PROFILE=k8s-platform-prod

terraform init
terraform plan
```

**Opção 4: IAM Role (EC2/Lambda)**

```hcl
# provider.tf - Terraform assume automaticamente a role da instância
provider "aws" {
  region = "us-east-1"
  # Sem credenciais explícitas - usa EC2 Instance Profile
}
```

**GitHub Actions CI/CD:**

```yaml
# .github/workflows/terraform.yml
name: Terraform Apply

on:
  push:
    branches: [main]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.7.0

      - name: Terraform Init
        run: terraform init
        working-directory: aws/environments/prod

      - name: Terraform Plan
        run: terraform plan -out=tfplan
        working-directory: aws/environments/prod

      - name: Terraform Apply
        if: github.ref == 'refs/heads/main'
        run: terraform apply -auto-approve tfplan
        working-directory: aws/environments/prod
```

### 4.5 Logs e Monitoramento

| Componente | Destino | Retenção |
|------------|---------|----------|
| EKS Control Plane | CloudWatch Logs | 30 dias |
| Container Logs | Loki (S3 backend) | 90 dias |
| RDS Logs | CloudWatch Logs | 30 dias |
| VPC Flow Logs | CloudWatch Logs | 7 dias |
| CloudTrail | S3 | 365 dias |

---

## 5️⃣ Estratégia de Testes e Validação

### 5.1 VPC e Networking

| Teste | Comando/Ação | Resultado Esperado |
|-------|--------------|-------------------|
| Subnets criadas | Console VPC → Subnets | 9 subnets (3 public + 3 private + 3 db) |
| NAT Gateway | Console VPC → NAT Gateways | Status: Available |
| Route Tables | Console VPC → Route Tables | Rotas corretas por subnet |
| Conectividade privada | Ping entre subnets | Resposta OK |

### 5.2 EKS Cluster

| Teste | Comando | Resultado Esperado |
|-------|---------|-------------------|
| Cluster ativo | `kubectl cluster-info` | URLs do cluster |
| Nodes prontos | `kubectl get nodes` | Todos os nodes `Ready` |
| Core DNS | `kubectl get pods -n kube-system` | CoreDNS running |
| Networking | `kubectl run test --image=nginx --restart=Never` | Pod running |

### 5.3 RDS e ElastiCache

| Teste | Ação | Resultado Esperado |
|-------|------|-------------------|
| RDS disponível | Console RDS | Status: Available |
| Conexão PostgreSQL | `psql -h <endpoint> -U postgres_admin` | Conexão bem-sucedida |
| Redis disponível | Console ElastiCache | Status: Available |
| Conexão Redis | `redis-cli -h <endpoint> PING` | PONG |

### 5.4 Teste de Carga

```bash
# Instalar k6 para teste de carga
kubectl run k6 --image=grafana/k6 --restart=Never -- run - <<EOF
import http from 'k6/http';
export default function () {
  http.get('https://gitlab.k8s-platform.seudominio.com.br');
}
EOF
```

### 5.5 Métricas a Observar

| Métrica | Threshold Warning | Threshold Critical |
|---------|-------------------|-------------------|
| CPU Nodes | >70% | >85% |
| Memory Nodes | >75% | >90% |
| RDS CPU | >70% | >85% |
| RDS Connections | >80% max | >90% max |
| EBS IOPS | >80% provisioned | >90% provisioned |

---

## 6️⃣ Gestão de Custos (FinOps)

### 6.1 Ativar AWS Billing e Cost Explorer

**Passo a passo no console:**

1. Clique no nome da conta (canto superior direito)
2. Clique em **Billing Dashboard**
3. Menu lateral → **Cost Management** → **Cost Explorer**
4. Clique em **Enable Cost Explorer** (se não estiver ativo)
5. Aguarde 24 horas para dados aparecerem

### 6.2 Criar Orçamento (Budget)

**Passo a passo no console:**

1. Em **Billing** → **Budgets**
2. Clique em **Create budget**
3. Selecione **Customized - Advanced**
4. Preencha:

   **Budget setup:**
   - **Name:** `k8s-platform-monthly-budget`
   - **Period:** Monthly
   - **Budget effective date:** Recurring budget
   - **Start month:** (mês atual)
   - **Budgeting method:** Fixed
   - **Enter your budgeted amount:** `1000` (USD)

   **Budget scope:**
   - **Filter:** Tag → `Project` = `k8s-platform`

5. Clique em **Next**

   **Configure alerts:**

   **Alert 1:**
   - **Threshold:** 50% of budgeted amount
   - **Trigger:** Actual
   - **Email:** devops-team@empresa.com.br

   **Alert 2:**
   - **Threshold:** 80% of budgeted amount
   - **Trigger:** Actual
   - **Email:** devops-team@empresa.com.br, finops@empresa.com.br

   **Alert 3:**
   - **Threshold:** 100% of budgeted amount
   - **Trigger:** Forecasted
   - **Email:** (todos + gerência)

6. Clique em **Create budget**

### 6.3 Serviços Mais Críticos em Custo

| Serviço | Custo Estimado | % Total | Ação de Otimização |
|---------|---------------|---------|-------------------|
| **EC2 (Node Groups)** | $486/mês | 44% | Reserved Instances |
| **RDS PostgreSQL** | $215/mês | 19% | Rightsizing ou RI |
| **NAT Gateway** | $121/mês | 11% | Reduzir para 1 NAT |
| **ALB** | $75/mês | 7% | - |
| **ElastiCache** | $50/mês | 4% | - |
| **EKS Control Plane** | $73/mês | 6% | - |

### 6.4 Estratégias de Redução de Custo

| Estratégia | Economia Estimada | Esforço |
|------------|------------------|---------|
| Reserved Instances (1 ano) | 31% em EC2/RDS | Médio |
| Savings Plans | 15-20% adicional | Baixo |
| 1 NAT Gateway (dev/staging) | $81/mês | Baixo |
| Spot Instances (workloads tolerantes) | 70% em EC2 | Alto |
| S3 Lifecycle (Glacier) | 80% em storage antigo | Baixo |
| Rightsizing RDS | Até $100/mês | Médio |

---

## 7️⃣ Estratégia de Desligamento e Economia

### 7.1 Ambiente Staging - Scheduled Stop

**Passo a passo para agendar stop dos nodes:**

1. Crie uma Lambda para stop/start:

```python
# lambda_function.py
import boto3

def lambda_handler(event, context):
    action = event.get('action', 'stop')
    client = boto3.client('eks')
    asg = boto3.client('autoscaling')

    # Obter ASGs do node group staging
    asgs = asg.describe_auto_scaling_groups(
        Filters=[{'Name': 'tag:eks:nodegroup-name', 'Values': ['system', 'workloads']}]
    )

    for group in asgs['AutoScalingGroups']:
        if 'staging' in group['AutoScalingGroupName']:
            if action == 'stop':
                asg.update_auto_scaling_group(
                    AutoScalingGroupName=group['AutoScalingGroupName'],
                    MinSize=0, MaxSize=0, DesiredCapacity=0
                )
            else:
                asg.update_auto_scaling_group(
                    AutoScalingGroupName=group['AutoScalingGroupName'],
                    MinSize=2, MaxSize=4, DesiredCapacity=2
                )

    return {'status': 'success', 'action': action}
```

2. Crie EventBridge Rules:

**Stop (20:00 BRT = 23:00 UTC):**
- Cron: `cron(0 23 ? * MON-FRI *)`
- Target: Lambda → `eks-staging-scheduler`
- Input: `{"action": "stop"}`

**Start (08:00 BRT = 11:00 UTC):**
- Cron: `cron(0 11 ? * MON-FRI *)`
- Target: Lambda → `eks-staging-scheduler`
- Input: `{"action": "start"}`

### 7.2 RDS Stop/Start

**Passo a passo no console:**

1. **RDS** → Selecione a instância staging
2. **Actions** → **Stop temporarily**
3. **IMPORTANTE:** RDS para automaticamente após 7 dias. Para paradas mais longas, use snapshot + delete.

### 7.3 S3 Lifecycle para Logs

```json
{
    "Rules": [
        {
            "ID": "move-to-glacier",
            "Status": "Enabled",
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                }
            ],
            "Expiration": {
                "Days": 365
            }
        }
    ]
}
```

### 7.4 Riscos de Esquecer Recursos Ligados

| Recurso | Custo se Esquecido | Mitigação |
|---------|-------------------|-----------|
| **NAT Gateway** | $32/mês (idle) | Budget alert |
| **RDS Multi-AZ** | $200+/mês | Lambda scheduled stop |
| **EKS Nodes** | $480+/mês | ASG MinSize=0 fora horário |
| **ALB** | $16/mês (idle) | Aceitar custo mínimo |
| **EBS não anexados** | Variável | Tag `DeleteAfter` + Lambda cleanup |

---

## 8️⃣ Checklist Final DevOps

### Segurança

- [ ] MFA habilitado para todas as contas IAM
- [ ] IAM Roles com menor privilégio
- [ ] **Autenticação AWS CLI configurada** (CloudShell, SSO ou Access Keys com rotação)
- [ ] Access Keys armazenadas no AWS Secrets Manager (se aplicável)
- [ ] Rotação de Access Keys a cada 90 dias validada (se aplicável)
- [ ] VPC com subnets públicas/privadas separadas
- [ ] Security Groups com regras mínimas
- [ ] KMS encryption habilitada em RDS, S3, EBS, EKS secrets
- [ ] WAF configurado e ativo
- [ ] CloudTrail habilitado
- [ ] Secrets no AWS Secrets Manager (não em código)
- [ ] Network Policies no Kubernetes
- [ ] Pod Security Standards aplicados

### Custo

- [ ] Budgets configurados com alertas
- [ ] Tags obrigatórias em todos os recursos
- [ ] Cost Explorer ativado
- [ ] Reserved Instances avaliadas
- [ ] S3 Lifecycle configurado
- [ ] Scheduled stop para staging
- [ ] Rightsizing inicial validado

### Monitoramento

- [ ] CloudWatch Logs habilitados (EKS, RDS, ElastiCache)
- [ ] Container Insights ativo
- [ ] Métricas customizadas definidas
- [ ] Alertas de threshold configurados
- [ ] Dashboard de custo criado
- [ ] Prometheus + Grafana instalados no cluster

### Testes

- [ ] Conectividade de rede validada
- [ ] EKS cluster acessível via kubectl
- [ ] RDS conexão testada
- [ ] Redis conexão testada
- [ ] DNS resolvendo corretamente
- [ ] Certificado SSL válido
- [ ] ALB respondendo

### Desligamento

- [ ] Lambda de scheduled stop criada
- [ ] EventBridge rules configuradas
- [ ] Procedimento de DR documentado
- [ ] Backups validados (restore test)

### Pronto para Produção?

**Status:** ⚠️ **Parcial**

**Justificativa:**

| Critério | Status | Comentário |
|----------|--------|------------|
| Infraestrutura base | ✅ | VPC, EKS, RDS prontos |
| Segurança | ⚠️ | Falta validar Network Policies |
| HA/DR | ✅ | Multi-AZ configurado |
| Backups | ✅ | AWS Backup ativo |
| Monitoramento | ⚠️ | Falta Prometheus/Grafana |
| CI/CD | ❌ | GitLab não instalado ainda |
| Documentação | ✅ | ADRs e runbooks |

**Próximos passos para produção:**
1. Deploy dos domínios Kubernetes (platform-core → cicd-platform)
2. Validação de Network Policies
3. Teste de DR completo
4. Aprovação do time de segurança

---

## Anexos

### A. Comandos Úteis

```bash
# Verificar custos via CLI
aws ce get-cost-and-usage \
    --time-period Start=2026-01-01,End=2026-01-31 \
    --granularity MONTHLY \
    --metrics "BlendedCost" \
    --filter '{"Tags":{"Key":"Project","Values":["k8s-platform"]}}'

# Listar recursos por tag
aws resourcegroupstaggingapi get-resources \
    --tag-filters Key=Project,Values=k8s-platform

# Verificar status do cluster
aws eks describe-cluster --name k8s-platform-prod --query 'cluster.status'

# Verificar nodes
aws eks list-nodegroups --cluster-name k8s-platform-prod
```

### B. Links Úteis

**Documentação AWS:**
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html)
- [EKS Workshop](https://www.eksworkshop.com/)
- [AWS Pricing Calculator](https://calculator.aws/)

**Autenticação e Segurança:**
- [AWS CLI V2 - SSO Configuration](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html)
- [AWS CloudShell User Guide](https://docs.aws.amazon.com/cloudshell/latest/userguide/welcome.html)
- [IAM Identity Center (SSO) Best Practices](https://docs.aws.amazon.com/singlesignon/latest/userguide/best-practices.html)
- [IAM Roles for Service Accounts (IRSA)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [AWS Security Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)

---

**Documento gerado em:** 2026-01-19
**Última atualização:** 2026-01-22
**Autor:** DevOps AWS Specialist
**Versão:** 1.1
**Alterações (v1.1):**
- Atualizada seção 3.1.4 com recomendações AWS 2026 (CloudShell, SSO, Access Keys)
- Atualizada seção 3.8.5 com múltiplos métodos de autenticação kubectl
- Atualizada seção 3.9.1 com suporte a perfis AWS
- Atualizada seção 4.4 com autenticação Terraform e CI/CD
- Adicionados itens de checklist para validação de autenticação
**Próxima revisão:** Após deploy inicial




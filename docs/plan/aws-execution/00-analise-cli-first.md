# Análise CLI-First dos Documentos de Execução AWS

**Data da Análise:** 2026-01-20
**Versão:** 1.0
**Objetivo:** Avaliar os documentos de execução contra os critérios CLI-first, Security by Design e automação de testes.

---

## 1. Sumário Executivo

### 1.1 Critérios de Avaliação (baseado no prompt de referência)

| Critério | Descrição | Peso |
|----------|-----------|------|
| **CLI-First** | Preferência por CLI, IaC (Terraform/Pulumi) sobre ClickOps | Alto |
| **Security by Design** | IAM least-privilege, RBAC, secrets management | Alto |
| **Testes por Fase** | Scripts de validação automatizados | Médio |
| **Automação** | Scripts reproduzíveis, idempotentes | Alto |
| **Governança** | Rastreabilidade, rollback, Definition of Done | Médio |

### 1.2 Resultado Geral por Documento

| Documento | CLI-First | Security | Testes | Automação | Score |
|-----------|-----------|----------|--------|-----------|-------|
| 01-infraestrutura-base | ⚠️ 30% | ✅ 80% | ⚠️ 50% | ❌ 20% | **45%** |
| 02-gitlab-helm-deploy | ✅ 85% | ✅ 75% | ⚠️ 60% | ✅ 80% | **75%** |
| 03-data-services-helm | ⚠️ 60% | ✅ 80% | ⚠️ 50% | ⚠️ 55% | **61%** |
| 04-observability-stack | ✅ 90% | ✅ 80% | ⚠️ 50% | ✅ 85% | **76%** |
| 05-security-hardening | ⚠️ 70% | ✅ 90% | ⚠️ 60% | ⚠️ 65% | **71%** |
| 06-backup-disaster-recovery | ✅ 80% | ✅ 85% | ✅ 70% | ✅ 75% | **78%** |
| 07-finops-automacao | ⚠️ 50% | ✅ 75% | ⚠️ 40% | ⚠️ 60% | **56%** |
| 08-validacao-checklist | ✅ 95% | ✅ 85% | ✅ 90% | ✅ 85% | **89%** |

**Legenda:** ✅ Bom (≥70%) | ⚠️ Parcial (40-69%) | ❌ Insuficiente (<40%)

---

## 2. Análise Detalhada por Documento

### 2.1 Doc 01 - Infraestrutura Base AWS

**Status atual:** ⚠️ Predominantemente ClickOps

#### Lacunas Identificadas:

| Seção | Problema | Impacto | Solução Proposta |
|-------|----------|---------|------------------|
| **2.1 VPC Wizard** | Console AWS (ClickOps) | Não reproduzível | Adicionar Terraform module |
| **2.2 Subnets de Dados** | Console AWS | Não versionável | Terraform ou AWS CLI |
| **2.3 Route Table Association** | Console AWS | Manual, erro-prone | AWS CLI script |
| **2.5 Security Groups** | Console AWS | Não auditável | Terraform ou AWS CLI |
| **3.1-3.2 IAM Roles** | Console AWS | Risco de drift | Terraform com policies |
| **3.3 EKS Cluster** | Console AWS | Longo, complexo | eksctl ou Terraform |
| **3.5-3.7 Node Groups** | Console AWS | Repetitivo | eksctl nodegroup create |

#### Pontos Positivos:
- ✅ Seção 2.4 (Tags EKS) já usa AWS CLI
- ✅ Seção 4 (StorageClass) usa kubectl
- ✅ Seção 5 (RBAC) usa kubectl
- ✅ Definition of Done bem estruturado

#### Ações Corretivas:
1. **[CRÍTICO]** Adicionar seção de Terraform completa para VPC + EKS
2. **[ALTO]** Adicionar AWS CLI alternativo para cada passo Console
3. **[MÉDIO]** Criar script `setup-infra.sh` idempotente

---

### 2.2 Doc 02 - GitLab Helm Deploy

**Status atual:** ✅ Predominantemente CLI

#### Lacunas Identificadas:

| Seção | Problema | Solução Proposta |
|-------|----------|------------------|
| Route53 records | Se via Console | Adicionar AWS CLI alternativo |
| ALB Controller | Bem documentado | OK |
| GitLab Helm | Completo com values.yaml | OK |

#### Pontos Positivos:
- ✅ Helm install bem documentado
- ✅ Values.yaml completo com comentários
- ✅ Comandos de verificação incluídos
- ✅ Troubleshooting adequado

#### Ações Corretivas:
1. **[BAIXO]** Garantir Route53 via CLI
2. **[MÉDIO]** Adicionar teste de smoke automatizado

---

### 2.3 Doc 03 - Data Services Helm

**Status atual:** ⚠️ Misto (RDS ClickOps, Redis/RabbitMQ CLI)

#### Lacunas Identificadas:

| Seção | Problema | Impacto | Solução Proposta |
|-------|----------|---------|------------------|
| **2.1 DB Subnet Group** | Console AWS | Não reproduzível | AWS CLI `create-db-subnet-group` |
| **2.2 Parameter Group** | Console AWS | Parâmetros perdidos | AWS CLI ou Terraform |
| **2.3 RDS Instance** | Console AWS (20+ campos) | Altíssimo risco de erro | Terraform module RDS |
| **2.5 Secrets Manager** | Console AWS | Secrets não versionados | AWS CLI `create-secret` |
| **3.x Redis** | ✅ Helm | OK | - |
| **4.x RabbitMQ** | ✅ Helm | OK | - |

#### Pontos Positivos:
- ✅ Redis e RabbitMQ via Helm (excelente)
- ✅ Values.yaml bem estruturados
- ✅ Testes de conexão incluídos
- ✅ NetworkPolicy nos Helm values

#### Ações Corretivas:
1. **[CRÍTICO]** Adicionar Terraform module para RDS PostgreSQL
2. **[ALTO]** Adicionar AWS CLI para Secrets Manager
3. **[MÉDIO]** Script de provisionamento unificado

---

### 2.4 Doc 05 - Security Hardening

**Status atual:** ⚠️ Misto (K8s CLI, AWS ClickOps)

#### Lacunas Identificadas:

| Seção | Problema | Solução Proposta |
|-------|----------|------------------|
| **6.1 WAF Web ACL** | Console AWS (complexo) | Terraform WAFv2 ou CLI |
| **6.3 WAF Association** | ✅ CLI disponível | OK |
| **7.2-7.3 Security Groups** | Console AWS | AWS CLI `modify-security-group-rules` |
| **8.1 Secrets Manager** | Console AWS | AWS CLI `create-secret` |

#### Pontos Positivos:
- ✅ Network Policies completas em YAML
- ✅ Pod Security Standards bem explicados
- ✅ RBAC com exemplos detalhados
- ✅ cert-manager via Helm
- ✅ External Secrets Operator via Helm
- ✅ Script de validação de segurança

#### Ações Corretivas:
1. **[CRÍTICO]** Adicionar Terraform ou AWS CLI para WAF
2. **[ALTO]** Adicionar CLI para Security Groups hardening
3. **[MÉDIO]** Script unificado `apply-security.sh`

---

## 3. Padrões de Melhoria Recomendados

### 3.1 Estrutura CLI-First para Cada Operação

```markdown
### X.Y Operação Nome

#### Opção A: Terraform (Recomendado - IaC)
\`\`\`hcl
resource "aws_xxx" "name" {
  # configuração
}
\`\`\`

#### Opção B: AWS CLI
\`\`\`bash
aws xxx create-yyy \
  --param value \
  --tags Key=Project,Value=k8s-platform
\`\`\`

#### Opção C: Console AWS (Referência Visual)
> ⚠️ **Nota:** Prefira as opções A ou B para ambientes de produção.
> Use o Console apenas para aprendizado ou troubleshooting.

1. Passo via console...
```

### 3.2 Bloco de Validação Padrão

```markdown
### Validação da Tarefa X.Y

\`\`\`bash
#!/bin/bash
# validate-task-xy.sh

set -euo pipefail

echo "🔍 Validando Task X.Y..."

# Teste 1: Recurso existe
RESOURCE=$(aws xxx describe-yyy --name "value" --query "..." --output text)
if [[ -z "$RESOURCE" ]]; then
  echo "❌ FALHA: Recurso não encontrado"
  exit 1
fi
echo "✅ Recurso criado: $RESOURCE"

# Teste 2: Configuração correta
CONFIG=$(aws xxx describe-yyy --query "Config.Param" --output text)
if [[ "$CONFIG" != "expected" ]]; then
  echo "❌ FALHA: Configuração incorreta"
  exit 1
fi
echo "✅ Configuração validada"

echo "🎉 Task X.Y validada com sucesso!"
\`\`\`
```

### 3.3 Diagrama de Fluxo Padrão (Mermaid)

```markdown
\`\`\`mermaid
flowchart TD
    A[Início Task X.Y] --> B{Recurso existe?}
    B -->|Não| C[Criar via CLI/Terraform]
    B -->|Sim| D[Verificar configuração]
    C --> D
    D --> E{Config OK?}
    E -->|Não| F[Atualizar configuração]
    E -->|Sim| G[Executar testes]
    F --> G
    G --> H{Testes passam?}
    H -->|Não| I[Rollback + Investigar]
    H -->|Sim| J[✅ Task completa]
    I --> A
\`\`\`
```

---

## 4. Priorização das Melhorias

### 4.1 Crítico (Implementar Imediatamente)

| ID | Documento | Melhoria | Justificativa |
|----|-----------|----------|---------------|
| C1 | Doc 01 | Terraform VPC + EKS | Base de toda infraestrutura |
| C2 | Doc 03 | Terraform/CLI para RDS | Dados críticos, reprodutibilidade |
| C3 | Doc 05 | Terraform/CLI para WAF | Segurança de borda |

### 4.2 Alto (Próxima Sprint)

| ID | Documento | Melhoria | Justificativa |
|----|-----------|----------|---------------|
| A1 | Doc 01 | AWS CLI para todos passos Console | Consistência |
| A2 | Doc 03 | AWS CLI para Secrets Manager | Gestão de credenciais |
| A3 | Doc 05 | CLI para Security Groups | Hardening automatizado |

### 4.3 Médio (Backlog)

| ID | Documento | Melhoria | Justificativa |
|----|-----------|----------|---------------|
| M1 | Todos | Scripts de setup unificados | DX (Developer Experience) |
| M2 | Todos | Diagramas Mermaid | Visualização |
| M3 | Todos | Testes automatizados por fase | CI/CD readiness |

---

## 5. Templates de Código Recomendados

### 5.1 Terraform: VPC + EKS (para Doc 01)

```hcl
# terraform/01-vpc-eks/main.tf

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "k8s-platform-terraform-state"
    key    = "vpc-eks/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "k8s-platform"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-${var.environment}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs
  database_subnets = var.database_subnet_cidrs

  enable_nat_gateway     = true
  single_nat_gateway     = var.environment != "prod"
  enable_dns_hostnames   = true
  enable_dns_support     = true

  # Tags para EKS
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = 1
  }
  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  enable_irsa = true

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
    aws-ebs-csi-driver = { most_recent = true }
  }

  eks_managed_node_groups = {
    system = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      labels = {
        "node-type" = "system"
      }
    }
    workloads = {
      instance_types = ["t3.large"]
      min_size       = 2
      max_size       = 6
      desired_size   = 3
      labels = {
        "node-type" = "workloads"
      }
    }
    critical = {
      instance_types = ["t3.xlarge"]
      min_size       = 2
      max_size       = 4
      desired_size   = 2
      labels = {
        "node-type" = "critical"
      }
      taints = [{
        key    = "workload"
        value  = "critical"
        effect = "NO_SCHEDULE"
      }]
    }
  }
}
```

### 5.2 Terraform: RDS PostgreSQL (para Doc 03)

```hcl
# terraform/03-rds/main.tf

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "${var.project_name}-${var.environment}-postgresql"

  engine               = "postgres"
  engine_version       = "15.4"
  family               = "postgres15"
  major_engine_version = "15"
  instance_class       = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "platform"
  username = "postgres_admin"
  port     = 5432

  multi_az               = var.environment == "prod"
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  maintenance_window      = "Sun:04:00-Sun:05:00"
  backup_window           = "03:00-04:00"
  backup_retention_period = 7

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  deletion_protection = var.environment == "prod"

  parameters = [
    {
      name  = "max_connections"
      value = "200"
    },
    {
      name  = "log_min_duration_statement"
      value = "1000"
    }
  ]

  tags = {
    CostCenter = "infrastructure"
  }
}

# Armazenar senha no Secrets Manager
resource "aws_secretsmanager_secret" "rds_password" {
  name = "${var.project_name}/${var.environment}/rds/master-password"
}

resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id = aws_secretsmanager_secret.rds_password.id
  secret_string = jsonencode({
    username = module.rds.db_instance_username
    password = module.rds.db_instance_password
    host     = module.rds.db_instance_endpoint
    port     = module.rds.db_instance_port
    database = "platform"
  })
}
```

### 5.3 AWS CLI: WAF Web ACL (para Doc 05)

```bash
#!/bin/bash
# scripts/create-waf.sh

set -euo pipefail

PROJECT_NAME="k8s-platform"
REGION="us-east-1"

echo "🔒 Criando WAF Web ACL..."

# 1. Criar IP Set para allowlist
IP_SET_ARN=$(aws wafv2 create-ip-set \
  --name "${PROJECT_NAME}-office-ips" \
  --scope REGIONAL \
  --ip-address-version IPV4 \
  --addresses "203.0.113.0/24" "198.51.100.0/24" \
  --region $REGION \
  --query 'Summary.ARN' --output text)

echo "✅ IP Set criado: $IP_SET_ARN"

# 2. Criar Web ACL com regras
aws wafv2 create-web-acl \
  --name "${PROJECT_NAME}-waf" \
  --scope REGIONAL \
  --default-action Block={} \
  --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=${PROJECT_NAME}-waf \
  --rules '[
    {
      "Name": "AllowOfficeIPs",
      "Priority": 0,
      "Statement": {
        "IPSetReferenceStatement": {
          "ARN": "'$IP_SET_ARN'"
        }
      },
      "Action": {"Allow": {}},
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "AllowOfficeIPs"
      }
    },
    {
      "Name": "RateLimit",
      "Priority": 1,
      "Statement": {
        "RateBasedStatement": {
          "Limit": 2000,
          "AggregateKeyType": "IP"
        }
      },
      "Action": {"Block": {}},
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "RateLimit"
      }
    },
    {
      "Name": "AWSManagedRulesCommon",
      "Priority": 2,
      "OverrideAction": {"None": {}},
      "Statement": {
        "ManagedRuleGroupStatement": {
          "VendorName": "AWS",
          "Name": "AWSManagedRulesCommonRuleSet"
        }
      },
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "AWSManagedRulesCommon"
      }
    },
    {
      "Name": "AWSManagedRulesSQLi",
      "Priority": 3,
      "OverrideAction": {"None": {}},
      "Statement": {
        "ManagedRuleGroupStatement": {
          "VendorName": "AWS",
          "Name": "AWSManagedRulesSQLiRuleSet"
        }
      },
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "AWSManagedRulesSQLi"
      }
    }
  ]' \
  --region $REGION

echo "✅ Web ACL criado com sucesso!"
```

---

## 6. Métricas de Acompanhamento

### 6.1 KPIs de CLI-First

| Métrica | Atual | Meta | Prazo |
|---------|-------|------|-------|
| % de operações com CLI/Terraform | 55% | 90% | Sprint 4 |
| % de operações com testes automatizados | 40% | 80% | Sprint 5 |
| Tempo médio de setup (novo ambiente) | 4-6h manual | <30min automated | Sprint 5 |
| Cobertura de scripts de validação | 60% | 95% | Sprint 4 |

### 6.2 Checklist de Conformidade por Documento

```
Doc 01: [ ] Terraform VPC [ ] Terraform EKS [ ] CLI fallback [ ] Testes
Doc 02: [✓] Helm charts [✓] CLI commands [ ] Testes automatizados
Doc 03: [ ] Terraform RDS [✓] Helm Redis [✓] Helm RabbitMQ [ ] CLI Secrets
Doc 04: [✓] Helm charts [✓] CLI commands [ ] Testes
Doc 05: [ ] CLI WAF [✓] K8s YAML [ ] CLI SG hardening [ ] Testes
Doc 06: [✓] Velero CLI [✓] Scripts DR [ ] Terraform Backup
Doc 07: [ ] CLI Budgets [✓] Lambda code [ ] Terraform
Doc 08: [✓] Scripts validação [✓] Definition of Done
```

---

## 7. Próximos Passos

1. **Imediato:** Atualizar Doc 01 com Terraform e AWS CLI alternativas
2. **Semana 1:** Atualizar Docs 03 e 05 com CLI/Terraform
3. **Semana 2:** Criar scripts unificados de setup
4. **Semana 3:** Adicionar testes automatizados em todos os docs
5. **Contínuo:** Manter documentação atualizada com cada mudança

---

**Autor:** DevOps Team
**Aprovado por:** [Pendente]
**Última revisão:** 2026-01-20

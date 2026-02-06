# conventions.md

> **Responsabilidade**: Usuário + AI (inferido do código + refinamentos)
> **Quando atualizar**: Setup inicial + quando convenções mudam
> **Prioridade de leitura**: 3

---

## Naming Conventions

### Infrastructure as Code (Terraform)

**Resources**:
- Padrão geral: `<tipo>_<contexto>_<nome>`
- Exemplo: `module.eks`, `aws_vpc.main`, `helm_release_gitlab`

**Modules**:
- Pasta: kebab-case
- Exemplo: `modules/kube-prometheus-stack/`, `modules/keycloak/`

**Variables**:
- Estilo: snake_case
- Descritivas e completas
- Sempre com `description` e `type`
- `validation` blocks quando aplicável
- Exemplo: `cluster_name`, `enable_monitoring`, `rds_instance_identifier`

**Outputs**:
- Estilo: snake_case
- Sempre com `description`
- `sensitive = true` para secrets/credentials
- Nomenclatura padronizada para consumo:
  ```hcl
  output "cluster_endpoint" {
    description = "Kubernetes API endpoint"
    value       = module.eks.cluster_endpoint
  }
  ```

**Files**:
- Ordem padrão:
  1. Header comment block (descrição, contexto)
  2. `terraform {}` block (version, providers)
  3. `provider {}` blocks
  4. Data sources
  5. Locals
  6. Resources/Modules
  7. Outputs (arquivo separado `outputs.tf`)
- Separação por comentários:
  ```hcl
  # =============================================================================
  # SECTION NAME
  # =============================================================================

  # -----------------------------------------------------------------------------
  # Subsection
  # -----------------------------------------------------------------------------
  ```

### Kubernetes Resources

**Naming**:
- Padrão: `<app>-<component>-<environment>`
- Exemplo: `gitlab-webservice-production`, `prometheus-server-staging`

**Labels obrigatórias**:
```yaml
labels:
  app.kubernetes.io/name: [app-name]
  app.kubernetes.io/component: [component]
  app.kubernetes.io/instance: [release-name]
  app.kubernetes.io/managed-by: [terraform/helm]
  environment: [staging/production]
```

**Namespaces**:
- Padrão: `<purpose>` ou `<purpose>-<environment>`
- Exemplos: `gitlab`, `monitoring`, `data-services`, `kube-system`

---

## Estrutura de Pastas

```
project-root/
├── docs/                           # Toda documentação
│   ├── context/                    # Docs de contexto
│   │   ├── project_brief.md
│   │   ├── architecture.md
│   │   ├── conventions.md          # Este arquivo
│   │   ├── current_state.md
│   │   ├── decisions.md
│   │   ├── costs.md
│   │   └── risks.md
│   ├── adr/                        # Architecture Decision Records
│   ├── logbook/                    # Diários de bordo (append-only)
│   ├── plan/                       # Markdowns de planejamento
│   ├── agents/                     # Perfis de agentes AI
│   ├── skills/                     # Skills por domínio
│   ├── checklists/                 # Checklists de qualidade
│   ├── templates/                  # Templates de documentos
│   ├── learning/                   # Sistema de aprendizagem
│   │   ├── lessons/
│   │   ├── agents/
│   │   └── feedback/
│   └── tests/                      # Organização de testes
│       ├── unit/
│       ├── integration/
│       ├── e2e/
│       └── performance/
│
├── platform-provisioning/
│   └── aws/
│       └── kubernetes/
│           └── terraform/
│               ├── main.tf
│               ├── variables.tf
│               ├── outputs.tf
│               ├── backend.tf
│               ├── modules/
│               │   ├── {module-name}/
│               │   │   ├── main.tf
│               │   │   ├── variables.tf
│               │   │   └── outputs.tf
│               └── envs/          # Futura estrutura multi-env (ADR-026)
│
├── domains/                        # Visão futura (6 domínios isolados)
│   ├── platform-core/
│   ├── cicd-platform/
│   ├── observability/
│   ├── data-services/
│   ├── security/
│   └── secrets-management/
│
├── k8s/                           # Kubernetes manifests (se não via Helm)
│   ├── apps/
│   └── namespaces/
│
└── scripts/                       # Scripts utilitários
    └── finops/
```

---

## Git

**Branches**:
- Main: `main`
- Feature/Task: descrição curta e clara
- Exemplo: `vault-eso-integration`, `finops-automation`

**Commits**:
- Formato: Conventional Commits
- Padrão: `<type>(<scope>): <description>`
  - Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`, `style`
  - Scope: opcional, indica componente/módulo
- Exemplo:
  ```
  feat(vault): add HA configuration with 3 replicas
  fix(gitlab): correct PostgreSQL connection string
  docs: update ADR-040 with security group justification
  chore(deps): update Terraform AWS provider to 5.40
  ```

**Co-authorship** (AI):
- Incluir em commits realizados com assistência AI:
  ```
  feat(keycloak): integrate with Vault for secrets

  Implemented External Secrets Operator integration.

  Co-Authored-By: Claude <noreply@anthropic.com>
  ```

**Commit size**:
- Commits atômicos (uma mudança lógica por commit)
- Pull requests < 400 linhas (guideline, não bloqueador)

---

## Terraform Style

**Formatter**: `terraform fmt` (SEMPRE rodar antes de commit)

**Validation**: `terraform validate` (SEMPRE rodar)

**Structure**:
```hcl
# =============================================================================
# FILE HEADER - DESCRIPTION
# Additional context if needed
# =============================================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

# -----------------------------------------------------------------------------
# Locals
# -----------------------------------------------------------------------------

locals {
  common_tags = {
    Project     = "Platform-Kubernetes"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# -----------------------------------------------------------------------------
# Resources
# -----------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-vpc"
  })
}
```

**Variables**:
- Sempre com `description`
- Sempre com `type`
- `validation` blocks para input críticos
- Exemplo:
  ```hcl
  variable "cluster_name" {
    description = "EKS cluster name. Must be unique per region."
    type        = string

    validation {
      condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.cluster_name))
      error_message = "Cluster name must be 3-40 chars, lowercase, start with letter."
    }
  }
  ```

**Outputs**:
- Sempre com `description`
- `sensitive = true` para dados sensíveis
- Outputs em arquivo separado `outputs.tf`

**Tags**:
- Usar `default_tags` no provider quando possível
- Tags mínimas obrigatórias:
  ```hcl
  Project     = "Platform-Kubernetes"
  Environment = "staging|production"
  ManagedBy   = "Terraform"
  Owner       = "DevOps-Team"
  CostCenter  = "Platform-Infrastructure"
  ```

**Backend**:
- SEMPRE state remoto (S3 + DynamoDB)
- NUNCA local state
- Por ambiente (futura estrutura multi-env):
  ```hcl
  terraform {
    backend "s3" {
      bucket  = "terraform-state-marco0-{account-id}"
      key     = "{environment}/terraform.tfstate"
      region  = "us-east-1"
      encrypt = true
    }
  }
  ```

---

## Comentários e Documentação

### Quando comentar

✅ **Sempre**:
- Decisões de design (por que, não o que)
- Trade-offs temporários com TODO e contexto
- Workarounds para bugs de providers
- Valores "mágicos" não óbvios
- Referências a ADRs

❌ **Nunca**:
- O que o código faz (código HCL é auto-explicativo)
- Comentários óbvios

### Exemplos

**BOM**:
```hcl
# PostgreSQL in public subnet to allow unseal from Lambda (temporary)
# TODO(ADR-046): Move to private subnet after VPC endpoints implementation
# Related: docs/logbook/2026-02-06-vault-recovery-vpc-endpoints.md
resource "aws_db_subnet_group" "postgresql" {
  name       = "${var.cluster_name}-postgresql"
  subnet_ids = var.public_subnet_ids  # Temporary, see TODO above
}
```

**RUIM**:
```hcl
# Create security group
resource "aws_security_group" "postgresql" {  # ❌ Óbvio pelo código
  name = "postgresql-sg"
}
```

### Header Blocks

Todo arquivo `.tf` principal deve ter header:
```hcl
# =============================================================================
# MODULE: {Nome}
# Description: {O que faz}
#
# Dependencies:
# - {Dependência 1}
# - {Dependência 2}
#
# Related ADRs:
# - ADR-XXX: {Título}
# =============================================================================
```

### Inline Documentation

Para módulos, incluir `README.md`:
```markdown
# Module: {nome}

## Description
{O que faz}

## Usage
\```hcl
module "example" {
  source = "./modules/{nome}"

  param1 = "value1"
  param2 = "value2"
}
\```

## Inputs
| Name   | Description | Type   | Default | Required |
| ------ | ----------- | ------ | ------- | -------- |
| param1 | ...         | string | n/a     | yes      |

## Outputs
| Name    | Description |
| ------- | ----------- |
| output1 | ...         |
```

---

## Security

### Secrets Management

- **NUNCA hardcoded** no código
- **SEMPRE via**: Vault + External Secrets Operator
- Temporário: AWS Secrets Manager (migrar para Vault)
- Formato de nome: snake_case (ex: `gitlab_root_password`)

### Sensitive Data

**No Terraform**:
```hcl
variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true  # ← OBRIGATÓRIO para secrets
}

output "db_endpoint" {
  value     = aws_db_instance.main.endpoint
  sensitive = false  # Não é secret
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true  # ← OBRIGATÓRIO
}
```

**Em logs**:
- NUNCA logar: senhas, tokens, chaves API
- Logar: IDs, endpoints, nomes de recursos

---

## Terraform Operação

### Workflow Obrigatório

```bash
# 1. Inicializar (apenas primeira vez ou mudança de backend)
terraform init

# 2. Formatar código
terraform fmt -recursive

# 3. Validar
terraform validate

# 4. Planejar (SEMPRE antes de apply)
terraform plan -out=tfplan

# 5. REVISAR PLAN (linha por linha se infra crítica)
# Apresentar ao usuário se mudanças significativas

# 6. Aplicar (SOMENTE após aprovação)
terraform apply tfplan

# 7. Verificar idempotência
terraform plan  # ← DEVE retornar "No changes"
```

### Regras Invioláveis (DevOps/Terraform)

Consultar: `docs/skills/devops.md` (seção Regras Invioláveis)

- NUNCA `terraform apply` sem `plan` revisado
- Todo ajuste codificado no IaC (nada manual via console)
- Idempotência: `plan` pós-apply DEVE retornar "No changes"
- NUNCA comandos longos (> 30s) sem background + monitoramento

---

## Testing

### Terraform Tests

**Ferramenta**: Terratest (Go)

**Localização**: `docs/tests/integration/`

**Naming**: `terraform_<module>_test.go`

**Estrutura**:
```go
func TestTerraformVaultModule(t *testing.T) {
    t.Parallel()

    terraformOptions := &terraform.Options{
        TerraformDir: "../../modules/vault",
    }

    defer terraform.Destroy(t, terraformOptions)

    terraform.InitAndApply(t, terraformOptions)

    // Validations
    vaultAddr := terraform.Output(t, terraformOptions, "vault_address")
    assert.NotEmpty(t, vaultAddr)
    assert.Contains(t, vaultAddr, "https://")
}
```

---

## Review

### Pull Requests

**Descrição obrigatória**:
```markdown
## Summary
[O que muda]

## Terraform Plan
\```
[Paste do terraform plan output]
\```

## Test Plan
- [ ] `terraform fmt` executado
- [ ] `terraform validate` passou
- [ ] `terraform plan` revisado
- [ ] Testado em {ambiente}
- [ ] Idempotência verificada (2º plan = No changes)

## Related
- ADR-XXX
- Issue #YYY
```

**Aprovação**:
- Mínimo: 1 aprovação
- Infraestrutura crítica: 2 aprovações (architect + security)

---

## ADRs e Decisões

**Quando criar ADR**:
- Decisões arquiteturais significativas
- Escolha entre múltiplas opções válidas
- Trade-offs importantes
- Mudanças que impactam múltiplos componentes

**Formato**: Consultar ADRs existentes em `docs/adr/`

**Registro em decisions.md**: Para decisões menores, registrar em `docs/context/decisions.md`

---

## FinOps

**Tagging para Cost Allocation**:
```hcl
tags = {
  Project     = "Platform-Kubernetes"
  Environment = "staging"  # ou "production"
  CostCenter  = "Platform-Infrastructure"
  Owner       = "DevOps-Team"
  AutoShutdown = "true"  # Para recursos com automação FinOps
}
```

**Automação**:
- Ambientes non-prod: auto-shutdown noturno (ADR-024)
- Cost monitoring via Lambda + EventBridge

---

## Projeto Específico

### Cloud Provider Strategy

- **Atual (MVP)**: AWS-only, mas design cloud-agnostic
- **Futuro**: Multi-cloud via Kubernetes operators
- **Guideline**: Preferir Kubernetes resources sobre AWS resources quando viável

### Ambientes

- **Staging**: `k8s-platform-prod` (nome histórico, é staging de fato)
- **Production**: futuro, naming será `k8s-platform-production`

### Banco de Dados

- **Atual**: AWS RDS PostgreSQL (managed)
- **Futuro**: CloudNativePG Operator (cloud-agnostic)
- **Decisão**: ADR-XXX (ver decisions.md)

---

_Última atualização: 2026-02-06_
_Inferido do código existente + refinamentos manuais_

# Comandos Executados - Marco 0

Este documento detalha todos os comandos AWS CLI executados durante o Marco 0, com explicações de cada um.

---

## 1. Bootstrap do Backend Terraform

### 1.1 Criar Bucket S3

```bash
aws s3api create-bucket \
  --bucket "terraform-state-marco0-891377105802" \
  --region us-east-1
```

**O que faz:**
- Cria um bucket S3 para armazenar o state file do Terraform
- Nome do bucket: `terraform-state-marco0-891377105802`
- Região: `us-east-1`
- **IMPORTANTE**: `us-east-1` NÃO aceita o parâmetro `--create-bucket-configuration LocationConstraint`
  - Outras regiões requerem: `--create-bucket-configuration LocationConstraint=$REGION`

**Por que este nome de bucket?**
- Padrão: `terraform-state-<ambiente>-<account-id>`
- Buckets S3 devem ter nomes globalmente únicos
- Account ID garante unicidade

**Output esperado:**
```json
{
    "Location": "/terraform-state-marco0-891377105802",
    "BucketArn": "arn:aws:s3:::terraform-state-marco0-891377105802"
}
```

---

### 1.2 Habilitar Versionamento do Bucket

```bash
aws s3api put-bucket-versioning \
  --bucket "terraform-state-marco0-891377105802" \
  --versioning-configuration Status=Enabled
```

**O que faz:**
- Ativa versionamento de objetos no bucket S3
- Cada mudança no state file cria uma nova versão
- Permite rollback para versões anteriores do state

**Por que é importante?**
- **Recuperação de desastres**: Se o state for corrompido, você pode restaurar versão anterior
- **Auditoria**: Histórico completo de mudanças na infraestrutura
- **Segurança**: Proteção contra exclusão acidental

**Como verificar:**
```bash
aws s3api get-bucket-versioning --bucket "terraform-state-marco0-891377105802"
# Output: {"Status": "Enabled"}
```

---

### 1.3 Configurar Criptografia do Bucket

```bash
aws s3api put-bucket-encryption \
  --bucket "terraform-state-marco0-891377105802" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

**O que faz:**
- Habilita criptografia server-side (SSE-S3) em todos os objetos do bucket
- Algoritmo: AES-256 (Advanced Encryption Standard com chave de 256 bits)
- Criptografia automática: Todos os objetos são criptografados ao serem salvos

**Por que é importante?**
- **Compliance**: Muitas regulamentações (GDPR, HIPAA, PCI-DSS) exigem dados em repouso criptografados
- **Segurança**: State files podem conter informações sensíveis (IPs, ARNs, configurações)
- **Zero custo adicional**: SSE-S3 é gratuito

**Alternativas:**
- `aws:kms`: Usar AWS KMS (chaves gerenciadas, auditoria via CloudTrail, custo adicional)
- `aws:kms:dsse`: Double encryption (KMS + AES256)

---

### 1.4 Bloquear Acesso Público

```bash
aws s3api put-public-access-block \
  --bucket "terraform-state-marco0-891377105802" \
  --public-access-block-configuration '{
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
  }'
```

**O que faz:**
- **BlockPublicAcls**: Bloqueia criação de ACLs públicas
- **IgnorePublicAcls**: Ignora ACLs públicas existentes
- **BlockPublicPolicy**: Bloqueia bucket policies que permitam acesso público
- **RestrictPublicBuckets**: Restringe acesso a buckets com políticas públicas

**Por que é CRÍTICO?**
- State files contêm informações sensíveis da infraestrutura
- Vazamento do state pode expor toda a arquitetura AWS
- Ataques comuns: bucket misconfiguration scanning

**Exemplo do que é bloqueado:**
```json
// Esta policy seria BLOQUEADA:
{
  "Effect": "Allow",
  "Principal": "*",
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::terraform-state-marco0-891377105802/*"
}
```

---

### 1.5 Criar Tabela DynamoDB para Locking

```bash
aws dynamodb create-table \
  --table-name "terraform-state-lock" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

**O que faz:**
- Cria tabela DynamoDB para controle de lock distribuído
- **Partition Key**: `LockID` (String)
- **Billing**: PAY_PER_REQUEST (on-demand, sem custo fixo)

**Estrutura da tabela:**
```
terraform-state-lock
├─ LockID (String) [HASH KEY]
│  Exemplo: "terraform-state-marco0-891377105802/marco0/terraform.tfstate-md5"
│
└─ Attributes (dinâmicos):
   ├─ Info (String): Informações sobre quem está com lock
   ├─ Who (String): Usuário + hostname
   ├─ Version (String): Versão do Terraform
   ├─ Created (String): Timestamp
   └─ Operation (String): plan, apply, etc.
```

**Como funciona o lock:**
```bash
# Terraform tenta criar item na tabela
terraform plan
  → DynamoDB PutItem (condition: item não existe)

# Se outro processo já tem lock:
  → ConditionalCheckFailedException
  → Terraform aguarda ou falha

# Quando termina:
  → DynamoDB DeleteItem
  → Lock liberado
```

**Por que PAY_PER_REQUEST?**
- Locks são operações raras (apenas durante plan/apply)
- Custo: ~$1.25 por milhão de writes
- Terraform típico: < 100 operações/mês = ~$0.000125/mês
- Alternativa (PROVISIONED): Custo fixo mínimo ~$0.50/mês mesmo sem uso

---

### 1.6 Aguardar Tabela Ficar Ativa

```bash
aws dynamodb wait table-exists \
  --table-name "terraform-state-lock" \
  --region us-east-1
```

**O que faz:**
- Aguarda status da tabela mudar de `CREATING` → `ACTIVE`
- Timeout padrão: 500 segundos (8 minutos)
- Pooling: Verifica status a cada 20 segundos

**Por que esperar?**
- Terraform init falharia se tentasse usar tabela ainda não ativa
- Evita race conditions em scripts de automação

**Estados possíveis da tabela:**
- `CREATING`: Sendo criada
- `ACTIVE`: Pronta para uso ✅
- `UPDATING`: Sendo modificada
- `DELETING`: Sendo deletada
- `ARCHIVED`: Arquivada

---

## 2. Configuração do Backend Terraform

### 2.1 backend.tf

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state-marco0-891377105802"
    key            = "marco0/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

**Parâmetros explicados:**

- **bucket**: Nome do bucket S3 criado anteriormente
- **key**: Caminho do state file dentro do bucket
  - Padrão: `<ambiente>/terraform.tfstate`
  - Permite múltiplos ambientes no mesmo bucket:
    ```
    s3://terraform-state-marco0-891377105802/
    ├── marco0/terraform.tfstate
    ├── staging/terraform.tfstate
    └── production/terraform.tfstate
    ```

- **region**: Região do bucket (us-east-1)

- **encrypt**: `true` força criptografia server-side
  - Mesmo que bucket não tenha default encryption configurada
  - Header adicionado: `x-amz-server-side-encryption: AES256`

- **dynamodb_table**: Nome da tabela para locking
  - Terraform adiciona sufixo `-md5` ao LockID automaticamente
  - Exemplo: `terraform-state-marco0-891377105802/marco0/terraform.tfstate-md5`

---

### 2.2 terraform.tfvars

```hcl
tf_state_bucket = "terraform-state-marco0-891377105802"
aws_region      = "us-east-1"
```

**Por que não versionado (.gitignore)?**
- Pode conter valores sensíveis em projetos futuros
- Cada desenvolvedor/ambiente pode ter valores diferentes
- Best practice: usar `.tfvars.example` como template

---

## 3. Inicialização do Terraform

### 3.1 Carregar Credenciais AWS

```bash
# Credenciais armazenadas em: ~/.aws/login/cache/*.json
export AWS_ACCESS_KEY_ID="ASIA47CRXHOFGOXTZCL6"
export AWS_SECRET_ACCESS_KEY="JYxALFWtpkd50Gh/d0mqY0omxTK9F+f0Di07PlgV"
export AWS_SESSION_TOKEN="IQoJb3JpZ2luX2VjEDUa..."
export AWS_DEFAULT_REGION="us-east-1"
```

**Tipos de credenciais AWS:**

1. **IAM User (long-term)**:
   ```bash
   AWS_ACCESS_KEY_ID="AKIA..."      # Começa com AKIA
   AWS_SECRET_ACCESS_KEY="..."      # Chave permanente
   # Não expira, mas menos seguro
   ```

2. **STS Temporary (short-term)** ← Usado no Marco 0:
   ```bash
   AWS_ACCESS_KEY_ID="ASIA..."      # Começa com ASIA
   AWS_SECRET_ACCESS_KEY="..."      # Chave temporária
   AWS_SESSION_TOKEN="IQoJ..."      # Token de sessão (obrigatório)
   # Expira em 1-12 horas, mais seguro
   ```

3. **SSO (AWS Identity Center)**:
   ```bash
   aws sso login --profile my-profile
   # Credenciais armazenadas em ~/.aws/sso/cache/
   ```

**Como o Terraform usa as credenciais:**
1. Variáveis de ambiente (`AWS_*`)
2. Arquivo `~/.aws/credentials`
3. EC2 Instance Profile (se rodando em EC2)
4. ECS Task Role (se rodando em ECS)

---

### 3.2 Terraform Init

```bash
terraform init
```

**O que acontece internamente:**

1. **Backend Initialization**:
   ```
   [Backend] Conectando ao S3...
   [Backend] Bucket: terraform-state-marco0-891377105802
   [Backend] Verificando se state existe: marco0/terraform.tfstate
   [Backend] State não encontrado, criando novo state vazio
   [Backend] Testando lock no DynamoDB...
   [Backend] Lock OK: terraform-state-lock
   ```

2. **Provider Download**:
   ```
   [Providers] Lendo .terraform.lock.hcl
   [Providers] hashicorp/aws v5.100.0 já instalado
   [Providers] Pulando download
   ```

3. **Module Initialization**:
   ```
   [Modules] Carregando módulos locais:
   [Modules]   - vpc (../../modules/vpc)
   [Modules]   - subnets (../../modules/subnets)
   [Modules]   - nat_gateways (../../modules/nat-gateways)
   [Modules]   - internet_gateway (../../modules/internet-gateway)
   [Modules]   - route_tables (../../modules/route-tables)
   ```

**Arquivos criados:**
```
.terraform/
├── providers/
│   └── registry.terraform.io/
│       └── hashicorp/
│           └── aws/
│               └── 5.100.0/
│                   └── linux_amd64/
│                       └── terraform-provider-aws_v5.100.0
└── terraform.tfstate (state local temporário)

.terraform.lock.hcl (lock de versões dos providers)
```

---

### 3.3 Verificar Identidade AWS

```bash
aws sts get-caller-identity
```

**Output:**
```json
{
    "UserId": "891377105802",
    "Account": "891377105802",
    "Arn": "arn:aws:iam::891377105802:root"
}
```

**O que cada campo significa:**
- **UserId**: ID único do usuário/role IAM
  - Root: Account ID
  - IAM User: `AIDA...`
  - Assumed Role: `AROA...:session-name`

- **Account**: ID da conta AWS (12 dígitos)

- **Arn**: Amazon Resource Name completo
  - `arn:aws:iam::891377105802:root` = Root user (máximo privilégio)
  - `arn:aws:sts::891377105802:assumed-role/Admin/gilvan` = Role assumida

**Por que verificar antes de init/plan/apply?**
- Confirma que credenciais estão válidas
- Confirma a conta correta (evita aplicar em prod por engano)
- Confirma permissões necessárias

---

## 4. Terraform Plan (Comportamento Observado)

```bash
terraform plan
```

**Output observado:**
```
Terraform will perform the following actions:

  # module.vpc.aws_vpc.vpc will be created
  + resource "aws_vpc" "vpc" {
      + cidr_block = "10.0.0.0/16"
      + ...
    }

  # module.subnets.aws_subnet.subnets["public-1a"] will be created
  + resource "aws_subnet" "subnets" {
      + cidr_block = "10.0.0.0/20"
      + ...
    }

Plan: 15 to add, 0 to change, 0 to destroy.
```

**Por que mostra "will be created" se a infraestrutura já existe?**

O Terraform compara:
```
┌─────────────────┐      ┌─────────────────┐
│  Desired State  │  VS  │  Current State  │
│   (código HCL)  │      │   (state file)  │
└─────────────────┘      └─────────────────┘
         │                        │
         │                        │
         ▼                        ▼
    VPC 10.0.0.0/16          (vazio)
    4 subnets                (vazio)
    2 NAT gateways           (vazio)
```

**State file está vazio porque:**
1. Nunca executamos `terraform import`
2. Infraestrutura foi criada manualmente (AWS Console/CLI)
3. Terraform não tem conhecimento dos recursos existentes

**Para obter "No changes" seria necessário:**

```bash
# Importar VPC
terraform import module.vpc.aws_vpc.vpc vpc-0b1396a59c417c1f0

# Importar cada subnet
terraform import 'module.subnets.aws_subnet.subnets["public-1a"]' subnet-0a1b2c3d4e5f

# Importar NAT gateways
terraform import 'module.nat_gateways.aws_nat_gateway.nat["0"]' nat-0a1b2c3d4e5f

# ... repetir para TODOS os recursos
```

**Decisão tomada:** NÃO importar
- Código serve como **blueprint** para novos ambientes
- Infraestrutura existente continua gerenciada manualmente
- Futuros ambientes serão 100% gerenciados via Terraform

---

## 5. Lock e Unlock do State

### 5.1 Lock Automático

Quando `terraform plan` é executado:
```bash
# Terraform automaticamente:
1. Cria lock no DynamoDB
   PutItem:
     LockID: "terraform-state-marco0-891377105802/marco0/terraform.tfstate-md5"
     Info: "..."
     Who: "gilvangalindo@FCC-KM-00075"
     Version: "1.14.3"
     Created: "2026-01-23 20:54:30"
     Operation: "OperationTypePlan"

2. Executa plan
3. Remove lock do DynamoDB (DeleteItem)
```

### 5.2 Lock Manual (Force Unlock)

Se o processo foi interrompido (Ctrl+C, crash, network error):
```bash
terraform force-unlock 35b7f29e-de45-262f-5dbe-23c609018a55
```

**PERIGO:**
- Só use se tiver CERTEZA que nenhum processo está usando o state
- Unlock forçado com outro processo rodando = **STATE CORRUPTION** 💥

---

## 6. Resumo dos Recursos AWS Criados

```bash
# Verificar bucket S3
aws s3api head-bucket --bucket terraform-state-marco0-891377105802
aws s3api get-bucket-versioning --bucket terraform-state-marco0-891377105802
aws s3api get-bucket-encryption --bucket terraform-state-marco0-891377105802

# Verificar tabela DynamoDB
aws dynamodb describe-table --table-name terraform-state-lock --region us-east-1

# Verificar state file
aws s3 ls s3://terraform-state-marco0-891377105802/marco0/

# Verificar versões do state
aws s3api list-object-versions \
  --bucket terraform-state-marco0-891377105802 \
  --prefix marco0/terraform.tfstate
```

---

## 7. Custos Estimados

| Recurso | Custo Mensal | Detalhes |
|---------|--------------|----------|
| S3 Bucket | ~$0.023/GB | State file típico: <1MB = $0.00002/mês |
| S3 Requests | $0.005/1000 PUT | ~10 applies/mês = $0.00005/mês |
| S3 Versioning | $0.023/GB | Histórico de 100 versions ~1MB = $0.00002/mês |
| DynamoDB | $1.25/M writes | ~10 locks/mês = $0.0000125/mês |
| **TOTAL** | **< $0.01/mês** | Praticamente gratuito! |

---

## 8. Troubleshooting Comum

### 8.1 Erro: No valid credential sources found
```bash
# Solução 1: Export manual
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."  # Se usar STS

# Solução 2: AWS CLI profile
export AWS_PROFILE=my-profile

# Solução 3: SSO login
aws sso login --profile my-profile
```

### 8.2 Erro: AccessDenied ao criar bucket
```bash
# Permissões necessárias:
s3:CreateBucket
s3:PutBucketVersioning
s3:PutBucketEncryption
s3:PutBucketPublicAccessBlock
dynamodb:CreateTable
dynamodb:DescribeTable
```

### 8.3 Erro: State lock timeout
```bash
# Ver quem está com lock
aws dynamodb get-item \
  --table-name terraform-state-lock \
  --key '{"LockID":{"S":"terraform-state-marco0-891377105802/marco0/terraform.tfstate-md5"}}'

# Force unlock (CUIDADO!)
terraform force-unlock <LOCK_ID>
```

---

## 9. Scripts Criados

### 9.1 create-tf-backend.sh
**Localização:** `platform-provisioning/aws/kubernetes/terraform-backend/`

**Melhorias implementadas:**
- Fix para us-east-1 (não usa LocationConstraint)
- Verificação de recursos existentes
- Aguarda tabela DynamoDB ficar ACTIVE
- Mensagens claras de progresso

**Uso:**
```bash
cd platform-provisioning/aws/kubernetes/terraform-backend/
./create-tf-backend.sh \
  --bucket terraform-state-marco0-891377105802 \
  --region us-east-1 \
  --yes
```

### 9.2 init-terraform.sh
**Localização:** `platform-provisioning/aws/kubernetes/terraform/envs/marco0/`

**Funcionalidades:**
- Carrega credenciais automaticamente do cache AWS CLI
- Verifica identidade antes de executar
- Executa terraform init
- Mostra próximos passos

**Uso:**
```bash
cd platform-provisioning/aws/kubernetes/terraform/envs/marco0/
./init-terraform.sh
```

### 9.3 plan-terraform.sh
**Localização:** `platform-provisioning/aws/kubernetes/terraform/envs/marco0/`

**Funcionalidades:**
- Carrega credenciais automaticamente
- Verifica identidade
- Executa terraform plan
- Suporta argumentos adicionais: `./plan-terraform.sh -out=tfplan`

**Uso:**
```bash
cd platform-provisioning/aws/kubernetes/terraform/envs/marco0/
./plan-terraform.sh
```

---

**Autor:** DevOps Team
**Data:** 2026-01-24
**Versão:** 1.0

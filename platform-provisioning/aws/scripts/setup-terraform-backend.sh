#!/bin/bash
set -euo pipefail

# ============================================================================
# Script: Setup Terraform Backend (S3 + DynamoDB)
# Projeto: k8s-platform
# Descrição: Cria bucket S3 e tabela DynamoDB para Terraform state management
# Autor: DevOps Team
# Data: 2026-01-23
# ============================================================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funções auxiliares
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Configurações
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
BUCKET_NAME="k8s-platform-terraform-state-${ACCOUNT_ID}"
DYNAMODB_TABLE="k8s-platform-terraform-locks"

echo ""
echo "============================================================================"
echo "🚀 Configurando Terraform Backend para k8s-platform"
echo "============================================================================"
echo ""
log_info "Account ID: ${ACCOUNT_ID}"
log_info "Região: ${REGION}"
log_info "Bucket S3: ${BUCKET_NAME}"
log_info "Tabela DynamoDB: ${DYNAMODB_TABLE}"
echo ""

# Verificar se AWS CLI está configurado
if ! aws sts get-caller-identity &>/dev/null; then
    log_error "AWS CLI não está configurado. Execute 'aws configure' primeiro."
    exit 1
fi

log_success "AWS CLI autenticado"
echo ""

# ============================================================================
# 1. CRIAR BUCKET S3
# ============================================================================
echo "============================================================================"
echo "📦 ETAPA 1/6: Criando bucket S3 para Terraform state"
echo "============================================================================"

if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
    log_warning "Bucket já existe: ${BUCKET_NAME}"
else
    log_info "Criando bucket ${BUCKET_NAME}..."
    aws s3api create-bucket \
        --bucket "${BUCKET_NAME}" \
        --region "${REGION}" \
        --acl private
    log_success "Bucket criado com sucesso"
fi
echo ""

# ============================================================================
# 2. HABILITAR VERSIONAMENTO
# ============================================================================
echo "============================================================================"
echo "🔄 ETAPA 2/6: Habilitando versionamento (rollback de states)"
echo "============================================================================"

log_info "Configurando versionamento..."
aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled

# Verificar
VERSION_STATUS=$(aws s3api get-bucket-versioning --bucket "${BUCKET_NAME}" --query 'Status' --output text)
if [[ "${VERSION_STATUS}" == "Enabled" ]]; then
    log_success "Versionamento habilitado com sucesso"
else
    log_error "Falha ao habilitar versionamento"
    exit 1
fi
echo ""

# ============================================================================
# 3. HABILITAR CRIPTOGRAFIA
# ============================================================================
echo "============================================================================"
echo "🔒 ETAPA 3/6: Habilitando criptografia em repouso (SSE-S3)"
echo "============================================================================"

log_info "Configurando criptografia padrão..."
aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        },
        "BucketKeyEnabled": true
      }]
    }'

log_success "Criptografia SSE-S3 habilitada com sucesso"
echo ""

# ============================================================================
# 4. BLOQUEAR ACESSO PÚBLICO
# ============================================================================
echo "============================================================================"
echo "🚫 ETAPA 4/6: Bloqueando todo acesso público (segurança)"
echo "============================================================================"

log_info "Aplicando bloqueio de acesso público..."
aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

log_success "Acesso público bloqueado com sucesso"
echo ""

# ============================================================================
# 5. ADICIONAR TAGS
# ============================================================================
echo "============================================================================"
echo "🏷️  ETAPA 5/6: Adicionando tags de rastreabilidade"
echo "============================================================================"

log_info "Adicionando tags ao bucket..."
aws s3api put-bucket-tagging \
    --bucket "${BUCKET_NAME}" \
    --tagging 'TagSet=[
        {Key=Project,Value=k8s-platform},
        {Key=Environment,Value=shared},
        {Key=Purpose,Value=terraform-state},
        {Key=ManagedBy,Value=terraform},
        {Key=CreatedBy,Value=setup-terraform-backend-script},
        {Key=CreatedAt,Value='$(date -u +%Y-%m-%dT%H:%M:%SZ)'}
    ]'

log_success "Tags adicionadas com sucesso"
echo ""

# ============================================================================
# 6. CRIAR TABELA DYNAMODB
# ============================================================================
echo "============================================================================"
echo "🗄️  ETAPA 6/6: Criando tabela DynamoDB para state locking"
echo "============================================================================"

if aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" --region "${REGION}" &>/dev/null; then
    log_warning "Tabela já existe: ${DYNAMODB_TABLE}"
else
    log_info "Criando tabela ${DYNAMODB_TABLE}..."
    aws dynamodb create-table \
        --table-name "${DYNAMODB_TABLE}" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "${REGION}" \
        --tags Key=Project,Value=k8s-platform \
               Key=Environment,Value=shared \
               Key=Purpose,Value=terraform-locks \
               Key=ManagedBy,Value=terraform \
               Key=CreatedBy,Value=setup-terraform-backend-script \
               Key=CreatedAt,Value="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    log_info "Aguardando tabela ficar ativa..."
    aws dynamodb wait table-exists --table-name "${DYNAMODB_TABLE}" --region "${REGION}"
    log_success "Tabela criada com sucesso"
fi
echo ""

# ============================================================================
# VALIDAÇÃO FINAL
# ============================================================================
echo "============================================================================"
echo "🔍 VALIDAÇÃO FINAL"
echo "============================================================================"
echo ""

# Validar bucket
log_info "Validando bucket S3..."
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
    log_success "Bucket S3: OK"
else
    log_error "Bucket S3: ERRO"
    exit 1
fi

# Validar versionamento
VERSION_STATUS=$(aws s3api get-bucket-versioning --bucket "${BUCKET_NAME}" --query 'Status' --output text)
if [[ "${VERSION_STATUS}" == "Enabled" ]]; then
    log_success "Versionamento: OK (Enabled)"
else
    log_error "Versionamento: ERRO (${VERSION_STATUS})"
fi

# Validar criptografia
ENCRYPTION=$(aws s3api get-bucket-encryption --bucket "${BUCKET_NAME}" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text)
if [[ "${ENCRYPTION}" == "AES256" ]]; then
    log_success "Criptografia: OK (SSE-S3/AES256)"
else
    log_error "Criptografia: ERRO (${ENCRYPTION})"
fi

# Validar bloqueio público
PUBLIC_BLOCK=$(aws s3api get-public-access-block --bucket "${BUCKET_NAME}" --query 'PublicAccessBlockConfiguration.BlockPublicAcls' --output text)
if [[ "${PUBLIC_BLOCK}" == "True" ]]; then
    log_success "Bloqueio público: OK (All blocked)"
else
    log_error "Bloqueio público: ERRO"
fi

# Validar DynamoDB
TABLE_STATUS=$(aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" --region "${REGION}" --query 'Table.TableStatus' --output text)
if [[ "${TABLE_STATUS}" == "ACTIVE" ]]; then
    log_success "Tabela DynamoDB: OK (ACTIVE)"
else
    log_error "Tabela DynamoDB: ERRO (${TABLE_STATUS})"
fi

echo ""
echo "============================================================================"
echo "✅ BACKEND TERRAFORM CONFIGURADO COM SUCESSO!"
echo "============================================================================"
echo ""
echo "📝 PRÓXIMOS PASSOS:"
echo ""
echo "1. Criar arquivo backend-config.hcl no diretório do ambiente:"
echo ""
echo "   cat > envs/marco0/backend-config.hcl <<'EOF'"
echo "   bucket         = \"${BUCKET_NAME}\""
echo "   key            = \"marco0/terraform.tfstate\""
echo "   region         = \"${REGION}\""
echo "   dynamodb_table = \"${DYNAMODB_TABLE}\""
echo "   encrypt        = true"
echo "   EOF"
echo ""
echo "2. Inicializar Terraform com o backend:"
echo ""
echo "   cd envs/marco0"
echo "   terraform init -backend-config=backend-config.hcl"
echo ""
echo "3. Validar configuração:"
echo ""
echo "   terraform workspace list"
echo "   terraform state list"
echo ""
echo "============================================================================"
echo "📊 CUSTOS ESTIMADOS:"
echo "   - S3 Bucket: ~\$0.02/mês (state files < 1 MB)"
echo "   - S3 Versioning: ~\$0.05/mês (~10 versões antigas)"
echo "   - DynamoDB: ~\$0.00/mês (<100 requisições/mês)"
echo "   - Total: ~\$0.07/mês (desprezível)"
echo "============================================================================"
echo ""

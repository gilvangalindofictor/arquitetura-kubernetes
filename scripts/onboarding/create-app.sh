#!/bin/bash
# Script de Onboarding de Aplicações - Corporate Domains
# Referência: ADR-048, ADR-060, ADR-061, ADR-062
# Uso: ./create-app.sh <produto> <domain> <env>

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Diretório base dos scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Função de log
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Função de ajuda
show_help() {
    cat << EOF
${BLUE}Script de Onboarding de Aplicações - Corporate Domains${NC}

${GREEN}Uso:${NC}
    ./create-app.sh <produto> <domain> <env> [options]

${GREEN}Argumentos:${NC}
    produto     Nome do produto (kebab-case: rpa-exemplo, hatch-api)
    domain      Domínio corporativo (platform|integration|data|operations|shared-services)
    env         Ambiente (dev|staging|prod)

${GREEN}Opções:${NC}
    --needs-postgres    Provisiona PostgreSQL database
    --needs-redis       Provisiona Redis instance
    --needs-rabbitmq    Provisiona RabbitMQ resources
    --skip-gitlab       Pula criação de repositórios GitLab
    --skip-argocd       Pula criação de ArgoCD Application
    --dry-run           Simula execução sem criar recursos

${GREEN}Exemplos:${NC}
    # RPA Python com PostgreSQL + Redis
    ./create-app.sh rpa-exemplo data staging --needs-postgres --needs-redis

    # API Gateway sem dependências de dados
    ./create-app.sh api-gateway integration staging

    # Aplicação completa com todas dependências
    ./create-app.sh hatch-api data prod --needs-postgres --needs-redis --needs-rabbitmq

${GREEN}Referências:${NC}
    - ADR-048: Naming Conventions Determinísticas
    - ADR-060: PostgreSQL Governance Standards
    - ADR-061: Redis Governance Standards
    - ADR-062: RabbitMQ Governance Standards

EOF
}

# Validação de argumentos
if [ $# -lt 3 ]; then
    show_help
    exit 1
fi

PRODUTO="$1"
DOMAIN="$2"
ENV="$3"
shift 3

# Opções
NEEDS_POSTGRES=false
NEEDS_REDIS=false
NEEDS_RABBITMQ=false
SKIP_GITLAB=false
SKIP_ARGOCD=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --needs-postgres)
            NEEDS_POSTGRES=true
            shift
            ;;
        --needs-redis)
            NEEDS_REDIS=true
            shift
            ;;
        --needs-rabbitmq)
            NEEDS_RABBITMQ=true
            shift
            ;;
        --skip-gitlab)
            SKIP_GITLAB=true
            shift
            ;;
        --skip-argocd)
            SKIP_ARGOCD=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Opção desconhecida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validações
log_info "Validando parâmetros..."

# Valida naming convention do produto (ADR-048)
if ! [[ "$PRODUTO" =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
    log_error "Nome do produto inválido: '$PRODUTO'"
    log_error "Formato esperado: ^[a-z][a-z0-9-]{0,62}$ (kebab-case)"
    exit 1
fi

# Valida domínio corporativo (ADR-047)
case "$DOMAIN" in
    platform|integration|data|operations|shared-services)
        log_success "Domínio válido: $DOMAIN"
        ;;
    *)
        log_error "Domínio inválido: '$DOMAIN'"
        log_error "Valores permitidos: platform, integration, data, operations, shared-services"
        exit 1
        ;;
esac

# Valida ambiente
case "$ENV" in
    dev|staging|prod)
        log_success "Ambiente válido: $ENV"
        ;;
    *)
        log_error "Ambiente inválido: '$ENV'"
        log_error "Valores permitidos: dev, staging, prod"
        exit 1
        ;;
esac

# Construir nome do namespace (ADR-048)
NAMESPACE="${ENV}-${DOMAIN}-${PRODUTO}"
log_info "Namespace: $NAMESPACE"

# Verificar dependências de CLI
log_info "Verificando dependências..."
MISSING_DEPS=()

if ! command -v kubectl &> /dev/null; then
    MISSING_DEPS+=("kubectl")
fi

if ! command -v helm &> /dev/null; then
    MISSING_DEPS+=("helm")
fi

if [ "$SKIP_GITLAB" = false ] && ! command -v gitlab &> /dev/null; then
    MISSING_DEPS+=("gitlab CLI")
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    log_error "Dependências faltando: ${MISSING_DEPS[*]}"
    exit 1
fi

log_success "Todas dependências disponíveis"

# Verificar se namespace já existe
if kubectl get namespace "$NAMESPACE" &> /dev/null; then
    log_warning "Namespace $NAMESPACE já existe"
    read -p "Continuar? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operação cancelada"
        exit 0
    fi
fi

# Dry run mode
if [ "$DRY_RUN" = true ]; then
    log_warning "Modo DRY RUN - nenhum recurso será criado"
fi

# ====================
# Criar Namespace
# ====================
log_info "Criando namespace $NAMESPACE..."

if [ "$DRY_RUN" = false ]; then
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

    # Adicionar labels obrigatórias (ADR-048)
    kubectl label namespace "$NAMESPACE" \
        domain="$DOMAIN" \
        environment="$ENV" \
        product="$PRODUTO" \
        managed-by="corporate-governance" \
        --overwrite

    log_success "Namespace criado com labels obrigatórias"
else
    log_info "[DRY RUN] kubectl create namespace $NAMESPACE"
fi

# ====================
# Provisionar PostgreSQL
# ====================
if [ "$NEEDS_POSTGRES" = true ]; then
    log_info "Provisionando PostgreSQL..."
    if [ "$DRY_RUN" = false ]; then
        bash "${SCRIPT_DIR}/provision-database.sh" "$PRODUTO" "$NAMESPACE"
        log_success "PostgreSQL provisionado"
    else
        log_info "[DRY RUN] bash provision-database.sh $PRODUTO $NAMESPACE"
    fi
fi

# ====================
# Provisionar Redis
# ====================
if [ "$NEEDS_REDIS" = true ]; then
    log_info "Provisionando Redis..."
    if [ "$DRY_RUN" = false ]; then
        bash "${SCRIPT_DIR}/provision-redis.sh" "$PRODUTO" "$NAMESPACE" "$ENV"
        log_success "Redis provisionado"
    else
        log_info "[DRY RUN] bash provision-redis.sh $PRODUTO $NAMESPACE $ENV"
    fi
fi

# ====================
# Provisionar RabbitMQ
# ====================
if [ "$NEEDS_RABBITMQ" = true ]; then
    log_info "Provisionando RabbitMQ..."
    if [ "$DRY_RUN" = false ]; then
        bash "${SCRIPT_DIR}/provision-rabbitmq.sh" "$PRODUTO" "$NAMESPACE" "$DOMAIN" "$ENV"
        log_success "RabbitMQ provisionado"
    else
        log_info "[DRY RUN] bash provision-rabbitmq.sh $PRODUTO $NAMESPACE $DOMAIN $ENV"
    fi
fi

# ====================
# Criar Repositórios GitLab
# ====================
if [ "$SKIP_GITLAB" = false ]; then
    log_info "Criando repositórios GitLab..."
    if [ "$DRY_RUN" = false ]; then
        bash "${SCRIPT_DIR}/create-gitlab-repos.sh" "$PRODUTO" "$DOMAIN" "$ENV"
        log_success "Repositórios GitLab criados"
    else
        log_info "[DRY RUN] bash create-gitlab-repos.sh $PRODUTO $DOMAIN $ENV"
    fi
fi

# ====================
# Criar ArgoCD Application
# ====================
if [ "$SKIP_ARGOCD" = false ]; then
    log_info "Criando ArgoCD Application..."
    if [ "$DRY_RUN" = false ]; then
        bash "${SCRIPT_DIR}/create-argocd-app.sh" "$PRODUTO" "$DOMAIN" "$ENV"
        log_success "ArgoCD Application criado"
    else
        log_info "[DRY RUN] bash create-argocd-app.sh $PRODUTO $DOMAIN $ENV"
    fi
fi

# ====================
# Sumário
# ====================
echo ""
log_success "========================================="
log_success "Onboarding Completo!"
log_success "========================================="
echo ""
log_info "Namespace: $NAMESPACE"
log_info "Domínio: $DOMAIN"
log_info "Ambiente: $ENV"
echo ""

if [ "$NEEDS_POSTGRES" = true ]; then
    log_info "✅ PostgreSQL: Secret '${PRODUTO}-postgres-credentials' criado"
    log_info "   Connection: postgresql://{user}:{password}@rds-shared-cluster.prod-platform-databases.svc.cluster.local:5432/${PRODUTO}"
fi

if [ "$NEEDS_REDIS" = true ]; then
    log_info "✅ Redis: Redis CR '${PRODUTO}-redis' criado"
    log_info "   Host: ${PRODUTO}-redis.${NAMESPACE}.svc.cluster.local:6379"
fi

if [ "$NEEDS_RABBITMQ" = true ]; then
    log_info "✅ RabbitMQ: Secret '${PRODUTO}-rabbitmq-credentials' criado"
    log_info "   Host: rabbitmq-shared-cluster.prod-platform-messaging.svc.cluster.local:5672"
fi

if [ "$SKIP_GITLAB" = false ]; then
    log_info "✅ GitLab: Repositórios criados em corporate-domains/${DOMAIN}/${PRODUTO}"
fi

if [ "$SKIP_ARGOCD" = false ]; then
    log_info "✅ ArgoCD: Application criado"
fi

echo ""
log_info "Próximos passos:"
log_info "1. Clone repositórios: git clone git@gitlab.empresa.com:corporate-domains/${DOMAIN}/${PRODUTO}/${PRODUTO}.git"
log_info "2. Configure CI/CD: Copie templates de .gitlab-ci.yml"
log_info "3. Deploy aplicação: Commit no repo app → ArgoCD faz deploy automaticamente"
log_info "4. Monitore: https://grafana.empresa.com/d/${PRODUTO}"
echo ""
log_success "Documentação: /docs/governance/application-onboarding.md"
log_success "========================================="

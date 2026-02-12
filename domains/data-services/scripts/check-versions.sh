#!/usr/bin/env bash
# =============================================================================
# Data Services - Version Checker Script
# =============================================================================
# Description: Verifica versões instaladas vs disponíveis dos data-services
# Usage: ./check-versions.sh
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Icons
CHECK_MARK="✅"
WARNING="⚠️"
ERROR="❌"
INFO="ℹ️"

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Data Services - Version Checker${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Function to compare semantic versions
version_compare() {
    local current=$1
    local latest=$2

    # Remove 'v' prefix if present
    current="${current#v}"
    latest="${latest#v}"

    if [ "$current" = "$latest" ]; then
        echo "UP_TO_DATE"
    else
        # Simple comparison - in production would need proper semver comparison
        echo "OUTDATED"
    fi
}

# Function to check helm repo
check_helm_repo() {
    local repo_name=$1
    if ! helm repo list | grep -q "^${repo_name}"; then
        echo -e "${WARNING} Helm repo ${YELLOW}${repo_name}${NC} não encontrado. Adicionando..."
        case $repo_name in
            "zalando-postgres")
                helm repo add zalando-postgres https://opensource.zalando.com/postgres-operator/charts/postgres-operator
                ;;
            "redis-operator")
                helm repo add redis-operator https://ot-container-kit.github.io/helm-charts
                ;;
            "rabbitmq")
                helm repo add rabbitmq https://charts.rabbitmq.com
                ;;
            "vmware-tanzu")
                helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
                ;;
        esac
        helm repo update > /dev/null 2>&1
    fi
}

# Function to get installed version
get_installed_version() {
    local release=$1
    local namespace=$2

    if helm list -n "$namespace" 2>/dev/null | grep -q "^${release}"; then
        helm list -n "$namespace" -o json | jq -r ".[] | select(.name==\"${release}\") | .chart" | sed 's/.*-//'
    else
        echo "NOT_INSTALLED"
    fi
}

# Function to get latest version from repo
get_latest_version() {
    local repo=$1
    local chart=$2

    helm search repo "${repo}/${chart}" --versions 2>/dev/null | awk 'NR==2 {print $2}'
}

# Check prerequisites
echo -e "${INFO} Verificando pré-requisitos..."
for cmd in helm kubectl jq; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${ERROR} ${RED}$cmd não encontrado. Instale antes de continuar.${NC}"
        exit 1
    fi
done
echo -e "${CHECK_MARK} ${GREEN}Pré-requisitos OK${NC}"
echo ""

# Update helm repos
echo -e "${INFO} Atualizando repositórios Helm..."
helm repo update > /dev/null 2>&1
echo -e "${CHECK_MARK} ${GREEN}Repositórios atualizados${NC}"
echo ""

# =============================================================================
# CHECK POSTGRES OPERATOR
# =============================================================================
echo -e "${BLUE}───────────────────────────────────────────────────────────────${NC}"
echo -e "${BLUE}🐘 Zalando Postgres Operator${NC}"
echo -e "${BLUE}───────────────────────────────────────────────────────────────${NC}"

check_helm_repo "zalando-postgres"

PG_INSTALLED=$(get_installed_version "postgres-operator" "postgres-operator")
PG_LATEST=$(get_latest_version "zalando-postgres" "postgres-operator")

echo -e "Versão Instalada:  ${YELLOW}${PG_INSTALLED}${NC}"
echo -e "Versão Disponível: ${GREEN}${PG_LATEST}${NC}"

if [ "$PG_INSTALLED" = "NOT_INSTALLED" ]; then
    echo -e "Status: ${WARNING} ${YELLOW}NÃO INSTALADO${NC}"
elif [ "$PG_INSTALLED" = "$PG_LATEST" ]; then
    echo -e "Status: ${CHECK_MARK} ${GREEN}ATUALIZADO${NC}"
else
    echo -e "Status: ${WARNING} ${YELLOW}DESATUALIZADO${NC}"
    echo -e "Ação: Considere upgrade: ${PG_INSTALLED} → ${PG_LATEST}"
fi
echo ""

# =============================================================================
# CHECK REDIS OPERATOR
# =============================================================================
echo -e "${BLUE}───────────────────────────────────────────────────────────────${NC}"
echo -e "${BLUE}🔴 Redis Cluster Operator${NC}"
echo -e "${BLUE}───────────────────────────────────────────────────────────────${NC}"

check_helm_repo "redis-operator"

REDIS_INSTALLED=$(get_installed_version "redis-operator" "redis-operator")
REDIS_LATEST=$(get_latest_version "redis-operator" "redis-operator")

echo -e "Versão Instalada:  ${YELLOW}${REDIS_INSTALLED}${NC}"
echo -e "Versão Disponível: ${GREEN}${REDIS_LATEST}${NC}"

if [ "$REDIS_INSTALLED" = "NOT_INSTALLED" ]; then
    echo -e "Status: ${WARNING} ${YELLOW}NÃO INSTALADO${NC}"
elif [ "$REDIS_INSTALLED" = "$REDIS_LATEST" ]; then
    echo -e "Status: ${CHECK_MARK} ${GREEN}ATUALIZADO${NC}"
else
    echo -e "Status: ${WARNING} ${YELLOW}DESATUALIZADO${NC}"
    echo -e "Ação: Considere upgrade: ${REDIS_INSTALLED} → ${REDIS_LATEST}"
fi
echo ""

# =============================================================================
# CHECK RABBITMQ OPERATOR
# =============================================================================
echo -e "${BLUE}───────────────────────────────────────────────────────────────${NC}"
echo -e "${BLUE}🐰 RabbitMQ Cluster Operator${NC}"
echo -e "${BLUE}───────────────────────────────────────────────────────────────${NC}"

check_helm_repo "rabbitmq"

RABBITMQ_INSTALLED=$(get_installed_version "rabbitmq-cluster-operator" "data-services")
RABBITMQ_LATEST=$(get_latest_version "rabbitmq" "cluster-operator")

echo -e "Versão Instalada:  ${YELLOW}${RABBITMQ_INSTALLED}${NC}"
echo -e "Versão Disponível: ${GREEN}${RABBITMQ_LATEST}${NC}"

if [ "$RABBITMQ_INSTALLED" = "NOT_INSTALLED" ]; then
    echo -e "Status: ${WARNING} ${YELLOW}NÃO INSTALADO${NC}"
elif [ "$RABBITMQ_INSTALLED" = "$RABBITMQ_LATEST" ]; then
    echo -e "Status: ${CHECK_MARK} ${GREEN}ATUALIZADO${NC}"
else
    echo -e "Status: ${WARNING} ${YELLOW}DESATUALIZADO${NC}"
    echo -e "Ação: Considere upgrade: ${RABBITMQ_INSTALLED} → ${RABBITMQ_LATEST}"
fi
echo ""

# =============================================================================
# CHECK VELERO
# =============================================================================
echo -e "${BLUE}───────────────────────────────────────────────────────────────${NC}"
echo -e "${BLUE}💾 Velero (Backup & Restore)${NC}"
echo -e "${BLUE}───────────────────────────────────────────────────────────────${NC}"

check_helm_repo "vmware-tanzu"

VELERO_INSTALLED=$(get_installed_version "velero" "velero")
VELERO_LATEST=$(get_latest_version "vmware-tanzu" "velero")

echo -e "Versão Instalada:  ${YELLOW}${VELERO_INSTALLED}${NC}"
echo -e "Versão Disponível: ${GREEN}${VELERO_LATEST}${NC}"

if [ "$VELERO_INSTALLED" = "NOT_INSTALLED" ]; then
    echo -e "Status: ${WARNING} ${YELLOW}NÃO INSTALADO${NC}"
elif [ "$VELERO_INSTALLED" = "$VELERO_LATEST" ]; then
    echo -e "Status: ${CHECK_MARK} ${GREEN}ATUALIZADO${NC}"
else
    echo -e "Status: ${WARNING} ${YELLOW}DESATUALIZADO${NC}"
    echo -e "Ação: Considere upgrade: ${VELERO_INSTALLED} → ${VELERO_LATEST}"
fi
echo ""

# =============================================================================
# SUMMARY
# =============================================================================
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}📊 Resumo${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Count statuses
total=4
not_installed=0
up_to_date=0
outdated=0

for version in "$PG_INSTALLED" "$REDIS_INSTALLED" "$RABBITMQ_INSTALLED" "$VELERO_INSTALLED"; do
    if [ "$version" = "NOT_INSTALLED" ]; then
        ((not_installed++))
    fi
done

# Calculate up_to_date and outdated (simplified)
if [ "$PG_INSTALLED" != "NOT_INSTALLED" ] && [ "$PG_INSTALLED" = "$PG_LATEST" ]; then ((up_to_date++)); fi
if [ "$REDIS_INSTALLED" != "NOT_INSTALLED" ] && [ "$REDIS_INSTALLED" = "$REDIS_LATEST" ]; then ((up_to_date++)); fi
if [ "$RABBITMQ_INSTALLED" != "NOT_INSTALLED" ] && [ "$RABBITMQ_INSTALLED" = "$RABBITMQ_LATEST" ]; then ((up_to_date++)); fi
if [ "$VELERO_INSTALLED" != "NOT_INSTALLED" ] && [ "$VELERO_INSTALLED" = "$VELERO_LATEST" ]; then ((up_to_date++)); fi

outdated=$((total - not_installed - up_to_date))

echo -e "Total de Componentes:    ${BLUE}$total${NC}"
echo -e "Não Instalados:          ${YELLOW}$not_installed${NC}"
echo -e "Atualizados:             ${GREEN}$up_to_date${NC}"
echo -e "Desatualizados:          ${RED}$outdated${NC}"
echo ""

# Recommendations
if [ $outdated -gt 0 ]; then
    echo -e "${WARNING} ${YELLOW}Recomendação:${NC}"
    echo -e "  Consulte ${BLUE}docs/VERSION-CONTROL.md${NC} para plano de atualização"
    echo -e "  Execute upgrades em staging antes de produção"
    echo ""
fi

# Check for security updates
echo -e "${INFO} ${BLUE}Próximos Passos:${NC}"
echo -e "  1. Revisar changelog das versões mais recentes"
echo -e "  2. Testar upgrades em ambiente de staging"
echo -e "  3. Planejar janela de manutenção"
echo -e "  4. Atualizar VERSION-CONTROL.md após upgrades"
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "Script executado em: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"

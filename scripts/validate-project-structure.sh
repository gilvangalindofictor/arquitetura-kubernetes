#!/bin/bash
# Script de Validação e Organização da Estrutura do Projeto
# Autor: Sistema de Governança
# Data: 2026-02-11
# Descrição: Valida a estrutura de arquivos do projeto e move arquivos em desconformidade

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Workspace root
WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WORKSPACE_ROOT"

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Validação de Estrutura do Projeto Kubernetes         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "📂 Workspace: $WORKSPACE_ROOT"
echo ""

# Contadores
ISSUES_FOUND=0
FILES_MOVED=0
DIRS_CREATED=0

# Função para criar diretórios se não existirem
create_dir_if_needed() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        echo -e "${YELLOW}📁 Criando diretório: $dir${NC}"
        mkdir -p "$dir"
        ((DIRS_CREATED++))
    fi
}

# Função para mover arquivo
move_file() {
    local source="$1"
    local dest="$2"
    local reason="$3"

    if [ -f "$source" ]; then
        echo -e "${YELLOW}📦 Movendo: $(basename "$source")${NC}"
        echo -e "   De: $source"
        echo -e "   Para: $dest"
        echo -e "   Motivo: $reason"

        # Criar diretório de destino se necessário
        create_dir_if_needed "$(dirname "$dest")"

        # Mover arquivo
        mv "$source" "$dest"
        ((FILES_MOVED++))
        echo -e "${GREEN}   ✅ Movido com sucesso${NC}"
        echo ""
    fi
}

# Função para verificar arquivo fora do lugar
check_file_location() {
    local file="$1"
    local expected_pattern="$2"
    local reason="$3"

    if [ -f "$file" ] && [[ ! "$file" =~ $expected_pattern ]]; then
        echo -e "${RED}❌ Arquivo fora do lugar: $file${NC}"
        echo -e "   Motivo: $reason"
        ((ISSUES_FOUND++))
        return 1
    fi
    return 0
}

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}1. Validando Arquivos de Custos (FinOps)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Criar diretório para relatórios de custos AWS
REPORTS_AWS_DIR="reports/aws-costs"
create_dir_if_needed "$REPORTS_AWS_DIR"

# Arquivos de custos na raiz que devem ser movidos
COST_FILES=(
    "costs.json"
    "costs-mtd.json"
    "cost-2026-02-01-by-service.json"
    "cost-2026-02-01-by-usage.json"
    "cost-by-operation.json"
    "cost-by-tag.json"
    "cost-by-usage.json"
    "cost-mtd-by-operation.json"
    "cost-mtd-by-service.json"
    "cost-resources.json"
)

for file in "${COST_FILES[@]}"; do
    if [ -f "$file" ]; then
        move_file "$file" "$REPORTS_AWS_DIR/$file" "Arquivos de custos devem estar em reports/aws-costs/ (ADR-022)"
    fi
done

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}2. Validando Arquivos de Acesso${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Verificar se há arquivos sensíveis na raiz que deveriam estar em access/
if [ -d "access" ]; then
    echo -e "${GREEN}✅ Diretório access/ existe${NC}"

    # Verificar se há arquivos .json de login na raiz
    for file in login*.json access*.json credentials*.json; do
        if [ -f "$file" ]; then
            move_file "$file" "access/$file" "Arquivos de acesso devem estar em access/"
        fi
    done
else
    create_dir_if_needed "access"
fi
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}3. Validando Estrutura de Diretórios Principais${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Diretórios que devem existir
REQUIRED_DIRS=(
    "docs"
    "docs/adr"
    "docs/agents"
    "docs/workflows"
    "docs/governance"
    "docs/finops"
    "docs/runbooks"
    "domains"
    "domains/observability"
    "domains/platform-core"
    "domains/cicd-platform"
    "domains/data-services"
    "domains/secrets-management"
    "domains/security"
    "platform-provisioning"
    "platform-provisioning/aws"
    "scripts"
    "scripts/finops"
    "reports"
    "reports/aws-costs"
    "tests"
    "SAD"
    "SAD/docs"
)

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo -e "${YELLOW}⚠️  Diretório ausente: $dir${NC}"
        create_dir_if_needed "$dir"
    else
        echo -e "${GREEN}✅ $dir${NC}"
    fi
done
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}4. Validando Arquivos de Configuração${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Arquivos de configuração que devem estar na raiz
ROOT_CONFIG_FILES=(
    "README.md"
    "PROJECT-CONTEXT.md"
    "platform-config.yaml"
    ".gitignore"
    ".editorconfig"
)

for file in "${ROOT_CONFIG_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✅ $file${NC}"
    else
        echo -e "${YELLOW}⚠️  Arquivo ausente: $file${NC}"
        ((ISSUES_FOUND++))
    fi
done
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}5. Validando Estrutura de Scripts${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Verificar scripts na raiz que deveriam estar em scripts/
for file in *.sh; do
    if [ -f "$file" ] && [ "$file" != "setup.sh" ]; then
        echo -e "${YELLOW}⚠️  Script na raiz (considerar mover para scripts/): $file${NC}"
        # Não movemos automaticamente scripts .sh da raiz pois podem ser intencionais
    fi
done

# Verificar se scripts têm permissão de execução
echo ""
echo "Verificando permissões de execução em scripts..."
find scripts -type f -name "*.sh" | while read -r script; do
    if [ ! -x "$script" ]; then
        echo -e "${YELLOW}⚠️  Script sem permissão de execução: $script${NC}"
        chmod +x "$script"
        echo -e "${GREEN}   ✅ Permissão adicionada${NC}"
    else
        echo -e "${GREEN}✅ $script (executável)${NC}"
    fi
done
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}6. Validando Documentação ADR${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Contar ADRs
ADR_COUNT=$(find docs/adr -type f -name "adr-*.md" 2>/dev/null | wc -l)
echo -e "${GREEN}📄 ADRs encontrados: $ADR_COUNT${NC}"

if [ $ADR_COUNT -gt 0 ]; then
    echo "Listando ADRs:"
    find docs/adr -type f -name "adr-*.md" -exec basename {} \; | sort
fi
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}7. Validando Estrutura de Domínios${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

# Verificar estrutura de domínios
DOMAINS=(
    "observability"
    "platform-core"
    "cicd-platform"
    "data-services"
    "secrets-management"
    "security"
)

for domain in "${DOMAINS[@]}"; do
    domain_path="domains/$domain"
    if [ -d "$domain_path" ]; then
        echo -e "${GREEN}✅ Domínio: $domain${NC}"

        # Verificar subdiretórios esperados (se existirem arquivos)
        if [ "$(ls -A "$domain_path" 2>/dev/null)" ]; then
            # Listar conteúdo
            ls -1 "$domain_path" | head -5 | while read -r item; do
                echo -e "   └─ $item"
            done
        else
            echo -e "${YELLOW}   (vazio)${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Domínio ausente: $domain${NC}"
        create_dir_if_needed "$domain_path"
    fi
done
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}📊 RESUMO DA VALIDAÇÃO${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "📁 Diretórios criados: ${YELLOW}$DIRS_CREATED${NC}"
echo -e "📦 Arquivos movidos: ${YELLOW}$FILES_MOVED${NC}"
echo -e "⚠️  Issues encontrados: ${YELLOW}$ISSUES_FOUND${NC}"
echo ""

if [ $FILES_MOVED -gt 0 ]; then
    echo -e "${GREEN}✅ Estrutura do projeto organizada com sucesso!${NC}"
    echo ""
    echo -e "${YELLOW}📝 Recomendação: Revisar as mudanças com 'git status' antes de commitar${NC}"
    echo ""
elif [ $ISSUES_FOUND -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Alguns issues foram encontrados mas não puderam ser corrigidos automaticamente${NC}"
    echo ""
else
    echo -e "${GREEN}✅ Estrutura do projeto está conforme as convenções!${NC}"
    echo ""
fi

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}📚 Referências${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "• ADR-022: FinOps Automation Strategy (reports/aws-costs/)"
echo "• ADR-048: Naming Conventions Determinísticas"
echo "• README.md: Estrutura do projeto"
echo ""

exit 0

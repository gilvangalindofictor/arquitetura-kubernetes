#!/bin/bash
# Pre-commit hook: Validação de Estrutura do Projeto
# Autor: Sistema de Governança
# Data: 2026-02-11
# Descrição: Valida que os arquivos estão nos locais corretos antes do commit

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Validando estrutura do projeto...${NC}"

VIOLATIONS=0
WARNINGS=0

# Função para verificar se arquivo está no local correto
check_file_location() {
    local file="$1"
    local expected_pattern="$2"
    local reason="$3"
    local severity="${4:-error}" # error ou warning

    if ! [[ "$file" =~ $expected_pattern ]]; then
        if [ "$severity" == "error" ]; then
            echo -e "${RED}❌ VIOLAÇÃO: $file${NC}"
            echo -e "   ${YELLOW}Motivo: $reason${NC}"
            ((VIOLATIONS++))
        else
            echo -e "${YELLOW}⚠️  AVISO: $file${NC}"
            echo -e "   ${YELLOW}Motivo: $reason${NC}"
            ((WARNINGS++))
        fi
        return 1
    fi
    return 0
}

# Obter arquivos sendo commitados
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

if [ -z "$STAGED_FILES" ]; then
    echo -e "${GREEN}✅ Nenhum arquivo para validar${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}Arquivos sendo validados:${NC}"
echo "$STAGED_FILES" | while read -r file; do
    echo "  • $file"
done
echo ""

# ============================================================================
# REGRA 1: Arquivos de custos devem estar em reports/aws-costs/
# ============================================================================
echo -e "${BLUE}📊 Validando localização de relatórios de custos...${NC}"

COST_PATTERNS=(
    "^cost.*\.json$"
    "^costs.*\.json$"
)

while IFS= read -r file; do
    for pattern in "${COST_PATTERNS[@]}"; do
        filename=$(basename "$file")
        if [[ "$filename" =~ $pattern ]]; then
            check_file_location \
                "$file" \
                "^reports/aws-costs/" \
                "Arquivos de custos devem estar em reports/aws-costs/ (ADR-022)" \
                "error"
        fi
    done
done <<< "$STAGED_FILES"

# ============================================================================
# REGRA 2: Arquivos de credenciais devem estar em access/ ou serem ignorados
# ============================================================================
echo -e "${BLUE}🔐 Validando localização de arquivos de acesso...${NC}"

ACCESS_PATTERNS=(
    "^login.*\.json$"
    "^credentials.*\.json$"
    "^access.*\.json$"
    ".*\.pem$"
    ".*\.key$"
)

while IFS= read -r file; do
    for pattern in "${ACCESS_PATTERNS[@]}"; do
        filename=$(basename "$file")
        if [[ "$filename" =~ $pattern ]]; then
            # Verifica se não está em access/ ou .gitignore
            if [[ ! "$file" =~ ^access/ ]]; then
                echo -e "${RED}❌ CRÍTICO: Arquivo sensível fora de access/: $file${NC}"
                echo -e "   ${RED}NUNCA commite credenciais! Adicione ao .gitignore${NC}"
                ((VIOLATIONS++))
            fi
        fi
    done
done <<< "$STAGED_FILES"

# ============================================================================
# REGRA 3: Scripts devem ter permissão de execução
# ============================================================================
echo -e "${BLUE}⚙️  Validando permissões de scripts...${NC}"

while IFS= read -r file; do
    if [[ "$file" == *.sh ]]; then
        if [ -f "$file" ] && [ ! -x "$file" ]; then
            echo -e "${YELLOW}⚠️  Script sem permissão de execução: $file${NC}"
            echo -e "   ${YELLOW}Execute: chmod +x $file${NC}"
            ((WARNINGS++))
        fi
    fi
done <<< "$STAGED_FILES"

# ============================================================================
# REGRA 4: ADRs devem seguir nomenclatura correta
# ============================================================================
echo -e "${BLUE}📝 Validando nomenclatura de ADRs...${NC}"

while IFS= read -r file; do
    if [[ "$file" =~ docs/adr/.*\.md$ ]]; then
        filename=$(basename "$file")
        if ! [[ "$filename" =~ ^adr-[0-9]{3}-.+\.md$ ]]; then
            check_file_location \
                "$file" \
                "^docs/adr/adr-[0-9]{3}-.+\.md$" \
                "ADRs devem seguir padrão: adr-XXX-titulo.md (ADR-048)" \
                "error"
        fi
    fi
done <<< "$STAGED_FILES"

# ============================================================================
# REGRA 5: Arquivos Terraform devem estar em estrutura correta
# ============================================================================
echo -e "${BLUE}🏗️  Validando estrutura Terraform...${NC}"

while IFS= read -r file; do
    if [[ "$file" == *.tf ]] || [[ "$file" == *.tfvars ]]; then
        # Terraform files devem estar em platform-provisioning/ ou domains/
        if [[ ! "$file" =~ ^(platform-provisioning|domains)/ ]]; then
            check_file_location \
                "$file" \
                "^(platform-provisioning|domains)/" \
                "Arquivos Terraform devem estar em platform-provisioning/ ou domains/" \
                "warning"
        fi
    fi
done <<< "$STAGED_FILES"

# ============================================================================
# REGRA 6: Documentação deve estar em docs/ ou domínios
# ============================================================================
echo -e "${BLUE}📚 Validando localização de documentação...${NC}"

ALLOWED_DOC_PATHS=(
    "^README\.md$"
    "^PROJECT-CONTEXT\.md$"
    "^ARCHITECTURE-DIAGRAMS\.md$"
    "^docs/"
    "^SAD/"
    "^domains/.*/docs/"
    "^domains/.*/README\.md$"
    "^platform-provisioning/.*/README\.md$"
)

while IFS= read -r file; do
    if [[ "$file" == *.md ]]; then
        is_allowed=false
        for pattern in "${ALLOWED_DOC_PATHS[@]}"; do
            if [[ "$file" =~ $pattern ]]; then
                is_allowed=true
                break
            fi
        done

        if [ "$is_allowed" = false ]; then
            check_file_location \
                "$file" \
                "^(docs|SAD|domains|platform-provisioning)/" \
                "Documentação deve estar em docs/, SAD/, ou dentro de domínios" \
                "warning"
        fi
    fi
done <<< "$STAGED_FILES"

# ============================================================================
# REGRA 7: Helm charts devem estar em estrutura correta
# ============================================================================
echo -e "${BLUE}☸️  Validando estrutura Helm...${NC}"

while IFS= read -r file; do
    if [[ "$file" =~ Chart\.yaml$ ]] || [[ "$file" =~ values.*\.yaml$ ]]; then
        # Charts devem estar em domains/*/infra/helm ou platform-provisioning/*/helm
        if [[ ! "$file" =~ (domains|platform-provisioning)/.*/helm/ ]]; then
            check_file_location \
                "$file" \
                "(domains|platform-provisioning)/.*/helm/" \
                "Helm charts devem estar em domains/*/infra/helm/ ou platform-provisioning/*/helm/" \
                "warning"
        fi
    fi
done <<< "$STAGED_FILES"

# ============================================================================
# Resultado Final
# ============================================================================
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}📊 RESUMO DA VALIDAÇÃO${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "❌ Violações (bloqueiam commit): ${RED}$VIOLATIONS${NC}"
echo -e "⚠️  Avisos (não bloqueiam): ${YELLOW}$WARNINGS${NC}"
echo ""

if [ "$VIOLATIONS" -gt 0 ]; then
    echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ❌ COMMIT BLOQUEADO - VIOLAÇÕES DE ESTRUTURA            ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}📋 AÇÕES NECESSÁRIAS:${NC}"
    echo -e "${YELLOW}1. Mova os arquivos para os locais corretos${NC}"
    echo -e "${YELLOW}2. Execute: scripts/validate-project-structure.sh${NC}"
    echo -e "${YELLOW}3. Execute 'git add' novamente${NC}"
    echo -e "${YELLOW}4. Tente o commit novamente${NC}"
    echo ""
    echo -e "${BLUE}📚 Referências:${NC}"
    echo "  • ADR-022: FinOps Automation Strategy"
    echo "  • ADR-048: Naming Conventions Determinísticas"
    echo "  • docs/governance/STRICT-RULES.md"
    echo ""
    exit 1
fi

if [ "$WARNINGS" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Avisos detectados, mas commit será permitido${NC}"
    echo -e "${YELLOW}Considere revisar os avisos acima${NC}"
    echo ""
fi

echo -e "${GREEN}✅ Validação de estrutura concluída - Commit permitido${NC}"
exit 0

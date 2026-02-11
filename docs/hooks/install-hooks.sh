#!/bin/bash
# Script de Instalação de Git Hooks
# Autor: Sistema de Governança
# Data: 2026-02-11
# Descrição: Instala ou atualiza hooks Git do projeto

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Instalação de Git Hooks - Projeto Kubernetes         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Workspace root
WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS_DIR="$WORKSPACE_ROOT/.git/hooks"
DOCS_HOOKS_DIR="$WORKSPACE_ROOT/docs/hooks"

cd "$WORKSPACE_ROOT"

echo "📂 Workspace: $WORKSPACE_ROOT"
echo "🔧 Hooks dir: $HOOKS_DIR"
echo ""

# Verificar se estamos em um repositório Git
if [ ! -d ".git" ]; then
    echo -e "${RED}❌ Erro: Não é um repositório Git${NC}"
    exit 1
fi

# Criar backup dos hooks existentes
echo -e "${BLUE}1. Criando backup dos hooks existentes...${NC}"
BACKUP_DIR="$HOOKS_DIR/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

for hook in pre-commit post-commit pre-push; do
    if [ -f "$HOOKS_DIR/$hook" ]; then
        echo "   Backup: $hook"
        cp "$HOOKS_DIR/$hook" "$BACKUP_DIR/"
    fi
done
echo -e "${GREEN}   ✅ Backup criado em: $BACKUP_DIR${NC}"
echo ""

# Instalar/atualizar pre-commit hook
echo -e "${BLUE}2. Instalando/atualizando pre-commit hook...${NC}"

# Ler o hook existente
EXISTING_PRECOMMIT="$HOOKS_DIR/pre-commit"
NEW_HOOK_CONTENT=""

if [ -f "$EXISTING_PRECOMMIT" ]; then
    echo "   Hook pre-commit existente encontrado"
    # Adicionar validação de estrutura ao hook existente

    # Verificar se já tem a validação de estrutura
    if grep -q "validate-project-structure.sh" "$EXISTING_PRECOMMIT"; then
        echo -e "${YELLOW}   ⚠️  Validação de estrutura já presente no hook${NC}"
    else
        echo "   Adicionando validação de estrutura ao hook existente..."

        # Criar novo hook combinado
        cat > "$EXISTING_PRECOMMIT.new" << 'HOOK_START'
#!/bin/bash

# Pre-commit hook para validação completa
# Combina validações de governança documental e estrutura de projeto

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Pre-Commit Validation - Projeto Kubernetes           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

TOTAL_VIOLATIONS=0

# ============================================================================
# VALIDAÇÃO 1: Estrutura de Projeto
# ============================================================================
echo -e "${BLUE}🔍 [1/2] Validando estrutura do projeto...${NC}"
echo ""

if [ -f "docs/hooks/pre/validate-project-structure.sh" ]; then
    bash docs/hooks/pre/validate-project-structure.sh
    STRUCTURE_EXIT=$?
    TOTAL_VIOLATIONS=$((TOTAL_VIOLATIONS + STRUCTURE_EXIT))
else
    echo -e "${YELLOW}⚠️  Hook de estrutura não encontrado, pulando...${NC}"
fi

echo ""

# ============================================================================
# VALIDAÇÃO 2: Governança Documental (hook original)
# ============================================================================
echo -e "${BLUE}🔍 [2/2] Validando governança documental...${NC}"
echo ""

HOOK_START

        # Adicionar o conteúdo do hook original (sem o shebang)
        tail -n +2 "$EXISTING_PRECOMMIT" >> "$EXISTING_PRECOMMIT.new"

        # Adicionar verificação final combinada
        cat >> "$EXISTING_PRECOMMIT.new" << 'HOOK_END'

# ============================================================================
# Resultado Final Combinado
# ============================================================================
if [ "$TOTAL_VIOLATIONS" -gt 0 ]; then
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  ❌ COMMIT BLOQUEADO - VIOLAÇÕES DETECTADAS              ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 1
else
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ TODAS AS VALIDAÇÕES PASSARAM - COMMIT PERMITIDO      ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 0
fi
HOOK_END

        # Substituir o hook antigo
        mv "$EXISTING_PRECOMMIT.new" "$EXISTING_PRECOMMIT"
        chmod +x "$EXISTING_PRECOMMIT"
        echo -e "${GREEN}   ✅ Hook pre-commit atualizado${NC}"
    fi
else
    # Criar novo hook do zero
    echo "   Criando novo hook pre-commit..."
    cp "$DOCS_HOOKS_DIR/pre/validate-project-structure.sh" "$EXISTING_PRECOMMIT"
    chmod +x "$EXISTING_PRECOMMIT"
    echo -e "${GREEN}   ✅ Hook pre-commit criado${NC}"
fi
echo ""

# Instalar post-commit hook
echo -e "${BLUE}3. Instalando post-commit hook...${NC}"

if [ -f "$DOCS_HOOKS_DIR/post/update-structure-report.sh" ]; then
    cp "$DOCS_HOOKS_DIR/post/update-structure-report.sh" "$HOOKS_DIR/post-commit"
    chmod +x "$HOOKS_DIR/post-commit"
    echo -e "${GREEN}   ✅ Hook post-commit instalado${NC}"
else
    echo -e "${YELLOW}   ⚠️  Hook post-commit não encontrado${NC}"
fi
echo ""

# Dar permissão de execução a todos os hooks
echo -e "${BLUE}4. Configurando permissões...${NC}"
chmod +x "$DOCS_HOOKS_DIR"/pre/*.sh 2>/dev/null || true
chmod +x "$DOCS_HOOKS_DIR"/post/*.sh 2>/dev/null || true
echo -e "${GREEN}   ✅ Permissões configuradas${NC}"
echo ""

# Testar hooks (dry-run)
echo -e "${BLUE}5. Testando hooks instalados...${NC}"

# Verificar se hooks são executáveis
for hook in pre-commit post-commit; do
    if [ -f "$HOOKS_DIR/$hook" ] && [ -x "$HOOKS_DIR/$hook" ]; then
        echo -e "${GREEN}   ✅ $hook (executável)${NC}"
    else
        echo -e "${YELLOW}   ⚠️  $hook (não encontrado ou sem permissão)${NC}"
    fi
done
echo ""

# Resumo final
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}📊 RESUMO DA INSTALAÇÃO${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}✅ Hooks instalados com sucesso!${NC}"
echo ""
echo -e "${BLUE}Hooks ativos:${NC}"
echo "  • pre-commit  → Valida estrutura + governança documental"
echo "  • post-commit → Gera relatório de validação (opcional)"
echo ""
echo -e "${BLUE}Backup dos hooks anteriores:${NC}"
echo "  $BACKUP_DIR"
echo ""
echo -e "${YELLOW}📝 Próximos passos:${NC}"
echo "  1. Seus próximos commits serão validados automaticamente"
echo "  2. Se houver violações, o commit será bloqueado"
echo "  3. Execute 'scripts/validate-project-structure.sh' para validação manual"
echo ""
echo -e "${BLUE}Para desinstalar:${NC}"
echo "  Restaure os hooks do backup: cp $BACKUP_DIR/* $HOOKS_DIR/"
echo ""

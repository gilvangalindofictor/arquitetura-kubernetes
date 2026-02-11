#!/bin/bash
# Post-commit hook: Atualizar relatório de estrutura
# Autor: Sistema de Governança
# Data: 2026-02-11
# Descrição: Executa validação completa pós-commit e gera relatório (opcional)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}📊 Validação pós-commit...${NC}"

# Opção: executar validação completa (não bloqueia, apenas informa)
if [ -f "scripts/validate-project-structure.sh" ]; then
    echo -e "${YELLOW}Executando validação completa da estrutura...${NC}"

    # Executar em modo não-bloqueante (sempre retorna 0)
    bash scripts/validate-project-structure.sh > /tmp/project-structure-report.txt 2>&1 || true

    # Mostrar resumo
    if grep -q "✅ Estrutura do projeto está conforme" /tmp/project-structure-report.txt; then
        echo -e "${GREEN}✅ Estrutura do projeto validada e conforme${NC}"
    else
        echo -e "${YELLOW}⚠️  Validação completa detectou alguns avisos${NC}"
        echo -e "${YELLOW}Execute: scripts/validate-project-structure.sh${NC}"
    fi

    rm -f /tmp/project-structure-report.txt
fi

echo -e "${GREEN}✅ Post-commit concluído${NC}"
exit 0

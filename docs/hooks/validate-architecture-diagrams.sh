#!/bin/bash
# =============================================================================
# HOOK: Validate Architecture Diagrams Update
# =============================================================================
# Propósito: Garantir que ARCHITECTURE-DIAGRAMS.md seja atualizado quando
#            houver mudanças em contextos estratégicos (ADRs, SAD, domínios)
#
# Disparo: pre-commit (validação antes do commit)
#
# Uso:
#   cp docs/hooks/validate-architecture-diagrams.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
# =============================================================================

set -e

# Cores para output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Validando atualização de diagramas arquiteturais...${NC}"

# Arquivos estratégicos que exigem atualização de diagramas
STRATEGIC_FILES=(
    "SAD/docs/sad.md"
    "SAD/docs/adrs/"
    "domains/*/README.md"
    "domains/*/docs/adr/"
    "domains/*/infra/terraform/main.tf"
    "PROJECT-CONTEXT.md"
    "TERRAFORM-IMPLEMENTATION-REPORT.md"
)

# Arquivo de diagramas que deve ser atualizado
DIAGRAMS_FILE="ARCHITECTURE-DIAGRAMS.md"

# Verificar se há mudanças staged
STAGED_FILES=$(git diff --cached --name-only)

if [ -z "$STAGED_FILES" ]; then
    echo -e "${GREEN}✅ Nenhum arquivo staged para commit${NC}"
    exit 0
fi

# Verificar se algum arquivo estratégico foi modificado
STRATEGIC_CHANGED=false
CHANGED_STRATEGIC_FILES=""

for pattern in "${STRATEGIC_FILES[@]}"; do
    # Expandir glob pattern
    for file in $(git diff --cached --name-only | grep -E "$pattern" || true); do
        if [ -n "$file" ]; then
            STRATEGIC_CHANGED=true
            CHANGED_STRATEGIC_FILES="$CHANGED_STRATEGIC_FILES\n  - $file"
        fi
    done
done

# Se nenhum arquivo estratégico foi modificado, permitir commit
if [ "$STRATEGIC_CHANGED" = false ]; then
    echo -e "${GREEN}✅ Nenhum arquivo estratégico modificado${NC}"
    exit 0
fi

echo -e "${YELLOW}⚠️  Arquivos estratégicos modificados:${CHANGED_STRATEGIC_FILES}${NC}"

# Verificar se ARCHITECTURE-DIAGRAMS.md foi atualizado
DIAGRAMS_UPDATED=false
if echo "$STAGED_FILES" | grep -q "$DIAGRAMS_FILE"; then
    DIAGRAMS_UPDATED=true
fi

# Se diagramas não foram atualizados, avisar
if [ "$DIAGRAMS_UPDATED" = false ]; then
    echo ""
    echo -e "${RED}❌ ATENÇÃO: Mudanças estratégicas detectadas sem atualização de diagramas!${NC}"
    echo ""
    echo -e "${YELLOW}Arquivos estratégicos modificados requerem atualização de:${NC}"
    echo -e "  📊 ${DIAGRAMS_FILE}"
    echo ""
    echo -e "${YELLOW}Mudanças que exigem atualização de diagramas:${NC}"
    echo -e "  • Novos domínios criados"
    echo -e "  • ADRs sistêmicos adicionados/modificados"
    echo -e "  • Mudanças no SAD (governança)"
    echo -e "  • Novos componentes em domínios (terraform/main.tf)"
    echo -e "  • Mudanças em contratos de domínio"
    echo -e "  • Alterações em dependências entre domínios"
    echo ""
    echo -e "${BLUE}📋 Seções para atualizar em ARCHITECTURE-DIAGRAMS.md:${NC}"
    
    # Detectar qual seção atualizar baseado nos arquivos modificados
    if echo "$CHANGED_STRATEGIC_FILES" | grep -q "SAD/docs/"; then
        echo -e "  • Diagrama 1: Visão Geral (novos componentes/domínios)"
        echo -e "  • Diagrama 2: Ordem de Deploy (se dependências mudaram)"
    fi
    
    if echo "$CHANGED_STRATEGIC_FILES" | grep -q "platform-core"; then
        echo -e "  • Diagrama 3: Platform-Core (componentes, contratos)"
    fi
    
    if echo "$CHANGED_STRATEGIC_FILES" | grep -q "cicd-platform"; then
        echo -e "  • Diagrama 4: CI/CD Platform (workflow, integrações)"
    fi
    
    if echo "$CHANGED_STRATEGIC_FILES" | grep -q "observability"; then
        echo -e "  • Diagrama 5: Observability (data flow, componentes)"
    fi
    
    if echo "$CHANGED_STRATEGIC_FILES" | grep -q "data-services"; then
        echo -e "  • Diagrama 6: Data Services (operators, instances)"
    fi
    
    if echo "$CHANGED_STRATEGIC_FILES" | grep -q "secrets-management"; then
        echo -e "  • Diagrama 7: Secrets Management (decisão ADR-002)"
    fi
    
    if echo "$CHANGED_STRATEGIC_FILES" | grep -q "security"; then
        echo -e "  • Diagrama 8: Security (decisão ADR-002, policies)"
    fi
    
    if echo "$CHANGED_STRATEGIC_FILES" | grep -q "ADR" || echo "$CHANGED_STRATEGIC_FILES" | grep -q "adr"; then
        echo -e "  • Diagrama 9: Comunicação Entre Domínios (novas integrações)"
    fi
    
    echo ""
    echo -e "${BLUE}💡 Ações recomendadas:${NC}"
    echo -e "  1. Abra: ${DIAGRAMS_FILE}"
    echo -e "  2. Atualize os diagramas Mermaid relevantes"
    echo -e "  3. Atualize a tabela de recursos (se aplicável)"
    echo -e "  4. Marque status (✅/⚠️) se domínios mudaram de estado"
    echo -e "  5. Execute: git add ${DIAGRAMS_FILE}"
    echo -e "  6. Commit novamente"
    echo ""
    echo -e "${YELLOW}🔧 Para ignorar esta validação (não recomendado):${NC}"
    echo -e "  git commit --no-verify"
    echo ""
    
    # Perguntar ao usuário se deseja continuar sem atualizar
    echo -e "${YELLOW}⚠️  Deseja continuar sem atualizar os diagramas? (y/N)${NC}"
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}⚠️  Commit permitido SEM atualização de diagramas${NC}"
        echo -e "${RED}⚠️  LEMBRE-SE: Atualizar diagramas manualmente antes do PR!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Commit bloqueado. Atualize os diagramas e tente novamente.${NC}"
        exit 1
    fi
fi

# Diagramas foram atualizados
echo -e "${GREEN}✅ ARCHITECTURE-DIAGRAMS.md atualizado junto com mudanças estratégicas${NC}"

# Validar que o arquivo tem conteúdo Mermaid válido
if ! grep -q '```mermaid' "$DIAGRAMS_FILE"; then
    echo -e "${RED}❌ ERRO: ${DIAGRAMS_FILE} não contém diagramas Mermaid válidos!${NC}"
    exit 1
fi

# Validar que a data de atualização foi modificada
LAST_UPDATE=$(grep "Última Atualização" "$DIAGRAMS_FILE" | head -n 1)
if [ -z "$LAST_UPDATE" ]; then
    echo -e "${YELLOW}⚠️  AVISO: Campo 'Última Atualização' não encontrado em ${DIAGRAMS_FILE}${NC}"
fi

# Sucesso
echo -e "${GREEN}✅ Validação de diagramas arquiteturais concluída com sucesso!${NC}"
exit 0

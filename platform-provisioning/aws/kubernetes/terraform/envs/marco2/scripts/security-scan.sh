#!/bin/bash
# ==============================================================================
# Security Scan Script for Marco 2 - Platform Services
# Descrição: Executa análise de segurança no código Terraform
# ==============================================================================

set -e

# --- Colors for output ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Security Scan - Marco 2${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# --- 1. Check if tfsec is installed ---
echo -e "${YELLOW}--- Checking Security Tools ---${NC}"

if ! command -v tfsec &> /dev/null; then
    echo -e "${RED}✖ tfsec is not installed.${NC}"
    echo -e "${YELLOW}Installing tfsec...${NC}"
    echo ""
    echo -e "Choose installation method:"
    echo -e "  1. Homebrew (macOS/Linux):    brew install tfsec"
    echo -e "  2. Go:                        go install github.com/aquasecurity/tfsec/cmd/tfsec@latest"
    echo -e "  3. Download binary:           https://github.com/aquasecurity/tfsec/releases"
    echo -e "  4. Docker:                    docker run --rm -it -v \"\$(pwd):/src\" aquasec/tfsec /src"
    echo ""
    read -p "Install via Homebrew? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if command -v brew &> /dev/null; then
            brew install tfsec
        else
            echo -e "${RED}✖ Homebrew not found. Please install manually.${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}Please install tfsec manually and re-run this script.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✔ tfsec is installed ($(tfsec --version))${NC}"
echo ""

# --- 2. Run tfsec scan ---
echo -e "${YELLOW}--- Running tfsec Security Scan ---${NC}"
cd "$TERRAFORM_DIR"

echo -e "${BLUE}Scanning: $TERRAFORM_DIR${NC}"
echo ""

# Run tfsec with detailed output
# --format: Output format (default, json, csv, checkstyle, junit, sarif)
# --exclude: Exclude specific checks (comma-separated)
# --minimum-severity: Only show issues of this severity or higher (CRITICAL, HIGH, MEDIUM, LOW)

tfsec . \
    --format default \
    --minimum-severity MEDIUM \
    --exclude-downloaded-modules \
    --out tfsec-report.txt \
    || true  # Don't fail on findings, we'll review them

# Display report
cat tfsec-report.txt

# --- 3. Generate JSON report for CI/CD ---
echo ""
echo -e "${YELLOW}--- Generating JSON Report ---${NC}"

tfsec . \
    --format json \
    --exclude-downloaded-modules \
    --out tfsec-report.json \
    || true

echo -e "${GREEN}✔ JSON report saved to: tfsec-report.json${NC}"

# --- 4. Check for CRITICAL issues ---
echo ""
echo -e "${YELLOW}--- Checking for CRITICAL Issues ---${NC}"

CRITICAL_COUNT=$(tfsec . --format json --exclude-downloaded-modules 2>/dev/null | jq '[.results[] | select(.severity == "CRITICAL")] | length' || echo "0")

if [ "$CRITICAL_COUNT" -gt 0 ]; then
    echo -e "${RED}✖ Found $CRITICAL_COUNT CRITICAL security issues!${NC}"
    echo -e "${RED}Please review tfsec-report.txt and fix before deploying.${NC}"
    exit 1
else
    echo -e "${GREEN}✔ No CRITICAL security issues found.${NC}"
fi

# --- 5. Summary ---
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Security Scan Completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Reports generated:"
echo -e "  - tfsec-report.txt  (human-readable)"
echo -e "  - tfsec-report.json (CI/CD integration)"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Review findings in tfsec-report.txt"
echo -e "  2. Fix any CRITICAL or HIGH severity issues"
echo -e "  3. Document accepted risks for MEDIUM/LOW issues"
echo -e "  4. Re-run scan after fixes"
echo ""

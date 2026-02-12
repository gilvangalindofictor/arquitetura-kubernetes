#!/bin/bash
# scripts/finops/cleanup-all.sh
#
# Master script to run ALL FinOps cleanup and audit scripts
# Generates consolidated report with total savings
#
# Usage:
#   DRY_RUN=true  bash scripts/finops/cleanup-all.sh   # scan only (default)
#   DRY_RUN=false bash scripts/finops/cleanup-all.sh   # execute cleanup
#
# Requires: aws-cli, jq, active AWS SSO session

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DRY_RUN="${DRY_RUN:-true}"
REPORT_DIR="$PROJECT_ROOT/reports/aws-costs"
CONSOLIDATED_REPORT="$REPORT_DIR/cleanup-all-$(date +%Y-%m-%d).json"

mkdir -p "$REPORT_DIR"

echo "=========================================="
echo " FinOps — Complete AWS Cleanup Audit"
echo "=========================================="
echo "Date:     $(date --iso-8601=seconds)"
echo "Dry-run:  $DRY_RUN"
echo "=========================================="
echo ""

# Initialize totals
TOTAL_SAVINGS=0
ALL_FINDINGS="[]"

# --- 1. Orphan Resources (EBS, Snapshots, ALBs) ---
echo "🔍 [1/7] Running orphan resources cleanup..."
DRY_RUN=$DRY_RUN bash "$SCRIPT_DIR/cleanup-orphan-resources.sh" || true
if [ -f "$REPORT_DIR/cleanup-$(date +%Y-%m-%d).json" ]; then
  SAVINGS=$(jq -r '.total_savings_annual_brl // 0' "$REPORT_DIR/cleanup-$(date +%Y-%m-%d).json")
  TOTAL_SAVINGS=$((TOTAL_SAVINGS + SAVINGS))
  echo "  Savings: R$ $SAVINGS/ano"
fi
echo ""

# --- 2. Elastic IPs ---
echo "🔍 [2/7] Running Elastic IPs cleanup..."
DRY_RUN=$DRY_RUN bash "$SCRIPT_DIR/cleanup-elastic-ips.sh" || true
if [ -f "$REPORT_DIR/cleanup-elastic-ips-$(date +%Y-%m-%d).json" ]; then
  SAVINGS=$(jq -r '.total_savings_annual_brl // 0' "$REPORT_DIR/cleanup-elastic-ips-$(date +%Y-%m-%d).json")
  TOTAL_SAVINGS=$((TOTAL_SAVINGS + SAVINGS))
  echo "  Savings: R$ $SAVINGS/ano"
fi
echo ""

# --- 3. NAT Gateways ---
echo "🔍 [3/7] Running NAT Gateways audit..."
DRY_RUN=$DRY_RUN bash "$SCRIPT_DIR/cleanup-nat-gateways.sh" || true
echo ""

# --- 4. CloudWatch Logs ---
echo "🔍 [4/7] Running CloudWatch Logs cleanup..."
DRY_RUN=$DRY_RUN bash "$SCRIPT_DIR/cleanup-cloudwatch-logs.sh" || true
if [ -f "$REPORT_DIR/cleanup-cloudwatch-logs-$(date +%Y-%m-%d).json" ]; then
  SAVINGS=$(jq -r '.total_savings_annual_brl // 0' "$REPORT_DIR/cleanup-cloudwatch-logs-$(date +%Y-%m-%d).json")
  TOTAL_SAVINGS=$((TOTAL_SAVINGS + SAVINGS))
  echo "  Savings: R$ $SAVINGS/ano"
fi
echo ""

# --- 5. ECR Images ---
echo "🔍 [5/7] Running ECR images cleanup..."
DRY_RUN=$DRY_RUN bash "$SCRIPT_DIR/cleanup-ecr-images.sh" || true
if [ -f "$REPORT_DIR/cleanup-ecr-images-$(date +%Y-%m-%d).json" ]; then
  SAVINGS=$(jq -r '.total_savings_annual_brl // 0' "$REPORT_DIR/cleanup-ecr-images-$(date +%Y-%m-%d).json")
  TOTAL_SAVINGS=$((TOTAL_SAVINGS + SAVINGS))
  echo "  Savings: R$ $SAVINGS/ano"
fi
echo ""

# --- 6. Security Groups ---
echo "🔍 [6/7] Running Security Groups audit..."
bash "$SCRIPT_DIR/audit-security-groups.sh" || true
echo ""

# --- 7. Weekly Cost Report (if not dry-run) ---
if [ "$DRY_RUN" = "true" ]; then
  echo "🔍 [7/7] Skipping weekly cost report (dry-run mode)"
else
  echo "🔍 [7/7] Generating weekly cost report..."
  bash "$SCRIPT_DIR/weekly-cost-report.sh" 7 || echo "  WARN: Cost report failed (may require AWS re-auth)"
fi
echo ""

# Generate consolidated report
echo "=========================================="
echo " CONSOLIDATED SUMMARY"
echo "=========================================="
echo "Total estimated savings:  R$ ${TOTAL_SAVINGS}/ano"
echo "Monthly savings:          R$ $((TOTAL_SAVINGS / 12))/mês"
echo "Dry-run:                  $DRY_RUN"
echo "=========================================="

# Save consolidated report
cat > "$CONSOLIDATED_REPORT" <<EOF
{
  "scan_date": "$(date --iso-8601=seconds)",
  "dry_run": $DRY_RUN,
  "total_savings_annual_brl": $TOTAL_SAVINGS,
  "monthly_savings_brl": $((TOTAL_SAVINGS / 12)),
  "reports": {
    "orphan_resources": "$REPORT_DIR/cleanup-$(date +%Y-%m-%d).json",
    "elastic_ips": "$REPORT_DIR/cleanup-elastic-ips-$(date +%Y-%m-%d).json",
    "nat_gateways": "$REPORT_DIR/cleanup-nat-gateways-$(date +%Y-%m-%d).json",
    "cloudwatch_logs": "$REPORT_DIR/cleanup-cloudwatch-logs-$(date +%Y-%m-%d).json",
    "ecr_images": "$REPORT_DIR/cleanup-ecr-images-$(date +%Y-%m-%d).json",
    "security_groups": "$REPORT_DIR/audit-security-groups-$(date +%Y-%m-%d).json"
  },
  "next_steps": [
    "Review individual reports for detailed findings",
    "Execute cleanup with DRY_RUN=false after approval",
    "Implement AWS Config Rules for proactive monitoring",
    "Schedule weekly cleanup automation via EventBridge + Lambda"
  ]
}
EOF

echo ""
echo "Consolidated report saved: $CONSOLIDATED_REPORT"
echo ""
echo "📊 Individual reports available in: $REPORT_DIR/"
echo ""

if [ "$DRY_RUN" = "true" ]; then
  echo "✅ Dry-run complete. No resources were modified."
  echo ""
  echo "To execute cleanup, run:"
  echo "  DRY_RUN=false bash $0"
else
  echo "✅ Cleanup complete. Resources were modified."
  echo ""
  echo "Next steps:"
  echo "  1. Review Cost Explorer for savings verification"
  echo "  2. Update MEMORY.md with new savings"
  echo "  3. Communicate savings to CTO/CFO"
fi

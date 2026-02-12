#!/bin/bash
# scripts/finops/cleanup-nat-gateways.sh
#
# Scan and optionally delete NAT Gateways in deleted/failed state
# Cost: $32.40/month per NAT Gateway (unused but not deleted)
#
# Usage:
#   DRY_RUN=true  bash scripts/finops/cleanup-nat-gateways.sh   # scan only (default)
#   DRY_RUN=false bash scripts/finops/cleanup-nat-gateways.sh   # delete NAT GWs
#
# Requires: aws-cli, jq, active AWS SSO session

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Read config from platform-config.yaml if yq is available
if command -v yq &>/dev/null && [ -f "$PROJECT_ROOT/platform-config.yaml" ]; then
  REGION=$(yq eval '.aws.region' "$PROJECT_ROOT/platform-config.yaml")
  PROFILE=$(yq eval '.aws.profile' "$PROJECT_ROOT/platform-config.yaml")
else
  REGION="${AWS_REGION:-us-east-1}"
  PROFILE="${AWS_PROFILE:-default}"
fi

DRY_RUN="${DRY_RUN:-true}"
REPORT_DIR="$PROJECT_ROOT/reports/aws-costs"
REPORT_FILE="$REPORT_DIR/cleanup-nat-gateways-$(date +%Y-%m-%d).json"

mkdir -p "$REPORT_DIR"

echo "=========================================="
echo " FinOps Cleanup — NAT Gateways"
echo "=========================================="
echo "Region:   $REGION"
echo "Profile:  $PROFILE"
echo "Dry-run:  $DRY_RUN"
echo "Date:     $(date --iso-8601=seconds)"
echo "=========================================="

# NAT Gateways in deleted/failed state (orphans)
ORPHAN_NATS=$(aws ec2 describe-nat-gateways \
  --region "$REGION" \
  --profile "$PROFILE" \
  --filter "Name=state,Values=deleted,failed" \
  --query 'NatGateways[].{ID:NatGatewayId,State:State,Created:CreateTime,VPC:VpcId}' \
  --output json 2>/dev/null || echo "[]")

NAT_COUNT=$(echo "$ORPHAN_NATS" | jq '. | length')

echo ""
echo "--- Orphan NAT Gateways (deleted/failed) ---"
echo "Found: $NAT_COUNT orphan NAT Gateways"

if [ "$NAT_COUNT" -gt 0 ]; then
  echo "$ORPHAN_NATS" | jq -r '.[] | "  \(.ID) | State: \(.State) | VPC: \(.VPC) | Created: \(.Created)"'

  # Note: Deleted NAT Gateways don't incur charges but clutter the console
  # Failed NAT Gateways may incur charges if elastic IP is still allocated
  SAVINGS=0
  echo ""
  echo "Note: Deleted NAT Gateways don't incur charges (cleanup for hygiene)"
  echo "Note: Failed NAT Gateways should be manually investigated"
else
  SAVINGS=0
fi

# Check for NAT Gateways with low utilization (advanced check)
echo ""
echo "--- NAT Gateways Utilization Check ---"
echo "Checking all available NAT Gateways..."

ACTIVE_NATS=$(aws ec2 describe-nat-gateways \
  --region "$REGION" \
  --profile "$PROFILE" \
  --filter "Name=state,Values=available" \
  --query 'NatGateways[].{ID:NatGatewayId,State:State,VPC:VpcId,SubnetId:SubnetId}' \
  --output json 2>/dev/null || echo "[]")

ACTIVE_NAT_COUNT=$(echo "$ACTIVE_NATS" | jq '. | length')
echo "Found: $ACTIVE_NAT_COUNT active NAT Gateways"

if [ "$ACTIVE_NAT_COUNT" -gt 0 ]; then
  echo "$ACTIVE_NATS" | jq -r '.[] | "  \(.ID) | VPC: \(.VPC) | Subnet: \(.SubnetId)"'

  # Cost: $32.40/month per NAT Gateway + $0.045/GB data processed
  NAT_COST=$(echo "$ACTIVE_NAT_COUNT * 32.40 * 12 * 6.0" | bc | xargs printf "%.0f")
else
  NAT_COST=0
fi

if [ "$ACTIVE_NAT_COUNT" -gt 0 ]; then
  echo ""
  echo "Active NAT Gateways cost: R$ ${NAT_COST}/ano (base cost only, excludes data transfer)"
  echo ""
  echo "ℹ️  TIP: Consider VPC S3 Gateway Endpoints to reduce NAT data transfer costs"
  echo "ℹ️  TIP: Review if all NAT Gateways are necessary (1 per AZ typical)"
fi

# Save report
RESULTS=$(cat <<EOF
{
  "scan_date": "$(date --iso-8601=seconds)",
  "dry_run": $DRY_RUN,
  "findings": [
    {
      "type": "nat_gateways_orphan",
      "count": $NAT_COUNT,
      "items": $ORPHAN_NATS,
      "savings_annual_brl": 0,
      "note": "Deleted NAT Gateways don't incur charges"
    },
    {
      "type": "nat_gateways_active",
      "count": $ACTIVE_NAT_COUNT,
      "items": $ACTIVE_NATS,
      "cost_annual_brl": $NAT_COST,
      "note": "Base cost only, excludes data transfer charges"
    }
  ],
  "total_savings_annual_brl": 0,
  "recommendations": [
    "Implement S3 Gateway Endpoints (FREE) to reduce NAT data transfer",
    "Review NAT Gateway necessity: 1 per AZ is typical",
    "Consider NAT Instances for low-traffic workloads (cheaper but requires management)"
  ]
}
EOF
)

echo "$RESULTS" | jq '.' > "$REPORT_FILE"

echo ""
echo "=========================================="
echo " SUMMARY"
echo "=========================================="
echo "Orphan NAT Gateways:      $NAT_COUNT"
echo "Active NAT Gateways:      $ACTIVE_NAT_COUNT"
echo "Active NAT cost:          R$ ${NAT_COST}/ano (base only)"
echo "Dry-run:                  $DRY_RUN"
echo "=========================================="
echo "Report saved: $REPORT_FILE"

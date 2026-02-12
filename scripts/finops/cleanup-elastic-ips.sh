#!/bin/bash
# scripts/finops/cleanup-elastic-ips.sh
#
# Scan and optionally release unattached Elastic IPs
# Cost: $3.60/month per unattached IP
#
# Usage:
#   DRY_RUN=true  bash scripts/finops/cleanup-elastic-ips.sh   # scan only (default)
#   DRY_RUN=false bash scripts/finops/cleanup-elastic-ips.sh   # release IPs
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
REPORT_FILE="$REPORT_DIR/cleanup-elastic-ips-$(date +%Y-%m-%d).json"

mkdir -p "$REPORT_DIR"

echo "=========================================="
echo " FinOps Cleanup — Elastic IPs"
echo "=========================================="
echo "Region:   $REGION"
echo "Profile:  $PROFILE"
echo "Dry-run:  $DRY_RUN"
echo "Date:     $(date --iso-8601=seconds)"
echo "=========================================="

# Unattached Elastic IPs
UNATTACHED_IPS=$(aws ec2 describe-addresses \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'Addresses[?AssociationId==null].{IP:PublicIp,AllocationId:AllocationId,Domain:Domain}' \
  --output json 2>/dev/null || echo "[]")

IP_COUNT=$(echo "$UNATTACHED_IPS" | jq '. | length')

echo ""
echo "--- Unattached Elastic IPs ---"
echo "Found: $IP_COUNT unattached Elastic IPs"

if [ "$IP_COUNT" -gt 0 ]; then
  echo "$UNATTACHED_IPS" | jq -r '.[] | "  \(.IP) | \(.AllocationId) | \(.Domain)"'

  # Cost: $3.60/month per IP (VPC), $0/month if attached
  SAVINGS=$(echo "$IP_COUNT * 3.60 * 12 * 6.0" | bc | xargs printf "%.0f")
  echo ""
  echo "Estimated savings: R$ ${SAVINGS}/ano"
  echo "Monthly savings:   R$ $((SAVINGS / 12))/mês"

  if [ "$DRY_RUN" = "false" ]; then
    echo ""
    echo "⚠️  WARNING: Releasing Elastic IPs is IRREVERSIBLE!"
    echo "⚠️  These IP addresses will be returned to AWS pool."
    echo ""
    read -p "Type 'RELEASE' to confirm: " CONFIRM

    if [ "$CONFIRM" = "RELEASE" ]; then
      echo "$UNATTACHED_IPS" | jq -r '.[].AllocationId' | while read -r ALLOC_ID; do
        echo "  Releasing: $ALLOC_ID"
        aws ec2 release-address \
          --allocation-id "$ALLOC_ID" \
          --region "$REGION" \
          --profile "$PROFILE" || echo "  WARN: Failed to release $ALLOC_ID"
      done
      echo "Released $IP_COUNT Elastic IPs"
    else
      echo "Aborted. No IPs released."
    fi
  fi
else
  SAVINGS=0
fi

# Save report
RESULTS=$(cat <<EOF
{
  "scan_date": "$(date --iso-8601=seconds)",
  "dry_run": $DRY_RUN,
  "findings": [
    {
      "type": "elastic_ips_unattached",
      "count": $IP_COUNT,
      "items": $UNATTACHED_IPS,
      "savings_annual_brl": $SAVINGS
    }
  ],
  "total_savings_annual_brl": $SAVINGS
}
EOF
)

echo "$RESULTS" | jq '.' > "$REPORT_FILE"

echo ""
echo "=========================================="
echo " SUMMARY"
echo "=========================================="
echo "Unattached Elastic IPs:   $IP_COUNT"
echo "Total estimated savings:  R$ ${SAVINGS}/ano"
echo "Dry-run:                  $DRY_RUN"
echo "=========================================="
echo "Report saved: $REPORT_FILE"

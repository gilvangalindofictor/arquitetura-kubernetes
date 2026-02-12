#!/bin/bash
# scripts/finops/cleanup-cloudwatch-logs.sh
#
# Scan CloudWatch Log Groups for:
#   - Log groups without retention policy (infinite retention)
#   - Large log groups (>5GB) candidates for archival
#   - Empty log groups (0 bytes)
#
# Cost: $0.50/GB stored + $0.03/GB ingested
#
# Usage:
#   DRY_RUN=true  bash scripts/finops/cleanup-cloudwatch-logs.sh   # scan only (default)
#   DRY_RUN=false bash scripts/finops/cleanup-cloudwatch-logs.sh   # set policies
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
REPORT_FILE="$REPORT_DIR/cleanup-cloudwatch-logs-$(date +%Y-%m-%d).json"

mkdir -p "$REPORT_DIR"

echo "=========================================="
echo " FinOps Cleanup — CloudWatch Logs"
echo "=========================================="
echo "Region:   $REGION"
echo "Profile:  $PROFILE"
echo "Dry-run:  $DRY_RUN"
echo "Date:     $(date --iso-8601=seconds)"
echo "=========================================="

# Get all log groups
ALL_LOGS=$(aws logs describe-log-groups \
  --region "$REGION" \
  --profile "$PROFILE" \
  --output json 2>/dev/null || echo '{"logGroups":[]}')

TOTAL_COUNT=$(echo "$ALL_LOGS" | jq '.logGroups | length')
echo ""
echo "Total Log Groups: $TOTAL_COUNT"

# --- 1. Log Groups without retention policy ---
echo ""
echo "--- [1/4] Log Groups Without Retention Policy ---"

NO_RETENTION=$(echo "$ALL_LOGS" | jq '[.logGroups[] | select(.retentionInDays == null) | {
  name: .logGroupName,
  size_gb: ((.storedBytes // 0) / 1073741824 | floor * 100 / 100),
  created: (.creationTime / 1000 | todate)
}]')

NO_RETENTION_COUNT=$(echo "$NO_RETENTION" | jq '. | length')
echo "Found: $NO_RETENTION_COUNT log groups with infinite retention"

if [ "$NO_RETENTION_COUNT" -gt 0 ]; then
  echo "$NO_RETENTION" | jq -r '.[] | "  \(.name) | \(.size_gb)GB | created: \(.created)"' | head -20

  if [ "$NO_RETENTION_COUNT" -gt 20 ]; then
    echo "  ... and $((NO_RETENTION_COUNT - 20)) more"
  fi

  TOTAL_SIZE_GB=$(echo "$NO_RETENTION" | jq '[.[].size_gb] | add // 0')
  SAVINGS=$(echo "$TOTAL_SIZE_GB * 0.50 * 12 * 6.0 * 0.5" | bc | xargs printf "%.0f")

  echo ""
  echo "Total size: ${TOTAL_SIZE_GB} GB"
  echo "Estimated savings (50% reduction with 30d retention): R$ ${SAVINGS}/ano"

  if [ "$DRY_RUN" = "false" ]; then
    echo ""
    echo "Setting 30-day retention policy..."
    echo "$NO_RETENTION" | jq -r '.[].name' | while read -r LOG_GROUP; do
      echo "  Setting retention: $LOG_GROUP"
      aws logs put-retention-policy \
        --log-group-name "$LOG_GROUP" \
        --retention-in-days 30 \
        --region "$REGION" \
        --profile "$PROFILE" 2>/dev/null || echo "  WARN: Failed to set retention for $LOG_GROUP"
    done
  fi
else
  SAVINGS=0
fi

SAVINGS_NO_RETENTION=$SAVINGS

# --- 2. Large log groups (>5GB) ---
echo ""
echo "--- [2/4] Large Log Groups (>5GB) ---"

LARGE_LOGS=$(echo "$ALL_LOGS" | jq '[.logGroups[] | select(.storedBytes > 5368709120) | {
  name: .logGroupName,
  size_gb: (.storedBytes / 1073741824 | floor),
  retention: .retentionInDays
}]')

LARGE_COUNT=$(echo "$LARGE_LOGS" | jq '. | length')
echo "Found: $LARGE_COUNT log groups >5GB"

if [ "$LARGE_COUNT" -gt 0 ]; then
  echo "$LARGE_LOGS" | jq -r '.[] | "  \(.name) | \(.size_gb)GB | retention: \(.retention // "infinite")d"'

  LARGE_SIZE_GB=$(echo "$LARGE_LOGS" | jq '[.[].size_gb] | add // 0')
  LARGE_COST=$(echo "$LARGE_SIZE_GB * 0.50 * 12 * 6.0" | bc | xargs printf "%.0f")

  echo ""
  echo "Total size: ${LARGE_SIZE_GB} GB"
  echo "Annual cost: R$ ${LARGE_COST}/ano"
  echo ""
  echo "ℹ️  TIP: Consider exporting to S3 ($0.023/GB) or S3 Glacier ($0.004/GB)"
fi

# --- 3. Empty log groups ---
echo ""
echo "--- [3/4] Empty Log Groups (0 bytes) ---"

EMPTY_LOGS=$(echo "$ALL_LOGS" | jq '[.logGroups[] | select(.storedBytes == 0 or .storedBytes == null) | {
  name: .logGroupName,
  created: (.creationTime / 1000 | todate)
}]')

EMPTY_COUNT=$(echo "$EMPTY_LOGS" | jq '. | length')
echo "Found: $EMPTY_COUNT empty log groups"

if [ "$EMPTY_COUNT" -gt 0 ]; then
  echo "$EMPTY_LOGS" | jq -r '.[].name' | head -20

  if [ "$EMPTY_COUNT" -gt 20 ]; then
    echo "  ... and $((EMPTY_COUNT - 20)) more"
  fi

  echo ""
  echo "ℹ️  TIP: Empty log groups can be safely deleted (no cost but clutter)"

  if [ "$DRY_RUN" = "false" ]; then
    echo ""
    read -p "Delete empty log groups? (yes/no): " CONFIRM

    if [ "$CONFIRM" = "yes" ]; then
      echo "$EMPTY_LOGS" | jq -r '.[].name' | while read -r LOG_GROUP; do
        echo "  Deleting: $LOG_GROUP"
        aws logs delete-log-group \
          --log-group-name "$LOG_GROUP" \
          --region "$REGION" \
          --profile "$PROFILE" 2>/dev/null || echo "  WARN: Failed to delete $LOG_GROUP"
      done
    fi
  fi
fi

# --- 4. Total storage summary ---
echo ""
echo "--- [4/4] Storage Summary ---"

TOTAL_SIZE_BYTES=$(echo "$ALL_LOGS" | jq '[.logGroups[].storedBytes // 0] | add')
TOTAL_SIZE_GB=$(echo "scale=2; $TOTAL_SIZE_BYTES / 1073741824" | bc)
TOTAL_COST=$(echo "$TOTAL_SIZE_GB * 0.50 * 12 * 6.0" | bc | xargs printf "%.0f")

echo "Total CloudWatch Logs storage: ${TOTAL_SIZE_GB} GB"
echo "Annual storage cost: R$ ${TOTAL_COST}/ano"

# Save report
RESULTS=$(cat <<EOF
{
  "scan_date": "$(date --iso-8601=seconds)",
  "dry_run": $DRY_RUN,
  "summary": {
    "total_log_groups": $TOTAL_COUNT,
    "total_size_gb": $TOTAL_SIZE_GB,
    "annual_cost_brl": $TOTAL_COST
  },
  "findings": [
    {
      "type": "no_retention_policy",
      "count": $NO_RETENTION_COUNT,
      "items": $NO_RETENTION,
      "savings_annual_brl": $SAVINGS_NO_RETENTION
    },
    {
      "type": "large_log_groups",
      "count": $LARGE_COUNT,
      "items": $LARGE_LOGS,
      "note": "Consider S3 archival"
    },
    {
      "type": "empty_log_groups",
      "count": $EMPTY_COUNT,
      "items": $EMPTY_LOGS,
      "note": "Can be safely deleted"
    }
  ],
  "total_savings_annual_brl": $SAVINGS_NO_RETENTION,
  "recommendations": [
    "Set 30-day retention policy for log groups without retention",
    "Export large log groups (>5GB) to S3 for archival",
    "Delete empty log groups (hygiene)",
    "Use S3 Lifecycle policies to move to Glacier after 90 days"
  ]
}
EOF
)

echo "$RESULTS" | jq '.' > "$REPORT_FILE"

echo ""
echo "=========================================="
echo " SUMMARY"
echo "=========================================="
echo "Total log groups:         $TOTAL_COUNT"
echo "Without retention:        $NO_RETENTION_COUNT"
echo "Large (>5GB):             $LARGE_COUNT"
echo "Empty:                    $EMPTY_COUNT"
echo "Total storage:            ${TOTAL_SIZE_GB} GB"
echo "Annual cost:              R$ ${TOTAL_COST}/ano"
echo "Estimated savings:        R$ ${SAVINGS_NO_RETENTION}/ano"
echo "Dry-run:                  $DRY_RUN"
echo "=========================================="
echo "Report saved: $REPORT_FILE"

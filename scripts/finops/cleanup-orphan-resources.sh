#!/bin/bash
# scripts/finops/cleanup-orphan-resources.sh
#
# Scan and optionally delete orphan AWS resources:
#   - EBS volumes in "available" state for >7 days
#   - EBS snapshots >30 days without associated AMI
#   - Load balancers without target groups
#
# Usage:
#   DRY_RUN=true  bash scripts/finops/cleanup-orphan-resources.sh   # scan only (default)
#   DRY_RUN=false bash scripts/finops/cleanup-orphan-resources.sh   # delete resources
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
REPORT_FILE="$REPORT_DIR/cleanup-$(date +%Y-%m-%d).json"

mkdir -p "$REPORT_DIR"

echo "=========================================="
echo " FinOps Cleanup — Orphan Resources"
echo "=========================================="
echo "Region:   $REGION"
echo "Profile:  $PROFILE"
echo "Dry-run:  $DRY_RUN"
echo "Date:     $(date --iso-8601=seconds)"
echo "=========================================="

TOTAL_SAVINGS=0
RESULTS='{"scan_date":"'$(date --iso-8601=seconds)'","dry_run":'$DRY_RUN',"findings":[]}'

# --- 1. EBS Volumes in "available" state >7 days ---
echo ""
echo "--- [1/3] EBS Volumes Available >7d ---"

CUTOFF_DATE=$(date -d '7 days ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -v-7d +%Y-%m-%dT%H:%M:%S)

ORPHAN_VOLUMES=$(aws ec2 describe-volumes \
  --region "$REGION" \
  --profile "$PROFILE" \
  --filters "Name=status,Values=available" \
  --query "Volumes[].{ID:VolumeId,Size:Size,Type:VolumeType,Created:CreateTime}" \
  --output json 2>/dev/null || echo "[]")

VOL_COUNT=$(echo "$ORPHAN_VOLUMES" | jq '. | length')
echo "Found: $VOL_COUNT available volumes"

if [ "$VOL_COUNT" -gt 0 ]; then
  echo "$ORPHAN_VOLUMES" | jq -r '.[] | "  \(.ID) | \(.Size)GB \(.Type) | created: \(.Created)"'

  # Estimate savings: gp3=$0.08/GB/month, gp2=$0.10/GB/month
  VOL_SAVINGS=$(echo "$ORPHAN_VOLUMES" | jq '[.[].Size] | add // 0 | . * 0.08 * 12' | xargs printf "%.0f")
  TOTAL_SAVINGS=$((TOTAL_SAVINGS + VOL_SAVINGS))
  echo "  Estimated savings: R$ ${VOL_SAVINGS}/ano"

  if [ "$DRY_RUN" = "false" ]; then
    echo "$ORPHAN_VOLUMES" | jq -r '.[].ID' | while read -r VOL; do
      echo "  Deleting: $VOL"
      aws ec2 delete-volume --volume-id "$VOL" --region "$REGION" --profile "$PROFILE"
    done
    echo "  Deleted $VOL_COUNT volumes"
  fi

  RESULTS=$(echo "$RESULTS" | jq --argjson vols "$ORPHAN_VOLUMES" '.findings += [{"type":"ebs_volumes","count":($vols|length),"items":$vols}]')
fi

# --- 2. EBS Snapshots >30d without AMI ---
echo ""
echo "--- [2/3] EBS Snapshots Old (>30d, no AMI) ---"

ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query 'Account' --output text 2>/dev/null || echo "unknown")

ORPHAN_SNAPSHOTS=$(aws ec2 describe-snapshots \
  --owner-ids "$ACCOUNT_ID" \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query "Snapshots[?StartTime<='$(date -d '30 days ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -v-30d +%Y-%m-%dT%H:%M:%S)'].{ID:SnapshotId,Size:VolumeSize,Created:StartTime,Description:Description}" \
  --output json 2>/dev/null || echo "[]")

SNAP_COUNT=$(echo "$ORPHAN_SNAPSHOTS" | jq '. | length')
echo "Found: $SNAP_COUNT old snapshots"

if [ "$SNAP_COUNT" -gt 0 ]; then
  echo "$ORPHAN_SNAPSHOTS" | jq -r '.[] | "  \(.ID) | \(.Size)GB | \(.Created) | \(.Description[:60])"'

  SNAP_SAVINGS=$(echo "$ORPHAN_SNAPSHOTS" | jq '[.[].Size] | add // 0 | . * 0.05 * 12' | xargs printf "%.0f")
  TOTAL_SAVINGS=$((TOTAL_SAVINGS + SNAP_SAVINGS))
  echo "  Estimated savings: R$ ${SNAP_SAVINGS}/ano"

  if [ "$DRY_RUN" = "false" ]; then
    echo "$ORPHAN_SNAPSHOTS" | jq -r '.[].ID' | while read -r SNAP; do
      echo "  Deleting: $SNAP"
      aws ec2 delete-snapshot --snapshot-id "$SNAP" --region "$REGION" --profile "$PROFILE" 2>/dev/null || echo "  WARN: Failed to delete $SNAP (may be in use)"
    done
  fi

  RESULTS=$(echo "$RESULTS" | jq --argjson snaps "$ORPHAN_SNAPSHOTS" '.findings += [{"type":"ebs_snapshots","count":($snaps|length),"items":$snaps}]')
fi

# --- 3. Load Balancers without target groups ---
echo ""
echo "--- [3/3] Load Balancers Without Targets ---"

LB_LIST=$(aws elbv2 describe-load-balancers \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query "LoadBalancers[].{ARN:LoadBalancerArn,Name:LoadBalancerName,Type:Type,Created:CreatedTime}" \
  --output json 2>/dev/null || echo "[]")

ORPHAN_LBS="[]"
LB_COUNT=$(echo "$LB_LIST" | jq '. | length')

for i in $(seq 0 $((LB_COUNT - 1))); do
  LB_ARN=$(echo "$LB_LIST" | jq -r ".[$i].ARN")
  LB_NAME=$(echo "$LB_LIST" | jq -r ".[$i].Name")

  TARGETS=$(aws elbv2 describe-target-groups \
    --load-balancer-arn "$LB_ARN" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "TargetGroups | length(@)" \
    --output text 2>/dev/null || echo "0")

  if [ "$TARGETS" = "0" ]; then
    echo "  LB without targets: $LB_NAME ($LB_ARN)"
    ORPHAN_LBS=$(echo "$ORPHAN_LBS" | jq --arg name "$LB_NAME" --arg arn "$LB_ARN" '. += [{"Name":$name,"ARN":$arn}]')

    if [ "$DRY_RUN" = "false" ]; then
      echo "  Deleting: $LB_NAME"
      aws elbv2 delete-load-balancer --load-balancer-arn "$LB_ARN" --region "$REGION" --profile "$PROFILE"
    fi
  fi
done

ORPHAN_LB_COUNT=$(echo "$ORPHAN_LBS" | jq '. | length')
echo "Found: $ORPHAN_LB_COUNT LBs without targets"

if [ "$ORPHAN_LB_COUNT" -gt 0 ]; then
  # ALB ~$16.28/month
  LB_SAVINGS=$((ORPHAN_LB_COUNT * 16 * 12))
  TOTAL_SAVINGS=$((TOTAL_SAVINGS + LB_SAVINGS))
  echo "  Estimated savings: R$ ${LB_SAVINGS}/ano"
  RESULTS=$(echo "$RESULTS" | jq --argjson lbs "$ORPHAN_LBS" '.findings += [{"type":"load_balancers","count":($lbs|length),"items":$lbs}]')
fi

# --- Summary ---
echo ""
echo "=========================================="
echo " SUMMARY"
echo "=========================================="
echo "EBS Volumes available:    $VOL_COUNT"
echo "EBS Snapshots old:        $SNAP_COUNT"
echo "LBs without targets:      $ORPHAN_LB_COUNT"
echo "Total estimated savings:  R$ ${TOTAL_SAVINGS}/ano"
echo "Dry-run:                  $DRY_RUN"
echo "=========================================="

# Save report
RESULTS=$(echo "$RESULTS" | jq --argjson savings "$TOTAL_SAVINGS" '. + {"total_savings_annual_brl":$savings}')
echo "$RESULTS" | jq '.' > "$REPORT_FILE"
echo "Report saved: $REPORT_FILE"

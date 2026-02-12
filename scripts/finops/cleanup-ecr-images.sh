#!/bin/bash
# scripts/finops/cleanup-ecr-images.sh
#
# Scan ECR repositories for:
#   - Untagged images (build artifacts, old layers)
#   - Old images (>90 days)
#   - Large repositories (>10GB)
#
# Cost: $0.10/GB per month
#
# Usage:
#   DRY_RUN=true  bash scripts/finops/cleanup-ecr-images.sh   # scan only (default)
#   DRY_RUN=false bash scripts/finops/cleanup-ecr-images.sh   # delete images
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
REPORT_FILE="$REPORT_DIR/cleanup-ecr-images-$(date +%Y-%m-%d).json"

mkdir -p "$REPORT_DIR"

echo "=========================================="
echo " FinOps Cleanup — ECR Images"
echo "=========================================="
echo "Region:   $REGION"
echo "Profile:  $PROFILE"
echo "Dry-run:  $DRY_RUN"
echo "Date:     $(date --iso-8601=seconds)"
echo "=========================================="

# Get all ECR repositories
REPOS=$(aws ecr describe-repositories \
  --region "$REGION" \
  --profile "$PROFILE" \
  --output json 2>/dev/null || echo '{"repositories":[]}')

REPO_COUNT=$(echo "$REPOS" | jq '.repositories | length')
echo ""
echo "Total ECR Repositories: $REPO_COUNT"

if [ "$REPO_COUNT" -eq 0 ]; then
  echo "No ECR repositories found. Exiting."
  exit 0
fi

TOTAL_UNTAGGED=0
TOTAL_OLD=0
TOTAL_SIZE_GB=0
FINDINGS="[]"

# Iterate through each repository
echo "$REPOS" | jq -r '.repositories[].repositoryName' | while read -r REPO; do
  echo ""
  echo "--- Repository: $REPO ---"

  # Get all images in repository
  IMAGES=$(aws ecr describe-images \
    --repository-name "$REPO" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --output json 2>/dev/null || echo '{"imageDetails":[]}')

  IMAGE_COUNT=$(echo "$IMAGES" | jq '.imageDetails | length')
  echo "  Total images: $IMAGE_COUNT"

  if [ "$IMAGE_COUNT" -eq 0 ]; then
    continue
  fi

  # Untagged images
  UNTAGGED=$(echo "$IMAGES" | jq '[.imageDetails[] | select(.imageTags == null or .imageTags == [])]')
  UNTAGGED_COUNT=$(echo "$UNTAGGED" | jq '. | length')

  if [ "$UNTAGGED_COUNT" -gt 0 ]; then
    TOTAL_UNTAGGED=$((TOTAL_UNTAGGED + UNTAGGED_COUNT))
    echo "  Untagged images: $UNTAGGED_COUNT"

    UNTAGGED_SIZE=$(echo "$UNTAGGED" | jq '[.[].imageSizeInBytes // 0] | add // 0')
    UNTAGGED_SIZE_GB=$(echo "scale=2; $UNTAGGED_SIZE / 1073741824" | bc)
    echo "  Untagged size: ${UNTAGGED_SIZE_GB} GB"

    TOTAL_SIZE_GB=$(echo "$TOTAL_SIZE_GB + $UNTAGGED_SIZE_GB" | bc)

    if [ "$DRY_RUN" = "false" ]; then
      echo "  Deleting untagged images..."
      echo "$UNTAGGED" | jq -r '.[].imageDigest' | while read -r DIGEST; do
        aws ecr batch-delete-image \
          --repository-name "$REPO" \
          --image-ids "imageDigest=$DIGEST" \
          --region "$REGION" \
          --profile "$PROFILE" >/dev/null 2>&1 || echo "    WARN: Failed to delete $DIGEST"
      done
    fi
  fi

  # Old images (>90 days)
  CUTOFF_DATE=$(date -d '90 days ago' +%s 2>/dev/null || date -v-90d +%s)
  OLD=$(echo "$IMAGES" | jq --argjson cutoff "$CUTOFF_DATE" '[.imageDetails[] | select(.imagePushedAt < $cutoff)]')
  OLD_COUNT=$(echo "$OLD" | jq '. | length')

  if [ "$OLD_COUNT" -gt 0 ]; then
    TOTAL_OLD=$((TOTAL_OLD + OLD_COUNT))
    echo "  Old images (>90d): $OLD_COUNT"
  fi

  # Repository total size
  REPO_SIZE=$(echo "$IMAGES" | jq '[.imageDetails[].imageSizeInBytes // 0] | add // 0')
  REPO_SIZE_GB=$(echo "scale=2; $REPO_SIZE / 1073741824" | bc)
  echo "  Repository size: ${REPO_SIZE_GB} GB"

done

# Calculate savings
SAVINGS=$(echo "$TOTAL_SIZE_GB * 0.10 * 12 * 6.0" | bc | xargs printf "%.0f")
TOTAL_COST=$(echo "$TOTAL_SIZE_GB * 0.10 * 12 * 6.0" | bc | xargs printf "%.0f")

# Save report
RESULTS=$(cat <<EOF
{
  "scan_date": "$(date --iso-8601=seconds)",
  "dry_run": $DRY_RUN,
  "summary": {
    "total_repositories": $REPO_COUNT,
    "total_untagged_images": $TOTAL_UNTAGGED,
    "total_old_images": $TOTAL_OLD,
    "untagged_size_gb": $TOTAL_SIZE_GB
  },
  "findings": [
    {
      "type": "untagged_images",
      "count": $TOTAL_UNTAGGED,
      "size_gb": $TOTAL_SIZE_GB,
      "savings_annual_brl": $SAVINGS
    }
  ],
  "total_savings_annual_brl": $SAVINGS,
  "recommendations": [
    "Implement ECR Lifecycle Policies to auto-delete untagged images after 7 days",
    "Keep only last 10 tagged images per repository",
    "Use image scanning to identify vulnerabilities before cleanup"
  ]
}
EOF
)

echo "$RESULTS" | jq '.' > "$REPORT_FILE"

echo ""
echo "=========================================="
echo " SUMMARY"
echo "=========================================="
echo "Total repositories:       $REPO_COUNT"
echo "Untagged images:          $TOTAL_UNTAGGED"
echo "Old images (>90d):        $TOTAL_OLD"
echo "Untagged size:            ${TOTAL_SIZE_GB} GB"
echo "Estimated savings:        R$ ${SAVINGS}/ano"
echo "Dry-run:                  $DRY_RUN"
echo "=========================================="
echo "Report saved: $REPORT_FILE"
echo ""
echo "ℹ️  TIP: Implement ECR Lifecycle Policies for automatic cleanup"
echo "ℹ️  Example: aws ecr put-lifecycle-policy --repository-name <repo>"

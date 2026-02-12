#!/bin/bash
# scripts/finops/apply-tags.sh
#
# Apply mandatory tags to all AWS resources that support tagging.
# Tags ensure cost allocation, ownership tracking, and compliance.
#
# Mandatory tags (per ADR-022):
#   - Environment: staging|production
#   - ManagedBy: Terraform
#   - Project: K8s-Platform
#   - CostCenter: Engineering
#   - Owner: Platform-Team
#
# Usage:
#   DRY_RUN=true  bash scripts/finops/apply-tags.sh   # scan only (default)
#   DRY_RUN=false bash scripts/finops/apply-tags.sh   # apply tags
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
ENVIRONMENT="${ENVIRONMENT:-staging}"
TAGGED=0
SKIPPED=0
ERRORS=0

TAGS="Key=Environment,Value=${ENVIRONMENT} Key=ManagedBy,Value=Terraform Key=Project,Value=K8s-Platform Key=CostCenter,Value=Engineering Key=Owner,Value=Platform-Team"

echo "=========================================="
echo " FinOps — Resource Tagging"
echo "=========================================="
echo "Region:      $REGION"
echo "Profile:     $PROFILE"
echo "Environment: $ENVIRONMENT"
echo "Dry-run:     $DRY_RUN"
echo "=========================================="

tag_resource() {
  local RESOURCE_TYPE="$1"
  local RESOURCE_ID="$2"

  if [ "$DRY_RUN" = "true" ]; then
    echo "  [DRY-RUN] Would tag: $RESOURCE_TYPE $RESOURCE_ID"
    TAGGED=$((TAGGED + 1))
  else
    if aws ec2 create-tags \
      --resources "$RESOURCE_ID" \
      --region "$REGION" \
      --profile "$PROFILE" \
      --tags $TAGS 2>/dev/null; then
      echo "  Tagged: $RESOURCE_TYPE $RESOURCE_ID"
      TAGGED=$((TAGGED + 1))
    else
      echo "  ERROR: Failed to tag $RESOURCE_TYPE $RESOURCE_ID"
      ERRORS=$((ERRORS + 1))
    fi
  fi
}

# --- 1. EBS Volumes ---
echo ""
echo "--- [1/5] EBS Volumes ---"

VOLUMES=$(aws ec2 describe-volumes \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query "Volumes[].VolumeId" \
  --output text 2>/dev/null || echo "")

if [ -n "$VOLUMES" ]; then
  for VOL in $VOLUMES; do
    # Check if already tagged
    HAS_ENV=$(aws ec2 describe-tags \
      --region "$REGION" \
      --profile "$PROFILE" \
      --filters "Name=resource-id,Values=$VOL" "Name=key,Values=Environment" \
      --query "Tags | length(@)" \
      --output text 2>/dev/null || echo "0")

    if [ "$HAS_ENV" = "0" ]; then
      tag_resource "EBS" "$VOL"
    else
      SKIPPED=$((SKIPPED + 1))
    fi
  done
else
  echo "  No volumes found"
fi

# --- 2. EC2 Instances (EKS Nodes) ---
echo ""
echo "--- [2/5] EC2 Instances ---"

INSTANCES=$(aws ec2 describe-instances \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text 2>/dev/null || echo "")

if [ -n "$INSTANCES" ]; then
  for INST in $INSTANCES; do
    HAS_ENV=$(aws ec2 describe-tags \
      --region "$REGION" \
      --profile "$PROFILE" \
      --filters "Name=resource-id,Values=$INST" "Name=key,Values=CostCenter" \
      --query "Tags | length(@)" \
      --output text 2>/dev/null || echo "0")

    if [ "$HAS_ENV" = "0" ]; then
      tag_resource "EC2" "$INST"
    else
      SKIPPED=$((SKIPPED + 1))
    fi
  done
else
  echo "  No instances found"
fi

# --- 3. EKS Node Groups ---
echo ""
echo "--- [3/5] EKS Node Groups ---"

CLUSTER_NAME="k8s-platform-prod"

NODEGROUPS=$(aws eks list-nodegroups \
  --cluster-name "$CLUSTER_NAME" \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query "nodegroups[]" \
  --output text 2>/dev/null || echo "")

if [ -n "$NODEGROUPS" ]; then
  for NG in $NODEGROUPS; do
    NG_ARN=$(aws eks describe-nodegroup \
      --cluster-name "$CLUSTER_NAME" \
      --nodegroup-name "$NG" \
      --region "$REGION" \
      --profile "$PROFILE" \
      --query "nodegroup.nodegroupArn" \
      --output text 2>/dev/null || echo "")

    if [ -n "$NG_ARN" ] && [ "$NG_ARN" != "None" ]; then
      if [ "$DRY_RUN" = "true" ]; then
        echo "  [DRY-RUN] Would tag: EKS-NodeGroup $NG"
        TAGGED=$((TAGGED + 1))
      else
        if aws eks tag-resource \
          --resource-arn "$NG_ARN" \
          --tags "Environment=${ENVIRONMENT},ManagedBy=Terraform,Project=K8s-Platform,CostCenter=Engineering,Owner=Platform-Team" \
          --region "$REGION" \
          --profile "$PROFILE" 2>/dev/null; then
          echo "  Tagged: EKS-NodeGroup $NG"
          TAGGED=$((TAGGED + 1))
        else
          echo "  ERROR: Failed to tag EKS-NodeGroup $NG"
          ERRORS=$((ERRORS + 1))
        fi
      fi
    fi
  done
else
  echo "  No node groups found"
fi

# --- 4. RDS Instances ---
echo ""
echo "--- [4/5] RDS Instances ---"

RDS_ARNS=$(aws rds describe-db-instances \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query "DBInstances[].DBInstanceArn" \
  --output text 2>/dev/null || echo "")

if [ -n "$RDS_ARNS" ]; then
  for RDS_ARN in $RDS_ARNS; do
    RDS_NAME=$(echo "$RDS_ARN" | awk -F: '{print $NF}')

    HAS_TAG=$(aws rds list-tags-for-resource \
      --resource-name "$RDS_ARN" \
      --region "$REGION" \
      --profile "$PROFILE" \
      --query "TagList[?Key=='CostCenter'] | length(@)" \
      --output text 2>/dev/null || echo "0")

    if [ "$HAS_TAG" = "0" ]; then
      if [ "$DRY_RUN" = "true" ]; then
        echo "  [DRY-RUN] Would tag: RDS $RDS_NAME"
        TAGGED=$((TAGGED + 1))
      else
        if aws rds add-tags-to-resource \
          --resource-name "$RDS_ARN" \
          --region "$REGION" \
          --profile "$PROFILE" \
          --tags "Key=Environment,Value=${ENVIRONMENT}" "Key=ManagedBy,Value=Terraform" "Key=Project,Value=K8s-Platform" "Key=CostCenter,Value=Engineering" "Key=Owner,Value=Platform-Team" 2>/dev/null; then
          echo "  Tagged: RDS $RDS_NAME"
          TAGGED=$((TAGGED + 1))
        else
          echo "  ERROR: Failed to tag RDS $RDS_NAME"
          ERRORS=$((ERRORS + 1))
        fi
      fi
    else
      SKIPPED=$((SKIPPED + 1))
    fi
  done
else
  echo "  No RDS instances found"
fi

# --- 5. Load Balancers ---
echo ""
echo "--- [5/5] Load Balancers ---"

LB_ARNS=$(aws elbv2 describe-load-balancers \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query "LoadBalancers[].LoadBalancerArn" \
  --output text 2>/dev/null || echo "")

if [ -n "$LB_ARNS" ]; then
  for LB_ARN in $LB_ARNS; do
    LB_NAME=$(aws elbv2 describe-load-balancers \
      --load-balancer-arns "$LB_ARN" \
      --region "$REGION" \
      --profile "$PROFILE" \
      --query "LoadBalancers[0].LoadBalancerName" \
      --output text 2>/dev/null || echo "unknown")

    HAS_TAG=$(aws elbv2 describe-tags \
      --resource-arns "$LB_ARN" \
      --region "$REGION" \
      --profile "$PROFILE" \
      --query "TagDescriptions[0].Tags[?Key=='CostCenter'] | length(@)" \
      --output text 2>/dev/null || echo "0")

    if [ "$HAS_TAG" = "0" ]; then
      if [ "$DRY_RUN" = "true" ]; then
        echo "  [DRY-RUN] Would tag: ALB $LB_NAME"
        TAGGED=$((TAGGED + 1))
      else
        if aws elbv2 add-tags \
          --resource-arns "$LB_ARN" \
          --region "$REGION" \
          --profile "$PROFILE" \
          --tags "Key=Environment,Value=${ENVIRONMENT}" "Key=ManagedBy,Value=Terraform" "Key=Project,Value=K8s-Platform" "Key=CostCenter,Value=Engineering" "Key=Owner,Value=Platform-Team" 2>/dev/null; then
          echo "  Tagged: ALB $LB_NAME"
          TAGGED=$((TAGGED + 1))
        else
          echo "  ERROR: Failed to tag ALB $LB_NAME"
          ERRORS=$((ERRORS + 1))
        fi
      fi
    else
      SKIPPED=$((SKIPPED + 1))
    fi
  done
else
  echo "  No load balancers found"
fi

# --- Summary ---
echo ""
echo "=========================================="
echo " SUMMARY"
echo "=========================================="
echo "Tagged:    $TAGGED resources"
echo "Skipped:   $SKIPPED (already tagged)"
echo "Errors:    $ERRORS"
echo "Dry-run:   $DRY_RUN"
echo "=========================================="

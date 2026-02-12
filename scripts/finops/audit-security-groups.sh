#!/bin/bash
# scripts/finops/audit-security-groups.sh
#
# Audit Security Groups for:
#   - Security groups not attached to any instance/resource
#   - Security groups with overly permissive rules (0.0.0.0/0)
#   - Unused security groups (default excluded)
#
# Cost: $0 (no direct cost, but security/hygiene issue)
#
# Usage:
#   bash scripts/finops/audit-security-groups.sh
#
# Note: Deletion requires manual review (security-sensitive)
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

REPORT_DIR="$PROJECT_ROOT/reports/aws-costs"
REPORT_FILE="$REPORT_DIR/audit-security-groups-$(date +%Y-%m-%d).json"

mkdir -p "$REPORT_DIR"

echo "=========================================="
echo " FinOps Audit — Security Groups"
echo "=========================================="
echo "Region:   $REGION"
echo "Profile:  $PROFILE"
echo "Date:     $(date --iso-8601=seconds)"
echo "=========================================="

# Get all security groups (exclude default)
ALL_SGS=$(aws ec2 describe-security-groups \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'SecurityGroups[?GroupName!=`default`]' \
  --output json 2>/dev/null || echo "[]")

TOTAL_COUNT=$(echo "$ALL_SGS" | jq '. | length')
echo ""
echo "Total Security Groups (excl. default): $TOTAL_COUNT"

# Get all network interfaces to check SG attachments
ENIS=$(aws ec2 describe-network-interfaces \
  --region "$REGION" \
  --profile "$PROFILE" \
  --query 'NetworkInterfaces[].Groups[].GroupId' \
  --output json 2>/dev/null || echo "[]")

ATTACHED_SGS=$(echo "$ENIS" | jq -r '.[] | select(. != null)' | sort -u)

# Find unused security groups
UNUSED_SGS="[]"
UNUSED_COUNT=0

echo ""
echo "--- [1/3] Unused Security Groups ---"
echo "Checking for security groups not attached to any resource..."

echo "$ALL_SGS" | jq -r '.[].GroupId' | while read -r SG_ID; do
  if ! echo "$ATTACHED_SGS" | grep -q "^$SG_ID$"; then
    SG_INFO=$(echo "$ALL_SGS" | jq --arg id "$SG_ID" '[.[] | select(.GroupId == $id)][0]')
    SG_NAME=$(echo "$SG_INFO" | jq -r '.GroupName')
    SG_VPC=$(echo "$SG_INFO" | jq -r '.VpcId')

    echo "  $SG_ID | $SG_NAME | VPC: $SG_VPC"
    UNUSED_COUNT=$((UNUSED_COUNT + 1))

    # Append to JSON (inefficient but works for small datasets)
    UNUSED_SGS=$(echo "$UNUSED_SGS" | jq --argjson sg "$SG_INFO" '. += [$sg]')
  fi
done

echo ""
echo "Found: $UNUSED_COUNT unused security groups"

# Find overly permissive security groups (0.0.0.0/0)
echo ""
echo "--- [2/3] Overly Permissive Security Groups ---"
echo "Checking for rules allowing 0.0.0.0/0..."

PERMISSIVE_SGS=$(echo "$ALL_SGS" | jq '[.[] | select(
  (.IpPermissions[]?.IpRanges[]?.CidrIp // "" | contains("0.0.0.0/0")) or
  (.IpPermissions[]?.Ipv6Ranges[]?.CidrIpv6 // "" | contains("::/0"))
) | {
  id: .GroupId,
  name: .GroupName,
  vpc: .VpcId,
  rules: [.IpPermissions[] | select(
    (.IpRanges[]?.CidrIp // "" | contains("0.0.0.0/0")) or
    (.Ipv6Ranges[]?.CidrIpv6 // "" | contains("::/0"))
  ) | {
    protocol: (.IpProtocol // "all"),
    port: (.FromPort // "all"),
    cidr: (.IpRanges[]?.CidrIp // .Ipv6Ranges[]?.CidrIpv6)
  }]
}]')

PERMISSIVE_COUNT=$(echo "$PERMISSIVE_SGS" | jq '. | length')
echo "Found: $PERMISSIVE_COUNT security groups with 0.0.0.0/0 rules"

if [ "$PERMISSIVE_COUNT" -gt 0 ]; then
  echo "$PERMISSIVE_SGS" | jq -r '.[] | "  \(.id) | \(.name) | VPC: \(.vpc)"' | head -20

  if [ "$PERMISSIVE_COUNT" -gt 20 ]; then
    echo "  ... and $((PERMISSIVE_COUNT - 20)) more"
  fi

  echo ""
  echo "⚠️  WARNING: These security groups allow unrestricted access from internet"
  echo "⚠️  Review and restrict to specific IP ranges where possible"
fi

# Large security groups (>50 rules)
echo ""
echo "--- [3/3] Large Security Groups (>50 rules) ---"

LARGE_SGS=$(echo "$ALL_SGS" | jq '[.[] | select(
  ((.IpPermissions | length) + (.IpPermissionsEgress | length)) > 50
) | {
  id: .GroupId,
  name: .GroupName,
  ingress_rules: (.IpPermissions | length),
  egress_rules: (.IpPermissionsEgress | length),
  total_rules: ((.IpPermissions | length) + (.IpPermissionsEgress | length))
}]')

LARGE_COUNT=$(echo "$LARGE_SGS" | jq '. | length')
echo "Found: $LARGE_COUNT security groups with >50 rules"

if [ "$LARGE_COUNT" -gt 0 ]; then
  echo "$LARGE_SGS" | jq -r '.[] | "  \(.id) | \(.name) | Total rules: \(.total_rules)"'

  echo ""
  echo "ℹ️  TIP: Consider consolidating rules or using AWS Network Firewall"
fi

# Save report
RESULTS=$(cat <<EOF
{
  "scan_date": "$(date --iso-8601=seconds)",
  "summary": {
    "total_security_groups": $TOTAL_COUNT,
    "unused_count": $UNUSED_COUNT,
    "permissive_count": $PERMISSIVE_COUNT,
    "large_count": $LARGE_COUNT
  },
  "findings": [
    {
      "type": "unused_security_groups",
      "count": $UNUSED_COUNT,
      "items": $UNUSED_SGS,
      "note": "Manual deletion required after review"
    },
    {
      "type": "overly_permissive",
      "count": $PERMISSIVE_COUNT,
      "items": $PERMISSIVE_SGS,
      "severity": "high",
      "note": "Restrict 0.0.0.0/0 rules to specific IPs"
    },
    {
      "type": "large_security_groups",
      "count": $LARGE_COUNT,
      "items": $LARGE_SGS,
      "note": "Consider consolidation or AWS Network Firewall"
    }
  ],
  "recommendations": [
    "Delete unused security groups (manual review required)",
    "Restrict 0.0.0.0/0 rules to specific IP ranges",
    "Consolidate large security groups",
    "Use Security Group naming conventions for better tracking",
    "Tag security groups with owner and purpose"
  ]
}
EOF
)

echo "$RESULTS" | jq '.' > "$REPORT_FILE"

echo ""
echo "=========================================="
echo " SUMMARY"
echo "=========================================="
echo "Total security groups:    $TOTAL_COUNT"
echo "Unused (not attached):    $UNUSED_COUNT"
echo "Overly permissive:        $PERMISSIVE_COUNT"
echo "Large (>50 rules):        $LARGE_COUNT"
echo "=========================================="
echo "Report saved: $REPORT_FILE"
echo ""
echo "⚠️  MANUAL ACTION REQUIRED:"
echo "   Review unused security groups before deletion"
echo "   Tighten overly permissive rules (0.0.0.0/0)"

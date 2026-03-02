#!/bin/bash
# Validate Loki StatefulSets have required corporate labels
# Usage: ./validate-loki-labels.sh
# Date: 2026-03-02
# Reference: ADR-048 Corporate Labels

set -euo pipefail

export AWS_PROFILE=k8s-platform-prod
NAMESPACE="staging-observability-monitoring"

echo "==================================================================="
echo "Loki StatefulSets Corporate Labels Validation"
echo "==================================================================="
echo ""
echo "Namespace: $NAMESPACE"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Required labels per ADR-048
REQUIRED_LABELS=(
  "domain"
  "owner"
  "environment"
  "app.kubernetes.io/name"
  "app.kubernetes.io/part-of"
)

# Loki StatefulSets
STATEFULSETS=(
  "loki-backend"
  "loki-chunks-cache"
  "loki-results-cache"
  "loki-write"
)

echo "==================================================================="
echo "Required Labels (ADR-048):"
echo "==================================================================="
for label in "${REQUIRED_LABELS[@]}"; do
  echo "  - $label"
done
echo ""

echo "==================================================================="
echo "Validation Results:"
echo "==================================================================="

TOTAL_VIOLATIONS=0

for sts in "${STATEFULSETS[@]}"; do
  echo ""
  echo "--- StatefulSet: $sts ---"

  # Get labels from pod template
  LABELS=$(kubectl get statefulset "$sts" -n "$NAMESPACE" -o jsonpath='{.spec.template.metadata.labels}' 2>/dev/null || echo "{}")

  if [ "$LABELS" == "{}" ]; then
    echo "  ❌ ERROR: StatefulSet not found"
    ((TOTAL_VIOLATIONS++))
    continue
  fi

  VIOLATIONS=0

  for label in "${REQUIRED_LABELS[@]}"; do
    VALUE=$(echo "$LABELS" | jq -r ".\"$label\" // empty")

    if [ -z "$VALUE" ]; then
      echo "  ❌ MISSING: $label"
      ((VIOLATIONS++))
    else
      # Validate against Kyverno policy rules
      case "$label" in
        "domain")
          if [[ ! "$VALUE" =~ ^(platform|integration|data|operations|shared-services)$ ]]; then
            echo "  ❌ INVALID: $label = $VALUE (allowed: platform, integration, data, operations, shared-services)"
            ((VIOLATIONS++))
          else
            echo "  ✅ VALID: $label = $VALUE"
          fi
          ;;
        "owner")
          if [[ ! "$VALUE" =~ ^[a-z0-9-]+-team$ ]]; then
            echo "  ❌ INVALID: $label = $VALUE (format: ^[a-z0-9-]+-team$)"
            ((VIOLATIONS++))
          else
            echo "  ✅ VALID: $label = $VALUE"
          fi
          ;;
        "environment")
          if [[ ! "$VALUE" =~ ^(dev|staging|prod)$ ]]; then
            echo "  ❌ INVALID: $label = $VALUE (allowed: dev, staging, prod)"
            ((VIOLATIONS++))
          else
            echo "  ✅ VALID: $label = $VALUE"
          fi
          ;;
        *)
          echo "  ✅ PRESENT: $label = $VALUE"
          ;;
      esac
    fi
  done

  if [ $VIOLATIONS -eq 0 ]; then
    echo "  ✅ COMPLIANT: All required labels present and valid"
  else
    echo "  ❌ VIOLATIONS: $VIOLATIONS label(s) missing or invalid"
    ((TOTAL_VIOLATIONS+=$VIOLATIONS))
  fi
done

echo ""
echo "==================================================================="
echo "Summary:"
echo "==================================================================="
if [ $TOTAL_VIOLATIONS -eq 0 ]; then
  echo "✅ SUCCESS: All StatefulSets are compliant with ADR-048"
  echo ""
  echo "Next steps:"
  echo "  - Verify no PolicyViolation events: kubectl describe pod -n $NAMESPACE | grep PolicyViolation"
  echo "  - Monitor Kyverno policy reports: kubectl get policyreport -n $NAMESPACE"
  exit 0
else
  echo "❌ FAILURE: $TOTAL_VIOLATIONS violation(s) found"
  echo ""
  echo "Next steps:"
  echo "  1. Apply missing labels via kubectl patch (see /docs/fixes/2026-03-02-loki-kyverno-policy-fix.md)"
  echo "  2. Update Helm values for permanent fix"
  echo "  3. Re-run this validation script"
  exit 1
fi

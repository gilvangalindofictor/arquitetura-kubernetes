#!/bin/bash
# scripts/finops/vpa-phase0-validation.sh
#
# VPA FASE 0 Savings Validation Script
# Validates that VPA baseline requests have converged and savings targets are met
#
# Usage:
#   ./vpa-phase0-validation.sh                    # Run validation
#   SLACK_WEBHOOK_URL="https://..." ./vpa-phase0-validation.sh  # With Slack notification
#
# Exit Codes:
#   0 = Success: Target achieved (≥R$ 15.000/ano)
#   1 = Warning: Below target (R$ 12.000-15.000/ano)
#   2 = Error: Execution failed or no data
#
# Requirements: kubectl, jq, bc (for calculations)

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCS_DIR="$PROJECT_ROOT/docs/finops"
REPORT_DIR="$DOCS_DIR"

# Baseline from FASE 0 (2026-02-20)
BASELINE_SAVINGS_BRL=62.28
TARGET_SAVINGS_BRL=15000  # Conservative target (80% of R$ 19.118,50 roadmap)
WARNING_THRESHOLD_BRL=12000

# Report metadata
VALIDATION_DATE=$(date +%Y%m%d)
REPORT_FILE="$REPORT_DIR/vpa-phase0-validation-report-${VALIDATION_DATE}.md"

# Slack integration (optional)
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $*${NC}"
}

send_slack_notification() {
    local message="$1"
    local status="$2"  # success, warning, error

    if [ -z "$SLACK_WEBHOOK_URL" ]; then
        return 0
    fi

    local color="good"
    case "$status" in
        warning) color="warning" ;;
        error) color="danger" ;;
    esac

    local payload=$(cat <<EOF
{
    "attachments": [
        {
            "color": "$color",
            "title": "VPA FASE 0 Validation Report",
            "text": "$message",
            "footer": "VPA Automation",
            "ts": $(date +%s)
        }
    ]
}
EOF
)

    curl -X POST -H 'Content-type: application/json' \
        --data "$payload" \
        "$SLACK_WEBHOOK_URL" 2>/dev/null || log_warn "Failed to send Slack notification"
}

# ============================================================================
# Validation Functions
# ============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    for tool in kubectl jq bc; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        return 1
    fi

    # Check kubectl cluster connection
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        return 1
    fi

    log_success "All prerequisites met"
    return 0
}

count_vpa_with_recommendations() {
    kubectl get vpa -A -o json 2>/dev/null | jq '[.items[] | select(.status.recommendation != null)] | length' || echo "0"
}

get_vpa_recommendations() {
    log_info "Fetching VPA recommendations..."

    # Get all VPAs with recommendations
    kubectl get vpa -A -o json 2>/dev/null | jq -r '
        .items[] |
        select(.status.recommendation != null) |
        "\(.metadata.namespace),\(.metadata.name),\(.status.recommendation.containerRecommendations[0].target.cpu // "0m"),\(.status.recommendation.containerRecommendations[0].target.memory // "0Mi")"
    ' || true
}

# Convert CPU string (e.g., "250m") to millicores (250)
cpu_to_millicores() {
    local cpu="$1"

    if [[ "$cpu" =~ ^([0-9]+)m$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$cpu" =~ ^([0-9.]+)$ ]]; then
        # Convert cores to millicores
        echo "$cpu" | awk '{printf "%.0f", $1 * 1000}'
    else
        echo "0"
    fi
}

# Convert memory string (e.g., "512Mi", "1Gi") to Mi
memory_to_mi() {
    local mem="$1"

    if [[ "$mem" =~ ^([0-9]+)Mi$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$mem" =~ ^([0-9.]+)Gi$ ]]; then
        echo "${BASH_REMATCH[1]}" | awk '{printf "%.0f", $1 * 1024}'
    else
        echo "0"
    fi
}

# Estimate node savings based on reduced resource requests
calculate_savings() {
    local total_cpu_freed=0
    local vpa_count=0

    log_info "Analyzing current vs recommended resources..."

    # Get all VPAs and calculate freed resources
    while IFS=',' read -r ns vpa target_cpu target_mem; do
        if [ -z "$vpa" ] || [ "$vpa" = "null" ]; then
            continue
        fi

        ((vpa_count++))

        # Get current pod resources
        local pod_selector=""
        case "$vpa" in
            vault) pod_selector="app.kubernetes.io/name=vault" ;;
            keycloak) pod_selector="app.kubernetes.io/name=keycloakx" ;;
            argocd-server) pod_selector="app.kubernetes.io/name=argocd-server" ;;
            grafana) pod_selector="app.kubernetes.io/name=grafana" ;;
            harbor-core) pod_selector="app=harbor" ;;
            loki-write) pod_selector="app.kubernetes.io/name=loki" ;;
            gitlab-*) pod_selector="release=$vpa" ;;
            prometheus) pod_selector="app.kubernetes.io/name=prometheus" ;;
            *);;
        esac

        if [ -n "$pod_selector" ]; then
            local current_resources=$(kubectl get pods -n "$ns" -l "$pod_selector" \
                -o jsonpath='{.items[0].spec.containers[0].resources.requests}' 2>/dev/null || echo "{}")

            local current_cpu=$(echo "$current_resources" | jq -r '.cpu // "0m"')
            local current_mem=$(echo "$current_resources" | jq -r '.memory // "0Mi"')

            # Calculate freed resources
            local freed_cpu_m=$(( $(cpu_to_millicores "$current_cpu") - $(cpu_to_millicores "$target_cpu") ))

            if [ "$freed_cpu_m" -lt 0 ]; then
                freed_cpu_m=0
            fi

            total_cpu_freed=$((total_cpu_freed + freed_cpu_m))
        fi
    done < <(get_vpa_recommendations)

    # Convert to annual savings (R$)
    # Conservative: 100m CPU = R$ 3/year (0.03 BRL per millicores per year)
    if [ "$vpa_count" -gt 0 ]; then
        echo "scale=2; $total_cpu_freed * 0.03" | bc
    else
        echo "0"
    fi
}

collect_workload_metrics() {
    log_info "Collecting workload metrics..."

    while IFS=',' read -r ns vpa target_cpu target_mem; do
        if [ -z "$vpa" ] || [ "$vpa" = "null" ]; then
            continue
        fi

        # Get pod count
        local pod_count=$(kubectl get pods -n "$ns" 2>/dev/null | tail -n +2 | wc -l || echo "0")

        # Get pod status
        local running_count=$(kubectl get pods -n "$ns" -o json 2>/dev/null | \
            jq '[.items[] | select(.status.phase == "Running")] | length' 2>/dev/null || echo "0")

        echo "$vpa|$ns|$pod_count|$running_count|$target_cpu|$target_mem"
    done < <(get_vpa_recommendations)
}

# ============================================================================
# Report Generation
# ============================================================================

generate_markdown_report() {
    local savings="$1"
    local exit_code="$2"

    mkdir -p "$REPORT_DIR"

    local status_emoji="✅"
    local status_text="SUCCESS: Target achieved"
    local status_details=""

    if [ "$exit_code" = "1" ]; then
        status_emoji="⚠️"
        status_text="WARNING: Below target"
        status_details="Savings achieved are below the R\$ 15.000/ano target. Additional optimization waves may be needed."
    elif [ "$exit_code" = "2" ]; then
        status_emoji="❌"
        status_text="ERROR: Validation failed"
        status_details="VPA data collection incomplete or validation encountered errors."
    fi

    cat > "$REPORT_FILE" <<REPORT_HEADER
# VPA FASE 0 Validation Report

**Generated:** $(date --iso-8601=seconds)
**Status:** $status_emoji $status_text
**Exit Code:** $exit_code

---

## Executive Summary

### Savings Target Achievement

| Metric | Value | Status |
|--------|-------|--------|
| Baseline (2026-02-20) | R\$ ${BASELINE_SAVINGS_BRL}/ano | - |
| Target (FASE 0 completion) | R\$ ${TARGET_SAVINGS_BRL}/ano | 🎯 |
| **Actual Savings** | **R\$ ${savings}/ano** | $([ "$(echo "$savings >= $TARGET_SAVINGS_BRL" | bc)" = "1" ] && echo "✅ ACHIEVED" || echo "⚠️ PARTIAL") |
| **Delta to Target** | R\$ $(echo "scale=2; $savings - $TARGET_SAVINGS_BRL" | bc) | - |
| **Percent of Target** | $(echo "scale=1; ($savings / $TARGET_SAVINGS_BRL) * 100" | bc)% | - |

**Status Details:** $status_details

---

## VPA Configuration Status

### VPAs with Active Recommendations

| Namespace | VPA Name | Target CPU | Target Memory | Pod Status |
|-----------|----------|-----------|----------------|-----------|
REPORT_HEADER

    collect_workload_metrics | while IFS='|' read -r vpa ns pod_count running_count target_cpu target_mem; do
        if [ -z "$vpa" ] || [ "$vpa" = "null" ]; then
            continue
        fi
        echo "| $ns | $vpa | $target_cpu | $target_mem | $running_count/$pod_count |" >> "$REPORT_FILE"
    done

    cat >> "$REPORT_FILE" <<'REPORT_FOOTER'

---

## Recommendations

### If Target Achieved (✅)

1. ✅ FASE 0 validation PASSED
2. Begin FASE 1: Rightsizing execution
   - Reduce headroom from 5×/4× to 2×/1.5×
   - Target additional R$ 8-10k/ano
3. Schedule FASE 1 for next week
4. Document patterns for future VPA waves

### If Target Partially Achieved (⚠️)

1. ⚠️ Investigate underperforming VPAs
2. Check VPA updateMode and recommendation delays
3. Verify metric collection: `kubectl describe vpa <name> -n <ns>`
4. Consider extending convergence window to 14 days
5. Plan supplementary optimization initiatives

### If Validation Failed (❌)

1. ❌ Troubleshoot VPA installation
2. Verify ExternalMetrics API availability
3. Check Prometheus metrics collection
4. Review logs: `kubectl logs -n kube-system -l app=vpa-recommender`

---

## Next Steps

1. **Short-term (This week):**
   - Review this validation report
   - Verify pod health: `kubectl get pods -A | grep -v Running`

2. **Medium-term (Next 2 weeks):**
   - If target achieved: Plan FASE 1 rightsizing
   - If below target: Extend VPA collection window to 14 days

3. **Long-term (Next quarter):**
   - Execute FASE 1 and FASE 2 optimizations
   - Target cumulative savings: R$ 30-40k/ano

---

## Appendix: Verification Commands

### Check VPA Status
```bash
kubectl get vpa -A
kubectl describe vpa <vpa-name> -n <namespace>
```

### View VPA Recommendations
```bash
kubectl get vpa <vpa-name> -n <namespace> -o json | jq '.status.recommendation'
```

### Monitor Pod Resources
```bash
kubectl top pods -n <namespace>
```

---

**Report Generated By:** vpa-phase0-validation.sh
**Validation Date:** ${VALIDATION_DATE}
**Reference:** docs/logbook/2026-02-20-phase0-baseline-execution.md

REPORT_FOOTER

    log_success "Report generated: $REPORT_FILE"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_info "Starting VPA FASE 0 Validation"
    echo ""
    echo "=========================================="
    echo " VPA FASE 0 Savings Validation"
    echo "=========================================="
    echo "Baseline Savings (2026-02-20): R\$ ${BASELINE_SAVINGS_BRL}/ano"
    echo "Target Savings:                R\$ ${TARGET_SAVINGS_BRL}/ano"
    echo "Warning Threshold:             R\$ ${WARNING_THRESHOLD_BRL}/ano"
    echo "Validation Date:               $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="
    echo ""

    # Check prerequisites
    if ! check_prerequisites; then
        log_error "Prerequisites check failed"
        send_slack_notification "Prerequisites check failed" "error"
        return 2
    fi

    # Count VPAs with recommendations
    local vpa_count
    vpa_count=$(count_vpa_with_recommendations)
    log_info "VPAs with recommendations: $vpa_count/10"

    # Calculate savings
    log_info "Calculating actual savings from VPA recommendations..."
    local savings
    savings=$(calculate_savings) || savings="0"

    echo ""
    echo "=========================================="
    echo " RESULTS"
    echo "=========================================="
    echo "Baseline Savings (2026-02-20): R\$ ${BASELINE_SAVINGS_BRL}/ano"
    echo "Target Savings:                R\$ ${TARGET_SAVINGS_BRL}/ano"
    echo "VPAs with Recommendations:     $vpa_count/10"
    echo "Actual Savings:                R\$ ${savings}/ano"
    echo "=========================================="
    echo ""

    # Determine exit code based on savings and VPA count
    local exit_code=0

    # If we have data, check savings
    if [ "$(echo "$savings > 0" | bc)" = "1" ]; then
        if (( $(echo "$savings >= $TARGET_SAVINGS_BRL" | bc -l) )); then
            log_success "Target achieved!"
            send_slack_notification "VPA FASE 0 validation PASSED: R\$ ${savings}/ano (target: R\$ ${TARGET_SAVINGS_BRL}/ano)" "success"
            exit_code=0
        elif (( $(echo "$savings >= $WARNING_THRESHOLD_BRL" | bc -l) )); then
            log_warn "Below target but acceptable"
            send_slack_notification "VPA FASE 0 validation PARTIAL: R\$ ${savings}/ano (target: R\$ ${TARGET_SAVINGS_BRL}/ano)" "warning"
            exit_code=1
        else
            log_error "Below warning threshold"
            send_slack_notification "VPA FASE 0 validation BELOW THRESHOLD: R\$ ${savings}/ano (target: R\$ ${TARGET_SAVINGS_BRL}/ano)" "error"
            exit_code=2
        fi
    elif [ "$vpa_count" -ge 8 ]; then
        log_warn "Most VPAs ready but savings calculation pending"
        exit_code=1
    else
        log_error "Insufficient VPA recommendations ($vpa_count/10)"
        exit_code=2
    fi

    # Generate report
    generate_markdown_report "$savings" "$exit_code"

    echo ""
    log_info "Validation complete. Report: $REPORT_FILE"
    return "$exit_code"
}

main "$@"

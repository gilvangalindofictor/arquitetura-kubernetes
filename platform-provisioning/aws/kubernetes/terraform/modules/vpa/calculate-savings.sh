#!/usr/bin/env bash
#
# VPA Savings Calculator v2
# Purpose: Analyze VPA recommendations and calculate cost savings
# Author: DevOps Specialist Agent
# Date: 2026-02-20
#
# Usage: ./calculate-savings-v2.sh [OPTIONS]

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

# AWS Pricing (us-east-1 t3 instances - on-demand)
readonly CPU_COST_PER_HOUR=0.0416        # $/vCPU/hour
readonly MEMORY_COST_PER_GB_HOUR=0.00456 # $/GB/hour
readonly BRL_EXCHANGE_RATE=6.0           # USD to BRL

# Time calculations
readonly HOURS_PER_MONTH=730  # 24 * 365 / 12
readonly MONTHS_PER_YEAR=12

# Global flags
VERBOSE=0
JSON_OUTPUT=0
OUTPUT_FILE="vpa-savings-report.txt"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log_info() {
    echo "[INFO] $*" >&2
}

log_success() {
    echo "[✓] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_verbose() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

show_help() {
    cat <<EOF
VPA Savings Calculator v2

Analyzes Kubernetes VPA recommendations and calculates cost savings.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -j, --json          Export results to JSON file
    -o, --output FILE   Specify output file (default: vpa-savings-report.txt)

REQUIREMENTS:
    - kubectl configured and connected to cluster
    - VPA CRD installed
    - jq for JSON parsing
    - bc for calculations

EOF
}

# Convert Kubernetes resource units to numeric values
parse_cpu() {
    local cpu="$1"
    if [[ $cpu =~ ^([0-9.]+)m$ ]]; then
        echo "scale=6; ${BASH_REMATCH[1]} / 1000" | bc
    elif [[ $cpu =~ ^([0-9.]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "0"
    fi
}

parse_memory() {
    local mem="$1"
    if [[ $mem =~ ^([0-9]+)$ ]]; then
        echo "scale=6; $mem / 1073741824" | bc
    elif [[ $mem =~ ^([0-9.]+)Ki$ ]]; then
        echo "scale=6; ${BASH_REMATCH[1]} / 1048576" | bc
    elif [[ $mem =~ ^([0-9.]+)Mi$ ]]; then
        echo "scale=6; ${BASH_REMATCH[1]} / 1024" | bc
    elif [[ $mem =~ ^([0-9.]+)Gi$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ $mem =~ ^([0-9.]+)Ti$ ]]; then
        echo "scale=6; ${BASH_REMATCH[1]} * 1024" | bc
    else
        echo "0"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -j|--json)
                JSON_OUTPUT=1
                shift
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    log_info "Starting VPA Savings Analysis..."
    echo ""

    # Check dependencies
    log_info "Checking dependencies..."
    for cmd in kubectl jq bc; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Missing required dependency: $cmd"
            exit 1
        fi
    done
    log_verbose "All dependencies satisfied"

    # Check cluster access
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot access Kubernetes cluster"
        exit 1
    fi
    log_verbose "Cluster access verified"

    # Check VPA CRD
    if ! kubectl get crd verticalpodautoscalers.autoscaling.k8s.io &>/dev/null; then
        log_error "VPA CRD not found in cluster"
        exit 2
    fi
    log_verbose "VPA CRD found"

    log_success "All pre-flight checks passed"
    echo ""

    # Collect VPA data
    log_info "Collecting VPA data from cluster..."

    # Get all VPAs with their recommendations in one call
    local vpa_data
    vpa_data=$(kubectl get vpa -A -o json)

    local total_vpas
    total_vpas=$(echo "$vpa_data" | jq '.items | length')

    if [[ $total_vpas -eq 0 ]]; then
        log_error "No VPA objects found in cluster"
        exit 2
    fi

    log_success "Found $total_vpas VPA objects"
    echo ""

    # Analyze VPAs
    log_info "Analyzing VPA recommendations..."

    local total_savings_usd=0
    local total_savings_brl=0
    local workloads_processed=0

    # Create output file with header
    {
        echo "================================================================================"
        echo "                    VPA SAVINGS ANALYSIS REPORT"
        echo "================================================================================"
        echo ""
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "Cluster: $(kubectl config current-context)"
        echo ""
        echo "Pricing Assumptions:"
        echo "  - CPU Cost:    \$$CPU_COST_PER_HOUR per vCPU/hour (us-east-1 t3)"
        echo "  - Memory Cost: \$$MEMORY_COST_PER_GB_HOUR per GB/hour (us-east-1 t3)"
        echo "  - Exchange Rate: 1 USD = $BRL_EXCHANGE_RATE BRL"
        echo ""
        echo "================================================================================"
        echo ""
        printf "%-25s %-20s %12s %12s %12s %12s\n" \
            "WORKLOAD" "NAMESPACE" "CPU %" "MEMORY %" "SAVINGS/YR" "BRL/YR"
        printf "%-25s %-20s %12s %12s %12s %12s\n" \
            "-------------------------" "--------------------" "------------" "------------" "------------" "------------"
    } > "$OUTPUT_FILE"

    # Process each VPA
    for i in $(seq 0 $((total_vpas - 1))); do
        local namespace vpa_name target_kind target_name

        namespace=$(echo "$vpa_data" | jq -r ".items[$i].metadata.namespace")
        vpa_name=$(echo "$vpa_data" | jq -r ".items[$i].metadata.name")
        target_kind=$(echo "$vpa_data" | jq -r ".items[$i].spec.targetRef.kind")
        target_name=$(echo "$vpa_data" | jq -r ".items[$i].spec.targetRef.name")

        log_verbose "Processing VPA $((i+1))/$total_vpas: $namespace/$vpa_name"

        # Get VPA recommendation
        local recommendation
        recommendation=$(echo "$vpa_data" | jq ".items[$i].status.recommendation.containerRecommendations[0] // null")

        if [[ "$recommendation" == "null" ]]; then
            log_verbose "  Skipping (no recommendation available)"
            continue
        fi

        # Extract target recommendation
        local target_cpu target_memory
        target_cpu=$(echo "$recommendation" | jq -r '.uncappedTarget.cpu // "0"')
        target_memory=$(echo "$recommendation" | jq -r '.uncappedTarget.memory // "0"')

        # Get current resources from target workload
        local current_requests
        case "$target_kind" in
            Deployment)
                current_requests=$(kubectl get deployment "$target_name" -n "$namespace" -o json 2>/dev/null | \
                    jq -r '.spec.template.spec.containers[0].resources.requests // {}') || continue
                ;;
            StatefulSet)
                current_requests=$(kubectl get statefulset "$target_name" -n "$namespace" -o json 2>/dev/null | \
                    jq -r '.spec.template.spec.containers[0].resources.requests // {}') || continue
                ;;
            DaemonSet)
                current_requests=$(kubectl get daemonset "$target_name" -n "$namespace" -o json 2>/dev/null | \
                    jq -r '.spec.template.spec.containers[0].resources.requests // {}') || continue
                ;;
            *)
                log_verbose "  Skipping unsupported workload kind: $target_kind"
                continue
                ;;
        esac

        local current_cpu current_memory
        current_cpu=$(echo "$current_requests" | jq -r '.cpu // "0"')
        current_memory=$(echo "$current_requests" | jq -r '.memory // "0"')

        # Skip if no current resources
        if [[ "$current_cpu" == "0" && "$current_memory" == "0" ]]; then
            log_verbose "  Skipping (no current resource requests)"
            continue
        fi

        # Parse to numeric values
        local current_cpu_cores current_memory_gb target_cpu_cores target_memory_gb
        current_cpu_cores=$(parse_cpu "$current_cpu")
        current_memory_gb=$(parse_memory "$current_memory")
        target_cpu_cores=$(parse_cpu "$target_cpu")
        target_memory_gb=$(parse_memory "$target_memory")

        log_verbose "  Current: CPU=${current_cpu_cores} cores, Memory=${current_memory_gb} GB"
        log_verbose "  Target:  CPU=${target_cpu_cores} cores, Memory=${target_memory_gb} GB"

        # Calculate savings
        local cpu_savings_month memory_savings_month total_savings_month total_savings_year total_savings_year_brl
        cpu_savings_month=$(echo "scale=2; ($current_cpu_cores - $target_cpu_cores) * $CPU_COST_PER_HOUR * $HOURS_PER_MONTH" | bc)
        memory_savings_month=$(echo "scale=2; ($current_memory_gb - $target_memory_gb) * $MEMORY_COST_PER_GB_HOUR * $HOURS_PER_MONTH" | bc)
        total_savings_month=$(echo "scale=2; $cpu_savings_month + $memory_savings_month" | bc)
        total_savings_year=$(echo "scale=2; $total_savings_month * $MONTHS_PER_YEAR" | bc)
        total_savings_year_brl=$(echo "scale=2; $total_savings_year * $BRL_EXCHANGE_RATE" | bc)

        # Calculate reduction percentages
        local cpu_reduction_pct="0"
        local memory_reduction_pct="0"

        if (( $(echo "$current_cpu_cores > 0" | bc -l) )); then
            cpu_reduction_pct=$(echo "scale=1; (($current_cpu_cores - $target_cpu_cores) / $current_cpu_cores) * 100" | bc)
        fi

        if (( $(echo "$current_memory_gb > 0" | bc -l) )); then
            memory_reduction_pct=$(echo "scale=1; (($current_memory_gb - $target_memory_gb) / $current_memory_gb) * 100" | bc)
        fi

        # Only show positive savings
        if (( $(echo "$total_savings_year_brl > 0" | bc -l) )); then
            printf "%-25s %-20s %11.1f%% %11.1f%% \$%10.2f R\$%10.2f\n" \
                "$vpa_name" "$namespace" "$cpu_reduction_pct" "$memory_reduction_pct" \
                "$total_savings_year" "$total_savings_year_brl" >> "$OUTPUT_FILE"

            total_savings_usd=$(echo "scale=2; $total_savings_usd + $total_savings_year" | bc)
            total_savings_brl=$(echo "scale=2; $total_savings_brl + $total_savings_year_brl" | bc)
            ((workloads_processed++))
        fi

        # Progress indicator
        if [[ $VERBOSE -eq 0 ]]; then
            printf "\r[INFO] Progress: %d/%d workloads analyzed..." "$((i+1))" "$total_vpas" >&2
        fi
    done

    if [[ $VERBOSE -eq 0 ]]; then
        echo "" >&2  # New line after progress indicator
    fi

    # Add summary to report
    {
        echo ""
        echo "================================================================================"
        echo ""
        echo "SUMMARY"
        echo "-------"
        echo "Total Workloads Analyzed:        $total_vpas"
        echo "Workloads with Savings:          $workloads_processed"
        printf "Total Annual Savings (USD):      \$%'.2f\n" "$total_savings_usd"
        printf "Total Annual Savings (BRL):      R\$ %'.2f\n" "$total_savings_brl"
        echo ""
        echo "================================================================================"
    } >> "$OUTPUT_FILE"

    log_success "Analysis complete"
    echo ""

    # Display summary
    echo "SUMMARY:"
    printf "  Total Annual Savings: R\$ %'.2f\n" "$total_savings_brl"
    echo "  Workloads with Savings: $workloads_processed/$total_vpas"
    echo ""
    echo "Full report saved to: $OUTPUT_FILE"
    echo ""

    # Generate JSON if requested
    if [[ $JSON_OUTPUT -eq 1 ]]; then
        local json_file="${OUTPUT_FILE%.txt}.json"
        cat > "$json_file" <<EOF
{
    "generated_at": "$(date -Iseconds)",
    "cluster": "$(kubectl config current-context)",
    "summary": {
        "total_workloads": $total_vpas,
        "workloads_with_savings": $workloads_processed,
        "total_savings_year_usd": $total_savings_usd,
        "total_savings_year_brl": $total_savings_brl
    }
}
EOF
        log_success "JSON report saved to: $json_file"
    fi
}

# Run main function if script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

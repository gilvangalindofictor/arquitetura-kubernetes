#!/usr/bin/env bash
#
# VPA Savings Calculator
# Purpose: Analyze VPA recommendations and calculate cost savings
# Author: DevOps Specialist Agent
# Date: 2026-02-20
#
# Usage: ./calculate-savings.sh [OPTIONS]
# Options:
#   -h, --help        Show help message
#   -v, --verbose     Enable verbose output
#   -j, --json        Export results to JSON
#   -o, --output FILE Output file path (default: vpa-savings-report.txt)
#   --html            Generate HTML report
#   --no-color        Disable colored output

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

# Color codes
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly BOLD='\033[1m'
    readonly RESET='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly CYAN=''
    readonly BOLD=''
    readonly RESET=''
fi

# Global flags
VERBOSE=0
JSON_OUTPUT=0
HTML_OUTPUT=0
NO_COLOR=0
OUTPUT_FILE="vpa-savings-report.txt"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${RESET} $*" >&2
}

log_success() {
    echo -e "${GREEN}[✓]${RESET} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${RESET} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $*" >&2
}

log_verbose() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo -e "${CYAN}[DEBUG]${RESET} $*" >&2
    fi
}

show_help() {
    cat <<EOF
${BOLD}VPA Savings Calculator${RESET}

Analyzes Kubernetes VPA recommendations and calculates cost savings.

${BOLD}USAGE:${RESET}
    $0 [OPTIONS]

${BOLD}OPTIONS:${RESET}
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -j, --json          Export results to JSON file
    -o, --output FILE   Specify output file (default: vpa-savings-report.txt)
    --html              Generate HTML report
    --no-color          Disable colored output

${BOLD}EXAMPLES:${RESET}
    # Basic usage
    $0

    # Verbose mode with JSON export
    $0 -v -j

    # Custom output file
    $0 -o /tmp/savings.txt

    # Generate HTML report
    $0 --html -o /tmp/report.html

${BOLD}REQUIREMENTS:${RESET}
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
        # Millicores
        echo "scale=6; ${BASH_REMATCH[1]} / 1000" | bc
    elif [[ $cpu =~ ^([0-9.]+)$ ]]; then
        # Cores
        echo "${BASH_REMATCH[1]}"
    else
        log_error "Invalid CPU format: $cpu"
        echo "0"
    fi
}

parse_memory() {
    local mem="$1"

    if [[ $mem =~ ^([0-9]+)$ ]]; then
        # Bytes
        echo "scale=6; $mem / 1073741824" | bc
    elif [[ $mem =~ ^([0-9.]+)Ki$ ]]; then
        # Kibibytes
        echo "scale=6; ${BASH_REMATCH[1]} / 1048576" | bc
    elif [[ $mem =~ ^([0-9.]+)Mi$ ]]; then
        # Mebibytes
        echo "scale=6; ${BASH_REMATCH[1]} / 1024" | bc
    elif [[ $mem =~ ^([0-9.]+)Gi$ ]]; then
        # Gibibytes
        echo "${BASH_REMATCH[1]}"
    elif [[ $mem =~ ^([0-9.]+)Ti$ ]]; then
        # Tebibytes
        echo "scale=6; ${BASH_REMATCH[1]} * 1024" | bc
    else
        log_error "Invalid memory format: $mem"
        echo "0"
    fi
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

check_dependencies() {
    local missing=()

    for cmd in kubectl jq bc; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        log_error "Please install missing tools and try again"
        return 1
    fi

    log_verbose "All dependencies satisfied"
    return 0
}

check_cluster_access() {
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot access Kubernetes cluster"
        log_error "Please configure kubectl and verify connection"
        return 1
    fi

    log_verbose "Cluster access verified"
    return 0
}

check_vpa_crd() {
    if ! kubectl get crd verticalpodautoscalers.autoscaling.k8s.io &>/dev/null; then
        log_error "VPA CRD not found in cluster"
        log_error "Please install VPA before running this script"
        return 2
    fi

    log_verbose "VPA CRD found"
    return 0
}

# ============================================================================
# DATA COLLECTION FUNCTIONS
# ============================================================================

get_vpa_list() {
    kubectl get vpa -A -o json | jq -r '.items[] | "\(.metadata.namespace)|\(.metadata.name)"'
}

get_current_resources() {
    local namespace="$1"
    local vpa_name="$2"

    log_verbose "Fetching current resources for VPA: $namespace/$vpa_name"

    # Get target workload info
    local target_info
    target_info=$(kubectl get vpa "$vpa_name" -n "$namespace" -o json | \
        jq -r '.spec.targetRef | "\(.kind)|\(.name)"')

    local kind="${target_info%%|*}"
    local name="${target_info##*|}"

    log_verbose "  Target: $kind/$name"

    # Get current resource requests
    local requests
    case "$kind" in
        Deployment)
            requests=$(kubectl get deployment "$name" -n "$namespace" -o json 2>/dev/null | \
                jq -r '.spec.template.spec.containers[0].resources.requests // {}')
            ;;
        StatefulSet)
            requests=$(kubectl get statefulset "$name" -n "$namespace" -o json 2>/dev/null | \
                jq -r '.spec.template.spec.containers[0].resources.requests // {}')
            ;;
        DaemonSet)
            requests=$(kubectl get daemonset "$name" -n "$namespace" -o json 2>/dev/null | \
                jq -r '.spec.template.spec.containers[0].resources.requests // {}')
            ;;
        *)
            log_warn "Unsupported workload kind: $kind"
            echo "{}"
            return
            ;;
    esac

    echo "$requests"
}

get_vpa_recommendation() {
    local namespace="$1"
    local vpa_name="$2"

    log_verbose "Fetching VPA recommendation for: $namespace/$vpa_name"

    local recommendation
    recommendation=$(kubectl get vpa "$vpa_name" -n "$namespace" -o json | \
        jq '.status.recommendation.containerRecommendations[0] // null')

    if [[ "$recommendation" == "null" ]]; then
        log_verbose "  No recommendation available yet"
        echo "null"
        return
    fi

    echo "$recommendation"
}

# ============================================================================
# CALCULATION FUNCTIONS
# ============================================================================

calculate_workload_savings() {
    local namespace="$1"
    local vpa_name="$2"
    local current_resources="$3"
    local recommendation="$4"

    # Extract current requests
    local current_cpu
    local current_memory
    current_cpu=$(echo "$current_resources" | jq -r '.cpu // "0"')
    current_memory=$(echo "$current_resources" | jq -r '.memory // "0"')

    # Extract VPA uncapped target (most accurate recommendation)
    local target_cpu
    local target_memory
    target_cpu=$(echo "$recommendation" | jq -r '.uncappedTarget.cpu // "0"')
    target_memory=$(echo "$recommendation" | jq -r '.uncappedTarget.memory // "0"')

    # Parse to numeric values
    local current_cpu_cores
    local current_memory_gb
    local target_cpu_cores
    local target_memory_gb

    current_cpu_cores=$(parse_cpu "$current_cpu")
    current_memory_gb=$(parse_memory "$current_memory")
    target_cpu_cores=$(parse_cpu "$target_cpu")
    target_memory_gb=$(parse_memory "$target_memory")

    log_verbose "  Current: CPU=${current_cpu_cores} cores, Memory=${current_memory_gb} GB"
    log_verbose "  Target:  CPU=${target_cpu_cores} cores, Memory=${target_memory_gb} GB"

    # Calculate CPU savings ($/month)
    local cpu_savings_month
    cpu_savings_month=$(echo "scale=2; ($current_cpu_cores - $target_cpu_cores) * $CPU_COST_PER_HOUR * $HOURS_PER_MONTH" | bc)

    # Calculate Memory savings ($/month)
    local memory_savings_month
    memory_savings_month=$(echo "scale=2; ($current_memory_gb - $target_memory_gb) * $MEMORY_COST_PER_GB_HOUR * $HOURS_PER_MONTH" | bc)

    # Total savings ($/month)
    local total_savings_month
    total_savings_month=$(echo "scale=2; $cpu_savings_month + $memory_savings_month" | bc)

    # Annual savings ($/year)
    local total_savings_year
    total_savings_year=$(echo "scale=2; $total_savings_month * $MONTHS_PER_YEAR" | bc)

    # Convert to BRL
    local total_savings_year_brl
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

    # Output JSON for aggregation
    cat <<EOF
{
    "namespace": "$namespace",
    "vpa_name": "$vpa_name",
    "current_cpu": "$current_cpu",
    "current_memory": "$current_memory",
    "target_cpu": "$target_cpu",
    "target_memory": "$target_memory",
    "cpu_cores_current": $current_cpu_cores,
    "memory_gb_current": $current_memory_gb,
    "cpu_cores_target": $target_cpu_cores,
    "memory_gb_target": $target_memory_gb,
    "cpu_reduction_pct": $cpu_reduction_pct,
    "memory_reduction_pct": $memory_reduction_pct,
    "savings_usd_month": $total_savings_month,
    "savings_usd_year": $total_savings_year,
    "savings_brl_year": $total_savings_year_brl
}
EOF
}

# ============================================================================
# REPORTING FUNCTIONS
# ============================================================================

generate_text_report() {
    local results="$1"
    local output_file="$2"

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

        # Summary statistics
        local total_workloads
        local workloads_with_recommendations
        local total_savings_year_usd
        local total_savings_year_brl
        local avg_cpu_reduction
        local avg_memory_reduction

        total_workloads=$(echo "$results" | jq -s 'length')
        workloads_with_recommendations=$(echo "$results" | jq -s '[.[] | select(.savings_usd_year > 0)] | length')
        total_savings_year_usd=$(echo "$results" | jq -s '[.[].savings_usd_year] | add // 0')
        total_savings_year_brl=$(echo "$results" | jq -s '[.[].savings_brl_year] | add // 0')
        avg_cpu_reduction=$(echo "$results" | jq -s '[.[].cpu_reduction_pct] | add / length')
        avg_memory_reduction=$(echo "$results" | jq -s '[.[].memory_reduction_pct] | add / length')

        echo "SUMMARY"
        echo "-------"
        echo "Total Workloads Analyzed:        $total_workloads"
        echo "Workloads with Recommendations:  $workloads_with_recommendations"
        printf "Total Annual Savings (USD):      \$%'.2f\n" "$total_savings_year_usd"
        printf "Total Annual Savings (BRL):      R\$ %'.2f\n" "$total_savings_year_brl"
        printf "Average CPU Reduction:           %.1f%%\n" "$avg_cpu_reduction"
        printf "Average Memory Reduction:        %.1f%%\n" "$avg_memory_reduction"
        echo ""
        echo "================================================================================"
        echo ""
        echo "WORKLOAD DETAILS (Sorted by Annual Savings)"
        echo "--------------------------------------------"
        echo ""

        # Table header
        printf "%-25s %-20s %12s %12s %12s %12s\n" \
            "WORKLOAD" "NAMESPACE" "CPU %" "MEMORY %" "SAVINGS/YR" "BRL/YR"
        printf "%-25s %-20s %12s %12s %12s %12s\n" \
            "-------------------------" "--------------------" "------------" "------------" "------------" "------------"

        # Sort by savings and display
        echo "$results" | jq -s 'sort_by(-.savings_brl_year)[]' | while IFS= read -r line; do
            local vpa_name namespace cpu_pct mem_pct savings_usd savings_brl
            vpa_name=$(echo "$line" | jq -r '.vpa_name')
            namespace=$(echo "$line" | jq -r '.namespace')
            cpu_pct=$(echo "$line" | jq -r '.cpu_reduction_pct')
            mem_pct=$(echo "$line" | jq -r '.memory_reduction_pct')
            savings_usd=$(echo "$line" | jq -r '.savings_usd_year')
            savings_brl=$(echo "$line" | jq -r '.savings_brl_year')

            # Skip if no savings
            if (( $(echo "$savings_brl <= 0" | bc -l) )); then
                continue
            fi

            printf "%-25s %-20s %11.1f%% %11.1f%% \$%10.2f R\$%10.2f\n" \
                "$vpa_name" "$namespace" "$cpu_pct" "$mem_pct" "$savings_usd" "$savings_brl"
        done

        echo ""
        echo "================================================================================"
        echo ""
        echo "DETAILED RESOURCE CHANGES"
        echo "-------------------------"
        echo ""

        echo "$results" | jq -s 'sort_by(-.savings_brl_year)[]' | while IFS= read -r line; do
            local vpa_name namespace current_cpu current_mem target_cpu target_mem savings_brl
            vpa_name=$(echo "$line" | jq -r '.vpa_name')
            namespace=$(echo "$line" | jq -r '.namespace')
            current_cpu=$(echo "$line" | jq -r '.current_cpu')
            current_mem=$(echo "$line" | jq -r '.current_memory')
            target_cpu=$(echo "$line" | jq -r '.target_cpu')
            target_mem=$(echo "$line" | jq -r '.target_memory')
            savings_brl=$(echo "$line" | jq -r '.savings_brl_year')

            # Skip if no recommendation
            if [[ "$target_cpu" == "0" || "$target_cpu" == "null" ]]; then
                continue
            fi

            echo "Workload: $namespace/$vpa_name"
            printf "  Current:  CPU=%-10s Memory=%-10s\n" "$current_cpu" "$current_mem"
            printf "  Target:   CPU=%-10s Memory=%-10s\n" "$target_cpu" "$target_mem"
            printf "  Savings:  R\$ %.2f/year\n" "$savings_brl"
            echo ""
        done

        echo "================================================================================"
        echo ""
        echo "ROI ANALYSIS"
        echo "------------"
        echo ""
        echo "Assuming VPA implementation cost (engineering time): \$5,000 USD"

        local impl_cost=5000
        local payback_months
        payback_months=$(echo "scale=1; ($impl_cost / $total_savings_year_usd) * 12" | bc)

        if (( $(echo "$total_savings_year_usd > 0" | bc -l) )); then
            printf "Payback Period: %.1f months\n" "$payback_months"
            printf "12-Month ROI: %.1f%%\n" "$(echo "scale=1; (($total_savings_year_usd - $impl_cost) / $impl_cost) * 100" | bc)"
        else
            echo "Insufficient data for ROI calculation"
        fi

        echo ""
        echo "================================================================================"
        echo ""
        echo "RECOMMENDATIONS"
        echo "---------------"
        echo ""
        echo "1. Review VPA recommendations for workloads with >50% overprovisioning"
        echo "2. Implement gradual rightsizing with updateMode: Auto on non-critical workloads"
        echo "3. Monitor application performance during rightsizing rollout"
        echo "4. Set up alerts for OOMKilled or CPU throttling events"
        echo "5. Re-run this analysis monthly to track optimization progress"
        echo ""
        echo "================================================================================"

    } > "$output_file"
}

generate_json_report() {
    local results="$1"
    local output_file="${2%.txt}.json"

    local total_savings_year_usd
    local total_savings_year_brl
    total_savings_year_usd=$(echo "$results" | jq -s '[.[].savings_usd_year] | add // 0')
    total_savings_year_brl=$(echo "$results" | jq -s '[.[].savings_brl_year] | add // 0')

    cat > "$output_file" <<EOF
{
    "generated_at": "$(date -Iseconds)",
    "cluster": "$(kubectl config current-context)",
    "pricing": {
        "cpu_cost_per_hour_usd": $CPU_COST_PER_HOUR,
        "memory_cost_per_gb_hour_usd": $MEMORY_COST_PER_GB_HOUR,
        "exchange_rate_usd_to_brl": $BRL_EXCHANGE_RATE
    },
    "summary": {
        "total_workloads": $(echo "$results" | jq -s 'length'),
        "workloads_with_recommendations": $(echo "$results" | jq -s '[.[] | select(.savings_usd_year > 0)] | length'),
        "total_savings_year_usd": $total_savings_year_usd,
        "total_savings_year_brl": $total_savings_year_brl,
        "average_cpu_reduction_pct": $(echo "$results" | jq -s '[.[].cpu_reduction_pct] | add / length'),
        "average_memory_reduction_pct": $(echo "$results" | jq -s '[.[].memory_reduction_pct] | add / length')
    },
    "workloads": $(echo "$results" | jq -s 'sort_by(-.savings_brl_year)')
}
EOF

    log_success "JSON report saved to: $output_file"
}

generate_html_report() {
    local results="$1"
    local output_file="${2%.txt}.html"

    local total_savings_year_brl
    total_savings_year_brl=$(echo "$results" | jq -s '[.[].savings_brl_year] | add // 0')

    cat > "$output_file" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPA Savings Analysis Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
               line-height: 1.6; color: #333; background: #f5f5f5; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; margin-bottom: 20px; }
        h2 { color: #34495e; margin-top: 30px; margin-bottom: 15px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin: 20px 0; }
        .summary-card { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px;
                        border-radius: 8px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
        .summary-card.green { background: linear-gradient(135deg, #56ab2f 0%, #a8e063 100%); }
        .summary-card.blue { background: linear-gradient(135deg, #2193b0 0%, #6dd5ed 100%); }
        .summary-card h3 { font-size: 14px; font-weight: 500; opacity: 0.9; margin-bottom: 10px; }
        .summary-card .value { font-size: 32px; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #34495e; color: white; font-weight: 600; }
        tr:hover { background: #f8f9fa; }
        .positive { color: #27ae60; font-weight: 600; }
        .negative { color: #e74c3c; font-weight: 600; }
        .badge { display: inline-block; padding: 4px 8px; border-radius: 4px; font-size: 12px; font-weight: 600; }
        .badge-success { background: #d4edda; color: #155724; }
        .badge-warning { background: #fff3cd; color: #856404; }
        .chart { margin: 30px 0; }
        footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #7f8c8d; font-size: 14px; text-align: center; }
    </style>
</head>
<body>
    <div class="container">
        <h1>VPA Savings Analysis Report</h1>
        <p><strong>Generated:</strong> <span id="timestamp"></span> | <strong>Cluster:</strong> <span id="cluster"></span></p>

        <div class="summary-grid">
            <div class="summary-card green">
                <h3>Total Annual Savings</h3>
                <div class="value" id="total-savings-brl">R$ 0.00</div>
            </div>
            <div class="summary-card blue">
                <h3>Workloads Analyzed</h3>
                <div class="value" id="total-workloads">0</div>
            </div>
            <div class="summary-card">
                <h3>Avg CPU Reduction</h3>
                <div class="value" id="avg-cpu-reduction">0%</div>
            </div>
            <div class="summary-card">
                <h3>Avg Memory Reduction</h3>
                <div class="value" id="avg-memory-reduction">0%</div>
            </div>
        </div>

        <h2>Workload Savings Breakdown</h2>
        <table id="workloads-table">
            <thead>
                <tr>
                    <th>Workload</th>
                    <th>Namespace</th>
                    <th>CPU Reduction</th>
                    <th>Memory Reduction</th>
                    <th>Annual Savings (BRL)</th>
                </tr>
            </thead>
            <tbody id="workloads-tbody">
            </tbody>
        </table>

        <h2>Resource Changes</h2>
        <div id="resource-changes"></div>

        <footer>
            <p>Generated by VPA Savings Calculator | DevOps Specialist Agent</p>
        </footer>
    </div>

    <script>
        // Data will be injected here
        const data = DATA_PLACEHOLDER;

        // Populate summary
        document.getElementById('timestamp').textContent = new Date(data.generated_at).toLocaleString();
        document.getElementById('cluster').textContent = data.cluster;
        document.getElementById('total-savings-brl').textContent = 'R$ ' + data.summary.total_savings_year_brl.toLocaleString('pt-BR', {minimumFractionDigits: 2});
        document.getElementById('total-workloads').textContent = data.summary.total_workloads;
        document.getElementById('avg-cpu-reduction').textContent = data.summary.average_cpu_reduction_pct.toFixed(1) + '%';
        document.getElementById('avg-memory-reduction').textContent = data.summary.average_memory_reduction_pct.toFixed(1) + '%';

        // Populate workloads table
        const tbody = document.getElementById('workloads-tbody');
        data.workloads.forEach(w => {
            if (w.savings_brl_year <= 0) return;
            const row = tbody.insertRow();
            row.innerHTML = `
                <td><strong>${w.vpa_name}</strong></td>
                <td>${w.namespace}</td>
                <td class="positive">${w.cpu_reduction_pct.toFixed(1)}%</td>
                <td class="positive">${w.memory_reduction_pct.toFixed(1)}%</td>
                <td class="positive">R$ ${w.savings_brl_year.toLocaleString('pt-BR', {minimumFractionDigits: 2})}</td>
            `;
        });

        // Populate resource changes
        const changesDiv = document.getElementById('resource-changes');
        data.workloads.forEach(w => {
            if (!w.target_cpu || w.target_cpu === '0') return;
            const card = document.createElement('div');
            card.style.cssText = 'background: #f8f9fa; padding: 15px; margin: 10px 0; border-radius: 6px; border-left: 4px solid #3498db;';
            card.innerHTML = `
                <h3 style="color: #2c3e50; margin-bottom: 10px;">${w.namespace}/${w.vpa_name}</h3>
                <p><strong>Current:</strong> CPU=${w.current_cpu}, Memory=${w.current_memory}</p>
                <p><strong>Target:</strong> CPU=${w.target_cpu}, Memory=${w.target_memory}</p>
                <p><strong>Annual Savings:</strong> <span class="positive">R$ ${w.savings_brl_year.toFixed(2)}</span></p>
            `;
            changesDiv.appendChild(card);
        });
    </script>
</body>
</html>
HTMLEOF

    # Inject JSON data into HTML
    local json_data
    json_data=$(generate_json_data "$results")
    sed -i "s|DATA_PLACEHOLDER|$json_data|g" "$output_file"

    log_success "HTML report saved to: $output_file"
}

generate_json_data() {
    local results="$1"
    local total_savings_year_usd
    local total_savings_year_brl
    total_savings_year_usd=$(echo "$results" | jq -s '[.[].savings_usd_year] | add // 0')
    total_savings_year_brl=$(echo "$results" | jq -s '[.[].savings_brl_year] | add // 0')

    cat <<EOF
{
    "generated_at": "$(date -Iseconds)",
    "cluster": "$(kubectl config current-context)",
    "summary": {
        "total_workloads": $(echo "$results" | jq -s 'length'),
        "total_savings_year_brl": $total_savings_year_brl,
        "average_cpu_reduction_pct": $(echo "$results" | jq -s '[.[].cpu_reduction_pct] | add / length'),
        "average_memory_reduction_pct": $(echo "$results" | jq -s '[.[].memory_reduction_pct] | add / length')
    },
    "workloads": $(echo "$results" | jq -s 'sort_by(-.savings_brl_year)')
}
EOF
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
            --html)
                HTML_OUTPUT=1
                shift
                ;;
            --no-color)
                NO_COLOR=1
                shift
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

    # Validation phase
    log_info "Running pre-flight checks..."
    check_dependencies || exit 1
    check_cluster_access || exit 1
    check_vpa_crd || exit 2
    log_success "All pre-flight checks passed"
    echo ""

    # Data collection phase
    log_info "Collecting VPA data from cluster..."
    local vpa_list
    vpa_list=$(get_vpa_list)
    local total_vpas
    total_vpas=$(echo "$vpa_list" | wc -l)

    if [[ $total_vpas -eq 0 ]]; then
        log_error "No VPA objects found in cluster"
        exit 2
    fi

    log_success "Found $total_vpas VPA objects"
    echo ""

    # Analysis phase
    log_info "Analyzing VPA recommendations..."
    local results=""
    local current=0

    while IFS='|' read -r namespace vpa_name; do
        [[ -z "$namespace" ]] && continue  # Skip empty lines

        ((current++))

        if [[ $VERBOSE -eq 0 ]]; then
            printf "\r[INFO] Progress: %d/%d workloads analyzed..." "$current" "$total_vpas" >&2
        fi

        log_verbose "Processing VPA: $namespace/$vpa_name ($current/$total_vpas)"

        # Get recommendation
        local recommendation
        recommendation=$(get_vpa_recommendation "$namespace" "$vpa_name") || {
            log_verbose "  Failed to get recommendation"
            continue
        }

        if [[ "$recommendation" == "null" || -z "$recommendation" ]]; then
            log_verbose "  Skipping (no recommendation available)"
            continue
        fi

        # Get current resources
        local current_resources
        current_resources=$(get_current_resources "$namespace" "$vpa_name") || {
            log_verbose "  Failed to get current resources"
            continue
        }

        # Calculate savings
        local workload_result
        workload_result=$(calculate_workload_savings "$namespace" "$vpa_name" "$current_resources" "$recommendation") || {
            log_verbose "  Failed to calculate savings"
            continue
        }

        if [[ -n "$results" ]]; then
            results="$results"$'\n'"$workload_result"
        else
            results="$workload_result"
        fi

    done <<< "$vpa_list"

    if [[ $VERBOSE -eq 0 ]]; then
        echo "" >&2  # New line after progress indicator
    fi

    log_success "Analysis complete"
    echo ""

    # Reporting phase
    log_info "Generating reports..."

    generate_text_report "$results" "$OUTPUT_FILE"
    log_success "Text report saved to: $OUTPUT_FILE"

    if [[ $JSON_OUTPUT -eq 1 ]]; then
        generate_json_report "$results" "$OUTPUT_FILE"
    fi

    if [[ $HTML_OUTPUT -eq 1 ]]; then
        generate_html_report "$results" "$OUTPUT_FILE"
    fi

    echo ""
    log_success "VPA Savings Analysis complete!"
    echo ""

    # Display summary
    echo -e "${BOLD}Quick Summary:${RESET}"
    local total_savings_brl
    total_savings_brl=$(echo "$results" | jq -s '[.[].savings_brl_year] | add // 0')
    printf "  Total Annual Savings: ${GREEN}R\$ %'.2f${RESET}\n" "$total_savings_brl"
    echo ""
    echo "View full report: $OUTPUT_FILE"
}

# Run main function
main "$@"

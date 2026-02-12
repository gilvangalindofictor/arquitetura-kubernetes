#!/usr/bin/env bash

################################################################################
# OIDC Monitoring Script
# Purpose: Monitor Keycloak, GitLab, and ArgoCD logs for OIDC authentication issues
# Usage: ./oidc-monitor.sh [OPTIONS]
# Author: Platform Team
# Date: 2026-02-12
################################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${LOG_DIR:-/var/log/oidc-monitor}"
REPORT_DIR="${REPORT_DIR:-/var/log/oidc-monitor/reports}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/oidc-monitor-${TIMESTAMP}.log"
REPORT_FILE="${REPORT_DIR}/oidc-report-${TIMESTAMP}.json"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
ERROR_THRESHOLD="${ERROR_THRESHOLD:-10}"
MONITORING_DURATION="${MONITORING_DURATION:-3600}" # Default: 1 hour
CHECK_INTERVAL="${CHECK_INTERVAL:-60}" # Check every 60 seconds

# Namespaces
KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
GITLAB_NAMESPACE="${GITLAB_NAMESPACE:-gitlab-staging}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

# Error patterns to detect
declare -A ERROR_PATTERNS=(
    ["login_error"]="LOGIN_ERROR|login.*error|authentication.*failed"
    ["invalid_request"]="invalid_request|invalid.*client|client.*not.*found"
    ["pkce_error"]="PKCE.*enforced|pkce.*required|code.*challenge.*required"
    ["expired_code"]="expired.*code|authorization.*code.*expired|code.*invalid"
    ["token_error"]="invalid.*token|token.*expired|token.*validation.*failed"
    ["redirect_error"]="redirect.*uri.*mismatch|invalid.*redirect"
    ["scope_error"]="invalid.*scope|scope.*not.*permitted"
    ["generic_error"]="ERROR|WARN.*oauth|WARN.*oidc"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Helper Functions
################################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Please install jq."
        exit 1
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi

    # Create directories
    mkdir -p "$LOG_DIR" "$REPORT_DIR"

    log_success "Prerequisites check passed"
}

get_pods() {
    local namespace="$1"
    local label_selector="$2"

    kubectl get pods -n "$namespace" -l "$label_selector" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo ""
}

fetch_logs() {
    local namespace="$1"
    local pod="$2"
    local since="$3"
    local container="${4:-}"

    local container_flag=""
    if [[ -n "$container" ]]; then
        container_flag="-c $container"
    fi

    kubectl logs -n "$namespace" "$pod" $container_flag \
        --since="${since}s" --timestamps 2>/dev/null || echo ""
}

analyze_logs() {
    local service_name="$1"
    local logs="$2"
    local -n results=$3

    if [[ -z "$logs" ]]; then
        return
    fi

    for pattern_name in "${!ERROR_PATTERNS[@]}"; do
        local pattern="${ERROR_PATTERNS[$pattern_name]}"
        local count=$(echo "$logs" | grep -iE "$pattern" | wc -l)

        if [[ $count -gt 0 ]]; then
            local key="${service_name}_${pattern_name}"
            results[$key]=$count

            # Extract sample error messages
            local samples=$(echo "$logs" | grep -iE "$pattern" | head -3)
            if [[ -n "$samples" ]]; then
                results["${key}_samples"]="$samples"
            fi
        fi
    done
}

monitor_keycloak() {
    local since="$1"
    local -n results=$2

    log_info "Monitoring Keycloak logs..."

    local pods=$(get_pods "$KEYCLOAK_NAMESPACE" "app.kubernetes.io/name=keycloakx")

    if [[ -z "$pods" ]]; then
        log_warn "No running Keycloak pods found in namespace: $KEYCLOAK_NAMESPACE"
        return
    fi

    for pod in $pods; do
        log_info "  Fetching logs from pod: $pod"
        local logs=$(fetch_logs "$KEYCLOAK_NAMESPACE" "$pod" "$since")
        analyze_logs "keycloak" "$logs" results
    done
}

monitor_gitlab() {
    local since="$1"
    local -n results=$2

    log_info "Monitoring GitLab logs..."

    # Monitor webservice pods (handles OIDC authentication)
    local webservice_pods=$(get_pods "$GITLAB_NAMESPACE" "app=webservice")

    if [[ -z "$webservice_pods" ]]; then
        log_warn "No running GitLab webservice pods found in namespace: $GITLAB_NAMESPACE"
    else
        for pod in $webservice_pods; do
            log_info "  Fetching logs from GitLab webservice pod: $pod"
            local logs=$(fetch_logs "$GITLAB_NAMESPACE" "$pod" "$since" "webservice")
            analyze_logs "gitlab_webservice" "$logs" results
        done
    fi

    # Monitor workhorse pods (proxy layer)
    local workhorse_pods=$(get_pods "$GITLAB_NAMESPACE" "app=webservice")

    for pod in $workhorse_pods; do
        log_info "  Fetching logs from GitLab workhorse container: $pod"
        local logs=$(fetch_logs "$GITLAB_NAMESPACE" "$pod" "$since" "gitlab-workhorse")
        analyze_logs "gitlab_workhorse" "$logs" results
    done
}

monitor_argocd() {
    local since="$1"
    local -n results=$2

    log_info "Monitoring ArgoCD logs..."

    # Monitor ArgoCD server (handles OIDC)
    local server_pods=$(get_pods "$ARGOCD_NAMESPACE" "app.kubernetes.io/name=argocd-server")

    if [[ -z "$server_pods" ]]; then
        log_warn "No running ArgoCD server pods found in namespace: $ARGOCD_NAMESPACE"
        return
    fi

    for pod in $server_pods; do
        log_info "  Fetching logs from ArgoCD server pod: $pod"
        local logs=$(fetch_logs "$ARGOCD_NAMESPACE" "$pod" "$since")
        analyze_logs "argocd_server" "$logs" results
    done

    # Monitor ArgoCD dex (SSO)
    local dex_pods=$(get_pods "$ARGOCD_NAMESPACE" "app.kubernetes.io/name=argocd-dex-server")

    for pod in $dex_pods; do
        log_info "  Fetching logs from ArgoCD dex pod: $pod"
        local logs=$(fetch_logs "$ARGOCD_NAMESPACE" "$pod" "$since")
        analyze_logs "argocd_dex" "$logs" results
    done
}

generate_report() {
    local -n results=$1
    local total_errors=0

    log_info "Generating report..."

    # Calculate total errors
    for key in "${!results[@]}"; do
        if [[ ! "$key" =~ _samples$ ]]; then
            total_errors=$((total_errors + results[$key]))
        fi
    done

    # Create JSON report
    local json_output='{"timestamp":"'"$TIMESTAMP"'","duration_seconds":'"$CHECK_INTERVAL"',"total_errors":'"$total_errors"',"errors":{'

    local first=true
    for key in "${!results[@]}"; do
        if [[ ! "$key" =~ _samples$ ]]; then
            if [[ "$first" = false ]]; then
                json_output+=','
            fi
            json_output+='"'"$key"'":'"${results[$key]}"
            first=false
        fi
    done

    json_output+='},"samples":{'

    first=true
    for key in "${!results[@]}"; do
        if [[ "$key" =~ _samples$ ]]; then
            if [[ "$first" = false ]]; then
                json_output+=','
            fi
            local escaped_samples=$(echo "${results[$key]}" | jq -Rs .)
            json_output+='"'"$key"'":'"$escaped_samples"
            first=false
        fi
    done

    json_output+='}}'

    echo "$json_output" | jq '.' > "$REPORT_FILE"

    log_success "Report saved to: $REPORT_FILE"

    # Print summary
    echo ""
    echo "========================================="
    echo "OIDC Monitoring Report - $TIMESTAMP"
    echo "========================================="
    echo "Total Errors Detected: $total_errors"
    echo ""

    if [[ $total_errors -gt 0 ]]; then
        echo "Error Breakdown:"
        for key in "${!results[@]}"; do
            if [[ ! "$key" =~ _samples$ ]]; then
                printf "  %-40s : %d\n" "$key" "${results[$key]}"
            fi
        done
        echo ""
    fi

    echo "$total_errors"
}

send_slack_alert() {
    local total_errors="$1"
    local -n results=$2

    if [[ -z "$SLACK_WEBHOOK_URL" ]]; then
        log_warn "Slack webhook URL not configured. Skipping Slack notification."
        return
    fi

    if [[ $total_errors -lt $ERROR_THRESHOLD ]]; then
        log_info "Total errors ($total_errors) below threshold ($ERROR_THRESHOLD). No alert sent."
        return
    fi

    log_info "Sending Slack alert (errors: $total_errors, threshold: $ERROR_THRESHOLD)..."

    local error_summary=""
    for key in "${!results[@]}"; do
        if [[ ! "$key" =~ _samples$ ]] && [[ ${results[$key]} -gt 0 ]]; then
            error_summary+="• $key: ${results[$key]}\n"
        fi
    done

    local payload=$(cat <<EOF
{
  "text": ":warning: OIDC Authentication Errors Detected",
  "blocks": [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": ":warning: OIDC Authentication Alert"
      }
    },
    {
      "type": "section",
      "fields": [
        {
          "type": "mrkdwn",
          "text": "*Total Errors:*\n$total_errors"
        },
        {
          "type": "mrkdwn",
          "text": "*Threshold:*\n$ERROR_THRESHOLD"
        },
        {
          "type": "mrkdwn",
          "text": "*Timestamp:*\n$TIMESTAMP"
        },
        {
          "type": "mrkdwn",
          "text": "*Check Interval:*\n${CHECK_INTERVAL}s"
        }
      ]
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Error Summary:*\n$error_summary"
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Report:* \`$REPORT_FILE\`"
      }
    }
  ]
}
EOF
)

    if curl -X POST -H 'Content-type: application/json' \
        --data "$payload" \
        "$SLACK_WEBHOOK_URL" &> /dev/null; then
        log_success "Slack alert sent successfully"
    else
        log_error "Failed to send Slack alert"
    fi
}

continuous_monitoring() {
    local duration="$MONITORING_DURATION"
    local elapsed=0

    log_info "Starting continuous monitoring for ${duration}s (check interval: ${CHECK_INTERVAL}s)"

    while [[ $elapsed -lt $duration ]]; do
        declare -A results

        log_info ""
        log_info "=== Monitoring cycle at $(date) ==="

        monitor_keycloak "$CHECK_INTERVAL" results
        monitor_gitlab "$CHECK_INTERVAL" results
        monitor_argocd "$CHECK_INTERVAL" results

        local total_errors=$(generate_report results)

        send_slack_alert "$total_errors" results

        elapsed=$((elapsed + CHECK_INTERVAL))

        if [[ $elapsed -lt $duration ]]; then
            log_info "Sleeping for ${CHECK_INTERVAL}s... (elapsed: ${elapsed}s/${duration}s)"
            sleep "$CHECK_INTERVAL"
        fi
    done

    log_success "Continuous monitoring completed after ${duration}s"
}

single_check() {
    declare -A results

    log_info "=== Running single check at $(date) ==="

    monitor_keycloak "$CHECK_INTERVAL" results
    monitor_gitlab "$CHECK_INTERVAL" results
    monitor_argocd "$CHECK_INTERVAL" results

    local total_errors=$(generate_report results)

    send_slack_alert "$total_errors" results
}

show_usage() {
    cat <<EOF
OIDC Monitoring Script

Usage: $0 [OPTIONS]

Options:
  -d, --duration SECONDS    Monitoring duration (default: 3600 = 1 hour)
  -i, --interval SECONDS    Check interval (default: 60 seconds)
  -t, --threshold COUNT     Error threshold for alerts (default: 10)
  -s, --single              Run a single check instead of continuous monitoring
  -h, --help                Show this help message

Environment Variables:
  LOG_DIR                   Directory for logs (default: /var/log/oidc-monitor)
  REPORT_DIR                Directory for reports (default: /var/log/oidc-monitor/reports)
  SLACK_WEBHOOK_URL         Slack webhook URL for alerts
  ERROR_THRESHOLD           Error threshold for alerts (default: 10)
  KEYCLOAK_NAMESPACE        Keycloak namespace (default: keycloak)
  GITLAB_NAMESPACE          GitLab namespace (default: gitlab-staging)
  ARGOCD_NAMESPACE          ArgoCD namespace (default: argocd)

Examples:
  # Run continuous monitoring for 48 hours
  $0 --duration 172800 --interval 3600

  # Run single check
  $0 --single

  # Run with custom threshold
  $0 --threshold 50 --interval 300

  # Run with Slack alerts
  SLACK_WEBHOOK_URL=https://hooks.slack.com/... $0 --duration 86400

EOF
}

################################################################################
# Main
################################################################################

main() {
    local single_mode=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--duration)
                MONITORING_DURATION="$2"
                shift 2
                ;;
            -i|--interval)
                CHECK_INTERVAL="$2"
                shift 2
                ;;
            -t|--threshold)
                ERROR_THRESHOLD="$2"
                shift 2
                ;;
            -s|--single)
                single_mode=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    log_info "OIDC Monitoring Script started"
    log_info "Configuration:"
    log_info "  Log Directory: $LOG_DIR"
    log_info "  Report Directory: $REPORT_DIR"
    log_info "  Error Threshold: $ERROR_THRESHOLD"
    log_info "  Check Interval: ${CHECK_INTERVAL}s"
    log_info "  Monitoring Duration: ${MONITORING_DURATION}s"
    log_info "  Namespaces: Keycloak=$KEYCLOAK_NAMESPACE, GitLab=$GITLAB_NAMESPACE, ArgoCD=$ARGOCD_NAMESPACE"

    check_prerequisites

    if [[ "$single_mode" = true ]]; then
        single_check
    else
        continuous_monitoring
    fi

    log_success "Monitoring completed successfully"
    log_info "Logs saved to: $LOG_FILE"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

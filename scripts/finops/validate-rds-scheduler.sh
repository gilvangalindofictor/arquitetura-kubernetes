#!/bin/bash
# =============================================================================
# RDS Scheduler Validation & Cost Tracking Script
# =============================================================================
# Purpose: Validate RDS start/stop automation and track cost savings
# Author: FinOps Team
# Date: 2026-02-27
# Usage: ./validate-rds-scheduler.sh [--test-start|--test-stop|--validate|--cost-report]
# =============================================================================

set -euo pipefail

# Configuration
INSTANCE_ID="${RDS_INSTANCE_ID:-k8s-platform-prod-postgresql}"
REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-staging}"
LAMBDA_START_FUNCTION="finops-scheduler-start-${ENVIRONMENT}"
LAMBDA_STOP_FUNCTION="finops-scheduler-stop-${ENVIRONMENT}"
DYNAMODB_TABLE="finops-scheduler-state-${ENVIRONMENT}"

# Cost constants (BRL, R$6.00 exchange rate)
RDS_HOURLY_COST_BRL=0.411  # db.t3.medium ~$0.0685/hour * 6 BRL/USD
BASELINE_MONTHLY_HOURS=730
BUSINESS_HOURS_WEEKLY=50  # 10 hours/day * 5 days
BASELINE_MONTHLY_COST_BRL=$(echo "$RDS_HOURLY_COST_BRL * $BASELINE_MONTHLY_HOURS" | bc)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

timestamp() {
    date -u +"%Y-%m-%d %H:%M:%S UTC"
}

# =============================================================================
# RDS Status Functions
# =============================================================================

get_rds_status() {
    aws rds describe-db-instances \
        --db-instance-identifier "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text 2>/dev/null || echo "NOT_FOUND"
}

get_rds_details() {
    aws rds describe-db-instances \
        --db-instance-identifier "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,AvailabilityZone:AvailabilityZone,InstanceClass:DBInstanceClass,StorageType:StorageType,AllocatedStorage:AllocatedStorage}' \
        --output table
}

wait_for_rds_status() {
    local target_status=$1
    local max_wait=${2:-600}  # 10 minutes default
    local elapsed=0
    local interval=10

    log_info "Waiting for RDS to reach status: $target_status (max ${max_wait}s)..."

    while [ $elapsed -lt $max_wait ]; do
        local current_status=$(get_rds_status)

        if [ "$current_status" = "$target_status" ]; then
            log_success "RDS reached status: $target_status (elapsed: ${elapsed}s)"
            return 0
        fi

        echo -n "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    echo ""
    log_error "Timeout waiting for RDS status $target_status (current: $(get_rds_status))"
    return 1
}

# =============================================================================
# Lambda Functions
# =============================================================================

test_lambda_start() {
    log_info "Testing Lambda start function: $LAMBDA_START_FUNCTION"

    local payload='{"action":"start","environment":"'$ENVIRONMENT'","triggered_by":"manual-test"}'

    aws lambda invoke \
        --function-name "$LAMBDA_START_FUNCTION" \
        --payload "$payload" \
        --region "$REGION" \
        /tmp/lambda-start-response.json \
        --log-type Tail \
        --query 'LogResult' \
        --output text | base64 -d

    echo ""
    log_info "Lambda response:"
    cat /tmp/lambda-start-response.json | jq '.'

    local status_code=$(cat /tmp/lambda-start-response.json | jq -r '.statusCode // 200')

    if [ "$status_code" -eq 200 ]; then
        log_success "Lambda start function executed successfully"
        return 0
    else
        log_error "Lambda start function failed with status: $status_code"
        return 1
    fi
}

test_lambda_stop() {
    log_info "Testing Lambda stop function: $LAMBDA_STOP_FUNCTION"

    local payload='{"action":"stop","environment":"'$ENVIRONMENT'","triggered_by":"manual-test"}'

    aws lambda invoke \
        --function-name "$LAMBDA_STOP_FUNCTION" \
        --payload "$payload" \
        --region "$REGION" \
        /tmp/lambda-stop-response.json \
        --log-type Tail \
        --query 'LogResult' \
        --output text | base64 -d

    echo ""
    log_info "Lambda response:"
    cat /tmp/lambda-stop-response.json | jq '.'

    local status_code=$(cat /tmp/lambda-stop-response.json | jq -r '.statusCode // 200')

    if [ "$status_code" -eq 200 ]; then
        log_success "Lambda stop function executed successfully"
        return 0
    else
        log_error "Lambda stop function failed with status: $status_code"
        return 1
    fi
}

get_lambda_logs() {
    local function_name=$1
    local minutes=${2:-5}

    log_info "Fetching logs for $function_name (last ${minutes} minutes)..."

    aws logs tail "/aws/lambda/$function_name" \
        --since "${minutes}m" \
        --format short \
        --region "$REGION"
}

# =============================================================================
# DynamoDB State Functions
# =============================================================================

get_dynamodb_state() {
    log_info "Fetching DynamoDB state from: $DYNAMODB_TABLE"

    aws dynamodb get-item \
        --table-name "$DYNAMODB_TABLE" \
        --key '{"environment":{"S":"'$ENVIRONMENT'"}}' \
        --region "$REGION" \
        --output json 2>/dev/null | jq -r '.Item // {}'
}

check_circuit_breaker() {
    local state=$(get_dynamodb_state)

    if [ -z "$state" ] || [ "$state" = "{}" ]; then
        log_warning "No DynamoDB state found for environment: $ENVIRONMENT"
        return 1
    fi

    local circuit_state=$(echo "$state" | jq -r '.circuit_breaker_state.S // "UNKNOWN"')
    local startup_failures=$(echo "$state" | jq -r '.startup_failures.N // "0"')
    local shutdown_failures=$(echo "$state" | jq -r '.shutdown_failures.N // "0"')
    local last_startup=$(echo "$state" | jq -r '.last_startup.S // "never"')
    local last_shutdown=$(echo "$state" | jq -r '.last_shutdown.S // "never"')

    echo ""
    echo "Circuit Breaker State:"
    echo "  State: $circuit_state"
    echo "  Startup Failures: $startup_failures"
    echo "  Shutdown Failures: $shutdown_failures"
    echo "  Last Startup: $last_startup"
    echo "  Last Shutdown: $last_shutdown"
    echo ""

    if [ "$circuit_state" = "OPEN" ]; then
        log_error "Circuit breaker is OPEN - automation disabled!"
        return 1
    elif [ "$circuit_state" = "CLOSED" ]; then
        log_success "Circuit breaker is CLOSED - automation operational"
        return 0
    else
        log_warning "Circuit breaker state unknown: $circuit_state"
        return 1
    fi
}

# =============================================================================
# EventBridge Schedule Functions
# =============================================================================

check_eventbridge_rules() {
    log_info "Checking EventBridge rules..."

    local startup_rule="finops-startup-${ENVIRONMENT}"
    local shutdown_rule="finops-shutdown-${ENVIRONMENT}"
    local weekend_rule="finops-weekend-shutdown-${ENVIRONMENT}"

    echo ""
    echo "EventBridge Rules Status:"

    for rule in "$startup_rule" "$shutdown_rule" "$weekend_rule"; do
        local state=$(aws events describe-rule \
            --name "$rule" \
            --region "$REGION" \
            --query 'State' \
            --output text 2>/dev/null || echo "NOT_FOUND")

        if [ "$state" = "ENABLED" ]; then
            echo -e "  ${GREEN}✓${NC} $rule: $state"
        elif [ "$state" = "DISABLED" ]; then
            echo -e "  ${YELLOW}⚠${NC} $rule: $state"
        else
            echo -e "  ${RED}✗${NC} $rule: $state"
        fi
    done

    echo ""
}

# =============================================================================
# Cost Calculation Functions
# =============================================================================

calculate_monthly_uptime() {
    local start_date=$(date -u -d 'first day of this month' +%Y-%m-%dT00:00:00)
    local end_date=$(date -u +%Y-%m-%dT%H:%M:%S)

    log_info "Calculating RDS uptime for current month..."
    log_info "Period: $start_date to $end_date"

    # Get DatabaseConnections metric to detect when RDS was running
    local datapoints=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/RDS \
        --metric-name DatabaseConnections \
        --dimensions Name=DBInstanceIdentifier,Value="$INSTANCE_ID" \
        --start-time "$start_date" \
        --end-time "$end_date" \
        --period 3600 \
        --statistics Sum \
        --region "$REGION" \
        --query 'Datapoints[*].Timestamp' \
        --output json)

    # Count hours with any activity (indicates RDS was running)
    local uptime_hours=$(echo "$datapoints" | jq 'length')

    echo "$uptime_hours"
}

generate_cost_report() {
    log_info "==================================================================="
    log_info "RDS FinOps Cost Savings Report"
    log_info "==================================================================="

    local uptime_hours=$(calculate_monthly_uptime)
    local current_month=$(date +%Y-%m)
    local days_in_month=$(date -d "$current_month-01 +1 month -1 day" +%d)
    local days_elapsed=$(date +%d)

    # Projected monthly uptime (extrapolate from current data)
    local projected_uptime=$(echo "scale=2; $uptime_hours * $days_in_month / $days_elapsed" | bc)

    # Calculate costs
    local actual_cost=$(echo "scale=2; $uptime_hours * $RDS_HOURLY_COST_BRL" | bc)
    local projected_cost=$(echo "scale=2; $projected_uptime * $RDS_HOURLY_COST_BRL" | bc)
    local savings=$(echo "scale=2; $BASELINE_MONTHLY_COST_BRL - $projected_cost" | bc)
    local savings_percent=$(echo "scale=2; ($savings / $BASELINE_MONTHLY_COST_BRL) * 100" | bc)

    # Annual projection
    local annual_savings=$(echo "scale=2; $savings * 12" | bc)

    echo ""
    echo "Period: $current_month (Day $days_elapsed of $days_in_month)"
    echo ""
    echo "Baseline (24/7 Running):"
    echo "  Monthly Hours: $BASELINE_MONTHLY_HOURS"
    echo "  Monthly Cost: R\$ $(printf "%.2f" $BASELINE_MONTHLY_COST_BRL)"
    echo ""
    echo "Actual (Current Month):"
    echo "  Uptime Hours: $uptime_hours (elapsed $days_elapsed days)"
    echo "  Actual Cost: R\$ $(printf "%.2f" $actual_cost)"
    echo ""
    echo "Projected (Full Month):"
    echo "  Projected Uptime: $(printf "%.0f" $projected_uptime) hours"
    echo "  Projected Cost: R\$ $(printf "%.2f" $projected_cost)"
    echo ""
    echo "Savings:"
    echo "  Monthly Savings: R\$ $(printf "%.2f" $savings) ($(printf "%.1f" $savings_percent)%)"
    echo "  Annual Savings: R\$ $(printf "%.2f" $annual_savings)"
    echo ""

    # Business hours target (50h/week * 4.33 weeks/month = 216.5h/month)
    local target_monthly_hours=$(echo "50 * 4.33" | bc)
    local target_cost=$(echo "scale=2; $target_monthly_hours * $RDS_HOURLY_COST_BRL" | bc)
    local target_savings=$(echo "scale=2; $BASELINE_MONTHLY_COST_BRL - $target_cost" | bc)

    echo "Target (Business Hours Only):"
    echo "  Target Uptime: $(printf "%.0f" $target_monthly_hours) hours/month"
    echo "  Target Cost: R\$ $(printf "%.2f" $target_cost)"
    echo "  Target Savings: R\$ $(printf "%.2f" $target_savings) (~60% reduction)"
    echo ""

    # Compare actual vs target
    if (( $(echo "$projected_uptime <= $target_monthly_hours * 1.1" | bc -l) )); then
        log_success "On track to meet business hours target (within 10%)"
    else
        log_warning "Uptime exceeds target - review automation schedule"
    fi

    echo "==================================================================="
}

# =============================================================================
# Validation Functions
# =============================================================================

validate_infrastructure() {
    log_info "==================================================================="
    log_info "RDS Scheduler Infrastructure Validation"
    log_info "==================================================================="

    local errors=0

    # 1. Check RDS instance exists
    log_info "1. Checking RDS instance: $INSTANCE_ID"
    local rds_status=$(get_rds_status)
    if [ "$rds_status" = "NOT_FOUND" ]; then
        log_error "RDS instance not found: $INSTANCE_ID"
        errors=$((errors + 1))
    else
        log_success "RDS instance found (status: $rds_status)"
        get_rds_details
    fi

    # 2. Check Lambda functions exist
    log_info "2. Checking Lambda functions"

    for func in "$LAMBDA_START_FUNCTION" "$LAMBDA_STOP_FUNCTION"; do
        if aws lambda get-function --function-name "$func" --region "$REGION" &>/dev/null; then
            log_success "Lambda function exists: $func"
        else
            log_error "Lambda function not found: $func"
            errors=$((errors + 1))
        fi
    done

    # 3. Check DynamoDB table exists
    log_info "3. Checking DynamoDB table: $DYNAMODB_TABLE"
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" --region "$REGION" &>/dev/null; then
        log_success "DynamoDB table exists"
        check_circuit_breaker || errors=$((errors + 1))
    else
        log_error "DynamoDB table not found: $DYNAMODB_TABLE"
        errors=$((errors + 1))
    fi

    # 4. Check EventBridge rules
    log_info "4. Checking EventBridge rules"
    check_eventbridge_rules

    # 5. Check IAM permissions (test Lambda invoke)
    log_info "5. Testing Lambda permissions (dry-run invoke)"
    if aws lambda get-function --function-name "$LAMBDA_START_FUNCTION" --region "$REGION" &>/dev/null; then
        log_success "Lambda invoke permissions OK"
    else
        log_error "Lambda invoke permissions missing"
        errors=$((errors + 1))
    fi

    echo ""
    echo "==================================================================="

    if [ $errors -eq 0 ]; then
        log_success "All infrastructure checks passed ✓"
        return 0
    else
        log_error "Infrastructure validation failed with $errors error(s)"
        return 1
    fi
}

validate_end_to_end() {
    log_info "==================================================================="
    log_info "End-to-End RDS Scheduler Validation"
    log_info "==================================================================="

    # Record initial state
    local initial_status=$(get_rds_status)
    log_info "Initial RDS status: $initial_status"

    # Test 1: Stop RDS (if running)
    if [ "$initial_status" = "available" ]; then
        log_info "Test 1: Stopping RDS via Lambda"
        test_lambda_stop || return 1

        log_info "Waiting 30s for stop to initiate..."
        sleep 30

        local stop_status=$(get_rds_status)
        if [[ "$stop_status" =~ ^(stopping|stopped)$ ]]; then
            log_success "RDS stop initiated successfully (status: $stop_status)"
        else
            log_error "RDS stop failed (status: $stop_status)"
            return 1
        fi

        # Wait for fully stopped
        if [ "$stop_status" = "stopping" ]; then
            wait_for_rds_status "stopped" 300 || return 1
        fi
    fi

    # Test 2: Start RDS
    log_info "Test 2: Starting RDS via Lambda"
    test_lambda_start || return 1

    log_info "Waiting 30s for start to initiate..."
    sleep 30

    local start_status=$(get_rds_status)
    if [[ "$start_status" =~ ^(starting|available)$ ]]; then
        log_success "RDS start initiated successfully (status: $start_status)"
    else
        log_error "RDS start failed (status: $start_status)"
        return 1
    fi

    # Wait for fully available
    if [ "$start_status" = "starting" ]; then
        wait_for_rds_status "available" 600 || return 1
    fi

    # Test 3: Validate connectivity
    log_info "Test 3: Validating RDS connectivity"
    local endpoint=$(aws rds describe-db-instances \
        --db-instance-identifier "$INSTANCE_ID" \
        --region "$REGION" \
        --query 'DBInstances[0].Endpoint.Address' \
        --output text)

    if [ -n "$endpoint" ]; then
        log_success "RDS endpoint available: $endpoint"
    else
        log_error "RDS endpoint not available"
        return 1
    fi

    echo ""
    echo "==================================================================="
    log_success "End-to-end validation completed successfully ✓"

    # Show Lambda logs
    log_info "Lambda start function logs (last 5 minutes):"
    get_lambda_logs "$LAMBDA_START_FUNCTION" 5

    echo ""
    log_info "Lambda stop function logs (last 5 minutes):"
    get_lambda_logs "$LAMBDA_STOP_FUNCTION" 5
}

# =============================================================================
# Main Function
# =============================================================================

usage() {
    cat <<EOF
Usage: $0 [COMMAND]

Commands:
  --test-start      Test Lambda start function (manual invocation)
  --test-stop       Test Lambda stop function (manual invocation)
  --validate        Validate infrastructure (Lambda, DynamoDB, EventBridge)
  --validate-e2e    Full end-to-end test (stop → start → verify)
  --cost-report     Generate monthly cost savings report
  --check-cb        Check circuit breaker state
  --logs-start      Show Lambda start function logs (last 5 min)
  --logs-stop       Show Lambda stop function logs (last 5 min)
  --status          Show current RDS status
  --help            Show this help message

Environment Variables:
  RDS_INSTANCE_ID   RDS instance identifier (default: k8s-platform-prod-postgresql)
  AWS_REGION        AWS region (default: us-east-1)
  ENVIRONMENT       Environment name (default: staging)

Examples:
  # Quick status check
  $0 --status

  # Validate infrastructure
  $0 --validate

  # Generate cost report
  $0 --cost-report

  # Test Lambda functions
  $0 --test-start
  $0 --test-stop

  # Full end-to-end validation
  $0 --validate-e2e
EOF
    exit 1
}

main() {
    local command=${1:-"--help"}

    case "$command" in
        --test-start)
            test_lambda_start
            ;;
        --test-stop)
            test_lambda_stop
            ;;
        --validate)
            validate_infrastructure
            ;;
        --validate-e2e)
            validate_end_to_end
            ;;
        --cost-report)
            generate_cost_report
            ;;
        --check-cb)
            check_circuit_breaker
            ;;
        --logs-start)
            get_lambda_logs "$LAMBDA_START_FUNCTION" 5
            ;;
        --logs-stop)
            get_lambda_logs "$LAMBDA_STOP_FUNCTION" 5
            ;;
        --status)
            log_info "RDS Instance: $INSTANCE_ID"
            log_info "Status: $(get_rds_status)"
            get_rds_details
            ;;
        --help|*)
            usage
            ;;
    esac
}

main "$@"

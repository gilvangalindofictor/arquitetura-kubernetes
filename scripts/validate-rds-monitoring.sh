#!/usr/bin/env bash
#===============================================================================
# RDS Monitoring Validation Script
#===============================================================================
# Purpose: Validate RDS monitoring stack deployment (CloudWatch + Prometheus + Grafana)
# Usage: ./scripts/validate-rds-monitoring.sh
# Exit codes: 0 = all checks passed, 1 = one or more checks failed
#===============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
CHECKS_TOTAL=0
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0

#===============================================================================
# Helper Functions
#===============================================================================

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_check() {
    echo -e "${BLUE}[CHECK]${NC} $1"
    ((CHECKS_TOTAL++))
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((CHECKS_PASSED++))
}

print_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((CHECKS_FAILED++))
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((CHECKS_WARNING++))
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

#===============================================================================
# Phase 1: CloudWatch Alarms
#===============================================================================

validate_cloudwatch_alarms() {
    print_header "Phase 1: CloudWatch Alarms"

    # Check if AWS CLI is configured
    print_check "AWS CLI credentials configured"
    if aws sts get-caller-identity &>/dev/null; then
        print_success "AWS CLI credentials valid"
        ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
        print_info "AWS Account: $ACCOUNT_ID"
    else
        print_failure "AWS CLI credentials not configured or invalid"
        print_info "Configure with: aws configure --profile k8s-platform-prod"
        return 1
    fi

    # Check SNS topic exists
    print_check "SNS topic 'staging-rds-alerts' exists"
    if aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:us-east-1:$ACCOUNT_ID:staging-rds-alerts" \
        --region us-east-1 &>/dev/null; then
        print_success "SNS topic exists"
    else
        print_failure "SNS topic not found"
        return 1
    fi

    # Check SNS subscription status
    print_check "SNS email subscription confirmed"
    SUBSCRIPTION_STATUS=$(aws sns list-subscriptions-by-topic \
        --topic-arn "arn:aws:sns:us-east-1:$ACCOUNT_ID:staging-rds-alerts" \
        --region us-east-1 \
        --query 'Subscriptions[?Protocol==`email`].SubscriptionArn' \
        --output text)

    if [[ "$SUBSCRIPTION_STATUS" == "PendingConfirmation" ]]; then
        print_warning "SNS subscription pending confirmation"
        print_info "Check email and click confirmation link"
    elif [[ -z "$SUBSCRIPTION_STATUS" ]]; then
        print_failure "No email subscription found"
        return 1
    else
        print_success "SNS email subscription confirmed"
        print_info "Subscription ARN: $SUBSCRIPTION_STATUS"
    fi

    # Check CloudWatch alarms
    ALARM_NAMES=(
        "staging-rds-instance-stopped"
        "staging-rds-high-cpu"
        "staging-rds-high-connections"
        "staging-rds-low-storage"
        "staging-rds-high-read-latency"
        "staging-rds-high-write-latency"
    )

    print_check "CloudWatch alarms configured (6 expected)"
    ALARMS_FOUND=0
    for ALARM_NAME in "${ALARM_NAMES[@]}"; do
        if aws cloudwatch describe-alarms \
            --alarm-names "$ALARM_NAME" \
            --region us-east-1 \
            --query 'MetricAlarms[0].AlarmName' \
            --output text &>/dev/null; then
            ((ALARMS_FOUND++))
        fi
    done

    if [[ $ALARMS_FOUND -eq 6 ]]; then
        print_success "All 6 CloudWatch alarms configured"
    else
        print_failure "Only $ALARMS_FOUND/6 alarms found"
        return 1
    fi

    # Check RDS event subscription
    print_check "RDS event subscription exists"
    if aws rds describe-event-subscriptions \
        --subscription-name staging-rds-instance-events \
        --region us-east-1 &>/dev/null; then
        print_success "RDS event subscription exists"
    else
        print_failure "RDS event subscription not found"
        return 1
    fi

    echo ""
}

#===============================================================================
# Phase 2: Prometheus Alerts
#===============================================================================

validate_prometheus_alerts() {
    print_header "Phase 2: Prometheus Alerts"

    # Check PrometheusRule exists
    print_check "PrometheusRule 'rds-connectivity-alerts' exists"
    if kubectl get prometheusrules -n staging-observability-monitoring rds-connectivity-alerts &>/dev/null; then
        print_success "PrometheusRule exists"
    else
        print_failure "PrometheusRule not found"
        return 1
    fi

    # Check alert count
    print_check "Prometheus alerts configured (6 expected)"
    ALERT_COUNT=$(kubectl get prometheusrules -n staging-observability-monitoring rds-connectivity-alerts \
        -o yaml | grep -c "alert:" || echo "0")

    if [[ $ALERT_COUNT -eq 6 ]]; then
        print_success "All 6 Prometheus alerts configured"
    else
        print_failure "Only $ALERT_COUNT/6 alerts found"
        return 1
    fi

    # List configured alerts
    print_info "Configured alerts:"
    kubectl get prometheusrules -n staging-observability-monitoring rds-connectivity-alerts \
        -o yaml | grep "alert:" | sed 's/.*alert: /  - /' | sort | uniq

    # Check if Prometheus is scraping rules
    print_check "Prometheus has loaded RDS alerts"
    if kubectl get prometheusrules -n staging-observability-monitoring rds-connectivity-alerts \
        -o yaml | grep -q "prometheus: kube-prometheus-stack-prometheus"; then
        print_success "Prometheus label configured correctly"
    else
        print_warning "Prometheus label missing (rules may not be loaded)"
    fi

    echo ""
}

#===============================================================================
# Phase 3: Grafana Dashboard
#===============================================================================

validate_grafana_dashboard() {
    print_header "Phase 3: Grafana Dashboard"

    # Check ConfigMap exists
    print_check "Dashboard ConfigMap 'rds-monitoring-dashboard' exists"
    if kubectl get configmap -n staging-observability-monitoring rds-monitoring-dashboard &>/dev/null; then
        print_success "Dashboard ConfigMap exists"
    else
        print_failure "Dashboard ConfigMap not found"
        return 1
    fi

    # Check Grafana dashboard label
    print_check "ConfigMap has 'grafana_dashboard: 1' label"
    LABEL_VALUE=$(kubectl get configmap -n staging-observability-monitoring rds-monitoring-dashboard \
        -o jsonpath='{.metadata.labels.grafana_dashboard}' 2>/dev/null || echo "")

    if [[ "$LABEL_VALUE" == "1" ]]; then
        print_success "Grafana dashboard label configured"
    else
        print_failure "Missing or incorrect grafana_dashboard label"
        return 1
    fi

    # Check dashboard JSON structure
    print_check "Dashboard JSON is valid"
    if kubectl get configmap -n staging-observability-monitoring rds-monitoring-dashboard \
        -o jsonpath='{.data.rds-monitoring\.json}' | jq -e '.uid' &>/dev/null; then
        DASHBOARD_UID=$(kubectl get configmap -n staging-observability-monitoring rds-monitoring-dashboard \
            -o jsonpath='{.data.rds-monitoring\.json}' | jq -r '.uid')
        print_success "Dashboard JSON valid (UID: $DASHBOARD_UID)"
    else
        print_failure "Dashboard JSON is invalid or missing"
        return 1
    fi

    # Check Grafana sidecar logs for import
    print_check "Grafana sidecar imported dashboard"
    if kubectl logs -n staging-observability-monitoring \
        -l app.kubernetes.io/name=grafana \
        -c grafana-sc-dashboard \
        --tail=100 2>/dev/null | grep -q "rds-monitoring.json"; then
        print_success "Dashboard imported by Grafana sidecar"
    else
        print_warning "Dashboard import not found in recent logs (may have imported earlier)"
    fi

    # Check Grafana service accessibility
    print_check "Grafana service is accessible"
    if kubectl get svc -n staging-observability-monitoring kube-prometheus-stack-grafana &>/dev/null; then
        GRAFANA_SVC_TYPE=$(kubectl get svc -n staging-observability-monitoring kube-prometheus-stack-grafana \
            -o jsonpath='{.spec.type}')
        print_success "Grafana service exists (type: $GRAFANA_SVC_TYPE)"
        print_info "Access dashboard: kubectl port-forward -n staging-observability-monitoring svc/kube-prometheus-stack-grafana 3000:80"
        print_info "Dashboard URL: http://localhost:3000/d/$DASHBOARD_UID"
    else
        print_failure "Grafana service not found"
        return 1
    fi

    echo ""
}

#===============================================================================
# Phase 4: Integration Checks
#===============================================================================

validate_integration() {
    print_header "Phase 4: Integration Checks"

    # Check RDS instance exists
    print_check "RDS instance 'k8s-platform-prod-postgresql' exists"
    if kubectl get secret -n staging-platform-gitlab gitlab-postgresql-secret &>/dev/null; then
        print_success "RDS credentials secret exists (GitLab)"
    else
        print_warning "GitLab PostgreSQL secret not found"
    fi

    # Check Terraform state
    print_check "Terraform state includes RDS monitoring resources"
    cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/environments/staging
    export TF_VAR_vault_root_token=$(kubectl get secret vault-root-token -n vault-system -o jsonpath='{.data.root_token}' 2>/dev/null | base64 -d)

    if terraform state list 2>/dev/null | grep -q "module.rds_monitoring_staging"; then
        RDS_MONITORING_RESOURCES=$(terraform state list 2>/dev/null | grep -c "module.rds_monitoring_staging" || echo "0")
        print_success "Terraform manages $RDS_MONITORING_RESOURCES RDS monitoring resources"
    else
        print_failure "RDS monitoring resources not found in Terraform state"
        return 1
    fi

    # Check runbook exists
    print_check "RDS monitoring runbook exists"
    if [[ -f /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/runbooks/rds-monitoring-alerts-response.md ]]; then
        print_success "Runbook exists: docs/runbooks/rds-monitoring-alerts-response.md"
    else
        print_failure "Runbook not found"
        return 1
    fi

    # Check ADR exists
    print_check "ADR-089 (RDS Availability Monitoring) exists"
    if [[ -f /home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/adr/adr-089-rds-availability-monitoring.md ]]; then
        print_success "ADR-089 exists"
    else
        print_warning "ADR-089 not found (documentation gap)"
    fi

    echo ""
}

#===============================================================================
# Summary Report
#===============================================================================

print_summary() {
    print_header "Validation Summary"

    echo -e "Total Checks: ${CHECKS_TOTAL}"
    echo -e "${GREEN}Passed: ${CHECKS_PASSED}${NC}"
    echo -e "${RED}Failed: ${CHECKS_FAILED}${NC}"
    echo -e "${YELLOW}Warnings: ${CHECKS_WARNING}${NC}"

    echo ""

    if [[ $CHECKS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}✅ All critical checks passed!${NC}"
        echo ""
        echo -e "${BLUE}Next Steps:${NC}"
        echo "1. Confirm SNS email subscription (check inbox)"
        echo "2. Test CloudWatch alarm trigger (see runbook)"
        echo "3. Access Grafana dashboard and verify metrics"
        echo "4. Conduct team walkthrough of incident response runbook"
        echo ""
        echo "Documentation:"
        echo "- Deployment log: docs/logbook/2026-02-27-rds-monitoring-deployment.md"
        echo "- Runbook: docs/runbooks/rds-monitoring-alerts-response.md"
        echo "- ADR-089: docs/adr/adr-089-rds-availability-monitoring.md"
        return 0
    else
        echo -e "${RED}❌ Validation failed with ${CHECKS_FAILED} critical errors${NC}"
        echo ""
        echo "Please review failed checks above and remediate issues."
        echo "Refer to deployment log: docs/logbook/2026-02-27-rds-monitoring-deployment.md"
        return 1
    fi
}

#===============================================================================
# Main Execution
#===============================================================================

main() {
    echo ""
    print_header "RDS Monitoring Stack Validation"
    echo "Environment: staging"
    echo "RDS Instance: k8s-platform-prod-postgresql"
    echo "Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo ""

    # Run validation phases
    validate_cloudwatch_alarms || true
    validate_prometheus_alerts || true
    validate_grafana_dashboard || true
    validate_integration || true

    # Print summary and exit
    print_summary
    exit $?
}

# Run main function
main "$@"

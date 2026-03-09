# WAF Incident Response Runbook

**Created**: 2026-02-27
**Owner**: Platform Team / Security Team
**Runbook**: Operational guide for AWS WAF security incident response
**Related**: GAP-010 iPaaS ALB protection

---

## 📋 Overview

This runbook provides step-by-step procedures for responding to AWS WAF security alerts and incidents.

**WAF Purpose**: Protect iPaaS public endpoints from Layer 7 attacks (DDoS, SQLi, XSS, OWASP Top 10).

**Integration Points**:
1. **AWS WAF v2**: WebACL with 5 rules (rate-limit, geo-block, OWASP, SQLi, known-bad-inputs)
2. **CloudWatch Metrics**: Published to namespace `AWS/WAFV2` (AllowedRequests, BlockedRequests)
3. **Prometheus**: Scrapes CloudWatch metrics via cloudwatch-exporter
4. **Grafana**: Dashboard [waf-security-dashboard](/d/waf-security-dashboard)
5. **Alertmanager**: Routes alerts to Teams (security-incidents, platform-alerts channels)

---

## 🚨 Alert Response Procedures

### Alert 1: WAFHighBlockRate

**Trigger**: >15% of requests blocked in 5-minute window
**Severity**: warning
**Impact**: Potential attack in progress OR false positive misconfiguration

#### Investigation Steps

1. **Open Grafana Dashboard**
   ```
   https://grafana.company.com/d/waf-security-dashboard
   ```
   - Check "Block Rate %" gauge (current value)
   - Review "Blocked Requests by Rule" chart (which rule triggered most blocks?)
   - Check "Request Distribution" pie chart (ratio of allowed vs blocked)

2. **Identify Top Triggered Rules**
   ```bash
   # Query CloudWatch metrics for last 30 minutes
   aws cloudwatch get-metric-statistics \
     --namespace AWS/WAFV2 \
     --metric-name BlockedRequests \
     --dimensions Name=WebACL,Value=waf-k8s-platform-prod-staging Name=Rule,Value=ALL \
     --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 300 \
     --statistics Sum \
     --region us-east-1
   ```

3. **Review Sampled Requests (WAF Console)**
   - Navigate to: [AWS WAF Console → Web ACLs → waf-k8s-platform-prod-staging → Sampled requests](https://console.aws.amazon.com/wafv2/homev2/web-acl/waf-k8s-platform-prod-staging/sampled-requests)
   - Filter by **Rule**: Select the rule with highest block count
   - Review **Source IP**, **URI**, **Headers**, **Action** (blocked)
   - Identify patterns: single IP? multiple IPs? specific endpoint?

4. **Determine if Legitimate Traffic or Attack**

   **Legitimate Traffic Indicators**:
   - Known customer IPs or user-agents
   - Requests to valid application endpoints (e.g., `/api/v1/proposals`)
   - HTTP methods: GET, POST (not unusual methods like PROPFIND)
   - No suspicious payloads in query strings or body

   **Attack Indicators**:
   - Unknown source IPs (check IP reputation: [AbuseIPDB](https://www.abuseipdb.com/))
   - Requests to non-existent endpoints (e.g., `/admin`, `/phpmyadmin`, `/.env`)
   - Unusual HTTP methods: OPTIONS, TRACE, DELETE on public endpoints
   - SQL injection patterns: `' OR 1=1--`, `UNION SELECT`, etc.
   - XSS payloads: `<script>`, `javascript:`, etc.

#### Resolution

**If Legitimate Traffic (False Positive)**:

1. **Add Rule Exception** (temporary mitigation)
   ```bash
   # Example: Whitelist specific IP or path
   # Add to WAF WebACL rule overrides in Terraform:
   # modules/waf/main.tf → rule "aws-managed-owasp-common" → rule_action_override
   rule_action_override {
     name = "SizeRestrictions_BODY"  # Example rule causing false positive
     action {
       count {}  # Change from BLOCK to COUNT (audit mode)
     }
   }
   ```

2. **Apply Terraform Changes**
   ```bash
   cd platform-provisioning/aws/kubernetes/terraform/environments/staging
   terraform plan -target=module.waf
   terraform apply -target=module.waf
   ```

3. **Monitor for 15 Minutes**
   - Verify block rate drops below 15%
   - Confirm legitimate traffic is now allowed
   - Document exception in [WAF Configuration Log](/docs/security/waf-config-log.md)

**If Attack (Malicious Traffic)**:

1. **Monitor for Escalation** (do NOT disable WAF rules)
   - Keep WAF rules enabled (they're working as intended)
   - Watch for block rate increase (>25% = potential DDoS)
   - Check if attacker rotates IPs (indicates sophisticated attack)

2. **Add Temporary IP Block** (if single-source attack)
   ```bash
   # Create IP Set in WAF
   aws wafv2 create-ip-set \
     --name blocked-attackers-$(date +%Y%m%d) \
     --scope REGIONAL \
     --ip-address-version IPV4 \
     --addresses 203.0.113.42/32 203.0.113.43/32 \
     --region us-east-1

   # Add IP Set rule to WebACL (priority 5, before rate-limit)
   # Update Terraform: modules/waf/main.tf → add new rule block
   ```

3. **Escalate to Security Team**
   - Teams: security-incidents channel
   - Include: Block rate, top triggered rule, attacker IPs, sample payloads
   - Security team will coordinate with AWS Support if needed

4. **Document Incident**
   - Create incident ticket: JIRA SEC-XXXX
   - Timeline: when detected, actions taken, resolution time
   - Root cause: attack type, attacker IPs, targeted endpoints

---

### Alert 2: WAFGeoBlockSpike

**Trigger**: >50 requests blocked from geo-blocked countries in 5 minutes
**Severity**: warning
**Impact**: Potential coordinated attack from CN/RU/KP

#### Investigation Steps

1. **Check Geo-Blocking Rule Metrics**
   ```bash
   # Query CloudWatch for geo-block rule
   aws cloudwatch get-metric-statistics \
     --namespace AWS/WAFV2 \
     --metric-name BlockedRequests \
     --dimensions Name=WebACL,Value=waf-k8s-platform-prod-staging \
                  Name=Rule,Value=geo-block-high-risk-countries \
     --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 300 \
     --statistics Sum \
     --region us-east-1
   ```

2. **Review WAF Logs in S3** (if logging enabled)
   ```bash
   # Download latest WAF logs
   aws s3 cp s3://aws-waf-logs-k8s-platform-prod-staging/AWSLogs/891377105802/WAFLogs/us-east-1/ \
     ./waf-logs/ \
     --recursive \
     --exclude "*" \
     --include "*$(date -u +%Y/%m/%d)*"

   # Parse logs for geo-blocked requests
   cat waf-logs/*.gz | gunzip | jq -r 'select(.action == "BLOCK" and .ruleGroupList[].nonTerminatingMatchingRules[].ruleId == "geo-block-high-risk-countries") | [.httpRequest.clientIp, .httpRequest.uri, .httpRequest.country] | @csv'
   ```

3. **Identify Attack Pattern**
   - Single IP or distributed (botnet)?
   - Single endpoint or scanning multiple paths?
   - User-agent: legitimate browser or bot/script?

#### Resolution

**If Legitimate Business Traffic** (rare):

1. **Review Business Justification**
   - Contact Product Owner: Is traffic from CN/RU/KP expected?
   - Example: International customer onboarding, partner integration

2. **Add Geo-Block Exception** (requires approval)
   ```bash
   # Option A: Disable geo-blocking entirely (NOT RECOMMENDED)
   # Terraform: modules/waf/variables.tf → enable_geo_blocking = false

   # Option B: Remove specific country from block list
   # Terraform: modules/waf/variables.tf → blocked_countries = ["KP"]  # Keep only North Korea blocked
   ```

3. **Apply with Security Team Approval**
   ```bash
   terraform apply -target=module.waf
   ```

**If Attack (Expected Behavior)**:

1. **No Action Required** — WAF is working correctly
   - Geo-blocking is expected to block traffic from high-risk countries
   - Only escalate if block count exceeds 500 requests/5min (DDoS threshold)

2. **Monitor for IP Rotation** (advanced attack)
   - Attacker may use VPN/proxy to bypass geo-blocking
   - If block rate remains high AFTER geo-block spike → investigate rate-limit rule
   - If attacker switches to allowed countries → consider adding rate-limit exceptions

---

### Alert 3: WAFSQLInjectionAttempts

**Trigger**: >10 SQL injection attempts blocked in 5 minutes
**Severity**: CRITICAL
**Impact**: Active database attack attempt, potential data breach risk

#### 🚨 IMMEDIATE ACTIONS (First 5 Minutes)

1. **Escalate to Security Team** (DO NOT delay)
   ```
   Teams: security-incidents channel
   Message Template:

   🚨 CRITICAL: SQL injection attack detected by WAF
   - WebACL: waf-k8s-platform-prod-staging
   - Blocked attempts: <N> in last 5 minutes
   - Dashboard: https://grafana/d/waf-security-dashboard
   - On-call engineer: @platform-oncall
   - Status: Investigating
   ```

2. **Verify Database Is NOT Compromised**
   ```bash
   # Check RDS slow query log for suspicious queries
   aws rds describe-db-log-files \
     --db-instance-identifier k8s-platform-prod-postgresql \
     --region us-east-1 | jq -r '.DescribeDBLogFiles[].LogFileName' | grep slowquery

   # Download recent slow queries
   aws rds download-db-log-file-portion \
     --db-instance-identifier k8s-platform-prod-postgresql \
     --log-file-name error/postgresql.log.$(date +%Y-%m-%d-%H) \
     --region us-east-1 \
     --output text > /tmp/rds-slowquery.log

   # Search for attacker IPs in application logs (if SQLi bypassed WAF)
   kubectl logs -n staging-apps-ipaas -l app=backend --since=30m | grep -E "203\.0\.113\.(42|43)"
   ```

3. **Confirm WAF Blocked All Attempts** (critical check)
   ```bash
   # Verify AllowedRequests did NOT spike during same period
   aws cloudwatch get-metric-statistics \
     --namespace AWS/WAFV2 \
     --metric-name AllowedRequests \
     --dimensions Name=WebACL,Value=waf-k8s-platform-prod-staging \
     --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 300 \
     --statistics Sum

   # If AllowedRequests spiked → attacker may have bypassed WAF via different rule
   # Check OWASP common rule for XSS/LFI attempts
   ```

#### Investigation (Next 30 Minutes)

1. **Extract SQLi Payloads from WAF Logs**
   ```bash
   # Download WAF logs for last hour
   aws s3 sync s3://aws-waf-logs-k8s-platform-prod-staging/AWSLogs/ \
     ./waf-logs/ \
     --exclude "*" \
     --include "*$(date -u +%Y/%m/%d/%H)*"

   # Parse SQLi blocked requests
   zcat waf-logs/*.gz | jq -r 'select(.action == "BLOCK" and (.ruleGroupList[].nonTerminatingMatchingRules[].ruleId | contains("sqli"))) | {
     timestamp: .timestamp,
     ip: .httpRequest.clientIp,
     uri: .httpRequest.uri,
     method: .httpRequest.httpMethod,
     payload: .httpRequest.args
   }' > /tmp/sqli-attempts.json
   ```

2. **Analyze Attack Pattern**
   ```bash
   # Top attacker IPs
   jq -r '.ip' /tmp/sqli-attempts.json | sort | uniq -c | sort -rn | head -10

   # Targeted endpoints
   jq -r '.uri' /tmp/sqli-attempts.json | sort | uniq -c | sort -rn | head -10

   # Sample payloads
   jq -r '.payload' /tmp/sqli-attempts.json | head -5
   ```

3. **IP Reputation Check**
   ```bash
   # Check top attacker IP on AbuseIPDB
   TOP_IP=$(jq -r '.ip' /tmp/sqli-attempts.json | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
   curl -s "https://api.abuseipdb.com/api/v2/check?ipAddress=$TOP_IP" \
     -H "Key: YOUR_ABUSEIPDB_API_KEY" \
     -H "Accept: application/json" | jq '.data.abuseConfidenceScore'

   # Score >75 = confirmed malicious IP
   ```

4. **Check Application Logs for Bypass Attempts**
   ```bash
   # Search for attacker IPs in application access logs
   kubectl logs -n staging-apps-ipaas -l app=backend --since=1h | \
     grep -E "$TOP_IP" | \
     grep -E "(SELECT|UNION|INSERT|UPDATE|DELETE|DROP)" > /tmp/app-sqli-attempts.log

   # If file is NOT empty → SQLi payloads reached application (WAF bypass!)
   # Escalate to CRITICAL incident, engage AWS Support
   ```

#### Resolution

**If WAF Blocked All Attempts** (expected):

1. **Add Temporary IP Block**
   ```bash
   # Block attacker IPs for 24 hours
   aws wafv2 create-ip-set \
     --name sqli-attackers-$(date +%Y%m%d-%H%M) \
     --scope REGIONAL \
     --ip-address-version IPV4 \
     --addresses $TOP_IP/32 \
     --region us-east-1

   # Add to WebACL (Terraform update required for permanent block)
   ```

2. **Monitor for 1 Hour**
   - Verify SQLi attempts stop after IP block
   - Check for attacker IP rotation (new IPs from same ASN/country)

3. **Document Incident**
   - JIRA ticket: SEC-XXXX
   - Include: Timeline, attacker IPs, payloads, targeted endpoints, resolution
   - Post-mortem: Review if rate-limit rule should be tightened (currently 1000 req/5min)

**If WAF Was Bypassed** (CRITICAL):

1. **🚨 ENGAGE AWS SUPPORT IMMEDIATELY**
   - Open critical support case: "SQL injection bypassed AWS WAF"
   - Provide: WebACL ARN, WAF logs, sample payloads, attacker IPs

2. **Enable Database Audit Logging** (if not already enabled)
   ```bash
   # Enable RDS audit logging
   aws rds modify-db-instance \
     --db-instance-identifier k8s-platform-prod-postgresql \
     --cloudwatch-logs-export-configuration '{"LogTypesToEnable":["postgresql"]}' \
     --apply-immediately
   ```

3. **Consider Temporary Maintenance Mode**
   - If data breach suspected: take application offline until investigation complete
   - Requires Product Owner approval

---

## 📊 Dashboard Usage

### Grafana WAF Security Dashboard

**URL**: https://grafana.company.com/d/waf-security-dashboard

**Panels**:
1. **Allowed Requests (5m)**: Total requests that passed WAF inspection
2. **Blocked Requests (5m)**: Total requests blocked by any WAF rule
3. **Block Rate %**: Percentage of blocked requests (threshold: 15% warning, 25% critical)
4. **Total Requests (5m)**: Sum of allowed + blocked (traffic volume indicator)
5. **Request Rate Over Time**: Time-series graph of allowed vs blocked requests
6. **Blocked Requests by Rule**: Stacked bar chart showing which rules triggered blocks
7. **Request Distribution**: Pie chart of allowed vs blocked ratio
8. **WAF Rule Statistics Table**: Per-rule block counts for last hour

**Variables**:
- `$web_acl_name`: Dropdown to select WebACL (default: waf-k8s-platform-prod-staging)

**Auto-Refresh**: 30 seconds

---

## 📈 Metrics Reference

### CloudWatch Metrics (AWS/WAFV2 namespace)

| Metric Name | Unit | Description |
|-------------|------|-------------|
| `AllowedRequests` | Count | Requests that passed all WAF rules |
| `BlockedRequests` | Count | Requests blocked by any WAF rule |
| `CountedRequests` | Count | Requests matched by COUNT-mode rules (audit) |
| `PassedRequests` | Count | Requests that passed Managed Rule Groups |

**Dimensions**:
- `WebACL`: WebACL name (e.g., waf-k8s-platform-prod-staging)
- `Rule`: Rule name (ALL, rate-limit-per-ip, geo-block-high-risk-countries, aws-managed-sqli, etc.)
- `Region`: us-east-1

### Prometheus Metrics (via cloudwatch-exporter)

```promql
# Block rate percentage (last 5 minutes)
100 * (
  sum(rate(aws_wafv2_blocked_requests_sum{dimension_WebACL=~"waf-.*"}[5m]))
  /
  (
    sum(rate(aws_wafv2_blocked_requests_sum{dimension_WebACL=~"waf-.*"}[5m]))
    +
    sum(rate(aws_wafv2_allowed_requests_sum{dimension_WebACL=~"waf-.*"}[5m]))
  )
)

# Geo-block count (last 5 minutes)
sum(increase(aws_wafv2_blocked_requests_sum{
  dimension_WebACL=~"waf-.*",
  dimension_Rule="geo-block-high-risk-countries"
}[5m]))

# SQLi attempts (last 5 minutes)
sum(increase(aws_wafv2_blocked_requests_sum{
  dimension_WebACL=~"waf-.*",
  dimension_Rule="aws-managed-sqli"
}[5m]))
```

---

## 🔧 Troubleshooting

### Dashboard Shows No Data

**Cause**: CloudWatch datasource not configured or cloudwatch-exporter not running

**Resolution**:
1. Check cloudwatch-exporter pod status:
   ```bash
   kubectl get pods -n staging-observability-monitoring -l app=cloudwatch-exporter
   ```

2. Verify Prometheus target:
   ```bash
   kubectl port-forward -n staging-observability-monitoring svc/prometheus-operated 9090:9090
   # Navigate to: http://localhost:9090/targets → search "cloudwatch"
   ```

3. Check IAM permissions (cloudwatch-exporter needs `cloudwatch:GetMetricStatistics`):
   ```bash
   aws iam get-role-policy \
     --role-name k8s-platform-prod-cloudwatch-exporter-role \
     --policy-name CloudWatchExporterPolicy
   ```

### WAF Rule Changes Not Applied

**Cause**: Terraform state drift or WAF capacity limit exceeded

**Resolution**:
1. Check WAF capacity usage:
   ```bash
   aws wafv2 get-web-acl \
     --id $(terraform output -raw waf_web_acl_id) \
     --scope REGIONAL \
     --region us-east-1 | jq '.WebACL.Capacity'

   # Capacity limit: 1500 WCU per WebACL
   # Current usage: Check output above
   ```

2. Apply Terraform changes:
   ```bash
   terraform plan -target=module.waf
   terraform apply -target=module.waf
   ```

### False Positive: Legitimate Traffic Blocked

**Cause**: Overly strict WAF rules (common with OWASP Common Rule Set)

**Resolution**:
1. Identify specific rule causing block (from sampled requests)
2. Add rule exception:
   ```hcl
   # modules/waf/main.tf → aws-managed-owasp-common rule
   rule_action_override {
     name = "SizeRestrictions_BODY"  # Example
     action {
       count {}  # Audit mode instead of block
     }
   }
   ```

3. Monitor for 24 hours to confirm fix doesn't introduce vulnerability

---

## 📚 References

### Terraform Modules
- `modules/waf/` - WAF WebACL configuration
- `modules/waf/variables.tf` - Configurable rules, rate limits, blocked countries

### Runbooks
- [WAF Configuration Guide](/docs/runbooks/waf-configuration.md)
- [WAF Drift Detection](/docs/runbooks/waf-drift-detection.md)

### ADRs
- [ADR-XXX: AWS WAF v2 for iPaaS Protection](/docs/adr/adr-XXX-waf-v2-ipaas.md)

### External Resources
- [AWS WAF Developer Guide](https://docs.aws.amazon.com/waf/latest/developerguide/)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [AbuseIPDB](https://www.abuseipdb.com/) - IP reputation database

---

**Last Updated**: 2026-02-27
**Runbook Version**: 1.0
**Owner**: Platform Team + Security Team
**Contact**: Teams channels — platform-team, security-incidents

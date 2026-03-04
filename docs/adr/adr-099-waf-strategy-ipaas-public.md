# ADR-099: WAF Strategy for iPaaS Public Endpoint

**Status**: Implementado
**Date**: 2026-03-04
**Author**: Observability & SRE Specialist Agent
**Priority**: P1 (Security — public ALB without WAF = critical exposure)
**Demand**: GAP-010
**Related**: ADR-090 (DR Strategy), ADR-086 (FinOps Node Group Protection)

---

## Context

The k8s-platform-prod cluster exposes an iPaaS (Integration Platform as a Service) endpoint publicly via an Application Load Balancer (ALB). The ALB faces the internet with no application-layer filtering.

**Threat landscape identified (pre-WAF):**

| Threat | Risk | Probability |
|--------|------|-------------|
| DDoS volumetric (HTTP flood) | Critical | High |
| SQL injection via API parameters | Critical | Medium |
| XSS in web-facing endpoints | High | Medium |
| Credential stuffing / brute force | High | Medium |
| Traffic from high-risk geographies | Medium | High |
| Log4Shell / known exploit payloads | Critical | Low-Medium |
| Web scraping / automated scanning | Low | High |

**Infrastructure context:**
- ALB: `k8s-platformstaging-00e0ecf3b4` (us-east-1)
- Cluster: k8s-platform-prod (EKS 1.34, 9 nodes, 3 AZs)
- Namespace: staging-observability-monitoring
- AWS Account: 891377105802
- Environment: staging (production parity architecture)

**BACEN/compliance note:**
The iPaaS handles financial integration flows. BACEN Circular 4.557/2021 (art. 15) requires appropriate access controls and monitoring for internet-facing services. WAF with audit logging satisfies this requirement.

---

## Decision

Deploy **AWS WAF v2** (REGIONAL scope) associated with the ALB Ingress Controller, with 5 rule layers:

### Rule Architecture

```
Internet → ALB → WAF (5 rules) → EKS nginx-ingress → Pods
                    │
                    ├── Priority 10: Rate Limiting (1000 req/5min/IP → 429)
                    ├── Priority 20: Geo Blocking (CN, RU, KP → 403)
                    ├── Priority 30: OWASP Common (XSS, LFI, SSRF → 403)
                    ├── Priority 40: SQL Injection (SQLi patterns → 403)
                    └── Priority 50: Known Bad Inputs (Log4Shell, etc → 403)
```

### WAF WebACL Deployed

| Field | Value |
|-------|-------|
| WebACL ID | `bb9d4557-ca28-4539-b493-b62b2f0d602c` |
| WebACL Name | `waf-k8s-platform-prod-staging` |
| Scope | REGIONAL (ALB) |
| Default Action | ALLOW (rules explicitly BLOCK) |
| WCU Used | ~1103 of 5000 limit |
| Monthly Cost | ~R$ 55/mês ($5 WebACL + $1/M rules) |

### Rule Configuration

| Priority | Name | Type | Action | Trigger |
|----------|------|------|--------|---------|
| 10 | `rate-limit-per-ip` | RateBasedStatement | BLOCK (429 + Retry-After: 300) | >1000 req/5min per IP |
| 20 | `geo-block-high-risk-countries` | GeoMatchStatement | BLOCK (403) | CN, RU, KP |
| 30 | `aws-managed-owasp-common` | ManagedRuleGroup | BLOCK (403) | OWASP Top 10 patterns |
| 40 | `aws-managed-sqli` | ManagedRuleGroup | BLOCK (403) | SQLi patterns (5 DB engines) |
| 50 | `aws-managed-known-bad-inputs` | ManagedRuleGroup | BLOCK (403) | Log4Shell, path traversal, SSRF |

### Logging

WAF logs shipped to S3 bucket `aws-waf-logs-k8s-platform-prod-staging` (us-east-1):
- Retention: 90 days (lifecycle policy)
- Encryption: AES256
- Authorization header redacted (prevents credential leakage)
- Partition: `AWSLogs/<accountId>/WAFLogs/<region>/<webacl-name>/YYYY/MM/DD/HH/mm/`

### Observability Stack (GAP-010)

Three components close the observability loop:

#### 1. YACE CloudWatch Exporter
- Chart: `nerdswords/yet-another-cloudwatch-exporter` v0.37.0
- Namespace: staging-observability-monitoring
- IRSA role: `k8s-platform-yace-cloudwatch-role`
- Exports: `aws_wafv2_blocked_requests_sum`, `aws_wafv2_allowed_requests_sum`, per-rule dimensions
- Scrape interval: 60s, period: 300s

#### 2. Grafana Dashboard
- Name: "AWS WAF Security Dashboard - GAP-010"
- UID: `waf-security-dashboard`
- Source: `domains/observability/infra/grafana/waf-dashboard-configmap.yaml`
- Panels: 8 (4 stat, 1 timeseries, 1 bar chart, 1 donut, 1 table)
- Auto-refresh: 30s
- Datasource: CloudWatch (IRSA via `k8s-platform-grafana-cloudwatch-role`)

#### 3. Prometheus Alerts (3 rules)
Source: `domains/observability/infra/prometheus/waf-prometheus-rules.yaml`

| Alert | Severity | Condition | For |
|-------|----------|-----------|-----|
| WAFHighBlockRate | warning | >15% of requests blocked in 5m | 5m |
| WAFGeoBlockSpike | warning | >50 geo blocks in 5m | 2m |
| WAFSQLInjectionAttempts | critical | >10 SQLi blocks in 5m | 1m |

---

## Alternatives Considered

### Option A: Cloudflare WAF
- **Pros**: Global CDN, DDoS scrubbing at edge, anycast routing, bot management
- **Cons**: R$ 2.400/mês (Business plan), external DNS dependency, vendor lock-in, BACEN data residency concerns for financial logs
- **Decision**: REJECTED — cost 44x AWS WAF, LGPD/BACEN data residency risk

### Option B: ModSecurity (in-cluster, nginx-ingress)
- **Pros**: Open-source, no additional cost, runs in-cluster
- **Cons**: High operational overhead (rule tuning), consumes pod CPU/memory, no managed rule updates, no CloudWatch integration, complex WAF log analysis
- **Decision**: REJECTED — operational burden exceeds benefit at current team size

### Option C: AWS Shield Advanced + WAF
- **Pros**: Automatic DDoS response team, SLA-backed protection, cost protection for DDoS-triggered scaling
- **Cons**: R$ 33.000/mês minimum ($3000/month), excessive for staging/iPaaS use case
- **Decision**: REJECTED — appropriate for production critical systems only; evaluate for prod promotion

### Option D: AWS WAF v2 REGIONAL (selected)
- **Pros**: Native AWS integration, managed rule updates, CloudWatch metrics, IRSA auth, S3 logging, $5/month base, no operational overhead for rule maintenance
- **Cons**: AWS-specific, limited DDoS scrubbing (mitigated by Shield Standard included free)
- **Decision**: ACCEPTED

---

## Implementation

### Terraform Module
Location: `platform-provisioning/aws/kubernetes/terraform/modules/waf/`

Files:
- `main.tf` — WebACL, rules, S3 bucket, logging config, ALB association
- `variables.tf` — Parameterized: `rate_limit`, `blocked_countries`, `enable_geo_blocking`, etc.
- `outputs.tf` — `web_acl_arn`, `web_acl_id`, `log_bucket_arn`

### IRSA Roles (Terraform)
Location: `domains/observability/infra/yace-cloudwatch-exporter/`

| Role | SA | Purpose |
|------|----|---------|
| `k8s-platform-yace-cloudwatch-role` | `yace-cloudwatch-exporter` | YACE reads CloudWatch WAFV2 metrics |
| `k8s-platform-grafana-cloudwatch-role` | `kube-prometheus-stack-grafana` | Grafana CloudWatch datasource |

### Deploy Sequence

```bash
# Step 1: Terraform — create IAM roles
cd domains/observability/infra/yace-cloudwatch-exporter/
terraform init
terraform apply -target=aws_iam_role.yace_cloudwatch -target=aws_iam_role.grafana_cloudwatch

# Step 2: Deploy YACE
helm repo add nerdswords https://nerdswords.github.io/yet-another-cloudwatch-exporter
helm repo update
helm upgrade --install yace-cloudwatch-exporter nerdswords/yet-another-cloudwatch-exporter \
  --namespace staging-observability-monitoring \
  --version 0.37.0 \
  -f domains/observability/infra/yace-cloudwatch-exporter/values.yaml

# Step 3: Provision CloudWatch datasource
kubectl apply -f domains/observability/infra/grafana/cloudwatch-datasource-configmap.yaml

# Step 4: Patch Grafana SA for IRSA
kubectl patch serviceaccount kube-prometheus-stack-grafana \
  -n staging-observability-monitoring \
  --patch-file domains/observability/infra/grafana/grafana-sa-irsa-patch.yaml
kubectl rollout restart deployment/kube-prometheus-stack-grafana \
  -n staging-observability-monitoring

# Step 5: Deploy WAF dashboard
kubectl apply -f domains/observability/infra/grafana/waf-dashboard-configmap.yaml

# Step 6: Deploy WAF alerts
kubectl apply -f domains/observability/infra/prometheus/waf-prometheus-rules.yaml

# Step 7: Validate
WAF_ALB_DNS="k8s-platformstaging-00e0ecf3b4.us-east-1.elb.amazonaws.com" \
  AWS_PROFILE="k8s-platform-prod" \
  bash scripts/waf/validate-waf-rules.sh
```

---

## Consequences

### Positive
- Public ALB protected against OWASP Top 10 without application code changes
- AWS manages rule updates — zero operational overhead for signature maintenance
- CloudWatch metrics enable SLO-based alerting (WAFHighBlockRate alert)
- S3 logs enable forensic analysis of blocked requests
- BACEN Circular 4.557 compliance: documented controls + audit trail
- Rate limiting prevents single-client DDoS from impacting all users

### Negative / Risks
- **False positives**: Legitimate API payloads may match OWASP rules. Monitor sampled requests and add `rule_action_override` blocks if needed. Start with OWASP rule in `count` mode if needed.
- **Cost**: ~R$ 55/mês added to AWS bill (WAF) + ~R$ 30/mês (S3 logs at 90-day retention). Total R$ 85/mês.
- **Geo blocking**: CN/RU/KP blocked by default may affect legitimate users. Review quarterly.
- **Rate limit**: 1000 req/5min/IP may be too aggressive for some API consumers. Adjust `rate_limit` variable if needed.
- **YACE scrape delay**: CloudWatch metrics have 1-2 minute publishing latency; Prometheus scrapes every 60s. Alert resolution window: ~3-4 minutes after incident starts.

### Mitigation
- **False positives**: `rule_action_override { name = "<rule>" action { count {} } }` in Terraform to count instead of block specific rules
- **Rate limit tuning**: Change `var.rate_limit` from 1000 to higher value, e.g. 2000, if legitimate API clients trigger
- **YACE latency**: Accepted trade-off — 3-4 minute detection window is acceptable for security alerting at this tier

---

## References

- WAF Runbook: `docs/runbooks/waf-incident-response.md`
- WAF Dashboard: `domains/observability/infra/grafana/waf-dashboard-configmap.yaml`
- WAF Alerts: `domains/observability/infra/prometheus/waf-prometheus-rules.yaml`
- WAF Terraform Module: `platform-provisioning/aws/kubernetes/terraform/modules/waf/`
- YACE Config: `domains/observability/infra/yace-cloudwatch-exporter/`
- Validation Script: `scripts/waf/validate-waf-rules.sh`
- AWS WAF v2 Docs: https://docs.aws.amazon.com/waf/latest/developerguide/
- BACEN Circular 4.557/2021: https://www.bcb.gov.br/estabilidadefinanceira/exibenormativo?tipo=Circular&numero=4557

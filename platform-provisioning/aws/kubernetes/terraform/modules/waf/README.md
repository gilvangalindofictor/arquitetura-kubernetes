# Module: waf

**GAP-010** — AWS WAF v2 + DDoS Protection for iPaaS public ALB endpoint.

## Problem

The iPaaS public endpoint exposed via the ALB Ingress Controller had no WAF or DDoS protection layer. A volumetric attack or exploitation attempt would generate unbounded AWS data transfer and EC2/ALB costs in addition to service degradation.

## Solution

AWS WAF v2 (Regional scope) associated directly with the ALB. Five ordered rules cover:

| Priority | Rule Name | Type | Action | Purpose |
|---|---|---|---|---|
| 10 | `rate-limit-per-ip` | RateBasedStatement | BLOCK (429) | Max 1000 req/5min per IP |
| 20 | `geo-block-high-risk-countries` | GeoMatchStatement | BLOCK | CN, RU, KP (configurable) |
| 30 | `aws-managed-owasp-common` | ManagedRuleGroup | BLOCK | OWASP Top 10, XSS, LFI, SSRF |
| 40 | `aws-managed-sqli` | ManagedRuleGroup | BLOCK | SQL injection (all engines) |
| 50 | `aws-managed-known-bad-inputs` | ManagedRuleGroup | BLOCK | Log4SHELL, path traversal, SSRF |

## Estimated Cost

| Resource | Unit Cost | Monthly Estimate |
|---|---|---|
| WAF WebACL | $5.00/month | $5.00 |
| Rule groups (5 rules) | $1.00/rule/month | $5.00 |
| Requests (up to 10M) | $0.60/million | ~$1-3 |
| **Total** | | **~$10-13/month** |

## Usage

### Minimal (use existing ALB, external log bucket)

```hcl
module "waf_staging" {
  source = "../../modules/waf"

  environment  = "staging"
  cluster_name = "k8s-platform-prod"
  alb_arn      = data.aws_lb.ingress.arn

  rate_limit        = 1000
  blocked_countries = ["CN", "RU", "KP"]

  enable_logging      = true
  log_destination_arn = "arn:aws:s3:::aws-waf-logs-my-bucket"

  common_tags = local.common_tags
}
```

### With self-managed log bucket

```hcl
module "waf_staging" {
  source = "../../modules/waf"

  environment  = "staging"
  cluster_name = "k8s-platform-prod"
  alb_arn      = data.aws_lb.ingress.arn

  rate_limit        = 1000
  blocked_countries = ["CN", "RU", "KP"]

  enable_logging     = true
  create_log_bucket  = true
  log_retention_days = 90

  common_tags = local.common_tags
}
```

### Disable geo-blocking (useful for testing from blocked countries)

```hcl
module "waf_staging" {
  source = "../../modules/waf"

  environment         = "staging"
  cluster_name        = "k8s-platform-prod"
  alb_arn             = data.aws_lb.ingress.arn
  enable_geo_blocking = false

  common_tags = local.common_tags
}
```

## How to get the ALB ARN

The ALB is created by the AWS Load Balancer Controller (ALB Ingress Controller). After the Ingress resources are applied, retrieve the ARN:

```bash
# 1. Get the ALB DNS name from the Ingress
kubectl get ingress -A -o jsonpath='{.items[*].status.loadBalancer.ingress[*].hostname}'

# 2. Find the ALB ARN by DNS name
ALB_DNS="k8s-platform-prod-xxxxx.us-east-1.elb.amazonaws.com"
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?DNSName=='${ALB_DNS}'].LoadBalancerArn" \
  --output text

# 3. Or use a data source in Terraform (preferred):
data "aws_lb" "ingress" {
  tags = {
    "kubernetes.io/cluster/k8s-platform-prod" = "owned"
    "kubernetes.io/ingress-class"             = "alb"
  }
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `environment` | string | required | `staging` or `production` |
| `cluster_name` | string | required | EKS cluster name |
| `alb_arn` | string | required | ARN of the ALB to protect |
| `rate_limit` | number | `1000` | Max requests per IP per 5min |
| `blocked_countries` | list(string) | `["CN","RU","KP"]` | ISO 3166-1 alpha-2 codes |
| `enable_geo_blocking` | bool | `true` | Toggle geo-blocking rule |
| `enable_owasp_common_ruleset` | bool | `true` | Toggle OWASP CRS |
| `enable_sqli_ruleset` | bool | `true` | Toggle SQLi rule group |
| `enable_known_bad_inputs_ruleset` | bool | `true` | Toggle Known Bad Inputs rule group |
| `enable_logging` | bool | `true` | Enable WAF logging |
| `log_destination_arn` | string | `""` | Existing S3 bucket ARN for logs |
| `create_log_bucket` | bool | `false` | Create a new S3 log bucket |
| `log_retention_days` | number | `90` | Days to retain log objects |
| `enable_sampled_requests` | bool | `true` | Enable request sampling |
| `cloudwatch_metrics_enabled` | bool | `true` | Enable CloudWatch metrics |
| `common_tags` | map(string) | `{}` | Tags applied to all resources |

## Outputs

| Name | Description |
|---|---|
| `waf_web_acl_arn` | WebACL ARN |
| `waf_web_acl_id` | WebACL UUID |
| `waf_web_acl_name` | WebACL name |
| `waf_web_acl_capacity` | Current WCU consumption |
| `waf_alb_association_id` | ALB association resource ID |
| `waf_log_bucket_name` | S3 log bucket name (if created) |
| `waf_log_bucket_arn` | S3 log bucket ARN (if created) |
| `waf_logging_enabled` | Boolean — logging active |
| `waf_cloudwatch_metric_name` | CloudWatch metric namespace |
| `waf_rules_summary` | Map summarizing active rules |

## Operational Runbook

### Monitor blocked requests

```bash
# CloudWatch Insights query — last 24h blocked by rule
aws logs start-query \
  --log-group-name "aws-waf-logs-k8s-platform-prod-staging" \
  --start-time $(date -d '24 hours ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, httpRequest.clientIp, terminatingRuleId | filter action = "BLOCK" | stats count() by terminatingRuleId | sort count desc'
```

### Temporarily override a rule to COUNT mode

To investigate false positives without full blocking, use rule_action_override in the managed rule group statement. Edit the module and replace `none {}` with a `count {}` override for the specific rule, then apply.

### Emergency: Disable WAF temporarily

Set `default_action { allow {} }` (already set) — the WAF already allows by default. To bypass a specific rule quickly, set its `override_action { count {} }` and apply.

## References

- [AWS WAF v2 Developer Guide](https://docs.aws.amazon.com/waf/latest/developerguide/)
- [AWS Managed Rule Groups](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-list.html)
- [Terraform aws_wafv2_web_acl](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl)
- [WAF Logging to S3](https://docs.aws.amazon.com/waf/latest/developerguide/logging-s3.html)
- GAP-010 ticket (internal)

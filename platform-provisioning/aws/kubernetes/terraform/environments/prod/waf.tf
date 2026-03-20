#------------------------------------------------------------------------------
# WAF v2 + DDoS Protection — PROD (2026-03-20)
# Protects the production ALB (k8s-platformprod-ca65b3f8b1) via WAF association.
# Rules (priority order):
#   0  → Office IP Allowlist: 201.28.188.130/32 (ALLOW) — default_action = BLOCK
#   10 → Rate limit: 500 req/5min per IP (BLOCK 429)
#   20 → Geo-block: CN, RU, KP (BLOCK)
#   30 → OWASP Common Rule Set — AWSManagedRulesCommonRuleSet (BLOCK)
#   40 → SQLi Protection — AWSManagedRulesSQLiRuleSet (BLOCK)
#   50 → Known Bad Inputs — AWSManagedRulesKnownBadInputsRuleSet (BLOCK)
#
# ALB prod ARN: arn:aws:elasticloadbalancing:us-east-1:891377105802:loadbalancer/app/k8s-platformprod-ca65b3f8b1/ced20c6e32f1c71b
# Logging: dedicated S3 bucket created by the module (aws-waf-logs-k8s-platform-prod-production)
# Cost estimate: ~$10-13/month (WAF WebACL + 5 rules + requests).
#
# NOTE: environment = "production" (not "prod") — required by WAF module validation.
# Module accepts: ["staging", "production"]. local.environment = "prod" is used
# for other modules; WAF uses "production" to satisfy the validation constraint.
#
# Reference: GAP-010 — iPaaS public endpoint WAF protection (P0 critical)
#------------------------------------------------------------------------------

module "waf_prod" {
  source = "../../modules/waf"

  # Identity
  # NOTE: environment must be "production" — module validation: contains(["staging", "production"], ...)
  environment  = "production"
  cluster_name = local.cluster_name
  common_tags  = local.common_tags

  # Primary ALB — k8s-platformprod-ca65b3f8b1 (prod platform ingress)
  # ARN resolved via var.waf_alb_arn (set in terraform.tfvars)
  alb_arn = var.waf_alb_arn

  # Rate limiting — production threshold: 500 req/5min per IP (stricter than staging 1000)
  rate_limit = var.waf_rate_limit

  # Geographic blocking — CN, RU, KP (same as staging)
  enable_geo_blocking = var.waf_enable_geo_blocking
  blocked_countries   = var.waf_blocked_countries

  # IP allowlist — only office IPs can reach prod ALB (default_action becomes BLOCK)
  enable_ip_allowlist = true
  office_ip_cidrs     = ["201.28.188.130/32"]

  # Managed rule groups (all enabled — validated in staging before production)
  enable_owasp_common_ruleset     = true
  enable_sqli_ruleset             = true
  enable_known_bad_inputs_ruleset = true

  # Logging — module creates the S3 bucket (aws-waf-logs-k8s-platform-prod-production)
  enable_logging     = true
  create_log_bucket  = true
  log_retention_days = var.waf_log_retention_days

  # Observability
  cloudwatch_metrics_enabled = true
  enable_sampled_requests    = true
}

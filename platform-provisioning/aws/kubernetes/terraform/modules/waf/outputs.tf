# =============================================================================
# WAF Module Outputs
# GAP-010: AWS WAF v2 + DDoS Protection for iPaaS ALB
# =============================================================================

#------------------------------------------------------------------------------
# WebACL Core Identifiers
#------------------------------------------------------------------------------

output "waf_web_acl_arn" {
  description = "ARN of the WAF v2 WebACL. Use this ARN to associate additional ALBs, CloudFront distributions, or API Gateways with the same WebACL."
  value       = aws_wafv2_web_acl.main.arn
}

output "waf_web_acl_id" {
  description = "Unique identifier (UUID) of the WAF v2 WebACL. Required for aws_wafv2_web_acl_association resources created outside this module."
  value       = aws_wafv2_web_acl.main.id
}

output "waf_web_acl_name" {
  description = "Name of the WAF v2 WebACL resource."
  value       = aws_wafv2_web_acl.main.name
}

#------------------------------------------------------------------------------
# WebACL Capacity
#------------------------------------------------------------------------------

output "waf_web_acl_capacity" {
  description = "Current WCU (WAF Capacity Units) consumed by the WebACL. Each account has a default limit of 1500 WCU per WebACL. Monitor this to avoid hitting the limit when adding more rules."
  value       = aws_wafv2_web_acl.main.capacity
}

#------------------------------------------------------------------------------
# ALB Association
#------------------------------------------------------------------------------

output "waf_alb_association_id" {
  description = "Terraform resource ID for the WAF WebACL → primary ALB association. Useful for explicit depends_on chains in consumer modules."
  value       = aws_wafv2_web_acl_association.alb.id
}

output "waf_additional_alb_association_ids" {
  description = "Map of Terraform resource IDs for additional WAF WebACL → ALB associations (keyed by the logical name from additional_alb_arns)."
  value       = { for k, v in aws_wafv2_web_acl_association.additional : k => v.id }
}

#------------------------------------------------------------------------------
# Logging (S3)
#------------------------------------------------------------------------------

output "waf_log_bucket_name" {
  description = "Name of the S3 bucket receiving WAF logs. Empty string when create_log_bucket = false."
  value       = var.create_log_bucket ? aws_s3_bucket.waf_logs[0].bucket : ""
}

output "waf_log_bucket_arn" {
  description = "ARN of the S3 bucket receiving WAF logs. Empty string when create_log_bucket = false."
  value       = var.create_log_bucket ? aws_s3_bucket.waf_logs[0].arn : ""
}

output "waf_logging_enabled" {
  description = "Boolean indicating whether WAF logging is active for this WebACL."
  value       = var.enable_logging && (var.create_log_bucket || var.log_destination_arn != "")
}

#------------------------------------------------------------------------------
# CloudWatch Metrics
#------------------------------------------------------------------------------

output "waf_cloudwatch_metric_name" {
  description = "CloudWatch metric namespace prefix for the WebACL. Use this to build dashboards and alarms in the observability module."
  value       = "waf-webacl-${var.cluster_name}-${var.environment}"
}

#------------------------------------------------------------------------------
# Configuration Summary (useful for debugging and documentation)
#------------------------------------------------------------------------------

output "waf_rules_summary" {
  description = "Summary map of active WAF rules and their configuration. Useful for auditing and documentation generation."
  value = {
    ip_allowlist = {
      enabled        = var.enable_ip_allowlist
      priority       = 0
      default_action = var.enable_ip_allowlist ? "BLOCK" : "ALLOW"
      office_cidrs   = var.enable_ip_allowlist ? var.office_ip_cidrs : []
    }
    rate_limit = {
      enabled  = true
      priority = 10
      limit    = var.rate_limit
    }
    geo_blocking = {
      enabled   = var.enable_geo_blocking
      priority  = 20
      countries = var.enable_geo_blocking ? var.blocked_countries : []
    }
    owasp_common = {
      enabled  = var.enable_owasp_common_ruleset
      priority = 30
      vendor   = "AWS"
      rule_set = "AWSManagedRulesCommonRuleSet"
    }
    sqli_protection = {
      enabled  = var.enable_sqli_ruleset
      priority = 40
      vendor   = "AWS"
      rule_set = "AWSManagedRulesSQLiRuleSet"
    }
    known_bad_inputs = {
      enabled  = var.enable_known_bad_inputs_ruleset
      priority = 50
      vendor   = "AWS"
      rule_set = "AWSManagedRulesKnownBadInputsRuleSet"
    }
  }
}

#------------------------------------------------------------------------------
# IP Allowlist
#------------------------------------------------------------------------------

output "waf_ip_set_arn" {
  description = "ARN of the office IP allowlist IP Set. Empty string when enable_ip_allowlist = false."
  value       = var.enable_ip_allowlist ? aws_wafv2_ip_set.office_allowlist[0].arn : ""
}

output "waf_ip_set_id" {
  description = "ID of the office IP allowlist IP Set. Empty string when enable_ip_allowlist = false."
  value       = var.enable_ip_allowlist ? aws_wafv2_ip_set.office_allowlist[0].id : ""
}

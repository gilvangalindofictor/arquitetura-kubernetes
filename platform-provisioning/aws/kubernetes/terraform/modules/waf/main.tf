# =============================================================================
# WAF Module - AWS WAF v2 + DDoS Protection
# GAP-010: iPaaS public endpoint protection via ALB association
#
# Rule execution order (lower priority number = evaluated first):
#   Priority 10 → Rate Limiting      (RateBasedStatement, BLOCK after 1000 req/5min per IP)
#   Priority 20 → Geographic Block   (GeoMatchStatement, BLOCK CN/RU/KP by default)
#   Priority 30 → OWASP Common       (AWSManagedRulesCommonRuleSet, BLOCK)
#   Priority 40 → SQLi Protection    (AWSManagedRulesSQLiRuleSet, BLOCK)
#   Priority 50 → Known Bad Inputs   (AWSManagedRulesKnownBadInputsRuleSet, BLOCK)
#
# Scope: REGIONAL (ALB association). CLOUDFRONT scope requires us-east-1.
# =============================================================================

locals {
  name_prefix = "${var.cluster_name}-${var.environment}"

  # Compute the actual log destination — either the created bucket or caller-provided ARN
  effective_log_destination_arn = var.create_log_bucket ? aws_s3_bucket.waf_logs[0].arn : var.log_destination_arn
}

# -----------------------------------------------------------------------------
# S3 Bucket for WAF Logs (optional — created when create_log_bucket = true)
# AWS requirement: bucket name MUST start with "aws-waf-logs-"
# Ref: https://docs.aws.amazon.com/waf/latest/developerguide/logging-s3.html
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "waf_logs" {
  count = var.create_log_bucket ? 1 : 0

  # Name prefix mandated by AWS WAF v2 logging service principal
  bucket = "aws-waf-logs-${local.name_prefix}"

  tags = merge(var.common_tags, {
    Name    = "aws-waf-logs-${local.name_prefix}"
    Purpose = "WAF access logs - GAP-010"
    Module  = "waf"
  })
}

resource "aws_s3_bucket_versioning" "waf_logs" {
  count  = var.create_log_bucket ? 1 : 0
  bucket = aws_s3_bucket.waf_logs[0].id

  versioning_configuration {
    status = "Suspended" # Logs are immutable; versioning increases cost with no benefit
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "waf_logs" {
  count  = var.create_log_bucket ? 1 : 0
  bucket = aws_s3_bucket.waf_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "waf_logs" {
  count  = var.create_log_bucket ? 1 : 0
  bucket = aws_s3_bucket.waf_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "waf_logs" {
  count  = var.create_log_bucket ? 1 : 0
  bucket = aws_s3_bucket.waf_logs[0].id

  # Expire WAF log objects after configured retention period
  rule {
    id     = "waf-logs-expiration"
    status = "Enabled"

    expiration {
      days = var.log_retention_days
    }

    # Also clean up incomplete multipart uploads (saves cost)
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Bucket policy granting WAF service delivery permissions
# Required for aws_wafv2_web_acl_logging_configuration to write logs
resource "aws_s3_bucket_policy" "waf_logs" {
  count  = var.create_log_bucket ? 1 : 0
  bucket = aws_s3_bucket.waf_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowWAFLogging"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.waf_logs[0].arn}/AWSLogs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AllowWAFAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.waf_logs[0].arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# WAF v2 WebACL
# Scope REGIONAL is required for ALB associations.
# All rules use "override_action" when referencing ManagedRuleGroups so that
# individual rule overrides can be applied without replacing the whole ACL.
# -----------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "main" {
  name        = "waf-${local.name_prefix}"
  description = "GAP-010: WAF protection for iPaaS public ALB - ${var.environment}"
  scope       = "REGIONAL"

  # Default action for requests that do NOT match any rule: ALLOW
  # Rules below explicitly BLOCK matched traffic.
  default_action {
    allow {}
  }

  # ---------------------------------------------------------------------------
  # Rule 1 — Rate Limiting (Priority 10)
  # Protects against volumetric DDoS and brute-force attacks.
  # Evaluation window: 5 minutes (AWS WAF v2 fixed window for RateBasedStatement).
  # Aggregate key: IP address (IPv4 and IPv6 are evaluated independently).
  # ---------------------------------------------------------------------------
  rule {
    name     = "rate-limit-per-ip"
    priority = 10

    statement {
      rate_based_statement {
        # Maximum requests per 5-minute window per IP before BLOCK triggers
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    action {
      block {
        # Return 429 Too Many Requests with a Retry-After hint
        custom_response {
          response_code = 429
          response_header {
            name  = "Retry-After"
            value = "300"
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
      metric_name                = "waf-rate-limit-${var.environment}"
      sampled_requests_enabled   = var.enable_sampled_requests
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 2 — Geographic Blocking (Priority 20)
  # Blocks entire countries with historically high attack origination.
  # Controlled via var.blocked_countries (default: CN, RU, KP).
  # Disabled entirely when var.enable_geo_blocking = false.
  # ---------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_geo_blocking ? [1] : []

    content {
      name     = "geo-block-high-risk-countries"
      priority = 20

      statement {
        geo_match_statement {
          country_codes = var.blocked_countries
        }
      }

      action {
        block {}
      }

      visibility_config {
        cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
        metric_name                = "waf-geo-block-${var.environment}"
        sampled_requests_enabled   = var.enable_sampled_requests
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 3 — AWS Managed Rules: Common Rule Set (OWASP Top 10) (Priority 30)
  # Covers: XSS, LFI, RFI, SSRF, protocol violations, HTTP method enforcement,
  # size restrictions. Managed and updated by AWS Threat Intelligence team.
  # Ref: https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html#aws-managed-rule-groups-baseline-crs
  # ---------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_owasp_common_ruleset ? [1] : []

    content {
      name     = "aws-managed-owasp-common"
      priority = 30

      override_action {
        # "none" means: use each individual rule's configured action (BLOCK).
        # Use "count" here during initial rollout to observe before enforcing.
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesCommonRuleSet"

          # Exclude rules known to generate false positives in iPaaS API workloads.
          # Add rule names here after reviewing sampled requests in CloudWatch.
          # Example: rule_action_override { name = "SizeRestrictions_BODY" action { count {} } }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
        metric_name                = "waf-owasp-common-${var.environment}"
        sampled_requests_enabled   = var.enable_sampled_requests
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 4 — AWS Managed Rules: SQL Injection Protection (Priority 40)
  # Covers: SQL injection patterns for MySQL, PostgreSQL, Oracle, MSSQL, SQLite.
  # Inspects: URI, query string, body, headers.
  # Ref: https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-use-case.html#aws-managed-rule-groups-use-case-sql-db
  # ---------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_sqli_ruleset ? [1] : []

    content {
      name     = "aws-managed-sqli"
      priority = 40

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesSQLiRuleSet"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
        metric_name                = "waf-sqli-${var.environment}"
        sampled_requests_enabled   = var.enable_sampled_requests
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Rule 5 — AWS Managed Rules: Known Bad Inputs (Priority 50)
  # Covers: Log4SHELL (CVE-2021-44228), SSRF attempts, path traversal,
  # JavaDeserializationExploits, and other known exploit payloads.
  # Ref: https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-use-case.html#aws-managed-rule-groups-use-case-known-bad-inputs
  # ---------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_known_bad_inputs_ruleset ? [1] : []

    content {
      name     = "aws-managed-known-bad-inputs"
      priority = 50

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesKnownBadInputsRuleSet"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
        metric_name                = "waf-known-bad-inputs-${var.environment}"
        sampled_requests_enabled   = var.enable_sampled_requests
      }
    }
  }

  # WebACL-level visibility (aggregate metrics for the entire ACL)
  visibility_config {
    cloudwatch_metrics_enabled = var.cloudwatch_metrics_enabled
    metric_name                = "waf-webacl-${local.name_prefix}"
    sampled_requests_enabled   = var.enable_sampled_requests
  }

  tags = merge(var.common_tags, {
    Name    = "waf-${local.name_prefix}"
    Purpose = "GAP-010 iPaaS DDoS protection"
    Module  = "waf"
  })
}

# -----------------------------------------------------------------------------
# WAF WebACL Association with ALB
# Associates the WebACL with the Application Load Balancer so all HTTP/S
# traffic passing through the ALB Ingress Controller is inspected by WAF.
# One WebACL can be associated with multiple resources; one resource can only
# have one WebACL associated at a time.
# -----------------------------------------------------------------------------

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# -----------------------------------------------------------------------------
# WAF Logging Configuration
# Enabled when var.enable_logging = true AND a log destination is available.
# The log destination must be an S3 bucket whose name starts with "aws-waf-logs-".
# Redacted fields: Authorization header (prevents token leakage in logs).
# -----------------------------------------------------------------------------

resource "aws_wafv2_web_acl_logging_configuration" "main" {
  # Only create when logging is enabled AND we have a destination ARN
  count = (var.enable_logging && (var.create_log_bucket || var.log_destination_arn != "")) ? 1 : 0

  log_destination_configs = [local.effective_log_destination_arn]
  resource_arn            = aws_wafv2_web_acl.main.arn

  # Redact sensitive headers from logs to prevent credential leakage
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  # Optionally filter which log entries are sent to S3 (log only blocked requests
  # to reduce S3 cost on high-traffic environments).
  # Uncomment to enable log filtering:
  # logging_filter {
  #   default_behavior = "DROP"
  #   filter {
  #     behavior = "KEEP"
  #     condition {
  #       action_condition {
  #         action = "BLOCK"
  #       }
  #     }
  #     requirement = "MEETS_ANY"
  #   }
  # }

  depends_on = [
    aws_wafv2_web_acl.main,
    aws_s3_bucket_policy.waf_logs,
  ]
}

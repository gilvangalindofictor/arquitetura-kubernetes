# =============================================================================
# GAP-CONF-026 (P3): AWS Budget Alerts — Cost Monitoring
# =============================================================================
# Problema: Sem alertas de budget configurados. Custos podem crescer sem
#   visibilidade ate a fatura mensal.
#
# Solucao: AWS Budgets com alertas em 80% e 100% do limite mensal.
#   - Budget: $500/mes (conservador — baseado no custo medio observado)
#   - SNS topic para notificacoes via email
#   - Filtro por tag Project=k8s-platform para isolar custos da plataforma
#
# Custo: $0 (AWS Budgets — primeiros 2 budgets sao gratuitos)
#
# Ref: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-create.html
# =============================================================================

# --- SNS Topic para Budget Alerts ---
resource "aws_sns_topic" "budget_alerts" {
  name = "k8s-platform-budget-alerts"

  tags = merge(local.common_tags, {
    Name = "k8s-platform-budget-alerts"
    Gap  = "GAP-CONF-026"
  })
}

# --- SNS Email Subscription ---
resource "aws_sns_topic_subscription" "budget_alerts_email" {
  topic_arn = aws_sns_topic.budget_alerts.arn
  protocol  = "email"
  endpoint  = var.finops_alert_email
}

# --- SNS Topic Policy (permite AWS Budgets publicar) ---
resource "aws_sns_topic_policy" "budget_alerts" {
  arn = aws_sns_topic.budget_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowBudgetsPublish"
        Effect    = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.budget_alerts.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.aws_account_id
          }
        }
      }
    ]
  })
}

# --- AWS Budget: $500/mes com alertas em 80% e 100% ---
resource "aws_budgets_budget" "monthly_platform" {
  name         = "k8s-platform-monthly"
  budget_type  = "COST"
  limit_amount = "500"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Filtro por tag Project=k8s-platform
  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Project$k8s-platform"]
  }

  # Alerta em 80% ($400)
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }

  # Alerta em 100% ($500)
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }

  # Alerta FORECAST 100% (previsto atingir antes do fim do mes)
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_sns_topic_arns  = [aws_sns_topic.budget_alerts.arn]
  }

  tags = merge(local.common_tags, {
    Name = "k8s-platform-monthly-budget"
    Gap  = "GAP-CONF-026"
  })
}

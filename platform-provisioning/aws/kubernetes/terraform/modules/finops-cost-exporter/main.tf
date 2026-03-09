################################################################################
# FinOps Cost Exporter — CronJob K8s + IRSA
#
# Funcao: Consultar AWS Cost Explorer API a cada 6h e push metricas para
# Prometheus Pushgateway (cluster-internal DNS).
#
# Arquitetura:
#   CronJob K8s (schedule: 0 */6 * * *)
#     → Pod python:3.12-slim com script montado via ConfigMap
#     → IRSA via ServiceAccount (eks.amazonaws.com/role-arn)
#     → Cost Explorer API (us-east-1, endpoint global)
#     → POST Prometheus Pushgateway (.svc.cluster.local — resolvido dentro do cluster)
#
# Metricas geradas:
#   aws_cost_daily_usd{service, date, environment}  — custo diario por servico
#   aws_cost_mtd_usd{service, environment}          — month-to-date por servico
#   aws_cost_forecast_usd{environment}              — projecao total do mes corrente
#   aws_cost_by_tag_usd{app, environment}           — custo MTD por tag app=
#   aws_budget_limit_usd{environment}               — limite do budget
#   aws_budget_actual_usd{environment}              — gasto real MTD vs budget
#
# Custo CE API: ~120 chamadas/mes (free tier: 1.000/mes) = $0 adicional
# Motivo CronJob vs Lambda: Lambda nao resolve .svc.cluster.local (CoreDNS interno)
################################################################################

# -----------------------------------------------------------------------------
# IRSA — IAM Role com trust policy para o OIDC provider do EKS
# Padrao identico ao usado por Velero, Harbor e ESO no projeto.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "finops_exporter_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.namespace}:finops-cost-exporter"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "finops_cost_exporter" {
  name               = "${var.cluster_name}-finops-cost-exporter"
  assume_role_policy = data.aws_iam_policy_document.finops_exporter_assume_role.json

  tags = merge(var.common_tags, {
    Name      = "${var.cluster_name}-finops-cost-exporter"
    component = "finops-cost-exporter"
  })
}

data "aws_iam_policy_document" "finops_cost_explorer_access" {
  statement {
    sid    = "CostExplorerReadOnly"
    effect = "Allow"
    actions = [
      "ce:GetCostAndUsage",
      "ce:GetCostForecast",
      "ce:GetDimensionValues",
      "ce:GetTags",
      "budgets:ViewBudget",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "finops_cost_exporter" {
  name   = "finops-cost-explorer-access"
  role   = aws_iam_role.finops_cost_exporter.id
  policy = data.aws_iam_policy_document.finops_cost_explorer_access.json
}

# -----------------------------------------------------------------------------
# ServiceAccount K8s — anotado com IRSA role ARN
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "finops_cost_exporter" {
  metadata {
    name      = "finops-cost-exporter"
    namespace = var.namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.finops_cost_exporter.arn
    }

    labels = {
      "app.kubernetes.io/name"       = "finops-cost-exporter"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "finops"
      environment                    = var.environment
      owner                          = "platform-team"
    }
  }
}

# -----------------------------------------------------------------------------
# ConfigMap — script Python montado no pod do CronJob
# -----------------------------------------------------------------------------

resource "kubernetes_config_map" "finops_cost_exporter_script" {
  metadata {
    name      = "finops-cost-exporter-script"
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "finops-cost-exporter"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "finops"
      environment                    = var.environment
    }
  }

  data = {
    "cost_exporter.py" = file("${path.module}/scripts/cost_exporter.py")
  }
}

# -----------------------------------------------------------------------------
# CronJob K8s — executa a cada 6h, usa IRSA via ServiceAccount
# -----------------------------------------------------------------------------

resource "kubernetes_cron_job_v1" "finops_cost_exporter" {
  metadata {
    name      = "finops-cost-exporter"
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/name"       = "finops-cost-exporter"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "finops"
      environment                    = var.environment
      owner                          = "platform-team"
    }
  }

  spec {
    schedule                      = "0 */6 * * *"
    concurrency_policy            = "Forbid"
    failed_jobs_history_limit     = 3
    successful_jobs_history_limit = 2
    starting_deadline_seconds     = 300

    job_template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "finops-cost-exporter"
          environment              = var.environment
        }
      }

      spec {
        backoff_limit              = 2
        ttl_seconds_after_finished = 3600

        template {
          metadata {
            labels = {
              "app.kubernetes.io/name" = "finops-cost-exporter"
              environment              = var.environment
            }
          }

          spec {
            service_account_name            = kubernetes_service_account.finops_cost_exporter.metadata[0].name
            automount_service_account_token = true
            restart_policy                  = "OnFailure"

            node_selector = {
              "kubernetes.io/os" = "linux"
            }

            toleration {
              key      = "workloads"
              operator = "Equal"
              value    = "true"
              effect   = "NoSchedule"
            }

            container {
              name              = "cost-exporter"
              image             = "python:3.12-slim"
              image_pull_policy = "IfNotPresent"

              command = [
                "sh", "-c",
                "pip install boto3 -q --no-cache-dir && python /scripts/cost_exporter.py"
              ]

              env {
                name  = "PUSHGATEWAY_URL"
                value = var.pushgateway_url
              }

              env {
                name  = "AWS_ACCOUNT_ID"
                value = var.aws_account_id
              }

              env {
                name  = "BUDGET_LIMIT_USD"
                value = tostring(var.budget_limit_usd)
              }

              env {
                name  = "BUDGET_NAME"
                value = var.budget_name
              }

              env {
                name  = "ENVIRONMENT"
                value = var.environment
              }

              # IRSA injeta AWS_ROLE_ARN e AWS_WEB_IDENTITY_TOKEN_FILE automaticamente
              env {
                name  = "AWS_DEFAULT_REGION"
                value = "us-east-1"
              }

              resources {
                requests = {
                  cpu    = "50m"
                  memory = "128Mi"
                }
                limits = {
                  cpu    = "200m"
                  memory = "256Mi"
                }
              }

              volume_mount {
                name       = "script"
                mount_path = "/scripts"
                read_only  = true
              }
            }

            volume {
              name = "script"
              config_map {
                name = kubernetes_config_map.finops_cost_exporter_script.metadata[0].name
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    aws_iam_role_policy.finops_cost_exporter,
    kubernetes_service_account.finops_cost_exporter,
    kubernetes_config_map.finops_cost_exporter_script,
  ]
}

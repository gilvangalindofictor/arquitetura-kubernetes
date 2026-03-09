"""
FinOps Cost Exporter — K8s CronJob Script
Consulta AWS Cost Explorer API e faz push de metricas para Prometheus Pushgateway.

Metricas geradas:
  aws_cost_daily_usd{service, date, environment}  -- custo diario por servico (ultimos 30 dias)
  aws_cost_mtd_usd{service, environment}          -- month-to-date por servico
  aws_cost_forecast_usd{environment}              -- projecao total do mes corrente
  aws_cost_by_tag_usd{app, environment}           -- custo MTD por tag app=
  aws_budget_limit_usd{environment}               -- limite do budget
  aws_budget_actual_usd{environment}              -- gasto real MTD vs budget

Frequencia: 4x/dia (CronJob schedule: 0 */6 * * *) = ~120 chamadas/mes CE API (free tier: 1000/mes)
Autenticacao: IRSA via ServiceAccount (AWS_ROLE_ARN + AWS_WEB_IDENTITY_TOKEN_FILE injetados pelo EKS)
"""

import logging
import os
import sys
import urllib.error
import urllib.request
from datetime import date, timedelta
from typing import Any

import boto3

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    stream=sys.stdout,
)
logger = logging.getLogger(__name__)

CE_CLIENT      = boto3.client("ce", region_name="us-east-1")  # Cost Explorer: endpoint global us-east-1
BUDGETS_CLIENT = boto3.client("budgets", region_name="us-east-1")

PUSHGATEWAY_URL  = os.environ["PUSHGATEWAY_URL"]
AWS_ACCOUNT_ID   = os.environ["AWS_ACCOUNT_ID"]
BUDGET_LIMIT_USD = float(os.environ.get("BUDGET_LIMIT_USD", "807"))
BUDGET_NAME      = os.environ.get("BUDGET_NAME", "staging-monthly")
ENVIRONMENT      = os.environ.get("ENVIRONMENT", "staging")
JOB_NAME         = "finops-cost-exporter"


def run() -> None:
    """Ponto de entrada principal — coleta metricas e push para Pushgateway."""
    logger.info("Starting FinOps cost export (environment=%s)", ENVIRONMENT)

    today          = date.today()
    first_of_month = today.replace(day=1)

    metrics_lines: list[str] = []

    # 1. Custo diario por servico (ultimos 30 dias)
    daily_metrics = _get_daily_cost_by_service(
        start=str(today - timedelta(days=30)),
        end=str(today),
    )
    metrics_lines.extend(daily_metrics)
    logger.info("Daily cost metrics: %d lines", len(daily_metrics))

    # 2. MTD por servico
    mtd_metrics = _get_mtd_cost_by_service(
        start=str(first_of_month),
        end=str(today),
    )
    metrics_lines.extend(mtd_metrics)
    logger.info("MTD cost metrics: %d lines", len(mtd_metrics))

    # 3. Forecast do mes
    forecast_metrics = _get_monthly_forecast(today)
    metrics_lines.extend(forecast_metrics)

    # 4. Custo MTD por tag app=
    tag_metrics = _get_cost_by_tag(
        start=str(first_of_month),
        end=str(today),
    )
    metrics_lines.extend(tag_metrics)
    logger.info("Tag cost metrics: %d lines", len(tag_metrics))

    # 5. Budget limite (estatico, configurado via env var)
    metrics_lines.append(f'aws_budget_limit_usd{{environment="{ENVIRONMENT}"}} {BUDGET_LIMIT_USD}')

    # 6. Budget actual (MTD total)
    mtd_total = _get_mtd_total(start=str(first_of_month), end=str(today))
    metrics_lines.append(f'aws_budget_actual_usd{{environment="{ENVIRONMENT}"}} {mtd_total:.4f}')

    # Push para Pushgateway
    payload = "\n".join(metrics_lines) + "\n"
    _push_to_gateway(payload)
    logger.info("Pushed %d metric lines to Pushgateway successfully", len(metrics_lines))


def _get_daily_cost_by_service(start: str, end: str) -> list[str]:
    """Retorna custo diario por servico como linhas de metricas Prometheus."""
    response = CE_CLIENT.get_cost_and_usage(
        TimePeriod={"Start": start, "End": end},
        Granularity="DAILY",
        Metrics=["UnblendedCost"],
        GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
    )

    lines = [
        "# HELP aws_cost_daily_usd Daily AWS cost in USD by service",
        "# TYPE aws_cost_daily_usd gauge",
    ]

    for result in response["ResultsByTime"]:
        date_str = result["TimePeriod"]["Start"]
        for group in result["Groups"]:
            service = group["Keys"][0].replace('"', "").replace(" ", "_").replace("/", "_")
            amount  = float(group["Metrics"]["UnblendedCost"]["Amount"])
            if amount > 0:
                lines.append(
                    f'aws_cost_daily_usd{{service="{service}",date="{date_str}",environment="{ENVIRONMENT}"}} {amount:.4f}'
                )

    return lines


def _get_mtd_cost_by_service(start: str, end: str) -> list[str]:
    """Retorna custo MTD por servico."""
    response = CE_CLIENT.get_cost_and_usage(
        TimePeriod={"Start": start, "End": end},
        Granularity="MONTHLY",
        Metrics=["UnblendedCost"],
        GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
    )

    lines = [
        "# HELP aws_cost_mtd_usd Month-to-date AWS cost in USD by service",
        "# TYPE aws_cost_mtd_usd gauge",
    ]

    for result in response["ResultsByTime"]:
        for group in result["Groups"]:
            service = group["Keys"][0].replace('"', "").replace(" ", "_").replace("/", "_")
            amount  = float(group["Metrics"]["UnblendedCost"]["Amount"])
            if amount > 0:
                lines.append(
                    f'aws_cost_mtd_usd{{service="{service}",environment="{ENVIRONMENT}"}} {amount:.4f}'
                )

    return lines


def _get_mtd_total(start: str, end: str) -> float:
    """Retorna custo MTD total (sem breakdown por servico)."""
    response = CE_CLIENT.get_cost_and_usage(
        TimePeriod={"Start": start, "End": end},
        Granularity="MONTHLY",
        Metrics=["UnblendedCost"],
    )
    return sum(
        float(r["Total"]["UnblendedCost"]["Amount"])
        for r in response["ResultsByTime"]
    )


def _get_monthly_forecast(today: date) -> list[str]:
    """Retorna projecao total do mes corrente (MTD real + forecast restante)."""
    last_day       = (today.replace(day=1) + timedelta(days=32)).replace(day=1) - timedelta(days=1)
    forecast_start = str(today + timedelta(days=1))
    forecast_end   = str(last_day + timedelta(days=1))

    if forecast_start >= forecast_end:
        logger.info("Last day of month — skipping forecast")
        return []

    try:
        response = CE_CLIENT.get_cost_forecast(
            TimePeriod={"Start": forecast_start, "End": forecast_end},
            Metric="UNBLENDED_COST",
            Granularity="MONTHLY",
        )
        forecast_amount = float(response["Total"]["Amount"])
    except Exception as exc:
        logger.warning("Could not get CE forecast: %s", exc)
        forecast_amount = 0.0

    first_of_month  = today.replace(day=1)
    mtd_total       = _get_mtd_total(start=str(first_of_month), end=str(today))
    total_projected = mtd_total + forecast_amount

    return [
        "# HELP aws_cost_forecast_usd Projected total cost for current month in USD (MTD real + CE forecast)",
        "# TYPE aws_cost_forecast_usd gauge",
        f'aws_cost_forecast_usd{{environment="{ENVIRONMENT}"}} {total_projected:.4f}',
    ]


def _get_cost_by_tag(start: str, end: str) -> list[str]:
    """Retorna custo MTD agrupado pela tag app=."""
    try:
        response = CE_CLIENT.get_cost_and_usage(
            TimePeriod={"Start": start, "End": end},
            Granularity="MONTHLY",
            Metrics=["UnblendedCost"],
            GroupBy=[{"Type": "TAG", "Key": "app"}],
        )
    except Exception as exc:
        logger.warning("Could not get cost by tag: %s", exc)
        return []

    lines = [
        "# HELP aws_cost_by_tag_usd Month-to-date AWS cost in USD by app tag",
        "# TYPE aws_cost_by_tag_usd gauge",
    ]

    for result in response["ResultsByTime"]:
        for group in result["Groups"]:
            raw_key   = group["Keys"][0]
            app_value = raw_key.split("$", 1)[1] if "$" in raw_key else raw_key.replace("app", "").strip()
            if not app_value:
                app_value = "untagged"
            amount = float(group["Metrics"]["UnblendedCost"]["Amount"])
            if amount > 0:
                lines.append(
                    f'aws_cost_by_tag_usd{{app="{app_value}",environment="{ENVIRONMENT}"}} {amount:.4f}'
                )

    return lines


def _push_to_gateway(payload: str) -> None:
    """Faz POST para o Prometheus Pushgateway com as metricas no formato texto."""
    url  = f"{PUSHGATEWAY_URL}/metrics/job/{JOB_NAME}"
    data = payload.encode("utf-8")
    req  = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={"Content-Type": "text/plain; version=0.0.4; charset=utf-8"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            logger.info("Pushgateway response: %s %s", resp.status, resp.reason)
    except urllib.error.HTTPError as exc:
        logger.error("Pushgateway HTTP error: %s %s", exc.code, exc.reason)
        raise
    except urllib.error.URLError as exc:
        logger.error("Pushgateway connection error: %s", exc.reason)
        raise


if __name__ == "__main__":
    run()

"""
FinOps Cost Exporter — Lambda Function
Consulta AWS Cost Explorer API e faz push de métricas para Prometheus Pushgateway.

Métricas geradas:
  aws_cost_daily_usd{service, date}     — custo diário por serviço (últimos 30 dias)
  aws_cost_mtd_usd{service}             — month-to-date por serviço
  aws_cost_forecast_usd{}               — forecast do mês corrente
  aws_cost_by_tag_usd{app}              — custo MTD por tag app=
  aws_budget_limit_usd{}                — limite do budget
  aws_budget_actual_usd{}               — gasto real vs budget

Frequência: 4x/dia (cron a cada 6h) = ~120 chamadas/mês CE API (free tier: 1000/mês)
"""

import boto3
import json
import logging
import os
import urllib.request
import urllib.error
from datetime import datetime, timedelta, date
from typing import Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

CE_CLIENT = boto3.client("ce", region_name="us-east-1")  # Cost Explorer is global, us-east-1
BUDGETS_CLIENT = boto3.client("budgets", region_name="us-east-1")

PUSHGATEWAY_URL = os.environ["PUSHGATEWAY_URL"]
AWS_ACCOUNT_ID  = os.environ["AWS_ACCOUNT_ID"]
BUDGET_LIMIT_USD = float(os.environ.get("BUDGET_LIMIT_USD", "807"))
BUDGET_NAME      = os.environ.get("BUDGET_NAME", "staging-monthly")
ENVIRONMENT      = os.environ.get("ENVIRONMENT", "staging")
JOB_NAME         = "finops-cost-exporter"


def lambda_handler(event: dict, context: Any) -> dict:
    """Main handler — coleta métricas e push para Pushgateway."""
    logger.info("Starting FinOps cost export")

    today = date.today()
    first_of_month = today.replace(day=1)

    metrics_lines = []

    try:
        # 1. Custo diário por serviço (últimos 30 dias)
        daily_metrics = _get_daily_cost_by_service(
            start=str(today - timedelta(days=30)),
            end=str(today),
        )
        metrics_lines.extend(daily_metrics)
        logger.info(f"Daily cost metrics: {len(daily_metrics)} lines")

        # 2. MTD por serviço
        mtd_metrics = _get_mtd_cost_by_service(
            start=str(first_of_month),
            end=str(today),
        )
        metrics_lines.extend(mtd_metrics)
        logger.info(f"MTD cost metrics: {len(mtd_metrics)} lines")

        # 3. Forecast do mês
        forecast_metrics = _get_monthly_forecast(today)
        metrics_lines.extend(forecast_metrics)

        # 4. Custo MTD por tag app=
        tag_metrics = _get_cost_by_tag(
            start=str(first_of_month),
            end=str(today),
        )
        metrics_lines.extend(tag_metrics)
        logger.info(f"Tag cost metrics: {len(tag_metrics)} lines")

        # 5. Budget estático (limite)
        metrics_lines.append(f'aws_budget_limit_usd{{environment="{ENVIRONMENT}"}} {BUDGET_LIMIT_USD}')

        # 6. Budget actual (MTD total)
        mtd_total = _get_mtd_total(start=str(first_of_month), end=str(today))
        metrics_lines.append(f'aws_budget_actual_usd{{environment="{ENVIRONMENT}"}} {mtd_total}')

        # Push para Pushgateway
        payload = "\n".join(metrics_lines) + "\n"
        _push_to_gateway(payload)
        logger.info(f"Pushed {len(metrics_lines)} metric lines to Pushgateway")

        return {"statusCode": 200, "body": f"Pushed {len(metrics_lines)} metrics"}

    except Exception as e:
        logger.error(f"Error during cost export: {e}", exc_info=True)
        raise


def _get_daily_cost_by_service(start: str, end: str) -> list[str]:
    """Retorna custo diário por serviço como linhas de métricas Prometheus."""
    response = CE_CLIENT.get_cost_and_usage(
        TimePeriod={"Start": start, "End": end},
        Granularity="DAILY",
        Metrics=["UnblendedCost"],
        GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
    )

    lines = []
    lines.append("# HELP aws_cost_daily_usd Daily AWS cost in USD by service")
    lines.append("# TYPE aws_cost_daily_usd gauge")

    for result in response["ResultsByTime"]:
        date_str = result["TimePeriod"]["Start"]
        for group in result["Groups"]:
            service = group["Keys"][0].replace('"', '').replace(' ', '_').replace('/', '_')
            amount = float(group["Metrics"]["UnblendedCost"]["Amount"])
            if amount > 0:
                lines.append(
                    f'aws_cost_daily_usd{{service="{service}",date="{date_str}",environment="{ENVIRONMENT}"}} {amount:.4f}'
                )

    return lines


def _get_mtd_cost_by_service(start: str, end: str) -> list[str]:
    """Retorna custo MTD por serviço."""
    response = CE_CLIENT.get_cost_and_usage(
        TimePeriod={"Start": start, "End": end},
        Granularity="MONTHLY",
        Metrics=["UnblendedCost"],
        GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
    )

    lines = []
    lines.append("# HELP aws_cost_mtd_usd Month-to-date AWS cost in USD by service")
    lines.append("# TYPE aws_cost_mtd_usd gauge")

    for result in response["ResultsByTime"]:
        for group in result["Groups"]:
            service = group["Keys"][0].replace('"', '').replace(' ', '_').replace('/', '_')
            amount = float(group["Metrics"]["UnblendedCost"]["Amount"])
            if amount > 0:
                lines.append(
                    f'aws_cost_mtd_usd{{service="{service}",environment="{ENVIRONMENT}"}} {amount:.4f}'
                )

    return lines


def _get_mtd_total(start: str, end: str) -> float:
    """Retorna custo MTD total (sem breakdown)."""
    response = CE_CLIENT.get_cost_and_usage(
        TimePeriod={"Start": start, "End": end},
        Granularity="MONTHLY",
        Metrics=["UnblendedCost"],
    )

    total = 0.0
    for result in response["ResultsByTime"]:
        total += float(result["Total"]["UnblendedCost"]["Amount"])
    return total


def _get_monthly_forecast(today: date) -> list[str]:
    """Retorna forecast do mês corrente."""
    last_day = (today.replace(day=1) + timedelta(days=32)).replace(day=1) - timedelta(days=1)

    # Forecast começa do dia seguinte ao hoje
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
    except Exception as e:
        logger.warning(f"Could not get forecast: {e}")
        forecast_amount = 0.0

    # MTD atual + forecast restante = total projetado
    first_of_month = today.replace(day=1)
    mtd_total = _get_mtd_total(start=str(first_of_month), end=str(today))
    total_projected = mtd_total + forecast_amount

    lines = [
        "# HELP aws_cost_forecast_usd Projected total cost for current month in USD",
        "# TYPE aws_cost_forecast_usd gauge",
        f'aws_cost_forecast_usd{{environment="{ENVIRONMENT}"}} {total_projected:.4f}',
    ]
    return lines


def _get_cost_by_tag(start: str, end: str) -> list[str]:
    """Retorna custo MTD agrupado pela tag app=."""
    try:
        response = CE_CLIENT.get_cost_and_usage(
            TimePeriod={"Start": start, "End": end},
            Granularity="MONTHLY",
            Metrics=["UnblendedCost"],
            GroupBy=[{"Type": "TAG", "Key": "app"}],
        )
    except Exception as e:
        logger.warning(f"Could not get cost by tag: {e}")
        return []

    lines = [
        "# HELP aws_cost_by_tag_usd Month-to-date AWS cost in USD by app tag",
        "# TYPE aws_cost_by_tag_usd gauge",
    ]

    for result in response["ResultsByTime"]:
        for group in result["Groups"]:
            raw_key = group["Keys"][0]
            # Tag key format: "app$value" — extract value
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
    """Faz POST para o Prometheus Pushgateway com as métricas."""
    url = f"{PUSHGATEWAY_URL}/metrics/job/{JOB_NAME}"
    data = payload.encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={"Content-Type": "text/plain; version=0.0.4; charset=utf-8"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            logger.info(f"Pushgateway response: {response.status} {response.reason}")
    except urllib.error.HTTPError as e:
        logger.error(f"Pushgateway HTTP error: {e.code} {e.reason}")
        raise
    except urllib.error.URLError as e:
        logger.error(f"Pushgateway connection error: {e.reason}")
        raise

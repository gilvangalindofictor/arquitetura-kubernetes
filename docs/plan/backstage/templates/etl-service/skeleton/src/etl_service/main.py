"""Entry point do ETL ${{ values.name }}."""
import os
import sys
import logging
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s" if os.getenv("LOG_FORMAT") != "json" else None,
)
logger = logging.getLogger(__name__)


def setup_tracing() -> None:
    """Configura OpenTelemetry tracing."""
    otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
    if not otlp_endpoint:
        return
    provider = TracerProvider()
    exporter = OTLPSpanExporter(endpoint=otlp_endpoint, insecure=True)
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)
    logger.info("Tracing configurado: %s", otlp_endpoint)


def run_etl() -> int:
    """Executa o pipeline ETL principal."""
    test_mode = os.getenv("ETL_TEST_MODE", "false").lower() == "true"
    if test_mode:
        limit_records = int(os.getenv("ETL_TEST_LIMIT_RECORDS", "100"))
        limit_pages = int(os.getenv("ETL_TEST_LIMIT_PAGES", "3"))
        logger.info("Modo teste ativo: max %d registros, %d páginas", limit_records, limit_pages)

    # TODO: Instanciar e executar os extractors declarados
    logger.info("ETL ${{ values.name }} iniciado (test_mode=%s)", test_mode)
    return 0


def main() -> None:
    """Main entry point."""
    setup_tracing()
    sys.exit(run_etl())


if __name__ == "__main__":
    main()

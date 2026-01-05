# Python Instrumentation Guide (OpenTelemetry)

This guide provides instructions for instrumenting Python applications to send telemetry data to the central OpenTelemetry Collector.

## 1. Install Dependencies

First, install the necessary OpenTelemetry packages. You need the SDK, the OTLP exporter, and any instrumentation libraries relevant to your application's frameworks and libraries (e.g., Flask, Django, Requests, Psycopg2).

```bash
# Core dependencies
pip install opentelemetry-api
pip install opentelemetry-sdk
pip install opentelemetry-exporter-otlp

# Automatic instrumentation for common libraries
pip install opentelemetry-instrumentation-flask
pip install opentelemetry-instrumentation-requests
pip install opentelemetry-instrumentation-psycopg2

# For structured logging with trace correlation
pip install opentelemetry-instrumentation-logging
```

## 2. Configure the SDK

The recommended way to configure and initialize OpenTelemetry is in a central location in your application, before any instrumented libraries are imported. A common pattern is to create a `telemetry.py` file.

**`telemetry.py`:**
```python
import logging
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.logging import LoggingInstrumentor

def setup_telemetry(service_name: str):
    """
    Configures and initializes OpenTelemetry for the application.
    """
    # 1. Set up the Resource
    # This identifies the service and attaches metadata.
    resource = Resource.create(attributes={
        "service.name": service_name,
        # Add other attributes like version, environment, etc.
        # "service.version": "1.0.0",
    })

    # 2. Set up the Tracer Provider
    # This is the core of the tracing SDK.
    tracer_provider = TracerProvider(resource=resource)
    trace.set_tracer_provider(tracer_provider)

    # 3. Set up the OTLP Exporter
    # This sends traces to the OpenTelemetry Collector.
    # The endpoint is typically configured via the OTEL_EXPORTER_OTLP_ENDPOINT env var.
    otlp_exporter = OTLPSpanExporter()
    span_processor = BatchSpanProcessor(otlp_exporter)
    tracer_provider.add_span_processor(span_processor)

    # 4. Instrument Logging
    # This adds trace_id and span_id to your logs automatically.
    LoggingInstrumentor().instrument(set_logging_format=True)
    logging.basicConfig(level=logging.INFO)

    # The tracer can now be retrieved anywhere in the app via trace.get_tracer(__name__)
```

## 3. Automatic Instrumentation

For the fastest and most comprehensive instrumentation, use the `opentelemetry-instrument` command. This command dynamically patches libraries at runtime.

**To run your application with auto-instrumentation:**

```bash
# Instead of: python app.py
# Use this:
opentelemetry-instrument python app.py
```

This command will automatically apply all installed instrumentation libraries (Flask, Requests, etc.).

**How to use it in a Dockerfile:**
Modify the `CMD` or `ENTRYPOINT` of your `Dockerfile`.

```dockerfile
# ... (your Dockerfile setup)

# Set environment variables for the OTel SDK
ENV OTEL_SERVICE_NAME=your-service-name
ENV OTEL_EXPORTER_OTLP_ENDPOINT="http://opentelemetry-collector.observability.svc.cluster.local:4317"
ENV OTEL_PYTHON_LOGGING_FORMAT="%(asctime)s %(levelname)s [%(name)s] [%(filename)s:%(lineno)d] [trace_id=%(otelTraceID)s span_id=%(otelSpanID)s] - %(message)s"

# Run the application with auto-instrumentation
CMD ["opentelemetry-instrument", "python", "app.py"]
```

## 4. Manual Instrumentation (Example)

While auto-instrumentation is powerful, you may need to add custom spans for specific business logic.

```python
import logging
from opentelemetry import trace
from .telemetry import setup_telemetry # Import from your telemetry.py

# Initialize telemetry at the start of your application
SERVICE_NAME = "my-python-service"
setup_telemetry(service_name=SERVICE_NAME)

# Get a tracer
tracer = trace.get_tracer(__name__)
logger = logging.getLogger(__name__)

def process_order(order_id: str):
    # This creates a new span for the process_order function
    with tracer.start_as_current_span("process_order") as span:
        # Add attributes to the span for more context
        span.set_attribute("order.id", order_id)
        
        logger.info(f"Processing order {order_id}")

        # ... your business logic here ...
        
        # Record events within the span
        span.add_event("Order validation complete")

        # ... more logic ...

        logger.info(f"Finished processing order {order_id}")

```

By following these steps, your Python application will be fully instrumented to send traces and logs to the observability platform, with automatic context propagation and correlation.

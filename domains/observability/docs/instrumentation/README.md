# Instrumentation Guide

This directory provides guidance on how to instrument applications to send telemetry data (metrics, logs, traces) to our OpenTelemetry Collector.

## Structure

-   `instrumentation-best-practices.md`: General principles for high-quality telemetry.
-   `instrumentation-golang.md`: Guide for instrumenting Go applications.
-   `instrumentation-java.md`: Guide for instrumenting Java applications.
-   `instrumentation-nodejs.md`: Guide for instrumenting Node.js applications.
-   `instrumentation-python.md`: Guide for instrumenting Python applications.

## Core Principles

The goal of instrumentation is to gain visibility into the behavior and performance of our applications. To ensure consistency and quality, follow these principles:

1.  **Use OpenTelemetry**: Standardize on the OpenTelemetry SDKs for your language. This provides a vendor-agnostic approach to instrumentation.
2.  **Configure via Environment Variables**: The OpenTelemetry SDKs can be configured using standard environment variables. This allows us to manage the telemetry pipeline without changing application code.
    -   `OTEL_EXPORTER_OTLP_ENDPOINT`: Set this to the address of our OpenTelemetry Collector Gateway (e.g., `http://opentelemetry-collector.observability.svc.cluster.local:4317`).
    -   `OTEL_SERVICE_NAME`: Set this to the name of your application (e.g., `user-service`, `product-api`). This is a critical tag for filtering and aggregation.
    -   `OTEL_RESOURCE_ATTRIBUTES`: Add other relevant attributes, such as `deployment.environment=production`.
3.  **Structured Logging**: All logs should be written to `stdout` as JSON. The logging library should automatically include context like `trace_id` and `span_id` to correlate logs with traces.
4.  **Automatic Instrumentation**: Leverage automatic instrumentation libraries for your language/framework whenever possible. This provides a wealth of telemetry for common operations (e.g., HTTP requests, database queries) with minimal effort.
5.  **Custom Instrumentation**: Add custom spans, metrics, and attributes for critical business logic that is not covered by automatic instrumentation.

See the specific guides for each language for detailed examples.

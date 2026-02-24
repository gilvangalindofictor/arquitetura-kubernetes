# Migration: otel-test → staging-observability-otel-test

**Data:** 2026-02-24
**Wave:** 1
**Agent:** Wave1-A5
**Pattern:** A (Test namespace)
**Duration:** ~3min
**Status:** SUCCESS

## Summary
Migrated OpenTelemetry test namespace (used for GAP-007 Tempo OTLP validation).

## Resources
- **Original:** otel-test
- **New:** staging-observability-otel-test
- **Workloads:**
  - Deployment: trace-generator (1 replica)
  - ConfigMap: trace-generator-script (OTLP HTTP trace generator)

## Configuration
- **OTLP Endpoint:** http://opentelemetry-collector.monitoring.svc.cluster.local:4318
- **Trace Operations:**
  - operation-fetch-users (100ms simulation)
  - operation-fetch-orders (200ms simulation)
  - operation-process-payment (150ms simulation)
- **Generation Interval:** Every 20 seconds (3 operations per cycle)

## Validation
- Namespace created: YES
- Labels:
  - environment=staging
  - domain=observability
  - product=otel-test
- Pod status: Running (1/1 Ready)
- Traces flowing: YES
  - HTTP Status: 200 (OpenTelemetry Collector accepting traces)
  - Sample traceIds:
    - 88391635a6eba138... (operation-fetch-users)
    - b087cf916bde988c... (operation-fetch-orders)
    - 62932e2a7d0ce030... (operation-process-payment)

## Migration Steps
1. Created namespace staging-observability-otel-test
2. Applied labels (environment, domain, product)
3. Migrated ConfigMap trace-generator-script
4. Migrated Deployment trace-generator
5. Verified pod startup and trace generation

## Post-Migration
- Old namespace (otel-test) still active for 7d grace period
- New trace-generator successfully sending traces to Tempo via OpenTelemetry Collector
- No downtime in trace generation (dual workloads for ~3min)

## Next Steps
- Monitor trace generation for 24h
- Delete old namespace after 7d (2026-03-03)
- Use for OTLP testing and Tempo trace validation

## Files
- Backup: /tmp/migration-otel-test-backup/
  - resources.yaml (full backup)
  - trace-generator.yaml (deployment manifest)
  - configmap.yaml (trace script)

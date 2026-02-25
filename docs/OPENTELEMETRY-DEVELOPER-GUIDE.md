# 🔭 OpenTelemetry Developer Guide — Instrumentação de Aplicações

**Data**: 2026-02-25
**Status**: ✅ Production Ready
**OpenTelemetry Collector**: `opentelemetry-collector.staging-observability-monitoring.svc.cluster.local`

---

## 🎯 Quick Start

### Endpoints OTLP Disponíveis

```bash
# gRPC (recomendado)
OTEL_EXPORTER_OTLP_ENDPOINT=http://opentelemetry-collector.staging-observability-monitoring.svc.cluster.local:4317

# HTTP/JSON
OTEL_EXPORTER_OTLP_ENDPOINT=http://opentelemetry-collector.staging-observability-monitoring.svc.cluster.local:4318
```

### Variáveis de Ambiente Obrigatórias

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://opentelemetry-collector.staging-observability-monitoring.svc.cluster.local:4317"
  - name: OTEL_SERVICE_NAME
    value: "minha-aplicacao"  # Nome do seu serviço
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "environment=staging,team=platform,domain=my-domain"
```

---

## 📚 Instrumentação por Linguagem

### Python (Flask/FastAPI)

**1. Instalar dependências:**
```bash
pip install opentelemetry-api opentelemetry-sdk opentelemetry-instrumentation-flask opentelemetry-exporter-otlp
```

**2. Instrumentar aplicação (automático):**
```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor

# Setup tracer
trace.set_tracer_provider(TracerProvider())
otlp_exporter = OTLPSpanExporter(
    endpoint="opentelemetry-collector.staging-observability-monitoring.svc.cluster.local:4317",
    insecure=True
)
trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(otlp_exporter))

# Auto-instrument Flask
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)
```

**3. Span manual (opcional):**
```python
from opentelemetry import trace

tracer = trace.get_tracer(__name__)

@app.route('/api/users')
def get_users():
    with tracer.start_as_current_span("fetch-users-from-db") as span:
        span.set_attribute("user.count", len(users))
        return jsonify(users)
```

---

### Go (Gin/Echo)

**1. Instalar dependências:**
```bash
go get go.opentelemetry.io/otel
go get go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc
go get go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin
```

**2. Instrumentar aplicação:**
```go
package main

import (
    "context"
    "github.com/gin-gonic/gin"
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
    "go.opentelemetry.io/otel/sdk/trace"
    "go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
)

func initTracer() func() {
    exporter, _ := otlptracegrpc.New(context.Background(),
        otlptracegrpc.WithEndpoint("opentelemetry-collector.staging-observability-monitoring.svc.cluster.local:4317"),
        otlptracegrpc.WithInsecure(),
    )

    tp := trace.NewTracerProvider(trace.WithBatcher(exporter))
    otel.SetTracerProvider(tp)

    return func() { tp.Shutdown(context.Background()) }
}

func main() {
    cleanup := initTracer()
    defer cleanup()

    r := gin.Default()
    r.Use(otelgin.Middleware("my-service"))

    r.GET("/api/users", getUsers)
    r.Run()
}
```

---

### Java (Spring Boot)

**1. Adicionar dependência (pom.xml):**
```xml
<dependency>
    <groupId>io.opentelemetry.instrumentation</groupId>
    <artifactId>opentelemetry-spring-boot-starter</artifactId>
    <version>1.32.0-alpha</version>
</dependency>
```

**2. Configurar (application.yml):**
```yaml
otel:
  exporter:
    otlp:
      endpoint: http://opentelemetry-collector.staging-observability-monitoring.svc.cluster.local:4317
  service:
    name: my-spring-app
  traces:
    exporter: otlp
```

**3. Java Agent (alternativa - zero code):**
```bash
# Download agent
wget https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v1.32.0/opentelemetry-javaagent.jar

# Dockerfile
ENV JAVA_TOOL_OPTIONS="-javaagent:/app/opentelemetry-javaagent.jar"
ENV OTEL_EXPORTER_OTLP_ENDPOINT="http://opentelemetry-collector.staging-observability-monitoring.svc.cluster.local:4317"
ENV OTEL_SERVICE_NAME="my-app"
```

---

### .NET (ASP.NET Core)

**1. Instalar pacotes:**
```bash
dotnet add package OpenTelemetry.Extensions.Hosting
dotnet add package OpenTelemetry.Instrumentation.AspNetCore
dotnet add package OpenTelemetry.Exporter.OpenTelemetryProtocol
```

**2. Configurar (Program.cs):**
```csharp
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenTelemetry()
    .WithTracing(tracerProviderBuilder =>
        tracerProviderBuilder
            .AddSource("MyApp")
            .SetResourceBuilder(ResourceBuilder.CreateDefault().AddService("my-dotnet-app"))
            .AddAspNetCoreInstrumentation()
            .AddOtlpExporter(options => {
                options.Endpoint = new Uri("http://opentelemetry-collector.staging-observability-monitoring.svc.cluster.local:4317");
            }));

var app = builder.Build();
app.Run();
```

---

### Node.js (Express)

**1. Instalar dependências:**
```bash
npm install @opentelemetry/api @opentelemetry/sdk-node @opentelemetry/auto-instrumentations-node @opentelemetry/exporter-trace-otlp-grpc
```

**2. Criar tracing.js:**
```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: 'http://opentelemetry-collector.staging-observability-monitoring.svc.cluster.local:4317',
  }),
  instrumentations: [getNodeAutoInstrumentations()],
  serviceName: 'my-node-app',
});

sdk.start();
```

**3. Inicializar (index.js):**
```javascript
require('./tracing'); // DEVE ser primeira linha
const express = require('express');
```

---

## 🚀 Deployment Template (Kubernetes)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minha-app
  namespace: meu-namespace
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: app
        image: minha-app:latest
        env:
          # OpenTelemetry Configuration
          - name: OTEL_EXPORTER_OTLP_ENDPOINT
            value: "http://opentelemetry-collector.staging-observability-monitoring.svc.cluster.local:4317"
          - name: OTEL_SERVICE_NAME
            value: "minha-app"
          - name: OTEL_RESOURCE_ATTRIBUTES
            value: "environment=staging,team=platform,domain=applications"

          # Optional: Sampling (reduce volume)
          - name: OTEL_TRACES_SAMPLER
            value: "parentbased_traceidratio"
          - name: OTEL_TRACES_SAMPLER_ARG
            value: "0.1"  # 10% sampling
```

---

## 🔍 Visualização de Traces

### Grafana Explore

1. Acesse Grafana: `https://grafana.staging.example.com`
2. Navegue: **Explore** → **Datasource: Tempo**
3. Query TraceQL:
   ```traceql
   # Buscar traces do meu serviço
   { service.name = "minha-aplicacao" }

   # Traces com erro
   { service.name = "minha-aplicacao" && status = error }

   # Traces lentos (>500ms)
   { service.name = "minha-aplicacao" && duration > 500ms }
   ```

### Correlação Logs ↔ Traces

Adicione `trace_id` nos logs:
```python
import logging
from opentelemetry import trace

span = trace.get_current_span()
trace_id = span.get_span_context().trace_id
logging.info(f"Processing request trace_id={trace_id:032x}")
```

Loki query com trace_id:
```logql
{namespace="meu-namespace"} |= "trace_id=621b494ad83c307a"
```

---

## 📊 Métricas Disponíveis

### Prometheus Metrics via OTel

```python
from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter

# Setup metrics
metric_exporter = OTLPMetricExporter(
    endpoint="opentelemetry-collector.staging-observability-monitoring.svc.cluster.local:4317",
    insecure=True
)
reader = PeriodicExportingMetricReader(metric_exporter)
provider = MeterProvider(metric_readers=[reader])
metrics.set_meter_provider(provider)

# Create custom metric
meter = metrics.get_meter(__name__)
request_counter = meter.create_counter(
    "http_requests_total",
    description="Total HTTP requests",
    unit="1"
)

# Increment
request_counter.add(1, {"method": "GET", "endpoint": "/api/users"})
```

---

## 🛠️ Troubleshooting

### Traces não aparecem no Grafana

**1. Verificar conectividade:**
```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://opentelemetry-collector.staging-observability-monitoring.svc.cluster.local:4318/v1/traces \
  -X POST -H "Content-Type: application/json" -d '{}'
# Esperado: HTTP/1.1 200 OK
```

**2. Verificar logs OTel Collector:**
```bash
kubectl logs -n staging-observability-monitoring -l app.kubernetes.io/name=opentelemetry-collector --tail=50
```

**3. Verificar variável de ambiente:**
```bash
kubectl exec -it meu-pod -- env | grep OTEL
```

### High Latency

**Usar sampling:**
```yaml
env:
  - name: OTEL_TRACES_SAMPLER
    value: "parentbased_traceidratio"
  - name: OTEL_TRACES_SAMPLER_ARG
    value: "0.1"  # 10% traces
```

### Network Policy Bloqueio

**Verificar se namespace tem label:**
```bash
kubectl get namespace meu-namespace --show-labels
# Se não: kubectl label namespace meu-namespace name=meu-namespace
```

---

## 📚 Referências

- [OpenTelemetry Docs](https://opentelemetry.io/docs/)
- [Grafana Tempo Docs](https://grafana.com/docs/tempo/latest/)
- [TraceQL Query Language](https://grafana.com/docs/tempo/latest/traceql/)
- [ADR-080: OpenTelemetry Collector Architecture](docs/adr/adr-080-opentelemetry-collector-implementation.md)

---

**Dúvidas?** Abra issue no repositório ou contate #platform-team

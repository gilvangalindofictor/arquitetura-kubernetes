# OpenTelemetry Collector Helm Values
# Mode: Deployment (Gateway pattern)
# Exporters: Tempo (traces) + Prometheus (metrics) + Loki (logs)

mode: deployment

replicaCount: ${replicas}

image:
  repository: "${ecr_registry != "" ? "${ecr_registry}/docker-hub/otel/opentelemetry-collector-contrib" : "otel/opentelemetry-collector-contrib"}"
  tag: "0.108.0"
  pullPolicy: IfNotPresent

resources:
  requests:
    cpu: ${cpu_request}
    memory: ${memory_request}
  limits:
    cpu: ${cpu_limit}
    memory: ${memory_limit}

service:
  type: ClusterIP

ports:
  otlp:
    enabled: true
    containerPort: 4317
    servicePort: 4317
    protocol: TCP
  otlp-http:
    enabled: true
    containerPort: 4318
    servicePort: 4318
    protocol: TCP
  metrics:
    enabled: true
    containerPort: 8888
    servicePort: 8888
    protocol: TCP

config:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318

  processors:
    batch:
      send_batch_size: 1024
      timeout: 10s
      send_batch_max_size: 2048

    memory_limiter:
      check_interval: 5s
      limit_mib: ${memory_limiter_limit}
      spike_limit_mib: 128

  exporters:
    otlp/tempo:
      endpoint: ${tempo_endpoint}
      tls:
        insecure: true
      sending_queue:
        enabled: true
        num_consumers: 10
        queue_size: 1000
      retry_on_failure:
        enabled: true
        initial_interval: 5s
        max_interval: 30s
        max_elapsed_time: 300s

    prometheusremotewrite:
      endpoint: ${prometheus_endpoint}
      tls:
        insecure: true

    loki:
      endpoint: ${loki_endpoint}
      tls:
        insecure: true

  service:
    pipelines:
      traces:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [otlp/tempo]

      metrics:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [prometheusremotewrite]

      logs:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [loki]

serviceMonitor:
  enabled: ${enable_servicemonitor}
  interval: ${servicemonitor_interval}

podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8888"
  prometheus.io/path: "/metrics"

podLabels:
  domain: ${domain}
  owner: ${owner}
  environment: ${environment}
  app.kubernetes.io/part-of: observability
  app.kubernetes.io/name: opentelemetry-collector

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app.kubernetes.io/name
            operator: In
            values:
            - opentelemetry-collector
        topologyKey: kubernetes.io/hostname

livenessProbe:
  httpGet:
    path: /
    port: 13133
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /
    port: 13133
  initialDelaySeconds: 10
  periodSeconds: 5

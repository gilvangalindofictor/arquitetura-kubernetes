# Helm Charts for Observability Platform

This directory contains the Helm configurations for deploying the observability stack on the EKS cluster provisioned by Terraform.

## Architecture

Based on **ADR-002**, we will use the following Helm charts:
- **kube-prometheus-stack**: For Prometheus, Alertmanager, and Grafana
- **loki**: For log aggregation
- **tempo**: For distributed tracing
- **opentelemetry-collector**: As a central gateway for all signals

## Structure

```
infra/helm/
├── README.md                     # This file
├── opentelemetry-collector/      # Configuration for OTEL Collector
│   └── values.yaml
├── kube-prometheus-stack/
│   └── values.yaml
├── loki/
│   └── values.yaml
└── tempo/
    └── values.yaml
```

## Prerequisites

1. **EKS Cluster**: Provisioned via Terraform (Fase 1)
2. **kubectl**: Configured to access the cluster
3. **Helm**: Version 3+ installed

## Deployment Steps

### 1. Add Helm Repositories

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update
```

### 2. Create Namespaces

(If not already created during Terraform setup)
```bash
kubectl create namespace observability-dev
kubectl create namespace observability-hml
kubectl create namespace observability-prd
```
For the stack itself, we'll use a dedicated namespace:
```bash
kubectl create namespace observability
```

### 3. Deploy OpenTelemetry Collector

This is the central hub for receiving data.

```bash
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  --namespace observability \
  -f opentelemetry-collector/values.yaml
```

### 4. Deploy Loki (for Logs)

```bash
helm upgrade --install loki grafana/loki \
  --namespace observability \
  -f loki/values.yaml
```

### 5. Deploy Tempo (for Traces)

```bash
helm upgrade --install tempo grafana/tempo \
  --namespace observability \
  -f tempo/values.yaml
```

### 6. Deploy kube-prometheus-stack (for Metrics & Visualization)

This stack includes Prometheus, Alertmanager, and Grafana.

```bash
helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace observability \
  -f kube-prometheus-stack/values.yaml
```

## Configuration Highlights

### `opentelemetry-collector/values.yaml`
- **Mode**: `gateway`
- **Receivers**: OTLP (gRPC, HTTP)
- **Processors**: `memory_limiter`, `batch`, `attributes`
- **Exporters**: `prometheusremotewrite`, `loki`, `otlp` (to Tempo)
- **Service**: LoadBalancer to expose the OTLP receiver endpoint.

### `kube-prometheus-stack/values.yaml`
- **Prometheus**:
  - `prometheusSpec.storageSpec`: Configure retention (e.g., 15d)
  - `prometheusSpec.remoteWrite`: Point to a long-term storage solution (e.g., Thanos, Cortex) in a future phase.
- **Grafana**:
  - `grafana.enabled = true`
  - `grafana.adminPassword`: Set a secure password (or use a secret).
  - `grafana.persistence`: Enable persistence for dashboards.
  - `grafana.additionalDataSources`: Pre-configure Loki and Tempo datasources.
- **Alertmanager**:
  - `alertmanager.config`: Configure receivers (e.g., Slack, PagerDuty).

### `loki/values.yaml`
- **Persistence**: `persistence.enabled = true`
- **Storage**: Configure S3 backend using IRSA.
  ```yaml
  loki:
    storage:
      type: s3
      s3:
        bucketNames:
          chunks: "your-loki-chunks-bucket"
          ruler: "your-loki-ruler-bucket"
          admin: "your-loki-admin-bucket"
        region: "us-east-1"
  ```
- **Service Account**: Annotate with the IAM role for S3 access.

### `tempo/values.yaml`
- **Persistence**: `persistence.enabled = true`
- **Storage**: Configure S3 backend using IRSA.
  ```yaml
  tempo:
    storage:
      trace:
        backend: s3
        s3:
          bucket: "your-tempo-traces-bucket"
          endpoint: "s3.us-east-1.amazonaws.com"
  ```
- **Service Account**: Annotate with the IAM role for S3 access.

## Next Steps

- Populate the `values.yaml` files with the specific configurations.
- Create a script to automate the deployment of all charts.
- Configure Grafana dashboards and alerts (Fase 3).

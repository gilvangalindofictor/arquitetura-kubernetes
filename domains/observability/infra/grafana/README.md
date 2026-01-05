# Grafana Dashboards and Alerts

This directory contains the configurations for Grafana dashboards and Prometheus alert rules.

## Structure

```
infra/grafana/
├── README.md
├── dashboards/
│   └── golden-signals.json   # Dashboard for RED/USE metrics
└── alerts/
    └── general-alerts.yaml   # Basic alert rules for services
```

## How it Works

### Dashboards

The `kube-prometheus-stack` Helm chart can automatically import dashboards from ConfigMaps. We will create a ConfigMap from the JSON files in the `dashboards/` directory.

1.  **Create ConfigMap**:
    ```bash
    kubectl create configmap golden-signals-dashboard \
      --from-file=dashboards/golden-signals.json \
      -n observability
    ```

2.  **Label the ConfigMap**:
    Grafana's sidecar will automatically pick up any ConfigMap with the label `grafana_dashboard: "1"`.
    ```bash
    kubectl label configmap golden-signals-dashboard grafana_dashboard="1" -n observability
    ```

This process can be automated by adding the dashboard configuration directly into the `kube-prometheus-stack/values.yaml` file, which is the recommended approach.

### Alerts

Prometheus can automatically load alert rules from `PrometheusRule` custom resources.

1.  **Create PrometheusRule CRD**:
    The `general-alerts.yaml` file is a `PrometheusRule` manifest. To apply it:
    ```bash
    kubectl apply -f alerts/general-alerts.yaml -n observability
    ```

Prometheus, managed by the Prometheus Operator, will detect this new resource and load the rules automatically.

## Customization

### Golden Signals Dashboard

The `golden-signals.json` dashboard is a template. It uses Grafana variables to allow you to select:
-   `$namespace`
-   `$service`
-   `$job`

The queries are based on standard OpenTelemetry metric names (e.g., `http_server_duration_seconds_bucket`, `http_server_requests_total`). You may need to adjust them based on your specific instrumentation.

### General Alerts

The `general-alerts.yaml` file includes alerts for:
-   **HighErrorRate**: Fires when the percentage of 5xx errors is > 5% for 5 minutes.
-   **HighLatency**: Fires when the P99 latency is > 500ms for 5 minutes.
-   **InstanceDown**: Fires when a service instance is down for more than 1 minute.

These thresholds are starting points and should be adjusted based on your service SLOs.

## Next Steps

- Review and customize the dashboard JSON and alert rules YAML.
- Apply the configurations to your cluster.
- Integrate the import process into the Helm chart for automated management.

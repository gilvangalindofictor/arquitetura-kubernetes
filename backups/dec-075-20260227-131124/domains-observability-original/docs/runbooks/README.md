# Runbooks

This directory contains runbooks for responding to alerts defined in `infra/alerts/`. Each runbook provides a step-by-step guide for on-call engineers to diagnose and mitigate issues.

## Structure

### General Alerts (pre-existing)
-   `runbook-high-error-rate.md`: Steps to take when the `HighErrorRate` alert fires.
-   `runbook-high-latency.md`: Steps to take when the `HighLatency` alert fires.
-   `runbook-instance-down.md`: Steps to take when the `InstanceDown` alert fires.

### DT-005: Infrastructure Alerts
-   `dt005-node-not-ready.md`: Node in NotReady state (critical)
-   `dt005-node-disk-pressure.md`: Node disk usage above thresholds (warning/critical)
-   `dt005-node-memory-pressure.md`: Node memory running low (warning/critical)
-   `dt005-pvc-near-full.md`: PersistentVolumeClaim approaching capacity (warning/critical)

### DT-005: Application Alerts
-   `dt005-pod-crash-looping.md`: Pod restarting repeatedly / OOMKilled (critical)
-   `dt005-pod-not-ready.md`: Pod running but failing readiness checks (warning)
-   `dt005-deployment-replicas-mismatch.md`: Deployment has fewer replicas than desired (warning/critical)
-   `dt005-high-5xx-rate.md`: High 5xx error rate on ingress endpoints (warning/critical)

### DT-005: Data Services Alerts
-   `dt005-postgresql-connections-high.md`: PostgreSQL connection pool approaching limit (warning/critical)
-   `dt005-postgresql-down.md`: PostgreSQL instance unreachable (critical)
-   `dt005-redis-high-memory.md`: Redis memory usage high / Redis down (warning/critical)
-   `dt005-redis-down.md`: Redis instance unreachable (critical)
-   `dt005-rabbitmq-queue-depth.md`: RabbitMQ queue backlog / RabbitMQ down (warning/critical)
-   `dt005-rabbitmq-down.md`: RabbitMQ instance unreachable (critical)

### DT-005: Security Alerts
-   `dt005-certificate-expiring.md`: TLS certificate nearing expiration (warning/critical)
-   `dt005-vault-sealed.md`: Vault sealed or down (critical)
-   `dt005-external-secret-sync-failure.md`: External Secrets Operator sync failures (warning/critical)

## How to Use

When an alert fires, the alert notification (e.g., in Slack) should contain a link to the corresponding runbook in this directory. The on-call engineer follows the steps in the runbook to resolve the issue.

## Runbook Template

Each runbook should follow a consistent structure:

1.  **Alert Name**: The name of the alert this runbook corresponds to.
2.  **Severity**: The severity of the alert (e.g., `warning`, `critical`).
3.  **Description**: A brief explanation of what the alert means.
4.  **Initial Triage**: Quick steps to validate the alert and assess the impact.
    -   Check the relevant Grafana dashboard.
    -   Identify the affected service(s), namespace(s), and pod(s).
    -   Determine the start time of the issue.
5.  **Diagnostic Steps**: Detailed instructions to find the root cause.
    -   Check application logs in Loki.
    -   Analyze traces in Tempo for the affected service.
    -   Inspect pod status, events, and resource usage with `kubectl`.
    -   Look for recent deployments or configuration changes.
6.  **Mitigation/Resolution**: Actions to take to resolve the issue.
    -   Roll back a recent deployment.
    -   Scale up the service.
    -   Restart a failing pod.
    -   Escalate to the service owner.
7.  **Post-Mortem**: A reminder to create a post-mortem to document the incident and identify follow-up actions to prevent recurrence.

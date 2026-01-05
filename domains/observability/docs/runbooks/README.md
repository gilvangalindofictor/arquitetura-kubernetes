# Runbooks

This directory contains runbooks for responding to alerts defined in `infra/grafana/alerts`. Each runbook provides a step-by-step guide for on-call engineers to diagnose and mitigate issues.

## Structure

-   `runbook-high-error-rate.md`: Steps to take when the `HighErrorRate` alert fires.
-   `runbook-high-latency.md`: Steps to take when the `HighLatency` alert fires.
-   `runbook-instance-down.md`: Steps to take when the `InstanceDown` alert fires.

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

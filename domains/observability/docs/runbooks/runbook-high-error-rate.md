# Runbook: HighErrorRate

- **Alert Name**: `HighErrorRate`
- **Severity**: `critical`
- **Description**: The percentage of server-side errors (5xx) for a service is above 5% for more than 5 minutes. This indicates a significant portion of user requests are failing.

---

## 1. Initial Triage

1.  **Open the Golden Signals Dashboard**: Click the link in the alert to open the [Golden Signals Dashboard](http://localhost:3000/d/golden-signals-template/golden-signals-dashboard).
2.  **Identify Scope**:
    -   Use the dashboard filters (`$namespace`, `$service`) to isolate the affected service(s) identified in the alert labels.
    -   Observe the **Error Rate** panel. Note the start time of the spike.
    -   Observe the **Request Rate** panel. Is there a corresponding drop in traffic? Or a sudden spike?
3.  **Check for Known Issues**: Check the `#deployments` or `#incidents` Slack channel for recent deployments or ongoing incidents that might be related.

## 2. Diagnostic Steps

1.  **Analyze Logs with Loki**:
    -   Go to the Grafana "Explore" view and select the **Loki** datasource.
    -   Use the following LogQL query to find error logs for the affected service. Replace `your-namespace` and `your-service` with the values from the alert.
        ```logql
        {namespace="your-namespace", service="your-service"} |= "error" or level="error"
        ```
    -   Look for stack traces, database connection errors, upstream service failures, or other exceptions that coincide with the alert start time.

2.  **Inspect Traces with Tempo**:
    -   In the Loki logs, find a `traceID` associated with a failed request.
    -   Copy the `traceID` and go to the Grafana "Explore" view, selecting the **Tempo** datasource.
    -   Paste the `traceID` into the search bar.
    -   Analyze the trace waterfall. Look for spans that are marked in red (indicating an error). The tags on the error span often contain the specific error message. Identify which component in the call chain is the source of the error.

3.  **Check Kubernetes Pods**:
    -   Get the list of pods for the affected service:
        ```bash
        kubectl get pods -n <namespace> -l service=<service-name>
        ```
    -   Check the status of the pods. Are they `Running`? Have there been recent restarts (`RESTARTS` column)?
    -   Describe a pod to look for recent events, such as OOMKilled, readiness probe failures, or other issues:
        ```bash
        kubectl describe pod <pod-name> -n <namespace>
        ```
    -   Check the logs of a specific pod for startup errors or other critical messages not captured in the centralized logging stream:
        ```bash
        kubectl logs <pod-name> -n <namespace>
        ```

## 3. Mitigation / Resolution

The appropriate action depends on the root cause found in the diagnostic steps.

-   **Bad Deployment**: If the errors started immediately after a recent deployment:
    -   **Action**: Roll back the deployment.
        ```bash
        kubectl rollout undo deployment/<deployment-name> -n <namespace>
        ```
    -   **Communicate**: Announce the rollback in the appropriate Slack channel.

-   **Upstream Service Failure**: If traces indicate an external or internal dependency is failing:
    -   **Action**: Investigate the upstream service. Escalate to the team that owns the upstream service.
    -   **Communicate**: Notify stakeholders that the issue is related to a dependency.

-   **Resource Exhaustion (CPU/Memory)**: If pods are crashing with `OOMKilled` or are heavily throttled:
    -   **Action**: Temporarily increase the number of replicas for the service.
        ```bash
        kubectl scale deployment/<deployment-name> --replicas=<new-replica-count> -n <namespace>
        ```
    -   **Follow-up**: Create a task to analyze and adjust the resource limits (`requests` and `limits`) for the service.

-   **Configuration Issue**: If logs indicate a misconfiguration (e.g., bad database connection string):
    -   **Action**: Correct the configuration in the relevant ConfigMap or Secret and redeploy the service.

## 4. Post-Mortem

Once the incident is resolved, create a post-mortem to document the timeline, root cause, and impact. Identify and assign action items to prevent the issue from recurring.

# Runbook: PodCrashLooping

- **Alert Name**: `PodCrashLooping`
- **Severity**: `critical`
- **Source**: DT-005 Application Alerts
- **Description**: A pod container has restarted more than 5 times in 10 minutes, indicating a persistent crash loop. The application is unable to start or stay running.

---

## 1. Initial Triage

1. **Check pod status and restart count**:
   ```bash
   kubectl get pod <pod-name> -n <namespace> -o wide
   kubectl describe pod <pod-name> -n <namespace>
   ```

2. **Check the pod events** for error messages:
   ```bash
   kubectl get events -n <namespace> --field-selector involvedObject.name=<pod-name> --sort-by='.lastTimestamp'
   ```

3. **Check if this is a widespread issue**:
   ```bash
   kubectl get pods -n <namespace> | grep -E "CrashLoopBackOff|Error"
   ```

## 2. Diagnostic Steps

1. **Check current container logs**:
   ```bash
   kubectl logs <pod-name> -n <namespace> -c <container-name>
   ```

2. **Check previous crash logs**:
   ```bash
   kubectl logs <pod-name> -n <namespace> -c <container-name> --previous
   ```

3. **Check termination reason**:
   ```bash
   kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.status.containerStatuses[*].lastState.terminated}' | jq .
   ```

4. **Common crash reasons**:
   - **OOMKilled**: Container exceeded memory limits. Check `lastState.terminated.reason`.
   - **Error (exit code 1)**: Application error. Check logs for stack traces.
   - **Error (exit code 137)**: SIGKILL (OOM or preemption).
   - **Error (exit code 143)**: SIGTERM (graceful shutdown failed).

5. **Check if dependencies are available**:
   ```bash
   # Database connectivity
   kubectl exec -n <namespace> <pod-name> -- nslookup <database-service>
   # Secret/ConfigMap availability
   kubectl get secret -n <namespace>
   kubectl get configmap -n <namespace>
   ```

6. **Check recent deployments**:
   ```bash
   kubectl rollout history deployment/<deployment-name> -n <namespace>
   ```

## 3. Mitigation / Resolution

- **OOMKilled**: Increase memory limits:
  ```bash
  kubectl set resources deployment/<deployment> -n <namespace> --limits=memory=<new-limit>
  ```

- **Bad deployment**: Roll back to the previous version:
  ```bash
  kubectl rollout undo deployment/<deployment-name> -n <namespace>
  ```

- **Missing secrets/configmaps**: Verify they exist and are correctly mounted:
  ```bash
  kubectl get secret <secret-name> -n <namespace>
  kubectl get configmap <configmap-name> -n <namespace>
  ```

- **Dependency failure** (database, Redis, etc.):
  1. Check the dependency service health
  2. Check network policies: `kubectl get networkpolicy -n <namespace>`
  3. Check DNS resolution from within the pod namespace

- **Image pull failure**:
  ```bash
  kubectl get events -n <namespace> | grep "image"
  # Check imagePullSecrets
  kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.imagePullSecrets}'
  ```

## 4. Post-Mortem

- Document the root cause of the crash loop
- Review liveness/readiness probe configurations
- Implement proper health checks
- Review resource limits (memory/CPU) based on actual usage patterns
- If dependency-related, consider adding proper health check init containers

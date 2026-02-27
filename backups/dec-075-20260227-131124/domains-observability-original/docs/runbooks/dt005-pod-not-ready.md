# Runbook: PodNotReady

- **Alert Name**: `PodNotReady`
- **Severity**: `warning`
- **Source**: DT-005 Application Alerts
- **Description**: A pod is in Running phase but has not passed readiness checks for more than 5 minutes. The pod is not serving traffic (removed from Service endpoints).

---

## 1. Initial Triage

1. **Check pod status**:
   ```bash
   kubectl get pod <pod-name> -n <namespace> -o wide
   kubectl describe pod <pod-name> -n <namespace>
   ```

2. **Check readiness probe configuration**:
   ```bash
   kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[*].readinessProbe}' | jq .
   ```

3. **Check endpoint status** (is the pod removed from Service?):
   ```bash
   kubectl get endpoints <service-name> -n <namespace>
   ```

## 2. Diagnostic Steps

1. **Check pod events for probe failures**:
   ```bash
   kubectl get events -n <namespace> --field-selector involvedObject.name=<pod-name> | grep -i "unhealthy\|readiness"
   ```

2. **Manually test the readiness endpoint**:
   ```bash
   kubectl exec -n <namespace> <pod-name> -- curl -s localhost:<port>/<path>
   # Or for TCP probes:
   kubectl exec -n <namespace> <pod-name> -- nc -zv localhost <port>
   ```

3. **Check application logs for errors**:
   ```bash
   kubectl logs <pod-name> -n <namespace> --tail=200
   ```

4. **Check if the application is waiting on dependencies**:
   - Database connections
   - Cache (Redis) connectivity
   - External API availability
   - Configuration loading

## 3. Mitigation / Resolution

- **Dependency not ready**: Wait for the dependency to become available, or fix the dependency issue.

- **Readiness probe misconfigured**: Adjust probe parameters:
  ```bash
  kubectl edit deployment/<deployment-name> -n <namespace>
  ```
  Consider adjusting: `initialDelaySeconds`, `periodSeconds`, `failureThreshold`, `timeoutSeconds`.

- **Application stuck**: Restart the pod:
  ```bash
  kubectl delete pod <pod-name> -n <namespace>
  ```

- **Resource constraints**: The application may be too slow to respond to probes:
  ```bash
  kubectl top pod <pod-name> -n <namespace>
  ```

## 4. Post-Mortem

- Review readiness probe settings relative to application startup time
- Check if the probe endpoint is appropriate (should check real application health)
- Consider using startup probes for slow-starting applications
- Document any dependency ordering requirements

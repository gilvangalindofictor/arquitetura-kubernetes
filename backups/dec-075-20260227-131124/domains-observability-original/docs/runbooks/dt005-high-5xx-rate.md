# Runbook: High5xxErrorRate

- **Alert Name**: `High5xxErrorRateWarning` / `High5xxErrorRateCritical`
- **Severity**: `warning` (>1%) / `critical` (>5%)
- **Source**: DT-005 Application Alerts
- **Description**: An ingress endpoint is returning a high rate of 5xx errors. This indicates backend service failures affecting user requests.

---

## 1. Initial Triage

1. **Open the Ingress Overview Dashboard** in Grafana filtered by the affected ingress/namespace.

2. **Identify the affected ingress**:
   ```bash
   kubectl get ingress -n <namespace>
   kubectl describe ingress <ingress-name> -n <namespace>
   ```

3. **Check backend service and pods**:
   ```bash
   kubectl get pods -n <namespace> -o wide
   kubectl get endpoints -n <namespace>
   ```

4. **Check for recent deployments**:
   ```bash
   kubectl rollout history deployment -n <namespace>
   ```

## 2. Diagnostic Steps

1. **Check ingress-nginx logs for upstream errors**:
   ```bash
   kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=200 | grep "5[0-9][0-9]"
   ```

2. **Check backend pod logs**:
   ```bash
   kubectl logs -n <namespace> -l app=<service-name> --tail=200
   ```

3. **Analyze with Loki** (if available):
   ```logql
   {namespace="<namespace>"} |= "error" | json | status >= 500
   ```

4. **Check if pods are healthy**:
   ```bash
   kubectl get pods -n <namespace> -o wide
   kubectl top pods -n <namespace>
   ```

5. **Check if the service has enough endpoints**:
   ```bash
   kubectl get endpoints <service-name> -n <namespace>
   ```

## 3. Mitigation / Resolution

- **Bad deployment**: Roll back immediately:
  ```bash
  kubectl rollout undo deployment/<deployment-name> -n <namespace>
  ```

- **Resource exhaustion**: Scale up the deployment:
  ```bash
  kubectl scale deployment/<deployment-name> --replicas=<N> -n <namespace>
  ```

- **Dependency failure** (database, cache, external API):
  Investigate and fix the dependency. Check database connection pool usage, Redis availability, etc.

- **Rate limiting or resource limits**: Check if HPA is configured and functioning:
  ```bash
  kubectl get hpa -n <namespace>
  ```

## 4. Post-Mortem

- Document timeline, root cause, and user impact
- Review error handling in the application
- Implement circuit breakers if not present
- Review auto-scaling policies
- Consider SLO budget consumption tracking

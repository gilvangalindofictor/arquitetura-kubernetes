# Runbook: DeploymentReplicasMismatch

- **Alert Name**: `DeploymentReplicasMismatch` / `DeploymentReplicasMismatchCritical`
- **Severity**: `warning` (>15 min) / `critical` (>30 min)
- **Source**: DT-005 Application Alerts
- **Description**: A deployment has fewer available replicas than desired for an extended period. This indicates pods are failing to start, pass readiness checks, or are being evicted.

---

## 1. Initial Triage

1. **Check deployment status**:
   ```bash
   kubectl get deployment <deployment-name> -n <namespace>
   kubectl describe deployment <deployment-name> -n <namespace>
   ```

2. **Check ReplicaSet status**:
   ```bash
   kubectl get rs -n <namespace> -l app=<deployment-name>
   ```

3. **Identify pods that are not Running/Ready**:
   ```bash
   kubectl get pods -n <namespace> -l app=<deployment-name>
   ```

## 2. Diagnostic Steps

1. **Check pending pods**:
   ```bash
   kubectl get pods -n <namespace> -l app=<deployment-name> --field-selector=status.phase=Pending
   kubectl describe pod <pending-pod-name> -n <namespace>
   ```

2. **Common reasons for mismatch**:

   - **Insufficient resources**: Check events for `Insufficient cpu` or `Insufficient memory`:
     ```bash
     kubectl get events -n <namespace> | grep -i "insufficient\|failed\|unschedulable"
     ```

   - **Node affinity/taints**: Pod cannot be scheduled due to node constraints:
     ```bash
     kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.nodeSelector}' | jq .
     kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.tolerations}' | jq .
     ```

   - **Image pull failure**:
     ```bash
     kubectl get events -n <namespace> | grep "image\|pull\|ErrImagePull"
     ```

   - **Volume mount issues**:
     ```bash
     kubectl get events -n <namespace> | grep -i "volume\|mount\|attach"
     ```

3. **Check cluster capacity**:
   ```bash
   kubectl describe nodes | grep -A5 "Allocated resources"
   kubectl top nodes
   ```

## 3. Mitigation / Resolution

- **Insufficient resources**: Scale the node group or reduce resource requests:
  ```bash
  # Scale node group
  aws autoscaling set-desired-capacity --auto-scaling-group-name <asg> --desired-capacity <N>

  # Or reduce requests
  kubectl set resources deployment/<name> -n <namespace> --requests=cpu=<new>,memory=<new>
  ```

- **Image pull failure**: Check image exists and credentials are valid:
  ```bash
  kubectl get secret -n <namespace> | grep docker
  # Test pull manually
  docker pull <image>:<tag>
  ```

- **Recent bad deployment**: Roll back:
  ```bash
  kubectl rollout undo deployment/<deployment-name> -n <namespace>
  kubectl rollout status deployment/<deployment-name> -n <namespace>
  ```

- **Stuck rollout**: If a rollout is stuck:
  ```bash
  kubectl rollout restart deployment/<deployment-name> -n <namespace>
  ```

## 4. Post-Mortem

- Identify the root cause of the scheduling or startup failure
- Review resource requests/limits allocation
- Document if node group capacity needs adjustment
- Set up PodDisruptionBudgets to ensure minimum availability during disruptions

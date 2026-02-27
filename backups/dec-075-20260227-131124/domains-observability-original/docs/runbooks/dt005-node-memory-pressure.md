# Runbook: NodeMemoryPressure

- **Alert Name**: `NodeMemoryPressureWarning` / `NodeMemoryPressureCritical`
- **Severity**: `warning` (<20% available) / `critical` (<10% available)
- **Source**: DT-005 Infrastructure Alerts
- **Description**: A Kubernetes node is running low on available memory. At critical levels, the OOM killer will terminate processes and the kubelet may evict pods.

---

## 1. Initial Triage

1. **Check node memory status**:
   ```bash
   kubectl describe node <node-name> | grep -A10 "Allocated resources"
   kubectl top node <node-name>
   ```

2. **Identify top memory-consuming pods on this node**:
   ```bash
   kubectl top pods --all-namespaces --sort-by=memory | head -20
   ```

3. **Check for recent OOMKill events**:
   ```bash
   kubectl get events --all-namespaces --field-selector reason=OOMKilling --sort-by='.lastTimestamp'
   ```

## 2. Diagnostic Steps

1. **Check memory allocation vs. actual usage**:
   ```bash
   # Total requested vs allocatable
   kubectl describe node <node-name> | grep -A20 "Allocated resources"
   ```

2. **Identify pods with high memory usage**:
   ```bash
   # Actual usage
   kubectl top pods --all-namespaces --field-selector spec.nodeName=<node-name> --sort-by=memory

   # Requested limits
   kubectl get pods --all-namespaces --field-selector spec.nodeName=<node-name> \
     -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,MEM_REQ:.spec.containers[*].resources.requests.memory,MEM_LIM:.spec.containers[*].resources.limits.memory'
   ```

3. **Check for memory leaks** (pods using significantly more than requested):
   Compare `kubectl top pods` output with configured resource requests.

4. **Check system-level memory** (if SSH access):
   ```bash
   free -h
   cat /proc/meminfo | head -20
   ps aux --sort=-%mem | head -20
   ```

## 3. Mitigation / Resolution

- **Evict non-critical pods** from the node:
  ```bash
  kubectl cordon <node-name>
  kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --grace-period=30
  ```

- **Scale node group** to add capacity:
  ```bash
  aws autoscaling set-desired-capacity \
    --auto-scaling-group-name <asg-name> \
    --desired-capacity <current+1>
  ```

- **Kill specific high-memory pods** if identifiable:
  ```bash
  kubectl delete pod <pod-name> -n <namespace>
  ```

- **Adjust resource limits** for pods consuming excessive memory:
  Update the deployment spec with appropriate memory limits.

- **Long-term fix**:
  - Review resource requests/limits for all workloads on the node
  - Implement VPA (Vertical Pod Autoscaler) for automatic right-sizing
  - Consider larger instance types for the node group
  - Implement pod priority classes to ensure critical workloads survive eviction

## 4. Post-Mortem

Document the root cause:
- Was it a memory leak in an application?
- Were resource limits misconfigured?
- Was the node group undersized for the workload?
- Create action items: fix memory leak, adjust limits, resize node group

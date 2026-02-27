# Runbook: NodeDiskPressure

- **Alert Name**: `NodeDiskPressureWarning` / `NodeDiskPressureCritical`
- **Severity**: `warning` (>80%) / `critical` (>90%)
- **Source**: DT-005 Infrastructure Alerts
- **Description**: The root filesystem on a Kubernetes node is running out of disk space. At critical levels, kubelet will begin evicting pods.

---

## 1. Initial Triage

1. **Check node disk usage**:
   ```bash
   kubectl describe node <node-name> | grep -A5 "Conditions"
   ```

2. **Check which pods are on this node**:
   ```bash
   kubectl get pods --all-namespaces --field-selector spec.nodeName=<node-name> -o wide
   ```

3. **Check disk metrics** in Grafana: Open the Node Overview dashboard filtered by the affected node.

## 2. Diagnostic Steps

1. **SSH to the node and check disk usage** (if access available):
   ```bash
   df -h /
   du -sh /* | sort -rh | head -20
   du -sh /var/lib/docker/* | sort -rh | head -10  # or containerd
   du -sh /var/log/* | sort -rh | head -10
   ```

2. **Check container image cache**:
   ```bash
   crictl images | wc -l
   crictl images --no-trunc | sort -k 4 -h -r | head -20
   ```

3. **Check for large log files**:
   ```bash
   find /var/log -type f -size +100M -exec ls -lh {} \;
   journalctl --disk-usage
   ```

4. **Check for orphaned container data**:
   ```bash
   crictl ps -a | grep -c "Exited"
   ```

## 3. Mitigation / Resolution

- **Emergency cleanup** (critical level):
  ```bash
  # Prune unused container images
  crictl rmi --prune

  # Clean old journal logs
  sudo journalctl --vacuum-size=200M

  # Remove old completed pods' logs
  find /var/log/pods -type f -name "*.log" -mtime +7 -delete
  ```

- **Container runtime cleanup**:
  ```bash
  # Remove stopped containers
  crictl rm $(crictl ps -a -q --state exited)

  # Clean unused images
  crictl rmi --prune
  ```

- **Prevent new workloads** while cleaning:
  ```bash
  kubectl cordon <node-name>
  # After cleanup:
  kubectl uncordon <node-name>
  ```

- **Increase EBS volume** if root volume is too small:
  1. Find the EBS volume ID for the instance in AWS Console
  2. Modify the volume to increase size
  3. SSH to the node and extend the filesystem:
     ```bash
     sudo growpart /dev/nvme0n1 1
     sudo resize2fs /dev/nvme0n1p1
     ```

- **Long-term fix**: Update the EKS node group launch template to use a larger root volume.

## 4. Post-Mortem

Document what consumed the disk space and implement preventive measures:
- Configure log rotation (logrotate, journald MaxRetentionSec)
- Set up periodic image pruning (kubelet imageGCHighThresholdPercent)
- Increase root EBS volume size in the launch template
- Consider dedicated volumes for /var/lib/containerd

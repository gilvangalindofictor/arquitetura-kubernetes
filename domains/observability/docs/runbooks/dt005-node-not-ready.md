# Runbook: NodeNotReady

- **Alert Name**: `NodeNotReady`
- **Severity**: `critical`
- **Source**: DT-005 Infrastructure Alerts
- **Description**: A Kubernetes node has been in NotReady state for more than 5 minutes. The kubelet is either not responding or has reported unhealthy conditions. Workloads on this node may be evicted.

---

## 1. Initial Triage

1. **Check node status**:
   ```bash
   kubectl get nodes -o wide
   kubectl describe node <node-name>
   ```

2. **Identify affected workloads**:
   ```bash
   kubectl get pods --all-namespaces --field-selector spec.nodeName=<node-name>
   ```

3. **Check for known issues**: Review `#incidents` Slack channel and recent change logs.

4. **Check EKS node group status** in AWS Console:
   - EC2 > Auto Scaling Groups > look for the relevant node group
   - Check instance health in EC2 console

## 2. Diagnostic Steps

1. **Check kubelet status** (if SSH access available):
   ```bash
   ssh <node-ip>
   systemctl status kubelet
   journalctl -u kubelet -n 200 --no-pager
   ```

2. **Check node conditions**:
   ```bash
   kubectl get node <node-name> -o jsonpath='{.status.conditions[*]}' | jq .
   ```
   Look for: `MemoryPressure`, `DiskPressure`, `PIDPressure`, `NetworkUnavailable`.

3. **Check EC2 instance**:
   ```bash
   aws ec2 describe-instance-status --instance-ids <instance-id>
   ```

4. **Check AWS CloudWatch** for EC2 system check failures:
   - StatusCheckFailed_System: Hardware/infrastructure issue
   - StatusCheckFailed_Instance: OS/software issue

5. **Check kube-proxy and CNI (VPC CNI)**:
   ```bash
   kubectl get pods -n kube-system -o wide | grep <node-name>
   ```

## 3. Mitigation / Resolution

- **Kubelet crash**: Restart kubelet on the node:
  ```bash
  ssh <node-ip>
  sudo systemctl restart kubelet
  ```

- **EC2 instance unhealthy**: Terminate the instance and let the ASG replace it:
  ```bash
  kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
  aws ec2 terminate-instances --instance-ids <instance-id>
  ```

- **Node group scaling issue**: Check ASG capacity and desired count:
  ```bash
  aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <asg-name>
  ```

- **Resource exhaustion**: If node has DiskPressure or MemoryPressure, see the corresponding runbooks.

- **Network issue**: Check VPC CNI plugin and security group rules:
  ```bash
  kubectl logs -n kube-system -l k8s-app=aws-node --tail=100
  ```

## 4. Post-Mortem

After resolution, document the incident:
- Timeline of events
- Root cause (hardware failure, software crash, resource exhaustion, network)
- Impact on workloads (which pods were evicted, service disruption duration)
- Action items to prevent recurrence (e.g., node group resize, resource limits)

# Runbook: PersistentVolumeClaimNearFull

- **Alert Name**: `PersistentVolumeClaimNearFullWarning` / `PersistentVolumeClaimNearFullCritical`
- **Severity**: `warning` (>85%) / `critical` (>95%)
- **Source**: DT-005 Infrastructure Alerts
- **Description**: A Persistent Volume Claim is running out of space. At critical levels, the application will fail to write new data, potentially causing data loss or service outage.

---

## 1. Initial Triage

1. **Identify the PVC and its consumer**:
   ```bash
   kubectl get pvc <pvc-name> -n <namespace>
   kubectl describe pvc <pvc-name> -n <namespace>
   ```

2. **Find which pod uses this PVC**:
   ```bash
   kubectl get pods -n <namespace> -o json | jq -r '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == "<pvc-name>") | .metadata.name'
   ```

3. **Check the underlying PV**:
   ```bash
   kubectl get pv $(kubectl get pvc <pvc-name> -n <namespace> -o jsonpath='{.spec.volumeName}')
   ```

## 2. Diagnostic Steps

1. **Check disk usage inside the pod**:
   ```bash
   kubectl exec -n <namespace> <pod-name> -- df -h
   kubectl exec -n <namespace> <pod-name> -- du -sh /* 2>/dev/null | sort -rh | head -20
   ```

2. **For specific services**:

   **PostgreSQL PVC**:
   ```bash
   # Check WAL size
   kubectl exec -n <namespace> <pod-name> -- du -sh /var/lib/postgresql/data/pg_wal/
   # Check table sizes
   kubectl exec -n <namespace> <pod-name> -- psql -U postgres -c "SELECT pg_size_pretty(pg_database_size(datname)) as size, datname FROM pg_database ORDER BY pg_database_size(datname) DESC;"
   ```

   **Prometheus PVC**:
   ```bash
   # Check TSDB blocks
   kubectl exec -n monitoring <prometheus-pod> -- du -sh /prometheus/
   ```

   **GitLab PVC**:
   ```bash
   kubectl exec -n <namespace> <pod-name> -- du -sh /var/opt/gitlab/*
   ```

3. **Check EBS volume in AWS**:
   ```bash
   PV_NAME=$(kubectl get pvc <pvc-name> -n <namespace> -o jsonpath='{.spec.volumeName}')
   VOLUME_ID=$(kubectl get pv $PV_NAME -o jsonpath='{.spec.csi.volumeHandle}')
   aws ec2 describe-volumes --volume-ids $VOLUME_ID
   ```

## 3. Mitigation / Resolution

- **Expand the PVC** (EBS CSI Driver supports online expansion):
  ```bash
  # Ensure the StorageClass allows expansion
  kubectl get storageclass gp2 -o jsonpath='{.allowVolumeExpansion}'

  # Expand the PVC
  kubectl patch pvc <pvc-name> -n <namespace> -p '{"spec":{"resources":{"requests":{"storage":"<new-size>"}}}}'

  # Monitor the resize operation
  kubectl get pvc <pvc-name> -n <namespace> -w
  ```

- **Clean up data** (service-specific):

  **PostgreSQL**: Run VACUUM and clean WAL:
  ```sql
  VACUUM FULL;
  SELECT pg_size_pretty(pg_database_size('dbname'));
  ```

  **Prometheus**: Reduce retention or delete old blocks:
  ```bash
  # Adjust retention in the Prometheus spec
  kubectl edit prometheus -n monitoring
  ```

- **Emergency**: If PVC is 100% full and application is crashing:
  1. Scale down the consuming deployment to 0
  2. Resize the PVC
  3. Wait for resize to complete
  4. Scale back up

## 4. Post-Mortem

- Review data retention policies for the affected service
- Implement proactive PVC monitoring with lower thresholds
- Consider automatic PVC resize policies (if using volume auto-expansion controllers)
- Document the growth rate to plan future capacity needs

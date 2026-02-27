# Runbook: PostgreSQLDown

- **Alert Name**: `PostgreSQLDown`
- **Severity**: `critical`
- **Source**: DT-005 Data Services Alerts
- **Description**: PostgreSQL exporter cannot reach the database instance. All dependent services will experience connection failures.

---

## 1. Initial Triage

1. **Check PostgreSQL pod status**:
   ```bash
   kubectl get pods -n <namespace> -l app=postgresql -o wide
   kubectl describe pod -n <namespace> -l app=postgresql
   ```

2. **Check service endpoints**:
   ```bash
   kubectl get endpoints -n <namespace> | grep postgresql
   kubectl get svc -n <namespace> | grep postgresql
   ```

3. **Check recent events**:
   ```bash
   kubectl get events -n <namespace> --sort-by='.lastTimestamp' | grep -i postgres
   ```

## 2. Diagnostic Steps

1. **Check PostgreSQL pod logs**:
   ```bash
   kubectl logs -n <namespace> -l app=postgresql --tail=200
   kubectl logs -n <namespace> -l app=postgresql --previous  # If pod restarted
   ```

2. **Check PVC status** (storage-related failure):
   ```bash
   kubectl get pvc -n <namespace> | grep postgresql
   kubectl describe pvc <postgresql-pvc> -n <namespace>
   ```

3. **Check if the issue is network-related**:
   ```bash
   kubectl exec -n <namespace> <any-pod> -- nslookup <postgresql-service-name>
   kubectl exec -n <namespace> <any-pod> -- nc -zv <postgresql-service-name> 5432
   ```

4. **For RDS**: Check AWS Console:
   - RDS instance status
   - CloudWatch metrics (CPU, storage, connections)
   - Recent RDS events

## 3. Mitigation / Resolution

- **Pod CrashLooping**: Check logs and follow the PodCrashLooping runbook.

- **Storage full**: Follow the PVC Near Full runbook. For PostgreSQL specifically:
  ```sql
  -- Check disk usage
  SELECT pg_size_pretty(pg_database_size(datname)), datname FROM pg_database;
  -- Clean WAL if applicable
  SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0'));
  ```

- **OOMKilled**: Increase memory limits:
  ```bash
  kubectl set resources statefulset/<postgresql-sts> -n <namespace> --limits=memory=<new-limit>
  ```

- **Corrupted data** (last resort): Restore from backup:
  1. Scale down dependent services
  2. Restore from latest backup/snapshot
  3. Validate data integrity
  4. Scale up dependent services

## 4. Post-Mortem

- Document the root cause of the outage
- Review backup and recovery procedures
- Ensure automated backups are running (check backup CronJobs)
- Review resource limits and disk space allocated
- Consider implementing read replicas for HA

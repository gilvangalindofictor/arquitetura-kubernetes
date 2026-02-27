# Runbook: PostgreSQLConnectionPoolHigh

- **Alert Name**: `PostgreSQLConnectionPoolHighWarning` / `PostgreSQLConnectionPoolHighCritical`
- **Severity**: `warning` (>70%) / `critical` (>85%)
- **Source**: DT-005 Data Services Alerts
- **Description**: PostgreSQL connection pool usage is approaching the configured `max_connections` limit. When the limit is reached, new connections will be refused and applications will fail.

---

## 1. Initial Triage

1. **Check current connection count**:
   ```sql
   SELECT count(*) as total_connections FROM pg_stat_activity;
   SELECT max_conn FROM (SELECT setting::int as max_conn FROM pg_settings WHERE name = 'max_connections') t;
   ```

2. **Check the PostgreSQL Overview Dashboard** in Grafana.

3. **Check which applications are consuming connections**:
   ```sql
   SELECT application_name, client_addr, count(*)
   FROM pg_stat_activity
   GROUP BY application_name, client_addr
   ORDER BY count DESC;
   ```

## 2. Diagnostic Steps

1. **Check connection distribution by state**:
   ```sql
   SELECT state, count(*)
   FROM pg_stat_activity
   GROUP BY state
   ORDER BY count DESC;
   ```
   Pay attention to: `idle`, `idle in transaction`, `active`.

2. **Identify idle-in-transaction connections** (these are often the problem):
   ```sql
   SELECT pid, now() - xact_start AS duration, application_name, query
   FROM pg_stat_activity
   WHERE state = 'idle in transaction'
   ORDER BY duration DESC;
   ```

3. **Check for long-running queries**:
   ```sql
   SELECT pid, now() - query_start AS duration, application_name, state, query
   FROM pg_stat_activity
   WHERE state != 'idle'
   ORDER BY duration DESC
   LIMIT 20;
   ```

4. **Check connection pooling** (PgBouncer, if used):
   ```bash
   kubectl get pods -n <namespace> -l app=pgbouncer
   # Connect to PgBouncer admin and check pools:
   # SHOW pools; SHOW stats;
   ```

## 3. Mitigation / Resolution

- **Kill idle connections** (WARNING: may affect applications):
  ```sql
  -- Kill connections idle for more than 10 minutes
  SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE state = 'idle'
    AND query_start < now() - interval '10 minutes'
    AND pid != pg_backend_pid();
  ```

- **Kill idle-in-transaction** (may cause transaction rollback):
  ```sql
  SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE state = 'idle in transaction'
    AND xact_start < now() - interval '5 minutes';
  ```

- **Restart leaking application pods**:
  ```bash
  kubectl rollout restart deployment/<leaking-app> -n <namespace>
  ```

- **Increase max_connections** (RDS parameter group):
  Note: This is a temporary fix. Investigate connection leaks first.
  ```bash
  aws rds modify-db-parameter-group \
    --db-parameter-group-name <param-group> \
    --parameters "ParameterName=max_connections,ParameterValue=200,ApplyMethod=pending-reboot"
  ```

- **Implement connection pooling** if not already in place (PgBouncer recommended).

## 4. Post-Mortem

- Identify which application has a connection leak
- Review connection pool configuration in application code
- Ensure applications properly close connections (use try-with-resources or context managers)
- Consider implementing PgBouncer or similar connection pooler
- Set `idle_in_transaction_session_timeout` in PostgreSQL configuration

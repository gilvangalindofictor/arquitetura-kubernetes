# Runbook: RedisHighMemoryUsage / RedisDown

- **Alert Name**: `RedisHighMemoryUsageWarning` / `RedisHighMemoryUsageCritical` / `RedisDown`
- **Severity**: `warning` (>80%) / `critical` (>90% or down)
- **Source**: DT-005 Data Services Alerts
- **Description**: Redis is either consuming excessive memory (risk of eviction or OOM) or completely unavailable. Redis is used for caching and session management; outage impacts application performance severely.

---

## 1. Initial Triage

1. **Check Redis pod status**:
   ```bash
   kubectl get pods -n <namespace> -l app=redis -o wide
   kubectl describe pod -n <namespace> -l app=redis
   ```

2. **Check Redis info** (if accessible):
   ```bash
   kubectl exec -n <namespace> <redis-pod> -- redis-cli INFO memory
   kubectl exec -n <namespace> <redis-pod> -- redis-cli INFO server
   ```

3. **Check Sentinel status** (if HA):
   ```bash
   kubectl exec -n <namespace> <sentinel-pod> -- redis-cli -p 26379 SENTINEL masters
   ```

## 2. Diagnostic Steps

### For High Memory Usage:

1. **Check memory breakdown**:
   ```bash
   kubectl exec -n <namespace> <redis-pod> -- redis-cli INFO memory
   ```
   Key values: `used_memory_human`, `maxmemory_human`, `mem_fragmentation_ratio`.

2. **Find biggest keys**:
   ```bash
   kubectl exec -n <namespace> <redis-pod> -- redis-cli --bigkeys
   ```

3. **Check eviction policy and evicted keys**:
   ```bash
   kubectl exec -n <namespace> <redis-pod> -- redis-cli CONFIG GET maxmemory-policy
   kubectl exec -n <namespace> <redis-pod> -- redis-cli INFO stats | grep evicted
   ```

4. **Check key count by database**:
   ```bash
   kubectl exec -n <namespace> <redis-pod> -- redis-cli INFO keyspace
   ```

### For Redis Down:

1. **Check pod logs**:
   ```bash
   kubectl logs -n <namespace> -l app=redis --tail=200
   kubectl logs -n <namespace> -l app=redis --previous
   ```

2. **Check PVC**:
   ```bash
   kubectl get pvc -n <namespace> | grep redis
   ```

3. **Check if Sentinel has promoted a replica** (HA setup):
   ```bash
   kubectl exec -n <namespace> <sentinel-pod> -- redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster
   ```

## 3. Mitigation / Resolution

### High Memory:

- **Flush specific database** (if safe -- e.g., cache only):
  ```bash
  kubectl exec -n <namespace> <redis-pod> -- redis-cli SELECT <db-number>
  kubectl exec -n <namespace> <redis-pod> -- redis-cli FLUSHDB
  ```

- **Remove specific large keys**:
  ```bash
  kubectl exec -n <namespace> <redis-pod> -- redis-cli DEL <key-name>
  ```

- **Increase maxmemory**:
  ```bash
  kubectl exec -n <namespace> <redis-pod> -- redis-cli CONFIG SET maxmemory <new-value>
  ```

- **Increase pod memory limits**:
  ```bash
  kubectl edit statefulset/<redis-sts> -n <namespace>
  ```

### Redis Down:

- **Restart Redis pod**:
  ```bash
  kubectl delete pod <redis-pod> -n <namespace>
  ```

- **If data corruption**: Remove the RDB/AOF file and restart:
  ```bash
  kubectl exec -n <namespace> <redis-pod> -- rm /data/dump.rdb
  kubectl delete pod <redis-pod> -n <namespace>
  ```

## 4. Post-Mortem

- Investigate the source of memory growth (application caching patterns)
- Review TTL policies on cached keys
- Consider implementing Redis key expiration policies
- Review Redis maxmemory-policy setting (allkeys-lru recommended for cache use cases)
- Document HA failover procedure

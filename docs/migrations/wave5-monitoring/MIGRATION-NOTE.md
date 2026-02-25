# Monitoring Migration Note - 2026-02-25

## Snapshot Issue: Prometheus & Loki-write-0

**Problem**: EBS snapshots for 2 volumes stuck at "pending 0%" for >10 minutes:
- vol-075c7f28aa4b988c7 (Prometheus 20GB)
- vol-057296e9f2d1d1032 (Loki-write-0 10GB)

**Attempted Solutions**:
1. Waited 10+ minutes (normal snapshots complete in 2-5min)
2. Deleted and recreated snapshots - same result
3. Tried CSI VolumeSnapshot - failed (in-tree volumes without CSI)

**Root Cause**: Likely AWS-side throttling or service issue. 7/9 other snapshots completed successfully.

**Decision - PRAGMATIC MIGRATION**:
- **Prometheus**: Deploy with fresh PVC. Time-series data has 15d retention, will rebuild from scrapes.
  - Impact: ~2-4h of historical query gaps (acceptable for staging)
  - Grafana dashboards will show "No data" for 2026-02-13 to 2026-02-25 range

- **Loki-write-0**: Deploy with fresh PVC, replica loki-write-1 has snapshot.
  - Impact: Minimal, write path is ephemeral (logs buffered before backend storage)
  - Backend storage (loki-backend-0, loki-backend-1) successfully snapshotted

**Successful Snapshots** (7/9):
- ✅ loki-backend-0 (snap-0d753e1d4bab7d443)
- ✅ loki-backend-1 (snap-0bebbc4997d7cdc5e)
- ✅ loki-write-1 (snap-0bf55521b350e3b8c)
- ✅ tempo-ingester-0 (snap-0d6aed6943e055547)
- ✅ tempo-ingester-1 (snap-07181f6fae320741f)
- ✅ grafana (snap-05539a2a7c7f5a827)
- ✅ alertmanager (snap-0490065954a1afb94)

**Failed Snapshots**:
- ❌ prometheus-db (retry snap-0c2379fe6f5c921ba pending)
- ❌ loki-write-0 (retry snap-090b305bce339fdd4 pending)

**Alternative Considered**: Scale down StatefulSets, detach volumes, snapshot - rejected due to time (would take 20-30min more).

**Validation Plan**:
1. Deploy monitoring stack in new namespace
2. Wait 5 minutes for Prometheus scrapes
3. Query `up{job="kubernetes-apiservers"}` - should return current data
4. Check Grafana dashboards - expect historical data gaps
5. Test Loki logs - should work (backend storage restored)

**Approval**: Proceeding with migration using 7 successful snapshots + 2 fresh PVCs.

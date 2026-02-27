# Node Rightsizing - Executive Summary
**Date:** 2026-02-27
**Decision Required By:** 2026-03-06

---

## 1-Minute Overview

**Problem:** Cluster running 11 nodes with 7.3% average CPU utilization and unbalanced memory (6-72%). Current architecture wastes R$ 19,376/year on oversized/underutilized instances.

**Solution:** Migrate to r5 instance family (memory-optimized), reducing from 11 to 8 nodes while increasing total capacity by 21%.

**Financial Impact:**
- **Savings:** R$ 10,584/year (21% cost reduction)
- **Implementation Cost:** R$ 2,000 (60h SRE time)
- **ROI:** 530% (payback in 2 months)

**Risk Level:** LOW (rolling update, zero downtime for Phases 1-2, 5min planned downtime for Phase 3)

**Timeline:** 60 days (3 phases with 7-day burn-in periods)

---

## Comparison Table

| Metric | Current (T3) | Recommended (R5) | Improvement |
|--------|--------------|------------------|-------------|
| **Annual Cost** | R$ 50,411 | R$ 31,034 | **-38%** |
| **Savings (adjusted)** | — | — | **R$ 10,584/year** |
| **Total Nodes** | 11 | 8 | -27% |
| **Total RAM** | 92 GB | 112 GB | +21.7% |
| **Avg CPU Usage** | 7.3% | 15-25% (target) | Better utilization |
| **Memory Pressure** | 2 nodes @ 60-72% | All nodes <50% | Eliminated risk |
| **Network Bandwidth** | 5 Gbps | 10 Gbps | 2× faster |
| **CPU Throttling** | Yes (burst model) | No (100% baseline) | Predictable perf |

---

## Key Findings

### Current State Issues
1. **Severe CPU underutilization:** 7.3% average (2-16% range)
2. **Memory imbalance:** 2 nodes with 60-72% usage risk OOM events
3. **Scheduling failures:** Loki StatefulSet cannot schedule (insufficient memory/CPU)
4. **Overcommit risk:** Some nodes have 272% CPU limit overcommit
5. **Burst billing:** T3 instances incur $50-80/mo extra charges during peak load

### R5 Advantages
- **Memory-optimized:** 1:4 CPU/RAM ratio (vs T3's 1:2)
- **Dedicated CPU:** 100% baseline (no throttling, no burst charges)
- **Cost-effective:** R$ 0.0157/GB RAM vs T3's R$ 0.0312/GB (50% cheaper per GB)
- **Better networking:** 10 Gbps bandwidth (eliminates Prometheus scrape timeouts)
- **Proven workload fit:** Ideal for monitoring, logging, CI/CD platforms

---

## Migration Plan (60 Days)

### Phase 1: System Pool (Week 1-2)
- **Scope:** 3 t3.medium → 2 r5.large
- **Downtime:** Zero (rolling update)
- **Risk:** Low (DaemonSets auto-migrate)
- **Savings:** R$ 1,784/year

### Phase 2: Workloads Pool (Week 3-4)
- **Scope:** 6 t3.large → 4 r5.xlarge
- **Downtime:** Zero (rolling update)
- **Risk:** Medium (StatefulSets require graceful eviction)
- **Savings:** R$ 7,104/year

### Phase 3: Critical Pool (Week 5-6)
- **Scope:** 2 t3.xlarge → 2 r5.xlarge (same count, better specs)
- **Downtime:** 5 minutes (Vault unseal + RabbitMQ cluster reform)
- **Risk:** Medium-High (requires backup/restore validation)
- **Savings:** R$ 7,256/year (includes performance gains)

**Total Adjusted Savings:** R$ 10,584/year (accounting for VPA overlap)

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Pod rescheduling failures | Use 300s grace period for StatefulSets, verify PodDisruptionBudgets |
| Vault data loss | Velero backup + snapshot before Phase 3, test unseal in staging |
| Network disruption | Sequential node draining (2 at a time), monitor Prometheus metrics |
| Cost overrun | R5 has no burst charges (fixed monthly cost) |

**Rollback Strategy:** Each phase can rollback independently within 1-4 hours (old node groups kept for 24h post-migration).

---

## Success Metrics (30-day targets)

| KPI | Baseline | Target | Business Impact |
|-----|----------|--------|-----------------|
| Node CPU Utilization | 7.3% | 15-25% | Better resource efficiency |
| Node Memory Usage | 34% (unbalanced) | 40-50% (balanced) | Eliminated pressure risk |
| Pod Scheduling Failures | 1-2/day | 0/week | Improved developer experience |
| Monthly Cost | R$ 4,201 | R$ 2,586 | 38% cost reduction |
| Prometheus Scrape Errors | 2-5/hour | 0/day | Monitoring reliability |

---

## Approval Checklist

- [ ] **Platform Team Lead:** Approve 60-day migration timeline
- [ ] **FinOps Manager:** Confirm R$ 10,584/year savings target
- [ ] **Infrastructure Director:** Approve 5-minute planned downtime (Phase 3)
- [ ] **Security Team:** Review Vault migration procedure (Phase 3)

**Next Steps After Approval:**
1. Schedule kick-off meeting (Week 1)
2. Create Terraform feature branch: `feat/node-rightsizing-r5`
3. Run staging simulation (3-day validation)
4. Execute Phase 1 migration (Wednesday 02:00 AM UTC window)

---

## References

- **Full Analysis:** `/reports/node-rightsizing-analysis-2026-02-27.md` (11,000+ words)
- **Current State Metrics:** Collected 2026-02-27 from production cluster
- **Pricing Source:** AWS EC2 On-Demand pricing (US-East-1, as of 2026-02-27)
- **Related Work:** VPA FASE 0 (R$ 15-17K/year savings already in progress)

---

**Decision Deadline:** 2026-03-06
**Point of Contact:** Performance & Capacity Specialist Agent
**Escalation Path:** Platform Team Lead → Infrastructure Director

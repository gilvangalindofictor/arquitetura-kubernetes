# DEC-074: Namespace Migration - Complete Documentation Index

**Generated:** 2026-02-24
**Total Documentation:** 5,434 lines, 16,490 words, 204KB
**Status:** COMPLETE - Ready for Review

---

## Document Structure

```
DEC-074-namespace-migration/
├── README.md                    [16KB] - Getting Started Guide
├── EXECUTIVE-SUMMARY.md         [14KB] - Decision Document (60-second TL;DR)
├── INDEX.md                     [THIS FILE] - Documentation Navigator
│
├── 01-namespace-mapping.md      [6.5KB] - Complete mapping: old → new names
├── 02-dependency-graph.md       [18KB] - Service dependencies & migration order
├── 03-migration-patterns.md     [13KB] - Migration strategies by workload type
├── 04-execution-plan.md         [25KB] - Detailed timeline, waves, validation
├── 05-risk-register.md          [15KB] - Risk assessment & mitigation
├── 06-ADR-074.md                [18KB] - Architectural Decision Record
│
└── scripts/
    ├── migrate-stateless.sh      [9.3KB] - Pattern A (stateless services)
    ├── migrate-stateful-pvc.sh   [16KB]  - Pattern C (StatefulSets + PVCs)
    ├── migrate-operator-crd.sh   [16KB]  - Pattern D (operator-managed CRDs)
    └── rollback.sh               [8.9KB] - Universal rollback script
```

**Total:** 8 documentation files, 4 executable scripts, 12 deliverables

---

## Who Should Read What?

### For Leadership (10 minutes)

**Start Here:**
1. [EXECUTIVE-SUMMARY.md](./EXECUTIVE-SUMMARY.md) - Decision document (3min)
   - TL;DR: Problem, solution, cost, ROI, approval form
2. [01-namespace-mapping.md](./01-namespace-mapping.md) - See what changes (2min)
3. [05-risk-register.md](./05-risk-register.md) - Risk matrix (5min)

**Key Questions Answered:**
- Why migrate? (Governance compliance + $67k/year benefit)
- What's the cost? ($15,700 one-time)
- What's the risk? (1 CRITICAL, 4 HIGH, manageable with safeguards)
- When? (2026-02-25 to 2026-03-05, 7 days)

---

### For Architects & Tech Leads (30 minutes)

**Start Here:**
1. [06-ADR-074.md](./06-ADR-074.md) - Architectural Decision Record (10min)
   - Context, decision, consequences, alternatives
2. [02-dependency-graph.md](./02-dependency-graph.md) - Service mesh (10min)
   - Dependency graph (Mermaid), critical paths
3. [03-migration-patterns.md](./03-migration-patterns.md) - Technical strategy (10min)
   - Pattern A/B/C/D, rollback procedures

**Key Questions Answered:**
- Why deterministic naming? (Multi-cluster, governance, cost allocation)
- How to handle StatefulSets? (VolumeSnapshots, Pattern C)
- What are the alternatives? (Evaluated and rejected)
- How does this affect production? (Blueprint for future cluster)

---

### For Engineers Executing Migrations (2 hours)

**Start Here:**
1. [README.md](./README.md) - Getting Started Guide (15min)
   - Prerequisites, workflow, troubleshooting
2. [04-execution-plan.md](./04-execution-plan.md) - Detailed timeline (30min)
   - Wave execution, validation checklists, go/no-go checkpoints
3. [03-migration-patterns.md](./03-migration-patterns.md) - Migration strategy (20min)
   - Pattern selection, rollback procedures
4. [scripts/](./scripts/) - Review scripts (30min)
   - Understand each script's behavior before execution

**Key Questions Answered:**
- Which pattern for my namespace? (A/B/C/D decision matrix)
- How to execute migration? (Step-by-step scripts)
- When to rollback? (Rollback triggers)
- How to validate success? (Checklists per pattern)

---

### For SREs & On-Call Engineers (1 hour)

**Start Here:**
1. [05-risk-register.md](./05-risk-register.md) - Risk assessment (20min)
   - Risk matrix, mitigation strategies, rollback triggers
2. [04-execution-plan.md](./04-execution-plan.md) - Execution timeline (20min)
   - Wave schedule, critical paths, maintenance windows
3. [README.md](./README.md) - Troubleshooting section (20min)
   - Common issues, solutions, escalation paths

**Key Questions Answered:**
- What can go wrong? (17 namespaces × risk factors)
- When to rollback? (CrashLoopBackOff >5min, data loss, ESO fail)
- Who to escalate to? (On-call by wave, Slack channels)
- How to recover from disaster? (VolumeSnapshot restore, RDS rollback)

---

### For Compliance & Security (30 minutes)

**Start Here:**
1. [06-ADR-074.md](./06-ADR-074.md) - ADR (15min)
   - Compliance context (GAP-009), data residency (LGPD)
2. [05-risk-register.md](./05-risk-register.md) - Audit trail (15min)
   - Backup retention, SOC 2 compliance

**Key Questions Answered:**
- GAP-009 compliance? (100% after migration)
- Data residency? (LGPD: no PII, stays in us-east-1)
- Audit trail? (Migration logs, backup manifests, 14d retention)

---

## Document Summaries

### EXECUTIVE-SUMMARY.md (14KB, 3min read)

**Purpose:** Decision document for leadership approval.

**Key Sections:**
- TL;DR (60 seconds)
- Problem statement (why migrate?)
- Solution approach (5 waves, 7 days)
- Cost-benefit analysis ($67k/year benefit, $15.7k cost, 427% ROI)
- Risk assessment (1 CRITICAL, 4 HIGH, 4 MEDIUM, 7 LOW)
- Approval form (stakeholder sign-off)

**For:** Platform Lead, SRE Lead, Security Lead, FinOps Lead

---

### 01-namespace-mapping.md (6.5KB, 5min read)

**Purpose:** Complete mapping of old → new namespace names.

**Key Sections:**
- Namespace mapping table (17 rows)
- Domain classification (platform, data, observability, security, governance)
- Critical decisions (cicd-argocd deprecation, data-services consolidation)
- Suffix standardization (remove `-system`)
- Statistics (17 non-compliant, 94%)

**For:** All stakeholders (reference document)

---

### 02-dependency-graph.md (18KB, 15min read)

**Purpose:** Identify namespace dependencies for migration order.

**Key Sections:**
- Dependency graph (Mermaid diagram)
- Detailed dependency analysis (17 namespaces)
  - Ingress, service, data, operator dependencies
  - Risk assessment per namespace
  - Mitigation strategies
- Dependency waves (bottom-up migration order)
- Critical path analysis (Vault → ESO → Keycloak → GitLab)
- Total migration time (optimized: 24.5h)

**For:** Architects, SREs, migration planners

**Highlight:**
- Critical path: 200min (Vault is bottleneck)
- Parallel execution saves 40% time (60h → 24.5h)

---

### 03-migration-patterns.md (13KB, 20min read)

**Purpose:** Define reusable migration patterns with rollback procedures.

**Key Sections:**
- **Pattern A (Stateless):** 7 namespaces, <10min downtime, easy rollback
- **Pattern B (External RDS):** 2 namespaces, RDS switch only, 10-20min downtime
- **Pattern C (PVCs):** 5 namespaces, VolumeSnapshots, 30-120min downtime, HIGH RISK
- **Pattern D (Operator CRDs):** 2 namespaces, CR recreation, 15-30min downtime
- Special case: GitLab (50GB PVC, CRITICAL risk, 4h dedicated window)
- Decision matrix: Which pattern for which namespace?

**For:** Engineers executing migrations

**Highlight:**
- Pattern C (PVCs) requires VolumeSnapshots (HIGH RISK)
- GitLab requires maintenance window (Friday 18:00-22:00)

---

### 04-execution-plan.md (25KB, 30min read)

**Purpose:** Detailed timeline with validation checklists.

**Key Sections:**
- Wave 1: Foundation (6 namespaces, 3h parallelized)
- Wave 2: Operators (2 namespaces, 3h sequential)
- Wave 3: Security + Data (2 namespaces, 7h, Vault CRITICAL PATH)
- Wave 4: Platform Core (3 namespaces, 7h, Keycloak SSO)
- Wave 5: Platform Services (2 namespaces, 9h, Harbor + Monitoring)
- Wave 6: GitLab (1 namespace, 4h dedicated, CRITICAL)
- Total: 35h execution + 10% buffer = 40h (7 days)

**For:** Project managers, engineers, on-call

**Highlight:**
- Go/No-Go checkpoints after each wave
- GitLab pre-migration communication (1 week advance)
- Validation periods: 7d standard, 14d extended (CRITICAL)

---

### 05-risk-register.md (15KB, 20min read)

**Purpose:** Comprehensive risk assessment & mitigation.

**Key Sections:**
- Risk scoring matrix (data loss + downtime + rollback = max 15)
- Risk register (17 namespaces × risk factors)
- Detailed risk analysis (gitlab: 15/15, vault: 12/15, etc.)
- Risk mitigation summary (pre/during/post checklists)
- Rollback decision matrix (when to rollback?)
- Financial risk assessment (downtime cost: $2,500)
- Compliance audit (LGPD, SOC 2)

**For:** Risk managers, leadership, SREs

**Highlight:**
- GitLab: CRITICAL risk (50GB source code, score 15/15)
- Total financial risk: $15,700 (vs $67k/year benefit)

---

### 06-ADR-074.md (18KB, 30min read)

**Purpose:** Architectural Decision Record (formal documentation).

**Key Sections:**
- Context: GAP-009 Kyverno governance, 94% non-compliance
- Decision: Migrate all 17 namespaces to `{env}-{domain}-{product}`
- Consequences: Positive (compliance, clarity), Negative (effort, risk)
- Alternatives considered (4 alternatives evaluated and rejected)
- Implementation plan (5 phases)
- Success metrics (quantitative + qualitative)
- Approval section (stakeholder sign-off)

**For:** Architects, compliance, audit trail

**Highlight:**
- Alternatives rejected: Keep legacy (doesn't solve), Label-based (not immutable), Blue/green (2× cost), In-place rename (not feasible)

---

### README.md (16KB, 20min read)

**Purpose:** Getting Started Guide (entry point for engineers).

**Key Sections:**
- Quick links (navigator to all docs)
- Executive summary
- Migration overview
- Getting started (prerequisites, verification)
- Execution workflow (step-by-step)
- Troubleshooting (common issues + solutions)
- Communication templates (pre/during/post migration)
- Scripts reference
- Success criteria

**For:** All engineers (primary entry point)

**Highlight:**
- Troubleshooting section (VolumeSnapshot pending, CrashLoopBackOff, Ingress 502, ESO not syncing)
- Communication templates (Slack announcements)

---

### scripts/ Directory (4 scripts, 50KB total)

#### migrate-stateless.sh (9.3KB)
**Pattern A:** Stateless services (cert-manager, kyverno, operators)

**Features:**
- Helm values export
- Namespace creation with label preservation
- Deployment to new namespace
- Pod readiness validation
- Ingress check
- Backup for audit trail

**Usage:**
```bash
./migrate-stateless.sh <old-ns> <new-ns> <helm-release> <helm-chart>
```

---

#### migrate-stateful-pvc.sh (16KB)
**Pattern C:** StatefulSets + PVCs (gitlab, harbor, monitoring, vault)

**Features:**
- VolumeSnapshot creation (all PVCs)
- Parallel snapshot processing
- PVC restore from snapshots
- Helm deployment
- Data integrity validation (manual + automated)
- Extended logging

**Usage:**
```bash
./migrate-stateful-pvc.sh <old-ns> <new-ns> <helm-release> <helm-chart>
```

**Warning:** HIGH RISK - manual data validation required

---

#### migrate-operator-crd.sh (16KB)
**Pattern D:** Operator-managed CRDs (data-services, rabbitmq-system)

**Features:**
- CR export (Custom Resources)
- VolumeSnapshot (if PVCs exist)
- CR recreation in new namespace
- Operator reconciliation wait
- StatefulSet validation
- Application-specific validation (RabbitMQ queues, Redis keys)

**Usage:**
```bash
./migrate-operator-crd.sh <old-ns> <new-ns> <crd-kind> <cr-name>
```

---

#### rollback.sh (8.9KB)
**Universal rollback script (all patterns).**

**Features:**
- New namespace deletion
- Old namespace verification
- Service endpoint testing
- Snapshot cleanup (optional)
- Audit trail backup
- Post-rollback summary

**Usage:**
```bash
./rollback.sh <new-ns> <old-ns> [delete-snapshots]
```

**When to Use:**
- CrashLoopBackOff >5min
- Data integrity fail
- Ingress 502/503 >30min
- ExternalSecrets fail

---

## Deliverables Checklist

### Documentation (8 files)

- [x] README.md - Getting Started Guide
- [x] EXECUTIVE-SUMMARY.md - Decision document
- [x] 01-namespace-mapping.md - Mapping table
- [x] 02-dependency-graph.md - Dependency analysis
- [x] 03-migration-patterns.md - Technical patterns
- [x] 04-execution-plan.md - Detailed timeline
- [x] 05-risk-register.md - Risk assessment
- [x] 06-ADR-074.md - Architectural Decision Record

### Scripts (4 files)

- [x] migrate-stateless.sh (Pattern A)
- [x] migrate-stateful-pvc.sh (Pattern C)
- [x] migrate-operator-crd.sh (Pattern D)
- [x] rollback.sh (Universal)

### Validation

- [x] All scripts executable (`chmod +x`)
- [x] Total lines: 5,434
- [x] Total words: 16,490
- [x] Total size: 204KB
- [x] Cross-references validated
- [x] Mermaid diagrams valid

---

## Key Metrics Summary

### Documentation Coverage

| Aspect | Coverage | Status |
|--------|----------|--------|
| Namespace mapping | 17/17 (100%) | ✅ Complete |
| Dependency analysis | 17/17 (100%) | ✅ Complete |
| Migration patterns | 4/4 (100%) | ✅ Complete |
| Risk assessment | 17/17 (100%) | ✅ Complete |
| Execution scripts | 4/4 (100%) | ✅ Complete |
| Rollback procedures | 17/17 (100%) | ✅ Complete |

### Technical Specifications

| Metric | Value |
|--------|-------|
| Total namespaces | 17 (16 migrate + 1 deprecate) |
| Total PVCs | 17 PVCs, 170GB |
| Total execution time | 40h (24.5h optimized) |
| Total downtime | 9h (staged over 7 days) |
| Risk breakdown | 1 CRITICAL, 4 HIGH, 4 MEDIUM, 7 LOW |
| Success rate target | 95-100% (zero rollbacks) |

### Financial Metrics

| Metric | Value |
|--------|-------|
| One-time cost | $15,700 |
| Annual benefit | $67,000 |
| ROI | 427% (Year 1) |
| Payback period | 3 months |

---

## Migration Timeline Quick Reference

```
2026-02-24 (Mon): Final approvals + stakeholder notification
2026-02-25 (Tue): Wave 1 + 2 → 8 namespaces (LOW/MEDIUM)
2026-02-26 (Wed): Wave 3 → 2 namespaces (HIGH - Vault critical path)
2026-02-27 (Thu): Wave 4 → 3 namespaces (MEDIUM - SSO + GitOps)
2026-02-28 (Fri): Wave 5 + 6 → 3 namespaces (HIGH/CRITICAL - GitLab 18:00-22:00)
2026-03-05 (Wed): Cleanup → 1 namespace deprecation (cicd-argocd)
2026-03-15 (Wed): Enable Kyverno enforce mode → Compliance achieved
```

---

## Critical Success Factors

### Must Have (Non-Negotiable)

1. **VolumeSnapshots working:** Test before Wave 3 (Vault)
2. **RDS backups:** Manual snapshots before Pattern B/C migrations
3. **Vault specialist on-call:** Wave 3 (2026-02-26)
4. **GitLab SME on-call:** Wave 6 (2026-02-28 18:00-22:00)
5. **14-day retention:** GitLab, Vault, Harbor, Monitoring (HIGH/CRITICAL)

### Should Have (Highly Recommended)

1. **Pre-migration testing:** Validate Pattern C in argocd-test first
2. **Parallel execution:** 6 agents for Wave 1 (saves 60% time)
3. **Communication:** 1 week advance for GitLab downtime
4. **Monitoring:** Slack status updates every 2 hours

### Nice to Have (Optional)

1. **Real-time rsync:** Parallel GitLab PVC copy (backup to backup)
2. **Blue/green testing:** Small namespace first (test-governance)
3. **Post-mortem:** Lessons learned workshop (2026-03-15)

---

## Approval & Next Steps

### Stakeholder Approval Required

- [ ] **Platform Lead** - Decision authority
- [ ] **SRE Lead** - Technical review
- [ ] **Security Lead** - Compliance review
- [ ] **FinOps Lead** - Cost approval

### If Approved (GO Decision)

**Immediate Actions (2026-02-24):**
1. Notify stakeholders (Slack #announcements)
2. Confirm resource allocation (4 engineers × 4 days)
3. Test VolumeSnapshot in test namespace
4. Final script review with team

**Day Before (2026-02-24 Evening):**
1. Rollback drill (test rollback.sh)
2. Backup validation (verify VolumeSnapshotClass)
3. Team readiness check

**Execution (2026-02-25 09:00):**
1. Wave 1 kickoff (6 namespaces parallel)
2. Slack #platform-ops status updates
3. Go/No-Go checkpoints per wave

### If Rejected (NO-GO Decision)

**Document Rationale:**
- Why rejected? (e.g., timing, resources, risk)
- Alternative approach? (e.g., delay 1 week, reduce scope)
- Next review date?

---

## Document Maintenance

**Owner:** Platform Team
**Last Updated:** 2026-02-24
**Next Review:** Post-migration (2026-03-15)

**Update Triggers:**
- Migration pattern changes
- Risk assessment updates
- New namespace added to cluster
- Kyverno policy updates

**Version History:**
- v1.0 (2026-02-24): Initial complete documentation

---

## Related Documentation

**External References:**
- GAP-009 Kyverno Policy: `/domains/governance/policies/namespace-naming.yaml`
- VPA FASE 0 Baseline: `/docs/logbooks/2026-02-20-phase0-baseline-execution.md`
- GitLab Multi-Container Pattern: ADR-068
- RabbitMQ CRD Pattern: ADR-069

**Future Work:**
- Production cluster migration (Q2 2026)
- Terraform namespace module (deterministic naming)
- ArgoCD ApplicationSet (namespace templates)

---

**For questions or clarifications, contact:**
- Slack: #platform-ops
- Email: platform-team@company.com
- On-Call: PagerDuty (k8s-platform rotation)

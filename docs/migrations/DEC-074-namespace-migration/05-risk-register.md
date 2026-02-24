# DEC-074: Risk Register & Mitigation Matrix

**Purpose:** Comprehensive risk assessment for all 16 namespace migrations.

---

## Risk Scoring Matrix

| Score | Data Loss Risk | Downtime Impact | Rollback Complexity |
|-------|---------------|-----------------|---------------------|
| 1 | NONE (stateless) | LOW (<10min) | EASY (delete namespace) |
| 2 | LOW (cache, rebuildable) | MEDIUM (10-30min) | EASY (RDS connection switch) |
| 3 | MEDIUM (external backup) | HIGH (30-60min) | MEDIUM (PVC restore) |
| 4 | HIGH (PVC data) | HIGH (60-120min) | HARD (multi-PVC restore) |
| 5 | CRITICAL (source code, secrets) | CRITICAL (>120min) | VERY HARD (14d retention) |

**Total Risk Score:** Data Loss + Downtime + Rollback (max 15)

---

## Risk Register (17 Namespaces)

| # | Namespace | New Name | Pattern | Data Loss | Downtime | Rollback | Total | Risk Level |
|---|-----------|----------|---------|-----------|----------|----------|-------|-----------|
| 1 | gitlab-staging | staging-platform-gitlab | C | 5 | 5 | 5 | **15** | **CRITICAL** |
| 2 | vault-system | staging-security-vault | C | 4 | 4 | 4 | **12** | **HIGH** |
| 3 | data-services | staging-data-infrastructure | D | 4 | 4 | 3 | **11** | **HIGH** |
| 4 | harbor-system | staging-platform-harbor | C | 4 | 3 | 3 | **10** | **HIGH** |
| 5 | monitoring | staging-observability-monitoring | C | 3 | 4 | 4 | **11** | **HIGH** |
| 6 | keycloak | staging-platform-keycloak | B | 2 | 4 | 2 | **8** | **MEDIUM** |
| 7 | argocd | staging-platform-argocd | B | 2 | 3 | 2 | **7** | **MEDIUM** |
| 8 | sonarqube | staging-platform-sonarqube | C | 2 | 3 | 3 | **8** | **MEDIUM** |
| 9 | kyverno | staging-governance-kyverno | A | 1 | 4 | 1 | **6** | **MEDIUM** |
| 10 | rabbitmq-system | staging-data-rabbitmq | A | 1 | 3 | 2 | **6** | **MEDIUM** |
| 11 | cert-manager | staging-security-certmanager | A | 1 | 2 | 1 | **4** | **LOW** |
| 12 | external-secrets-system | staging-security-externalsecrets | A | 1 | 3 | 1 | **5** | **LOW** |
| 13 | redis-operator | staging-data-redis-operator | A | 1 | 2 | 1 | **4** | **LOW** |
| 14 | argocd-test | staging-platform-argocd-test | A | 1 | 1 | 1 | **3** | **LOW** |
| 15 | otel-test | staging-observability-otel-test | A | 1 | 1 | 1 | **3** | **LOW** |
| 16 | test-governance | staging-governance-test | A | 1 | 1 | 1 | **3** | **LOW** |
| 17 | cicd-argocd | **DEPRECATED** | N/A | 1 | 1 | 1 | **3** | **LOW** |

---

## Detailed Risk Analysis

### 1. gitlab-staging (CRITICAL - Score 15/15)

**Data Loss Risk: 5/5 (CRITICAL)**
- 50GB PVC: Git repository storage (`repo-data-gitlab-gitaly-0`)
- Contains source code for entire platform
- No alternative backup (Git repos not in external storage)
- **Impact:** Loss of all development history, MRs, CI artifacts

**Downtime Impact: 5/5 (CRITICAL)**
- Blocks all CI/CD pipelines (platform-wide impact)
- Developers cannot push/pull code
- 3 ingress endpoints: gitlab, registry, kas (Kubernetes Agent)
- **Estimated Downtime:** 90-120 minutes (50GB PVC restore)

**Rollback Complexity: 5/5 (VERY HARD)**
- 50GB PVC restore from snapshot
- RDS connection switch (external PostgreSQL)
- 3 ingress DNS cutover
- **Rollback Time:** 60-90 minutes

**Mitigation Strategy:**
1. **Maintenance Window:** Friday 18:00-22:00 (4h dedicated)
2. **Double Backup:**
   - VolumeSnapshot (50GB)
   - RDS manual snapshot
   - Real-time rsync pod (parallel copy during migration)
3. **Extended Retention:** 14 days (vs standard 7d)
4. **Pre-Migration Testing:** Test pattern in argocd-test namespace first
5. **Rollback Trigger:** Repository count mismatch, git clone fails
6. **Communication:** 1 week advance notice, Slack alerts

**Acceptance Criteria:**
- Git clone succeeds for test repository
- CI pipeline completes successfully
- Container registry push/pull works
- All repository count matches pre-migration

---

### 2. vault-system (HIGH - Score 12/15)

**Data Loss Risk: 4/5 (HIGH)**
- 10GB PVC: Encrypted secrets (`data-vault-0`)
- 5GB PVC: Audit logs (`audit-vault-0`)
- All platform secrets stored in Vault KV v2
- **Impact:** Loss of all secrets → platform-wide outage

**Downtime Impact: 4/4 (HIGH)**
- ESO fails → all ExternalSecrets desync
- 7 dependent namespaces (grafana, harbor, keycloak, gitlab, sonarqube, argocd)
- **Estimated Downtime:** 60 minutes (PVC restore + unseal)

**Rollback Complexity: 4/5 (HARD)**
- PVC restore from snapshot
- Vault unseal process (requires 3 key shards)
- ESO reconnection validation
- **Rollback Time:** 45 minutes

**Mitigation Strategy:**
1. **Pre-Migration Backup:**
   - Raft snapshot: `vault operator raft snapshot save`
   - Upload to S3: `s3://k8s-platform-backups/vault/`
   - VolumeSnapshot (15GB total)
2. **Unseal Keys:** Document and store securely (required post-migration)
3. **ESO Validation:** Test all 7 ExternalSecrets sync after migration
4. **Extended Retention:** 14 days
5. **Rollback Trigger:** Unseal fails, KV paths inaccessible, ESO fails

**Acceptance Criteria:**
- Vault unsealed (sealed=false)
- All 7 KV paths accessible
- All ExternalSecrets show SecretSynced=True
- Vault UI accessible

---

### 3. data-services (HIGH - Score 11/15)

**Data Loss Risk: 4/5 (HIGH)**
- 1GB PVC: Redis persistence (`redis-redis-0`)
- 5GB PVC: RabbitMQ persistence (`persistence-k8s-platform-prod-rabbitmq-server-0`)
- **Impact:** Redis cache rebuild (acceptable), RabbitMQ queue loss (critical)

**Downtime Impact: 4/5 (HIGH)**
- GitLab + Harbor degraded without Redis cache
- GitLab CI job queue in RabbitMQ
- **Estimated Downtime:** 45 minutes (CR recreation + PVC restore)

**Rollback Complexity: 3/5 (MEDIUM)**
- Operator-managed CRs (delete + recreate in old namespace)
- PVC restore from snapshots
- **Rollback Time:** 30 minutes

**Mitigation Strategy:**
1. **RabbitMQ Backup:** Export definitions (`rabbitmqadmin export`)
2. **Redis:** Acceptable data loss (cache rebuilds from source)
3. **Operator Validation:** Verify redis-operator + rabbitmq-system reconcile CRs in new namespace
4. **VolumeSnapshots:** Both PVCs (6GB total)
5. **Rollback Trigger:** RabbitMQ queues missing, Redis connection fails

**Acceptance Criteria:**
- Redis PING → PONG
- RabbitMQ management UI HTTP 200
- RabbitMQ queues/exchanges exist (count matches backup)
- GitLab + Harbor can connect to Redis

---

### 4. harbor-system (HIGH - Score 10/15)

**Data Loss Risk: 4/5 (HIGH)**
- 5GB PVC: OCI image blobs (`harbor-registry`)
- 1GB PVC: Job service cache (`harbor-jobservice`)
- External RDS: Image metadata (Harbor database)
- **Impact:** Container images lost → CI/CD cannot pull images

**Downtime Impact: 3/5 (MEDIUM)**
- CI pipelines fail without image pulls
- **Estimated Downtime:** 60 minutes (PVC restore)

**Rollback Complexity: 3/5 (MEDIUM)**
- PVC restore from snapshots
- RDS connection switch
- **Rollback Time:** 30 minutes

**Mitigation Strategy:**
1. **VolumeSnapshots:** Both PVCs (6GB total)
2. **RDS Backup:** Manual snapshot (Harbor metadata)
3. **Image Validation:** Test `docker pull harbor.staging.internal/library/nginx`
4. **Rollback Trigger:** Image pull fails, image count mismatch

**Acceptance Criteria:**
- Docker pull succeeds for test image
- Harbor UI accessible
- OIDC login works (Keycloak SSO)
- Image count matches pre-migration

---

### 5. monitoring (HIGH - Score 11/15)

**Data Loss Risk: 3/5 (MEDIUM)**
- 9 PVCs (94GB total):
  - Prometheus: 20GB (metrics TSDB)
  - Grafana: 5GB (dashboards)
  - Loki: 40GB (logs, 4×10GB)
  - Tempo: 20GB (traces, 2×10GB)
  - Alertmanager: 2GB
- Metrics/logs can rebuild (30d retention)
- **Impact:** Monitoring gap during migration (acceptable)

**Downtime Impact: 4/5 (HIGH)**
- No monitoring during migration → blind operations
- **Estimated Downtime:** 90 minutes (9 PVCs, 94GB)

**Rollback Complexity: 4/5 (HARD)**
- 9 PVC restore from snapshots
- Multiple StatefulSets (Prometheus, Loki, Tempo, Grafana, Alertmanager)
- **Rollback Time:** 60 minutes

**Mitigation Strategy:**
1. **VolumeSnapshots:** All 9 PVCs (parallel snapshot creation)
2. **Acceptable Metrics Gap:** Prometheus rebuilds from targets post-migration
3. **Grafana Backup:** Export dashboards via API
4. **Migration Window:** Sunday morning (low traffic)
5. **Priority Order:** Prometheus → Grafana → Loki → Tempo

**Acceptance Criteria:**
- All pods Running (may take 30min for large PVCs)
- Prometheus scraping targets (no DOWN targets)
- Grafana dashboards rendered
- OIDC login works (Keycloak SSO)
- Loki + Tempo ingesting new data

---

### 6. keycloak (MEDIUM - Score 8/15)

**Data Loss Risk: 2/5 (LOW)**
- No PVCs (stateless pods)
- All data in external RDS (PostgreSQL)
- **Impact:** Zero data loss (RDS switch only)

**Downtime Impact: 4/5 (HIGH)**
- All SSO logins fail during migration
- 5 dependent services: Grafana, ArgoCD, Harbor, GitLab, SonarQube
- **Estimated Downtime:** 15-20 minutes (DNS propagation)

**Rollback Complexity: 2/5 (EASY)**
- Delete new namespace, old namespace operational
- **Rollback Time:** 5 minutes

**Mitigation Strategy:**
1. **RDS Backup:** Manual snapshot (Keycloak database)
2. **Short Maintenance Window:** 15min target
3. **OIDC Validation:** Test all 5 SSO clients post-migration
4. **Rollback Trigger:** OIDC endpoint unreachable, SSO login fails

**Acceptance Criteria:**
- Keycloak UI accessible
- OIDC endpoint responds: `/.well-known/openid-configuration`
- All 5 SSO clients login successfully
- SAML 2.0 works (SonarQube)

---

### 7-10. MEDIUM Risk Namespaces (Score 6-8)

**argocd** (Score 7):
- Stateless (external RDS)
- No PVCs
- Export applications before migration
- Pause auto-sync during migration

**sonarqube** (Score 8):
- 20GB PVC (plugins + cache)
- External RDS (analysis data)
- VolumeSnapshot required
- SAML validation (Keycloak SSO)

**kyverno** (Score 6):
- Stateless admission controller
- High downtime impact (webhook failures)
- Export ClusterPolicies
- Short migration window (<15min)

**rabbitmq-system** (Score 6):
- Stateless operator
- Manages CRs in data-services
- Operator watches all namespaces (cluster-scoped)

---

### 11-16. LOW Risk Namespaces (Score 3-5)

**cert-manager, external-secrets-system, redis-operator:**
- Stateless operators
- Short downtime (<10min)
- Easy rollback (delete namespace)

**argocd-test, otel-test, test-governance:**
- Testing namespaces
- No production traffic
- Zero impact on platform
- Pattern validation (test migrations first)

---

## Risk Mitigation Summary

### Pre-Migration Checklist (ALL Namespaces)

**24 Hours Before:**
- [ ] Notify stakeholders (Slack #platform-ops)
- [ ] Review rollback procedures
- [ ] Verify backup/snapshot tools available
- [ ] Document current state (pod count, PVC sizes, ingress)

**1 Hour Before:**
- [ ] Backup RDS databases (if applicable)
- [ ] Export Helm values
- [ ] Export manifests (`kubectl get all -o yaml`)
- [ ] Create VolumeSnapshots (Pattern C only)

### During Migration

**Pattern A (Stateless):**
- [ ] No snapshots needed
- [ ] Deploy to new namespace
- [ ] Validate pods Running
- [ ] Test ingress (if applicable)

**Pattern B (External RDS):**
- [ ] RDS backup (manual snapshot)
- [ ] No PVC migration
- [ ] Deploy to new namespace
- [ ] Validate RDS connection
- [ ] Test ingress + SSO

**Pattern C (PVCs):**
- [ ] VolumeSnapshots (all PVCs)
- [ ] Wait for snapshots readyToUse
- [ ] Restore PVCs in new namespace
- [ ] Deploy Helm chart
- [ ] Validate data integrity
- [ ] Test ingress

**Pattern D (Operator CRs):**
- [ ] Export CR definition
- [ ] VolumeSnapshots (if PVCs exist)
- [ ] Recreate CR in new namespace
- [ ] Wait for operator reconciliation
- [ ] Validate CR status

### Rollback Decision Matrix

| Condition | Action | Priority |
|-----------|--------|----------|
| All pods Running + Data validated | **PROCEED** (migration success) | - |
| CrashLoopBackOff (1 pod, <5min) | **WAIT** (investigate logs) | Medium |
| CrashLoopBackOff (>5min) | **ROLLBACK** (pattern issue) | High |
| Data integrity fail | **ROLLBACK** (critical) | Critical |
| Ingress 502/503 (<10min DNS) | **WAIT** (DNS propagation) | Low |
| Ingress 502/503 (>30min) | **ROLLBACK** (routing issue) | High |
| ESO SecretSynced=False | **ROLLBACK** (Vault connection) | Critical |

### Post-Migration Validation

**Immediate (0-1h):**
- [ ] All pods Running
- [ ] PVCs Bound (if applicable)
- [ ] Ingress HTTP 200
- [ ] Logs show no errors

**24 Hours:**
- [ ] Monitor Prometheus alerts (zero new alerts)
- [ ] Grafana dashboards show normal metrics
- [ ] User reports (zero incidents)

**7 Days (Standard Retention):**
- [ ] Zero rollbacks needed
- [ ] Application functionality validated
- [ ] Delete old namespace (LOW/MEDIUM risk only)

**14 Days (Extended Retention):**
- [ ] HIGH/CRITICAL risk namespaces validated
- [ ] Delete old namespace
- [ ] Delete VolumeSnapshots (cost optimization)

---

## Aggregate Risk Metrics

| Risk Level | Namespace Count | % Total | ETA |
|-----------|-----------------|---------|-----|
| CRITICAL | 1 | 6% | 4h |
| HIGH | 4 | 25% | 18h |
| MEDIUM | 4 | 25% | 10h |
| LOW | 7 | 44% | 8h |
| **TOTAL** | **16** | **100%** | **40h** |

**Optimized with Parallelization:** 24.5h (7 working days)

---

## Financial Risk Assessment

### Cost of Downtime (Staging Environment)

**Assumptions:**
- Staging = development/testing environment
- Developer hourly cost: $50/hour
- Team size: 10 developers
- Blocked hours = downtime per namespace

| Namespace | Downtime | Dev Hours Lost | Cost Impact |
|-----------|----------|----------------|-------------|
| gitlab-staging | 2h | 20h | $1,000 |
| keycloak | 0.5h | 5h | $250 |
| monitoring | 1.5h | 15h (partial) | $750 |
| Others | 5h total | 10h | $500 |
| **TOTAL** | **9h** | **50h** | **$2,500** |

**Mitigation:** Schedule migrations during low-traffic windows (Friday evenings, weekends)

### Cost of Migration Failure (Rollback)

**Assumptions:**
- Rollback time = 50% of migration time
- Retry migration = 100% of original time
- Total cost = 1.5× migration cost

**Worst Case (GitLab Rollback):**
- Migration: 4h
- Rollback: 2h
- Retry: 4h
- Total: 10h downtime
- Cost: 10h × 10 devs × $50 = **$5,000**

**Risk Mitigation ROI:**
- Pre-migration testing: 2h × $500 = $1,000 cost
- Prevents rollback: $5,000 - $1,000 = **$4,000 saved**
- ROI: 400%

---

## Compliance & Audit

### Data Residency (LGPD)

**All namespaces labeled:**
- `DataClassification=Internal`
- `LGPD=Synthetic` (no PII in staging)

**Migration Impact:** Zero (data stays in us-east-1, same region)

### Backup Retention (SOC 2)

**VolumeSnapshots:**
- Standard: 7 days
- Extended: 14 days (CRITICAL namespaces)
- Long-term: 30 days (RDS backups)

**Audit Trail:**
- Migration logs: `migration-*.log`
- Backup manifests: `backup-*/`
- Rollback logs: `rollback-*.log`

---

## Next: Review ADR-074
→ `/06-ADR-074.md`

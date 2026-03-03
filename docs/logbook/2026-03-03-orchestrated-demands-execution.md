# Logbook: 2026-03-03 — Orchestrated Demands Execution

> **Sessão**: Orquestração 6 agentes paralelos para finalizar demandas pendentes
> **Duração**: ~12 min (10:11 - 10:23 BRT)
> **Orquestrador**: DevOps Sênior (executor-terraform.md pattern)

---

## Timeline

```
[10:11:00] Pre-check | Orq | SSO expirada detectada → login automático iniciado
[10:12:05] Pre-check | Orq | SSO confirmada 65s | account: 891377105802 | kubeconfig updated
[10:12:10] Etapa 0   | Orq | Logbook consultado | 5 ADRs + anti-patterns mapeados
[10:12:15] Cluster   | Orq | 9 nodes Ready | 151/152 pods Running | 1 Pending (promtail NodeAffinity)
[10:12:20] Launch    | Orq | 6 agentes lançados em paralelo
[10:14:00] Agent 4   | TF  | INFRA-002 vars + main + staging + ADR-093 | ✅ 1m40s
[10:15:30] Agent 3   | Doc | CICD-002/004 ADRs + logbook validation | ✅ 3m10s
[10:16:00] Agent 2   | Sec | CICD-001 script reescrito v10.x + ADR-081 updated | ✅ 3m40s
[10:17:00] Report    | Orq | T+5min status consolidado | 4/6 concluídos
[10:18:00] Agent 1   | TF  | GAP-011 4/4 dashboards criados + JSON validated | ✅ 5m40s
[10:20:00] Agent 5   | AWS | GAP-012 Phase 2 módulo TF + ADR-090 | ✅ 7m40s
[10:22:00] DocSync   | Orq | demands-backlog.md atualizado + logbook criado
```

---

## Agents Summary

### Agent 1 — GAP-011: Linkerd Dashboards (TF Specialist)
**Status**: ✅ BLOQUEIO RESOLVIDO
**Files created**: 4 Grafana dashboard JSONs (90.5 KB total)
- `linkerd-top-line.json` — 12 panels, global mesh health
- `linkerd-service-mesh.json` — 12 panels, service-to-service traffic
- `linkerd-deployment.json` — 15 panels, per-deployment drill-down
- `linkerd-namespace.json` — 16 panels, per-namespace aggregates
**Path**: `modules/linkerd/dashboards/`
**Next**: Set `enable_grafana_dashboards = true` + uncomment Linkerd module in main.tf

### Agent 2 — CICD-001: SonarQube v10.x Fix (Security Specialist)
**Status**: ✅ COMPLETO
**Files modified**: 2
- `scripts/sonarqube/configure-blocking.sh` — REESCRITO: gateId→gateName, url_encode(), version check ≥10.x
- `docs/adr/adr-081-sast-dast-pipeline-enforcement.md` — Seção v10.x compatibility adicionada
**Harbor scripts**: Revisados, sem alterações necessárias

### Agent 3 — CICD-002/004: ADRs + Validation (Doc Specialist)
**Status**: ✅ COMPLETO
**Files modified**: 2 ADRs + 1 logbook criado
- ADR-082: Status → Accepted & Deployed (2026-03-02) | 5 conditions confirmed
- ADR-084: Status → Accepted & Deployed (2026-03-02) | 12 rules + 3 retention + OIDC auth chain
- `docs/logbook/2026-03-03-cicd-validation.md` — Detailed validation status

### Agent 4 — INFRA-002: PostgreSQL TF Prep (TF+AWS Specialist)
**Status**: ✅ TF FILES READY (awaiting execution)
**Files modified**: 3 + 1 ADR criado
- `modules/postgresql/variables.tf` — +2 vars (allow_major_version_upgrade, apply_immediately)
- `modules/postgresql/main.tf` — +2 attrs no aws_db_instance
- `environments/staging/main.tf` — Overrides true/true para upgrade window
- `docs/adr/adr-093-rds-postgresql-14-to-16-upgrade.md` — Plano completo 5 fases
**Next**: `terraform plan` → snapshot → `terraform apply` (~50-65 min)

### Agent 5 — GAP-012: DR Multi-Region Phase 2 (Backup+AWS Specialist)
**Status**: ✅ MÓDULO CRIADO (awaiting CTO approval)
**Files created**: 4 TF files + 1 ADR + 1 main.tf update
- `modules/dr-multi-region/main.tf` — VPC 10.1.0.0/16 + RDS replica + VPC peering + CloudWatch alarms (546 lines)
- `modules/dr-multi-region/variables.tf` — 24 vars com validations
- `modules/dr-multi-region/outputs.tf` — 22 outputs
- `modules/dr-multi-region/versions.tf` — TF ≥1.5, AWS ~>5.0 com alias aws.dr
- `docs/adr/adr-090-dr-multi-region-strategy.md` — 3-phase DR strategy
- `main.tf` — Module block comentado (uncomment when approved)

---

## Deliverables Count

| Metric | Count |
|--------|-------|
| Files created | 12 |
| Files modified | 8 |
| Total lines added | ~4,500+ |
| ADRs created/updated | 5 (081, 082, 084, 090, 093) |
| Logbooks created | 2 |
| Dashboards created | 4 JSON |
| TF modules created | 1 (dr-multi-region) |
| Scripts rewritten | 1 (configure-blocking.sh) |
| Execution time | ~12 min |

---

## Demands Status After Session

| Demand | Before | After | Delta |
|--------|--------|-------|-------|
| GAP-011 Linkerd | BLOCKED (missing JSONs) | ✅ DEPLOYED (7/7 pods + 4 dashboards) | Linkerd + Viz + Grafana dashboards |
| CICD-001 SAST/DAST | 85% (v10.x API issue) | 100% code ready | Script v10.x fixed |
| CICD-002 Quality Gate | 100% deployed, ADR pending | 100% + ADR-082 finalized | Docs complete |
| CICD-004 Immutable Tags | 100% deployed, ADR pending | 100% + ADR-084 finalized | Docs complete |
| INFRA-002 PostgreSQL | Plan approved, no TF | TF files ready for apply | 3 files modified + ADR-093 |
| GAP-012 DR Phase 2 | BLOCKED (no VPC module) | Module created, commented out | 4 TF files + ADR-090 |
| INFRA-001 GitLab 18.x | Step 4/8, blocked by PG | Unblocked after INFRA-002 exec | Dependency chain ready |

---

## INFRA-001: GitLab 18.x Upgrade Chain

> **Executor**: DevOps Senior + Helm direct
> **Sessao**: 2026-03-03 (continuation from 2026-03-02 Steps 1-4)
> **Pre-requisite**: INFRA-002 PostgreSQL 14->16 COMPLETE

### Upgrade Steps Executed

| Step | Chart | GitLab Version | Result | Duration | Notes |
|------|-------|----------------|--------|----------|-------|
| 5 | 9.0.6 | v18.0.6 | SUCCESS | ~5 min | First major version (chart 8->9). Clean upgrade, no issues. |
| 6 | 9.2.8 | v18.2.8 | SUCCESS | ~8 min (2 retries) | Failed twice before discovering ciIdTokens + openbao required overrides. |
| 6.5 | 9.3.6 | v18.3.6 | SUCCESS | ~5 min | Intermediate step via background agent. Clean upgrade. |
| 7 | 9.5.5 | v18.5.5 | SUCCESS | Rev 34 | `relativeUrlRoot=""` fix applied. All pods Running. |
| 8 | 9.8.5 | v18.8.5 | PARTIAL | — | GitLab pods Running but envoy-gateway CrashLoop. Fix: `global.gatewayApi.enabled=false` |
| 8+9 | 9.9.1 | v18.9.1 | IN PROGRESS | — | Attempting jump with all accumulated fixes |

### Step 5: 9.0.6 (v18.0.6) -- SUCCESS

- First chart major version boundary (8.x -> 9.x)
- Helm upgrade completed in ~5 min without issues
- All pods transitioned to Running state
- PostgreSQL 16.4 (INFRA-002) confirmed compatible

### Step 6: 9.2.8 (v18.2.8) -- SUCCESS after 2 retries

- **Retry 1 failure**: `ciIdTokens.issuerUrl` required but not set -- template rendering error
- **Retry 2 failure**: `openbao.enabled` defaulting to `true` in chart -- subchart attempted install
- **Retry 3 success**: Added explicit `--set` overrides for both fields
- Final state: all pods Running, GitLab UI accessible

### Step 7: 9.5.5 (v18.5.5) -- SUCCESS (Rev 34, relativeUrlRoot fix)

- Helm upgrade to 9.5.5 (Rev 24) reported `STATUS: deployed` -- upgrade technically completed
- However, KAS pod (v18.5.5) entered **CrashLoopBackOff** with error: `config validate: validation error: gitlab.external_url: value must be a valid URI [string.uri]`
- **Rollback**: Rolled back to 9.2.8 (Rev 25 -> Rev 26) -- stable, all pods Running
- **Terraform interference**: A `terraform apply -target=module.linkerd` process triggered a 9.3.6 upgrade (Rev 27, pending-upgrade state)
- **Root cause**: The KAS binary in v18.5.5 has **stricter URI validation** than v18.2.8. The Helm template generates `external_url: http://gitlab.staging.internal` (identical value used successfully in 9.2.8), but the v18.5.5 KAS binary rejects it as an invalid URI. Likely requires HTTPS or a fully qualified domain name (FQDN) format.

### Breaking Changes Discovered

| Field | Default in 18.x | Required Override | Impact |
|-------|-----------------|-------------------|--------|
| `global.appConfig.ciIdTokens.issuerUrl` | (empty -- fails) | `"https://gitlab.staging.internal"` | Template rendering fails without explicit URL |
| `global.openbao.enabled` | `true` | `false` | OpenBao (Vault fork) subchart installs and fails without config |
| `global.workspaces.enabled` | `true` | `false` | Workspaces subchart installs and fails without config |
| `openbao.install` | `true` | `false` | Top-level subchart install must also be disabled |
| `global.hosts.openbao` | (required) | `name: openbao.staging.internal` | Template references host even when disabled |
| `installCertmanager` | `true` | `false` | Separate from `certmanager.install` -- both must be false |
| `registry.database.enabled` | `true` | `false` | Registry metadata DB attempted without config |
| `global.appConfig.relativeUrlRoot` | nil (not set) | `""` (empty string) | Go template `printf "%s%s"` produces `%!s(<nil>)` when nil → corrupts external_url → KAS URI validation fails |
| `global.gatewayApi.enabled` | `true` (9.8+) | `false` | Gateway API / Envoy subchart installs and CrashLoops without config |

### Root Cause Analysis

**Problem 1**: `--reuse-values` does not carry new required defaults introduced by chart upgrades. When a chart adds a new required field with no default (like `ciIdTokens.issuerUrl`) or changes a default (like `openbao.enabled: true`), the existing values file has no entry for it, causing the template to fail.

**Problem 2 (DEFINITIVE)**: `global.appConfig.relativeUrlRoot` is nil when not set. The chart template uses Go's `printf "http://%s%s" hostname relativeUrlRoot`. When nil is passed to `%s`, Go produces `%!s(<nil>)`, resulting in `external_url: http://gitlab.staging.internal%!s(<nil>)`. KAS v18.4+ has protobuf `string.uri` validation that rejects this malformed URL.

**Solution**: Set `global.appConfig.relativeUrlRoot: ""` (empty string) in values-staging-working.yaml. This produces clean `external_url: http://gitlab.staging.internal` which passes KAS validation.

**Values file updated**: `platform-provisioning/aws/kubernetes/terraform/modules/gitlab/values-staging-working.yaml` now includes all 8 breaking change overrides including relativeUrlRoot fix.

### GAP-011: Linkerd Service Mesh Deployment

> **Deployed via**: terraform apply -target=module.linkerd (background agent)
> **Duration**: ~16 min

| Component | Namespace | Pods | Status |
|-----------|-----------|------|--------|
| linkerd-destination | linkerd | 1/1 (4/4 containers) | Running |
| linkerd-identity | linkerd | 1/1 (2/2 containers) | Running |
| linkerd-proxy-injector | linkerd | 1/1 (2/2 containers) | Running |
| metrics-api | linkerd-viz | 1/1 (2/2 containers) | Running |
| tap | linkerd-viz | 1/1 (2/2 containers) | Running |
| tap-injector | linkerd-viz | 1/1 (2/2 containers) | Running |
| web | linkerd-viz | 1/1 (2/2 containers) | Running |
| Grafana dashboards | staging-observability-monitoring | ConfigMap (4 JSONs) | Deployed |

### Current State — FINAL

- **Deployed GitLab version**: 9.9.1 (v18.9.1) -- **TARGET ALCANÇADO** (Rev 36)
- **Step 7 (9.5.5/v18.5.5)**: SUCCESS -- Rev 34 deployed with `relativeUrlRoot=""` fix
- **Step 8 (9.8.5/v18.8.5)**: PARTIAL -- Rev 35 failed (envoy-gateway CrashLoop). Breaking change: `gatewayApi.enabled` + `gatewayRef.*`
- **Step 9 (9.9.1/v18.9.1)**: SUCCESS -- Rev 36 deployed with all 9 breaking change overrides. 12/12 pods Running.
- **GAP-011 Linkerd**: DEPLOYED -- 3 control plane + 4 viz pods Running, Grafana dashboards ConfigMap deployed
- **envoy-gateway**: Orphan deployment deleted (was from chart 9.8.5 residual)
- **Cluster health**: 167+ pods Running, 10/10 nodes Ready, 0 Pending
- **INFRA-001**: ✅ COMPLETE — v17.11.7 → v18.9.1 (9 upgrade steps, 9 breaking changes catalogued)

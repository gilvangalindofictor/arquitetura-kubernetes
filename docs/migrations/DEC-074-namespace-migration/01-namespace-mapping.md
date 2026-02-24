# DEC-074: Namespace Mapping Table

**Migration Date:** 2026-02-24
**Target Completion:** 2026-03-05 (7.5 working days)
**Total Namespaces:** 17 (100% non-compliant with GAP-009 Kyverno pattern)

---

## Namespace Mapping: Current → New

| Current Name | New Name | Domain | Product | Rationale | Risk Level |
|--------------|----------|--------|---------|-----------|-----------|
| argocd | staging-platform-argocd | platform | argocd | Primary GitOps controller for cluster | MEDIUM |
| argocd-test | staging-platform-argocd-test | platform | argocd-test | Testing ArgoCD instance for validation | LOW |
| cert-manager | staging-security-certmanager | security | certmanager | TLS certificate management (Let's Encrypt) | LOW |
| cicd-argocd | **DEPRECATED** | - | - | Duplicate ArgoCD instance (linkerd injection), merge into argocd | N/A |
| data-services | staging-data-infrastructure | data | infrastructure | PostgreSQL RDS connections, Redis, RabbitMQ | HIGH |
| external-secrets-system | staging-security-externalsecrets | security | externalsecrets | External Secrets Operator (Vault integration) | LOW |
| gitlab-staging | staging-platform-gitlab | platform | gitlab | Source code hosting + CI/CD pipelines | CRITICAL |
| harbor-system | staging-platform-harbor | platform | harbor | Container image registry (OCI storage) | HIGH |
| keycloak | staging-platform-keycloak | platform | keycloak | SSO Identity Provider (OIDC/SAML) | HIGH |
| kyverno | staging-governance-kyverno | governance | kyverno | Policy engine (admission controller) | MEDIUM |
| monitoring | staging-observability-monitoring | observability | monitoring | Prometheus, Grafana, Loki, Tempo stack | HIGH |
| otel-test | staging-observability-otel-test | observability | otel-test | OpenTelemetry Collector testing | LOW |
| rabbitmq-system | staging-data-rabbitmq | data | rabbitmq | RabbitMQ Cluster Operator + CR | MEDIUM |
| redis-operator | staging-data-redis-operator | data | redis-operator | Redis Operator + CR | LOW |
| sonarqube | staging-platform-sonarqube | platform | sonarqube | Code quality analysis (SAST) | MEDIUM |
| test-governance | staging-governance-test | governance | test | Kyverno policy testing namespace | LOW |
| vault-system | staging-security-vault | security | vault | HashiCorp Vault (secrets backend) | HIGH |

---

## Critical Decisions

### Decision 1: cicd-argocd Deprecation
**Problem:** Two ArgoCD namespaces exist (`argocd` + `cicd-argocd`)

**Analysis:**
- `argocd`: Primary instance (17d age, 8 pods, ingress active)
- `cicd-argocd`: Test instance (3d22h age, linkerd.io/inject=enabled)

**Decision:**
- **DEPRECATE** `cicd-argocd`
- Keep only `staging-platform-argocd` (migrated from `argocd`)
- Export `cicd-argocd` applications → import to `staging-platform-argocd` before deletion

**Rationale:**
- Duplicate GitOps controllers cause split-brain issues
- ArgoCD ApplicationSets can manage multiple environments from single instance
- Linkerd injection can be enabled on primary instance if needed

---

### Decision 2: data-services Namespace Consolidation
**Problem:** `data-services` contains 3 heterogeneous services (PostgreSQL RDS connections, Redis, RabbitMQ)

**Options:**
- **A)** Split into 3 namespaces: `staging-data-postgresql`, `staging-data-redis`, `staging-data-rabbitmq`
- **B)** Keep consolidated: `staging-data-infrastructure`

**Decision:** **Option B** (Keep consolidated as `staging-data-infrastructure`)

**Rationale:**
- All 3 services share common RBAC policies (DataClassification=Internal, LGPD=Synthetic)
- GitLab + Harbor consume all 3 services → reduces cross-namespace NetworkPolicy complexity
- Splitting would require 9 ExternalSecrets (3 services × 3 namespaces) vs current 3
- FinOps labels already applied at namespace level (CostCenter, Environment, Marco)
- Operator watches (RabbitMQ, Redis) are cluster-scoped → namespace location irrelevant

**Trade-off:**
- Less granular RBAC (all services share namespace permissions)
- Acceptable for staging environment (production may split later)

---

### Decision 3: Suffix Standardization (-system)
**Current state:** Inconsistent suffixes (`-system`, `-staging`, none)

**Decision:** **Remove all suffixes**, use only `{env}-{domain}-{product}`

**Examples:**
- `harbor-system` → `staging-platform-harbor` (not `staging-platform-harbor-system`)
- `vault-system` → `staging-security-vault`
- `rabbitmq-system` → `staging-data-rabbitmq`

**Rationale:**
- GAP-009 Kyverno pattern is `{env}-{domain}-{product}` (no suffix)
- `-system` suffix is Kubernetes convention (kube-system), not application-level
- Simplifies naming convention (less cognitive load)

---

## Domain Classification

### Platform (7 namespaces)
Core platform services consumed by developers:
- ArgoCD (GitOps), GitLab (SCM/CI), Harbor (Registry), Keycloak (SSO), SonarQube (SAST)
- **ArgoCD Test** (isolated testing instance)

### Data (3 namespaces)
Data layer services:
- Infrastructure (PostgreSQL RDS, Redis, RabbitMQ), RabbitMQ Operator, Redis Operator

### Observability (2 namespaces)
Monitoring + distributed tracing:
- Monitoring (Prometheus, Grafana, Loki, Tempo), OpenTelemetry Test

### Security (3 namespaces)
Security infrastructure:
- Cert-Manager (TLS), External Secrets (Vault sync), Vault (secrets backend)

### Governance (2 namespaces)
Policy enforcement:
- Kyverno (admission controller), Test (policy validation)

---

## Statistics

| Metric | Count |
|--------|-------|
| Total namespaces analyzed | 22 |
| System namespaces (excluded) | 4 (kube-system, kube-public, kube-node-lease, default) |
| Compliant namespaces | 1 (staging-integration-test) |
| **Non-compliant namespaces** | **17** |
| Namespaces to deprecate | 1 (cicd-argocd) |
| **Namespaces to migrate** | **16** |
| Domains | 5 (platform, data, observability, security, governance) |

---

## Migration Priority Matrix

| Priority | Risk Level | Namespace Count | Examples |
|----------|-----------|-----------------|----------|
| P4 (Last) | CRITICAL | 1 | gitlab-staging (10 PVCs, 50GB gitaly, source code) |
| P3 | HIGH | 4 | data-infrastructure, harbor, keycloak, monitoring |
| P2 | MEDIUM | 4 | argocd, kyverno, rabbitmq, sonarqube |
| P1 (First) | LOW | 7 | cert-manager, argocd-test, otel-test, test-governance, etc |

**Execution order:** P1 → P2 → P3 → P4 (low risk first, validate pattern)

---

## Next Steps

1. Review dependency graph: `/02-dependency-graph.md`
2. Select migration patterns: `/03-migration-patterns.md`
3. Review execution plan: `/04-execution-plan.md`
4. Validate scripts: `/scripts/`

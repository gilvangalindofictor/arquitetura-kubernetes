# ADR-046: Keycloak SSO Platform Strategy

**Status**: ✅ Aceito e Implementado
**Date**: 2026-02-06
**Decision Makers**: Platform Team
**Context**: Marco 4 - CI/CD Platform Integration

---

## Context

A plataforma Kubernetes precisa de uma solução centralizada de autenticação e autorização (SSO/OIDC) para integrar múltiplas ferramentas da plataforma:

- **ArgoCD** - GitOps deployment
- **SonarQube** - Code quality analysis
- **GitLab** - SCM e CI/CD
- **Grafana** - Observability dashboards

**Requisitos**:

- Single Sign-On (SSO) centralizado
- Protocolo OIDC (OpenID Connect)
- Gerenciamento de grupos/roles
- High Availability
- Integração com PostgreSQL RDS existente
- Secrets management via Vault

**Alternativas Consideradas**:

1. **Keycloak** (escolhida)
2. Dex (CNCF)
3. Auth0 (SaaS)
4. Okta (SaaS)
5. AWS Cognito

---

## Decision

**Escolhemos Keycloak** como plataforma SSO centralizada.

### Justificativa

**Vantagens**:

- ✅ Open-source e self-hosted (sem vendor lock-in)
- ✅ OIDC/SAML compliant (protocolo padrão)
- ✅ Suporte a múltiplos realms e identity providers
- ✅ UI administrativa completa
- ✅ Integração PostgreSQL nativa
- ✅ High Availability via StatefulSet
- ✅ Comunidade ativa e documentação extensa
- ✅ Custo: ~$35/mês (infra) vs $1.200+/mês (SaaS)

**Comparação com Alternativas**:

| Critério | Keycloak | Dex | Auth0/Okta | AWS Cognito |
|----------|----------|-----|------------|-------------|
| OIDC Support | ✅ Full | ✅ Full | ✅ Full | ✅ Full |
| Self-hosted | ✅ Yes | ✅ Yes | ❌ No | ❌ No |
| Admin UI | ✅ Rich | ❌ CLI only | ✅ Rich | ✅ Basic |
| Multi-realm | ✅ Yes | ❌ No | ✅ Yes | ❌ No |
| PostgreSQL | ✅ Native | ❌ No DB | N/A | N/A |
| Cost | $35/mês | $15/mês | $1200+/mês | $500+/mês |
| Complexity | Medium | Low | Low | Medium |

**Por que NÃO Dex**:

- Sem UI administrativa (configuração via YAML/CLI)
- Não persiste dados (stateless - requer external storage)
- Menos features de gerenciamento de usuários

**Por que NÃO SaaS (Auth0/Okta)**:

- Custo proibitivo: $100-150/usuário/mês
- Vendor lock-in
- Latência (external service)

**Por que NÃO AWS Cognito**:

- Vendor lock-in (cloud-specific)
- Limitado a 1 realm
- UI/UX inferior
- Custo escala rapidamente

---

## Implementation

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Applications (OIDC Clients)                            │
│  • ArgoCD                                               │
│  • SonarQube                                            │
│  • GitLab                                               │
│  • Grafana                                              │
└────────────────────┬────────────────────────────────────┘
                     │ OIDC Authorization Code Flow
                     ▼
┌─────────────────────────────────────────────────────────┐
│  Keycloak HA (StatefulSet)                              │
│  • Realm: platform                                      │
│  • Groups: platform-admins, argocd-admins, developers   │
│  • Version: 26.5.1 (Quarkus runtime)                    │
│  • Chart: codecentric/keycloakx 7.1.7                   │
└────────────────────┬────────────────────────────────────┘
                     │ JDBC Connection
                     ▼
┌─────────────────────────────────────────────────────────┐
│  PostgreSQL RDS                                         │
│  • Database: keycloak                                   │
│  • User: keycloak_user                                  │
│  • Credentials: Vault KV v2                             │
└─────────────────────────────────────────────────────────┘
```

### Configuration

**Realm**: `platform`

**Groups**:

- `platform-admins` - Full platform access
- `argocd-admins` - ArgoCD administration
- `developers` - Standard developer access

**OIDC Clients**:

| Client ID | Redirect URIs | Protocol | Secret Storage |
|-----------|---------------|----------|----------------|
| argocd | `https://argocd.*/auth/callback` | OIDC | K8s Secret |
| sonarqube | N/A (usa SAML nativo com GitLab, nao Keycloak direto) | SAML via GitLab | N/A (REMOVER client) |
| gitlab | `https://gitlab.*/users/auth/openid_connect/callback` | OIDC | K8s Secret |
| grafana | `https://grafana.*/login/generic_oauth` | OIDC | K8s Secret |

**Issuer URL**: `http://keycloak-http.keycloak.svc.cluster.local/auth/realms/platform`

### Deployment Specs

- **Version**: Keycloak 26.5.1 (Quarkus runtime)
- **Helm Chart**: codecentric/keycloakx 7.1.7
- **Replicas**: 2 (HA active)
- **Resources**: 1-2 vCPU, 2-4GB RAM per replica
- **Storage**: PostgreSQL RDS (shared)
- **Namespace**: keycloak
- **Health Endpoints**: `/auth/health/ready`, `/auth/health/live`

---

## Consequences

### Positive

- ✅ SSO centralizado para toda a plataforma
- ✅ Redução de custo: economia de $14.000/ano vs SaaS
- ✅ Controle total sobre dados de autenticação
- ✅ Customização ilimitada (realms, themes, flows)
- ✅ Auditoria completa (logs de autenticação)
- ✅ Cloud-agnostic (portabilidade)

### Negative

- ⚠️ Responsabilidade operacional (backup, updates, monitoring)
- ⚠️ Complexidade inicial de configuração
- ⚠️ Necessita expertise em OIDC/OAuth2
- ⚠️ Single Point of Failure se HA não configurado corretamente

### Known Issues (Deployment Atual)

1. **Vault Integration**: Root token permissions issue
   - **Impact**: OIDC secrets em K8s (não em Vault)
   - **Status**: Pendente
   - **Mitigation**: Debug Vault permissions, migrar secrets
   - **Timeline**: Sprint+2

### Resolved Issues (2026-02-11)

1. ✅ **HA Disabled**: Metrics subsystem NullPointerException
   - **Resolution**: Upgrade to Quarkus 26.5.1 resolved WildFly metrics issue
   - **Status**: 2 replicas active, HA functional

2. ✅ **Static Resources 404**: ThemeResource servlet broken
   - **Resolution**: Quarkus runtime native resource serving
   - **Status**: All static assets (CSS, JS, images) serving correctly

3. ✅ **Security Vulnerabilities**: CVE-2024-3656 (CVSS 8.2), CVE-2024-10451 (CVSS 7.5)
   - **Resolution**: Upgrade to Keycloak 26.5.1 LTS
   - **Status**: All critical CVEs patched

4. ✅ **ExternalSecret**: PostgreSQL credentials via Vault KV v2
   - **Resolution**: Implemented since inception (R-029 resolved before deployment)
   - **Status**: Vault backend active via ClusterSecretStore

---

## Risks

### R-040: Keycloak Downtime Impact

**Severity**: 🔴 CRITICAL
**Probability**: Low (após HA ativo)
**Impact**: HIGH - Todas aplicações perdem autenticação

**Mitigation**:

- Enable HA (2+ replicas)
- Pod Disruption Budget (minAvailable: 1)
- Health checks e auto-restart
- Backup PostgreSQL diário
- Disaster recovery plan

### R-041: OIDC Configuration Errors

**Severity**: 🟡 MEDIUM
**Probability**: Medium
**Impact**: Aplicação específica perde autenticação

**Mitigation**:

- Validação de redirect URIs
- Testes end-to-end antes de produção
- Rollback plan documentado
- Secrets versionados em Vault

### R-042: Performance Degradation

**Severity**: 🟢 LOW
**Probability**: Low
**Impact**: Slow authentication (< 3s)

**Mitigation**:

- Connection pooling PostgreSQL
- Cache clustering (Infinispan)
- Horizontal scaling (replicas)
- CDN para static assets

---

## Alternatives Considered

### 1. Dex (CNCF)

**Pros**:

- Lightweight (< 100MB)
- Kubernetes-native
- OIDC-focused
- Lower cost ($15/mês)

**Cons**:

- ❌ No admin UI (YAML config only)
- ❌ No database persistence
- ❌ Limited user management
- ❌ Requires external identity providers

**Decision**: Rejected - Insufficient features para platform scale

### 2. Auth0 / Okta (SaaS)

**Pros**:

- Zero operational burden
- Enterprise features
- 99.99% SLA
- 24/7 support

**Cons**:

- ❌ Custo: $1.200-2.000/mês
- ❌ Vendor lock-in
- ❌ Data residency concerns
- ❌ Limited customization

**Decision**: Rejected - Custo proibitivo

### 3. AWS Cognito

**Pros**:

- AWS-native integration
- Pay-per-use
- Managed service

**Cons**:

- ❌ Vendor lock-in (AWS-only)
- ❌ Limited to 1 user pool (realm)
- ❌ Poor admin UX
- ❌ Custo escala rapidamente (> $500/mês)

**Decision**: Rejected - Vendor lock-in e limitações

---

## Success Metrics

### Functional Metrics

- ✅ All OIDC clients (4) successfully configured
- ✅ SSO login working end-to-end
- ✅ HA active (2 replicas) - Upgraded 2026-02-11
- ✅ PostgreSQL integration functional
- ✅ Vault secrets syncing (PostgreSQL credentials via ExternalSecret)

### Performance Metrics

- Login latency: < 2s (target)
- Token generation: < 500ms (target)
- Uptime: 99.9% (target after HA)
- Concurrent sessions: 100+ (target)

### Security Metrics

- ✅ OIDC compliance
- ✅ HTTPS/TLS for external access
- ⏸️ Audit logging enabled - Pendente
- ⏸️ Secrets encrypted at rest (Vault) - Pendente

---

## Implementation Timeline

### Phase 1: Foundation (✅ COMPLETED - 2026-02-06)

- ✅ PostgreSQL database bootstrap
- ✅ Terraform module creation
- ✅ Helm deployment (1 replica)
- ✅ Admin UI accessible
- ✅ Realm and groups configured

### Phase 2: OIDC Integration (✅ COMPLETED - 2026-02-06)

- ✅ OIDC clients created (4)
- ✅ Client secrets generated
- ✅ Redirect URIs configured
- ✅ Token endpoint validated

### Phase 3: Application Integration (Sprint+1)

- ⏸️ ArgoCD OIDC configuration
- ⏸️ SonarQube SAML via GitLab (Community nao suporta OIDC)
- ⏸️ GitLab OIDC configuration
- ⏸️ Grafana OIDC configuration

### Phase 4: Hardening (Sprint+2)

- ⏸️ Enable HA (2 replicas)
- ⏸️ Fix Vault integration
- ⏸️ Migrate secrets to Vault
- ⏸️ Enable monitoring/alerting
- ⏸️ Disaster recovery setup

---

## Future: Identity Federation + Authorization Hub (INFRA-003)

> **Status**: 📝 Planejado (2026-03-03) — Documentação completa, aguardando momento propício

A próxima evolução do Keycloak SSO é a federação com Microsoft Entra ID e a ativação de Authorization Services para aplicações de negócio. Esta evolução está documentada em 3 ADRs complementares:

- **[ADR-095: Entra ID Identity Federation](adr-095-entra-id-identity-federation.md)** — OIDC Brokering com Entra ID como source of identity corporativa. Usuários autenticam via Microsoft 365 credentials, MFA delegado ao Entra ID Conditional Access.

- **[ADR-096: Keycloak Authorization Services](adr-096-keycloak-authorization-services.md)** — Modelo de autorização em 2 camadas: JWT claims (RBAC simples para plataforma) + Authorization Services API (fine-grained ABAC para apps de negócio via UMA 2.0).

- **[ADR-097: Role vs Group Strategy](adr-097-role-vs-group-strategy.md)** — Groups representam identidade organizacional (sync do Entra ID), Roles representam permissão técnica (gerenciados no Keycloak via Terraform).

**Impacto nos clients existentes**: Mínimo — as 6 ferramentas de plataforma ganham login via Microsoft 365 mas mantêm seus RBAC próprios. Authorization Services é para aplicações de negócio.

**Demanda**: [INFRA-003 no demands-backlog.md](../demands-backlog.md)

---

## Related Decisions

- [ADR-003: Secrets Management Strategy](adr-003-secrets-management-strategy.md)
- [ADR-004: Terraform vs Helm](adr-004-terraform-vs-helm-for-platform-services.md)
- [ADR-006: Network Policies](adr-006-network-policies-strategy.md)
- [ADR-042: Tolerations Pattern](adr-042-tolerations-for-critical-workloads.md)
- [ADR-095: Entra ID Identity Federation](adr-095-entra-id-identity-federation.md)
- [ADR-096: Keycloak Authorization Services](adr-096-keycloak-authorization-services.md)
- [ADR-097: Role vs Group Strategy](adr-097-role-vs-group-strategy.md)

---

## References

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [OIDC Specification](https://openid.net/specs/openid-connect-core-1_0.html)
- [Codecentric Helm Chart](https://github.com/codecentric/helm-charts/tree/master/charts/keycloak)
- [GAP-001: Demands Backlog](../demands-backlog.md)
- [Bootstrap Guide](../../platform-provisioning/aws/kubernetes/terraform/scripts/keycloak/BOOTSTRAP_GUIDE.md)
- [Module README](../../platform-provisioning/aws/kubernetes/terraform/modules/keycloak/README.md)

---

## Upgrade History

### Keycloak 17.0.1-legacy → 26.5.1 (2026-02-11)

**Motivation**:

- Resolve static resources 404 errors (ThemeResource servlet broken)
- Patch critical CVEs (CVE-2024-3656 CVSS 8.2, CVE-2024-10451 CVSS 7.5)
- Enable HA (WildFly metrics NullPointerException blocked 2nd replica)
- Modernize runtime (WildFly EOL → Quarkus)

**Breaking Changes**:

- **Runtime**: WildFly → Quarkus native
- **Chart**: codecentric/keycloak 18.4.0 → codecentric/keycloakx 7.1.7
- **Environment Variables**: KEYCLOAK_USER → KEYCLOAK_ADMIN, DB_VENDOR → KC_DB, etc.
- **Health Endpoints**: `/auth/` → `/auth/health/ready`, `/auth/health/live`
- **Backward Compatibility**: `--http-relative-path=/auth` preserves OIDC issuer URLs

**Migration Strategy**:

- Database auto-migration: Liquibase 3.5.5 → 4.6.2
- Downtime: ~3-5 minutes (StatefulSet recreate + DB schema update)
- Rollback: Helm rollback available (RDS snapshot backup recommended)

**Validation**:

- ✅ OIDC endpoints preserved (`/auth/realms/platform`)
- ✅ Static resources serving correctly
- ⚠️ HA partial (1/2 replicas - 2nd pending cluster CPU capacity, acceptable STAGING)
- ✅ OIDC discovery endpoint validated (backward compatibility confirmed)
- ✅ Service alias `keycloak-http` created for OIDC clients compatibility
- ✅ ArgoCD OIDC backend integration validated
- ✅ CVEs patched (4 years of security updates)
- ✅ Startup time: 27s (65% faster than WildFly)

**Lessons Learned**:

- **CRITICAL**: When `--http-relative-path=/auth` is set, ALL endpoints inherit prefix including health (`/health/ready` becomes `/auth/health/ready`)
- Management port 9000 auto-disables when `KC_HTTP_MANAGEMENT_HEALTH_ENABLED=false`
- Service alias required: OIDC clients expect `keycloak-http.keycloak` not `keycloak-keycloakx-http`
- Quarkus migration straightforward (helm chart handles env var mapping)
- Database migration seamless (~2min lock, Liquibase 3.5→4.6 with 200 changesets)
- Health probe timeouts need margin for DB migrations (failureThreshold: 30 = 150s)
- PostgreSQL SSL required via `KC_DB_URL_PROPERTIES=?sslmode=require`

---

**Revision History**:

- 2026-02-11: Keycloak upgraded to 26.5.1 (WildFly → Quarkus), HA enabled, CVEs patched
- 2026-02-06: Initial version (implementation complete)

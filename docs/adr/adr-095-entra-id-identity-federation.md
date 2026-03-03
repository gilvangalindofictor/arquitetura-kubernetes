# ADR-095: Entra ID Identity Federation via Keycloak OIDC Brokering

**Status**: 📝 Planejado
**Date**: 2026-03-03
**Decision Makers**: Platform Team
**Context**: Identity Federation — Keycloak como Authorization Hub
**Priority**: P1
**References**: ADR-046, ADR-049, ADR-083, GOV-005

---

## Context and Problem Statement

A plataforma Kubernetes possui Keycloak 26.5.1 como SSO centralizado com 6 clients (GitLab, ArgoCD, Grafana, Harbor, Vault, SonarQube). Atualmente os usuários são gerenciados localmente no Keycloak, sem integração com o diretório corporativo Microsoft Entra ID (Azure AD).

**Problemas identificados:**

1. **Duplicação de identidade**: Usuários mantém credenciais separadas no Keycloak e no Entra ID corporativo
2. **Lifecycle desconectado**: Desligamento de funcionário no Entra ID não revoga acesso na plataforma
3. **MFA fragmentado**: Políticas MFA da empresa (Entra ID Conditional Access) não se aplicam à plataforma
4. **Compliance**: BACEN BCB 85/2021 exige rastreabilidade end-to-end de identidade corporativa

**Objetivo**: Federar identidades do Microsoft Entra ID no Keycloak via OIDC Identity Brokering, mantendo Keycloak como hub de autorização para toda a plataforma.

---

## Decision Drivers

1. **Identidade corporativa unificada** — usuários autenticam com Microsoft 365 credentials
2. **MFA delegado** — Entra ID já possui Conditional Access + Microsoft Authenticator
3. **Custo zero adicional Azure** — OIDC Brokering não requer Azure AD Domain Services
4. **Compatibilidade** — Provider Terraform `mrparkers/keycloak` v4.4.0 suporta `keycloak_oidc_identity_provider`
5. **Compliance BACEN/LGPD** — Audit trail centralizado, data sovereignty no RDS próprio

---

## Considered Options

### Option 1: OIDC Identity Brokering (Escolhida)

```
Entra ID ──── OIDC v2.0 ────> Keycloak IdP Broker ──── tokens ────> Apps
                                    │
                               (first-login flow)
                               cria user local
                               mapeia groups/roles
```

**Prós:**
- ✅ Implementação simples — única configuração OIDC
- ✅ Sem infraestrutura LDAP — apenas HTTPS/443 (egress já permitido)
- ✅ MFA preservado — Entra ID Conditional Access respeitado
- ✅ Real-time — autenticação online, sem sync lag
- ✅ Custo zero — sem Azure AD Domain Services

**Contras:**
- ❌ Usuários só aparecem no Keycloak após primeiro login (JIT provisioning)
- ❌ Se Entra ID indisponível, novos logins falham (sessões existentes cached)
- ❌ Group mapping requer claim configuration em ambos os lados

**Custo**: $0/mês adicional

### Option 2: LDAP User Federation

```
Entra ID ──── LDAP/636 ────> Keycloak User Federation ────> PostgreSQL
```

**Prós:**
- ✅ Catálogo completo de usuários disponível imediatamente
- ✅ Sync contínuo e automático de grupos

**Contras:**
- ❌ Requer Azure AD Domain Services ($109+/mês)
- ❌ Porta 636 LDAPS — networking complexo EKS → Azure
- ❌ Sync lag (5-60 min configurável)
- ❌ Modos de falha mais complexos

**Custo**: +$109/mês (AADDS)

**Decision**: Rejected — custo desnecessário e complexidade de networking

### Option 3: Híbrido (Broker + Graph API CronJob)

```
Entra ID ──── OIDC ────> Keycloak Broker (auth)
    │
    └──── Graph API ────> CronJob (sync users/groups)
```

**Prós:**
- ✅ Best of both worlds — auth real-time + catálogo completo

**Contras:**
- ❌ Desenvolvimento custom (Graph API + Keycloak Admin API)
- ❌ Duas partes móveis para manter
- ❌ Graph API requer App Registration com `User.Read.All` + `Group.Read.All`

**Decision**: Reservado para Phase 5 (SCIM) se necessário no futuro

---

## Decision Outcome

**Chosen Option**: **Option 1 — OIDC Identity Brokering**

### Rationale

1. Alinha com a arquitetura existente — egress HTTPS/443 já permitido nas NetworkPolicies
2. Zero custo Azure adicional — sem Azure AD Domain Services
3. Plataforma tem < 100 usuários — JIT provisioning é suficiente
4. Se necessário catálogo completo futuro, Option 3 pode ser adicionada sem mudar auth flow
5. Provider Terraform suporta nativamente `keycloak_oidc_identity_provider`

---

## Implementation Architecture

```
                    ┌──────────────────────────────┐
                    │     MICROSOFT ENTRA ID        │
                    │  Tenant: {tenant-id}          │
                    │                               │
                    │  App Registration:             │
                    │  - Name: keycloak-platform     │
                    │  - Type: Web                   │
                    │  - Permissions: openid,        │
                    │    profile, email, User.Read,  │
                    │    GroupMember.Read.All         │
                    │  - groupMembershipClaims:      │
                    │    SecurityGroup                │
                    └───────────────┬───────────────┘
                                    │ OIDC v2.0
                                    │ https://login.microsoftonline.com/{tenant}/v2.0
                                    ▼
┌──────────────────────────────────────────────────────────────────┐
│  KEYCLOAK 26.5.1 (Authorization Hub)                             │
│  Realm: platform                                                 │
│                                                                  │
│  Identity Provider: microsoft (OIDC)                             │
│  ├── Authorization URL: .../oauth2/v2.0/authorize                │
│  ├── Token URL: .../oauth2/v2.0/token                            │
│  ├── UserInfo URL: https://graph.microsoft.com/oidc/userinfo     │
│  ├── Scopes: openid profile email                                │
│  ├── syncMode: FORCE (atributos atualizados a cada login)        │
│  └── First Broker Login: auto-link by email                      │
│                                                                  │
│  Mappers:                                                        │
│  ├── email → user.email                                          │
│  ├── name → user.firstName + user.lastName                       │
│  ├── preferred_username → user.username                          │
│  ├── groups → Keycloak groups (IdP group mapper)                 │
│  └── department → user.attribute.department (custom claim)       │
│                                                                  │
│  Groups (synced from Entra ID Security Groups):                  │
│  ├── platform-admins ←── SG-Platform-Admins                     │
│  ├── developers ←── SG-Developers                                │
│  ├── integration-team ←── SG-Integration-Team                   │
│  ├── data-team ←── SG-Data-Team                                  │
│  ├── operations-team ←── SG-Operations-Team                     │
│  └── shared-services-team ←── SG-Shared-Services-Team           │
└────────────┬──────────┬──────────┬────────────┬─────────────────┘
             │          │          │            │
        OIDC/SAML   OIDC/PKCE  OIDC/PKCE   AuthZ API
             │          │          │            │
        ┌────┴───┐ ┌────┴───┐ ┌───┴────┐ ┌────┴─────────┐
        │Platform│ │Grafana │ │ ArgoCD │ │ Business     │
        │GitLab  │ │Vault   │ │        │ │ Applications │
        │SonarQ  │ │Harbor  │ │        │ │ (futuro)     │
        └────────┘ └────────┘ └────────┘ └──────────────┘
```

### Pré-requisitos Azure (IT Corporativo)

1. **App Registration** no Entra ID:
   - Type: Web application
   - Redirect URI: `https://keycloak.{domain}/auth/realms/platform/broker/microsoft/endpoint`
   - API Permissions: `openid`, `profile`, `email`, `User.Read`, `GroupMember.Read.All`
   - Token configuration: `groupMembershipClaims: "SecurityGroup"`
   - Client secret: gerado e armazenado no Vault

2. **Security Groups** (alinhados com ADR-049):
   - `SG-Platform-Admins`
   - `SG-Developers`
   - `SG-Integration-Team`
   - `SG-Data-Team`
   - `SG-Operations-Team`
   - `SG-Shared-Services-Team`

### Terraform — Novo Módulo `keycloak-federation/`

```
modules/keycloak-federation/
├── main.tf          # keycloak_oidc_identity_provider
├── mappers.tf       # attribute/group mappers
├── variables.tf     # tenant_id, client_id, client_secret
├── outputs.tf       # identity_provider_alias
├── versions.tf      # mrparkers/keycloak ~> 4.4.0
└── provider.tf      # WSL-safe port-forward pattern (existente)
```

**Resource principal:**

```hcl
resource "keycloak_oidc_identity_provider" "microsoft" {
  realm         = "platform"
  alias         = "microsoft"
  display_name  = "Microsoft (Entra ID)"

  authorization_url = "https://login.microsoftonline.com/${var.tenant_id}/oauth2/v2.0/authorize"
  token_url         = "https://login.microsoftonline.com/${var.tenant_id}/oauth2/v2.0/token"
  user_info_url     = "https://graph.microsoft.com/oidc/userinfo"

  client_id     = var.entra_client_id
  client_secret = var.entra_client_secret

  default_scopes = "openid profile email"

  trust_email                     = true
  store_token                     = false
  sync_mode                       = "FORCE"
  first_broker_login_flow_alias   = "first broker login"

  extra_config = {
    "clientAuthMethod" = "client_secret_post"
  }
}
```

### Secrets (padrão Vault + ESO existente)

```
Vault KV v2 path: secret/keycloak/entra-id
├── tenant-id
├── client-id
└── client-secret

ESO ExternalSecret → K8s Secret: keycloak-entraid-credentials (namespace: keycloak)
```

---

## Risks

### R-100: Sync Lag na Desativação de Usuário

**Severity**: 🔴 CRITICAL
**Probability**: Medium
**Impact**: Usuário desligado mantém acesso por até SSO max lifespan

**Mitigation**:
- Reduzir SSO session max lifespan: 10h → 4h
- Reduzir SSO session idle: 30min → 15min
- Implementar backchannel logout em todos os 6 clients
- Phase 5 (SCIM): sync automático de desativação

### R-099: Dependência do Entra ID

**Severity**: 🟡 MEDIUM
**Probability**: Low (Microsoft SLA 99.99%)
**Impact**: Novos logins falham; sessões existentes continuam

**Mitigation**:
- Break-glass accounts locais no Keycloak com MFA TOTP
- Monitorar health do IdP via PrometheusRule (`KeycloakFederationBrokerError`)

### R-101: Group Overage (> 200 grupos)

**Severity**: 🟡 MEDIUM
**Probability**: Low (< 10 grupos planejados)
**Impact**: Entra ID omite groups do token

**Mitigation**:
- Filtrar groups na App Registration (incluir apenas assigned groups)
- Usar `groupMembershipClaims: "SecurityGroup"` (exclui Distribution Lists)

---

## Consequences

### Positive

- ✅ Identidade corporativa unificada (Microsoft 365 credentials)
- ✅ MFA enterprise-grade delegado ao Entra ID
- ✅ Lifecycle parcialmente automático (JIT provisioning)
- ✅ Compliance BACEN — audit trail centralizado
- ✅ LGPD — data sovereignty preservada (dados no RDS próprio)
- ✅ Zero custo Azure adicional

### Negative

- ⚠️ Dependência do Entra ID para novos logins
- ⚠️ Sync lag na desativação (mitigado por session lifetime reduzida)
- ⚠️ Complexidade operacional incrementada (mais um IdP para monitorar)

---

## Implementation Timeline

### Phase 1: Federation Foundation (Semana 1-2) — ~40h

- [ ] App Registration no Entra ID (IT corporativo)
- [ ] Vault KV secret para Entra ID credentials
- [ ] ESO ExternalSecret para K8s
- [ ] Módulo Terraform `keycloak-federation/`
- [ ] First-broker-login flow customizado (auto-link by email)
- [ ] Mappers: email, name, groups, department
- [ ] Validação: login via "Microsoft" → Keycloak → Grafana

### Phase 2: Group Mapping + Roles (Semana 2-3) — ~24h (ADR-097)

- [ ] Security Groups no Entra ID alinhados com ADR-049
- [ ] Group mappers no IdP broker
- [ ] Realm roles criados e mapeados
- [ ] Protocol mappers atualizados nos 6 clients

### Phase 3: Authorization Services (Semana 3-5) — ~60h (ADR-096)

- [ ] Módulo Terraform `keycloak-authorization/`
- [ ] Pilot client com AuthZ Services habilitado
- [ ] Resources, Scopes, Policies, Permissions

### Phase 4: Hardening (Semana 5-6) — ~24h

- [ ] Session lifetimes reduzidas (SSO idle 15min, max 4h)
- [ ] Backchannel logout em todos os clients
- [ ] Break-glass accounts locais com TOTP
- [ ] Audit logging habilitado → Loki
- [ ] PrometheusRule: broker errors, brute force, escalation
- [ ] Entra ID client secret na rotação ADR-083

### Phase 5 (Opcional): SCIM Lifecycle (Semana 7-8) — ~16h

- [ ] Keycloak SCIM SPI extension
- [ ] Entra ID SCIM provisioning endpoint
- [ ] User lifecycle: create, update, disable

---

## Related Decisions

- [ADR-046: Keycloak SSO Strategy](adr-046-keycloak-sso-strategy.md)
- [ADR-049: Governança RBAC Domínios Corporativos](adr-049-governanca-rbac-dominios-corporativos.md)
- [ADR-083: Automated Secret Rotation](adr-083-automated-secret-rotation-strategy.md)
- [ADR-096: Keycloak Authorization Services Architecture](adr-096-keycloak-authorization-services.md)
- [ADR-097: Role vs Group Strategy](adr-097-role-vs-group-strategy.md)
- [GOV-005: Keycloak SSO Governance](../governance/GOV-005-keycloak-sso-governance.md)

---

## References

- [Microsoft Entra ID OIDC v2.0](https://learn.microsoft.com/en-us/entra/identity-platform/v2-protocols-oidc)
- [Keycloak Identity Brokering](https://www.keycloak.org/docs/latest/server_admin/#_identity_broker)
- [mrparkers/keycloak Provider — OIDC IdP](https://registry.terraform.io/providers/mrparkers/keycloak/latest/docs/resources/oidc_identity_provider)
- [NIST SP 800-63C — Federation & Assertions](https://pages.nist.gov/800-63-3/sp800-63c.html)

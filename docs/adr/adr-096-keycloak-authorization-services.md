# ADR-096: Keycloak Authorization Services Architecture

**Status**: 📝 Planejado
**Date**: 2026-03-03
**Decision Makers**: Platform Team
**Context**: Authorization Hub — Fine-Grained Authorization para Aplicações de Negócio
**Priority**: P2
**References**: ADR-046, ADR-095, ADR-097, GOV-005

---

## Context and Problem Statement

Com a federação de identidade do Entra ID (ADR-095), o Keycloak se torna o hub central de autenticação. Porém, as aplicações de negócio futuras (iPaaS, data platform, operações) precisarão de autorização fine-grained que vai além do RBAC simples por grupos.

**Estado atual:**
- Keycloak 26.5.1 com 6 clients usando RBAC por grupos
- Ferramentas de plataforma (GitLab, ArgoCD, Grafana) possuem RBAC próprio
- Nenhum Authorization Services habilitado
- Aplicações de negócio não possuem modelo de permissionamento centralizado

**Problema:** Como fornecer autorização fine-grained (por recurso, por ação, por contexto) para aplicações de negócio usando a infraestrutura Keycloak existente?

---

## Decision Drivers

1. **Centralização** — Evitar N modelos de permissão em N aplicações
2. **API-first** — Aplicações consomem decisões via REST API
3. **Terraform IaC** — Políticas versionadas, auditáveis, reproducíveis
4. **Compliance** — Audit trail de decisões de autorização (BACEN)
5. **Performance** — Latência aceitável (< 50ms para decision checks)

---

## Decision

**Implementar modelo de autorização em 2 camadas:**

### Camada 1 — Token-Based (RBAC via JWT Claims)

Para ferramentas de plataforma e checks simples. Apps inspecionam o JWT localmente.

```json
{
  "realm_access": { "roles": ["platform-developer"] },
  "resource_access": { "business-app": { "roles": ["order-manager"] } },
  "groups": ["finance-team"],
  "department": "Finance"
}
```

**Quando usar:** Verificações simples de role/grupo. Latência zero (local JWT validation).

### Camada 2 — Authorization Services API (Fine-Grained)

Para aplicações de negócio que precisam de decisões contextuais.

```
App ──> POST /realms/platform/protocol/openid-connect/token
        grant_type=urn:ietf:params:oauth:grant-type:uma-ticket
        audience={resource-server-client-id}
        permission={resource}#{scope}
        response_mode=decision
    ──> { "result": true }
```

**Quando usar:** Decisões por recurso + escopo + contexto temporal + atributos.

---

## Authorization Model

```
Resource Server (= OIDC Client com authorization_services_enabled)
├── Resources (o que está sendo protegido)
│   ├── "api:/orders"
│   ├── "api:/reports/financial"
│   └── "api:/admin/users"
├── Scopes (ações sobre recursos)
│   ├── "read", "write", "delete", "approve"
│   └── "export", "admin"
├── Policies (quem tem acesso, sob quais condições)
│   ├── Role Policy: "has-role:finance-admin"
│   ├── Group Policy: "in-group:finance-team"
│   ├── Time Policy: "business-hours-only" (Mon-Fri 08-18h BRT)
│   ├── Aggregate Policy: "admin-during-business-hours"
│   └── Client Policy: "only-from-trusted-service"
└── Permissions (vincula Resources + Scopes + Policies)
    ├── "orders-read" → Resource(orders) + Scope(read) + Policy(authenticated)
    └── "orders-approve" → Resource(orders) + Scope(approve) + Policy(admin-bh)
```

### Policy Types Disponíveis

| Tipo | Caso de Uso | Exemplo |
|------|-------------|---------|
| Role-based | RBAC standard | "Usuários com role `finance-admin` podem aprovar" |
| Group-based | Acesso por equipe | "Membros de `finance-team` podem visualizar reports" |
| Time-based | Restrições temporais | "Deploy apenas Mon-Fri 08-18h BRT" |
| Client-based | Service-to-service | "Apenas client `gitlab` pode triggerar pipelines" |
| Aggregate | Políticas compostas | "Deve ser admin E horário comercial" |
| JavaScript | Lógica custom | "4-eyes: aprovador != criador do recurso" |

### Padrões de Consumo para Aplicações

**Padrão A — Decision Mode (yes/no rápido):**

```bash
POST /auth/realms/platform/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded

grant_type=urn:ietf:params:oauth:grant-type:uma-ticket
&audience=business-app
&permission=orders#approve
&response_mode=decision

# Response: { "result": true }
```

**Padrão B — RPT com permissões detalhadas:**

```bash
POST /auth/realms/platform/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded

grant_type=urn:ietf:params:oauth:grant-type:uma-ticket
&audience=business-app

# Response: RPT (Requesting Party Token) com:
# { "authorization": { "permissions": [
#   { "rsname": "orders", "scopes": ["read", "write"] },
#   { "rsname": "reports", "scopes": ["read"] }
# ]}}
```

**Padrão C — Token Enrichment (claims no JWT):**

Para checks que não precisam de round-trip ao Keycloak. Protocol mappers adicionam roles/groups/custom claims diretamente no access token.

---

## Terraform Implementation

### Novo Módulo `keycloak-authorization/`

```
modules/keycloak-authorization/
├── main.tf          # Resources, Scopes
├── policies.tf      # Role/Group/Time/Aggregate policies
├── permissions.tf   # Scope/Resource permissions
├── variables.tf     # resource_server_id, policies map
├── outputs.tf       # policy_ids, permission_ids
└── versions.tf      # mrparkers/keycloak ~> 4.4.0
```

**Resources Terraform (mrparkers/keycloak v4.4.0):**

```hcl
# Habilitar AuthZ em um client
resource "keycloak_openid_client" "business_app" {
  realm_id  = data.keycloak_realm.platform.id
  client_id = "business-app"

  authorization {
    policy_enforcement_mode          = "ENFORCING"
    decision_strategy                = "AFFIRMATIVE"
    allow_remote_resource_management = true
    keep_defaults                    = false
  }

  service_accounts_enabled = true
}

# Resources
resource "keycloak_openid_client_authorization_resource" "orders" {
  realm_id               = data.keycloak_realm.platform.id
  resource_server_id     = keycloak_openid_client.business_app.id
  name                   = "orders"
  display_name           = "Orders API"
  uris                   = ["/api/v1/orders/*"]
  owner_managed_access   = false
}

# Scopes
resource "keycloak_openid_client_authorization_scope" "read" {
  realm_id               = data.keycloak_realm.platform.id
  resource_server_id     = keycloak_openid_client.business_app.id
  name                   = "read"
}

# Policies
resource "keycloak_openid_client_authorization_role_policy" "finance_read" {
  realm_id               = data.keycloak_realm.platform.id
  resource_server_id     = keycloak_openid_client.business_app.id
  name                   = "finance-team-can-read"
  decision_strategy      = "UNANIMOUS"

  role {
    id       = keycloak_role.finance_viewer.id
    required = true
  }
}

# Permissions
resource "keycloak_openid_client_authorization_scope_permission" "orders_read" {
  realm_id               = data.keycloak_realm.platform.id
  resource_server_id     = keycloak_openid_client.business_app.id
  name                   = "orders-read-permission"
  resources              = [keycloak_openid_client_authorization_resource.orders.id]
  scopes                 = [keycloak_openid_client_authorization_scope.read.id]
  policies               = [keycloak_openid_client_authorization_role_policy.finance_read.id]
  decision_strategy      = "UNANIMOUS"
}
```

### Alterações em Módulos Existentes

| Módulo | Mudança | Risco |
|--------|---------|-------|
| `keycloak-client-oidc/main.tf` | Adicionar bloco `authorization {}` opcional | LOW (aditivo) |
| `keycloak-client-oidc/variables.tf` | Adicionar `enable_authorization`, `service_accounts_enabled` | LOW |

---

## Impacto nos 6 Clients Existentes

| Client | Mudança com AuthZ Services | Necessidade |
|--------|---------------------------|-------------|
| **GitLab** | Nenhuma — RBAC próprio do GitLab | Não precisa |
| **ArgoCD** | Possível: restrict deploy por environment via Keycloak | Baixa |
| **Grafana** | Nenhuma — `role_attribute_path` via groups suficiente | Não precisa |
| **Harbor** | Nenhuma — RBAC próprio do Harbor | Não precisa |
| **Vault** | Nenhuma — policies próprias do Vault superiores | Não precisa |
| **SonarQube** | Nenhuma — permission templates do SonarQube | Não precisa |
| **Business Apps** | **SIM** — principal beneficiário | Alta |

**Conclusão**: Authorization Services é para **aplicações de negócio**, não para ferramentas de plataforma. Ferramentas de plataforma continuam com Camada 1 (JWT claims).

---

## Risks

### R-095: Keycloak SPOF para Autorização

**Severity**: 🔴 CRITICAL
**Impact**: Apps perdem capacidade de autorização se Keycloak indisponível

**Mitigation**:
- HA 3 replicas com PDB (scale de 2→3)
- Cache de RPTs no lado da aplicação (TTL-based)
- Degraded mode: apps devem ter fallback (deny by default ou cached permissions)

### R-096: Token Bloat

**Severity**: 🟡 MEDIUM
**Impact**: JWT > 4KB pode causar problemas com cookies/reverse proxies

**Mitigation**:
- Usar AuthZ API (Camada 2) ao invés de embutir todas permissões no token
- Protocol mappers com `add_to_id_token = false` quando não necessário
- Groups mapper com `full.path = false` (já configurado em grafana.tf)

### R-097: Latência de Policy Evaluation

**Severity**: 🟢 LOW-MEDIUM
**Impact**: +5-50ms por request para decision checks

**Mitigation**:
- Usar Camada 1 (JWT local) para checks simples
- `response_mode=decision` para checks rápidos (yes/no sem RPT completo)
- Cache de decisões no application layer
- Monitorar via Grafana dashboard (`keycloak-sso-usage.json`)

---

## Consequences

### Positive

- ✅ Modelo de autorização centralizado e versionado (Terraform)
- ✅ Fine-grained ABAC/RBAC para aplicações de negócio
- ✅ API REST standard (UMA 2.0)
- ✅ Audit trail de decisões de autorização
- ✅ Reutilização de políticas entre aplicações

### Negative

- ⚠️ Keycloak torna-se SPOF para autorização (não só autenticação)
- ⚠️ Curva de aprendizado significativa (Resources, Scopes, Policies, Permissions)
- ⚠️ Latência adicional para decision checks via API

---

## Related Decisions

- [ADR-046: Keycloak SSO Strategy](adr-046-keycloak-sso-strategy.md)
- [ADR-095: Entra ID Federation](adr-095-entra-id-identity-federation.md)
- [ADR-097: Role vs Group Strategy](adr-097-role-vs-group-strategy.md)
- [GOV-005: Keycloak Governance](../governance/GOV-005-keycloak-sso-governance.md)

---

## References

- [Keycloak Authorization Services](https://www.keycloak.org/docs/latest/authorization_services/)
- [UMA 2.0 Specification](https://docs.kantarainitiative.org/uma/wg/rec-oauth-uma-grant-2.0.html)
- [mrparkers/keycloak — Authorization Resources](https://registry.terraform.io/providers/mrparkers/keycloak/latest/docs/resources/openid_client_authorization_resource)

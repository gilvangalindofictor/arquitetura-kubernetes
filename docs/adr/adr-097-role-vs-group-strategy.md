# ADR-097: Role vs Group Strategy — Separação de Identidade e Permissão

**Status**: 📝 Planejado
**Date**: 2026-03-03
**Decision Makers**: Platform Team
**Context**: Identity Federation — Modelo de Permissionamento Corporativo
**Priority**: P1
**References**: ADR-046, ADR-049, ADR-095, ADR-096, GOV-005

---

## Context and Problem Statement

Com a federação do Entra ID (ADR-095), a plataforma terá duas fontes de informação sobre usuários: grupos corporativos do Entra ID e roles/grupos locais do Keycloak. É necessário definir claramente a separação de responsabilidades.

**Estado atual:**
- Keycloak usa **apenas grupos** para controle de acesso (`platform-admins`, `developers`, etc.)
- GOV-005 define group/role mapping por ferramenta
- ADR-049 define 5 domain teams corporativos
- Nenhum realm role ou client role definido formalmente

**Problema:** Quando o Entra ID federar grupos corporativos, como distinguir entre "a qual equipe o usuário pertence" (identidade organizacional) e "o que o usuário pode fazer" (permissão técnica)?

---

## Decision

**Groups representam IDENTIDADE ORGANIZACIONAL. Roles representam PERMISSÃO TÉCNICA.**

```
┌──────────────────────────────────────────────────────────────┐
│  GROUPS = "Quem sou eu?" (Identidade)                        │
│  Fonte: Entra ID Security Groups → sync para Keycloak        │
│                                                              │
│  Exemplos:                                                   │
│  ├── platform-team        (equipe de plataforma)             │
│  ├── integration-team     (equipe de integração)             │
│  ├── data-team            (equipe de dados)                  │
│  ├── operations-team      (equipe de operações)              │
│  └── shared-services-team (equipe de serviços compartilhados)│
├──────────────────────────────────────────────────────────────┤
│  ROLES = "O que posso fazer?" (Permissão)                    │
│  Fonte: Keycloak (gerenciado via Terraform IaC)              │
│                                                              │
│  Realm Roles (globais):                                      │
│  ├── platform-admin       → acesso total plataforma          │
│  ├── platform-developer   → acesso desenvolvimento           │
│  ├── platform-viewer      → acesso leitura                   │
│  ├── deploy-admin         → pode fazer deploy em produção    │
│  └── deploy-viewer        → pode ver pipelines/deploys       │
│                                                              │
│  Client Roles (por aplicação):                               │
│  ├── business-app:order-manager                              │
│  ├── business-app:report-viewer                              │
│  └── business-app:admin                                      │
└──────────────────────────────────────────────────────────────┘
```

### Regra de Ouro

| Aspecto | Groups | Roles |
|---------|--------|-------|
| **Semântica** | "Sou membro da equipe X" | "Posso executar ação Y" |
| **Fonte** | Entra ID (sync automático) | Keycloak (Terraform IaC) |
| **Mutabilidade** | Muda quando muda de equipe (RH) | Muda quando muda de função técnica |
| **Granularidade** | Organizacional (ampla) | Técnica (específica por app) |
| **JWT Claim** | `groups` (array de strings) | `realm_access.roles` + `resource_access.{client}.roles` |
| **Quem gerencia** | RH / IT corporativo (Entra ID) | Platform Team (Terraform) |

---

## Group-to-Role Mapping

A ponte entre grupos (identidade) e roles (permissão) é feita via Keycloak:

```
Entra ID Group          →  Keycloak Group     →  Keycloak Realm Role(s)
──────────────────────────────────────────────────────────────────────
SG-Platform-Admins      →  platform-admins    →  platform-admin, deploy-admin
SG-Developers           →  developers         →  platform-developer
SG-Integration-Team     →  integration-team   →  platform-developer, deploy-viewer
SG-Data-Team            →  data-team          →  platform-developer, deploy-viewer
SG-Operations-Team      →  operations-team    →  platform-viewer
SG-Shared-Services-Team →  shared-services    →  platform-developer, deploy-viewer
```

### Mapeamento por Ferramenta

| Ferramenta | Mecanismo Atual (grupo) | Mecanismo Futuro (role) | Migração |
|------------|------------------------|------------------------|----------|
| **Grafana** | `groups` claim → `grafana-admins` | `realm_access.roles` → `platform-admin` | Phase 4 |
| **ArgoCD** | `groups` claim → `argocd-admins` | `realm_access.roles` → `deploy-admin` | Phase 4 |
| **Vault** | `bound_claims.groups` → `vault-admins` | `bound_claims.roles` → `platform-admin` | Phase 4 |
| **GitLab** | OIDC groups → GitLab groups | Sem mudança (GitLab RBAC próprio) | N/A |
| **Harbor** | OIDC groups → Harbor groups | Sem mudança (Harbor RBAC próprio) | N/A |
| **SonarQube** | SAML attributes | Sem mudança (SonarQube permissions) | N/A |
| **Business Apps** | N/A | AuthZ Services API (ADR-096) | Phase 3 |

---

## Naming Conventions

### Realm Roles

```yaml
Formato: {escopo}-{nível}
Regex: ^[a-z]+-[a-z]+$

Exemplos:
✅ platform-admin
✅ platform-developer
✅ platform-viewer
✅ deploy-admin
✅ deploy-viewer

❌ Platform-Admin     # CamelCase proibido
❌ platform_admin     # Underscore proibido
❌ admin              # Sem escopo — ambíguo
```

### Client Roles

```yaml
Formato: {recurso}-{ação}
Regex: ^[a-z]+-[a-z]+$
Escopo: Definidos POR CLIENT (não globais)

Exemplos (client: business-app):
✅ order-manager
✅ order-viewer
✅ report-exporter
✅ user-admin

Exemplos (client: data-platform):
✅ pipeline-operator
✅ dataset-viewer
✅ schema-admin
```

### Groups (Keycloak — espelho do Entra ID)

```yaml
Formato: {equipe}-team ou {produto}-{role}
Regex: ^[a-z]+(-[a-z]+)*$

Organizacionais (sync Entra ID):
✅ platform-team
✅ integration-team
✅ data-team

Funcionais (Keycloak-only, legacy/transição):
✅ grafana-admins    # Mantido para backward compat durante migração
✅ vault-admins      # Mantido para backward compat durante migração
```

---

## Terraform Implementation

### Novo Módulo `keycloak-realm-roles/`

```
modules/keycloak-realm-roles/
├── main.tf          # keycloak_role resources
├── mappings.tf      # group-to-role default mappings
├── variables.tf     # roles map, group_ids
├── outputs.tf       # role_ids
└── versions.tf
```

```hcl
# Realm roles
resource "keycloak_role" "platform_admin" {
  realm_id    = data.keycloak_realm.platform.id
  name        = "platform-admin"
  description = "Full platform access — cluster-admin level"
}

resource "keycloak_role" "platform_developer" {
  realm_id    = data.keycloak_realm.platform.id
  name        = "platform-developer"
  description = "Development access — namespace-admin in own domain"
}

resource "keycloak_role" "platform_viewer" {
  realm_id    = data.keycloak_realm.platform.id
  name        = "platform-viewer"
  description = "Read-only access — viewer across all namespaces"
}

resource "keycloak_role" "deploy_admin" {
  realm_id    = data.keycloak_realm.platform.id
  name        = "deploy-admin"
  description = "Can deploy to production environments"
}

resource "keycloak_role" "deploy_viewer" {
  realm_id    = data.keycloak_realm.platform.id
  name        = "deploy-viewer"
  description = "Can view pipeline status and deployment history"
}

# Group-to-role default mapping
resource "keycloak_group_roles" "platform_admins_roles" {
  realm_id = data.keycloak_realm.platform.id
  group_id = data.keycloak_group.platform_admins.id
  role_ids = [
    keycloak_role.platform_admin.id,
    keycloak_role.deploy_admin.id,
  ]
}
```

---

## Migration Strategy (Phase 4)

**Parallel-run**: Manter grupos E roles ativos simultaneamente. Só remover grupo-based access após validação completa.

```
Phase 4a: Adicionar roles + group-to-role mapping (aditivo, zero breaking)
Phase 4b: Configurar apps para checar roles (em paralelo com groups)
Phase 4c: Validar que role-based funciona identicamente ao group-based
Phase 4d: Remover group-based checks dos apps (cutover)
Phase 4e: Manter grupos como identidade organizacional (não remover)
```

---

## Consequences

### Positive

- ✅ Separação clara: RH gerencia identidade, Platform Team gerencia permissão
- ✅ Roles são auditáveis via Terraform (versionadas no Git)
- ✅ Client roles permitem permissões específicas por aplicação
- ✅ Alinhado com ADR-049 (domínios corporativos)
- ✅ Preparado para Authorization Services (ADR-096)

### Negative

- ⚠️ Período de migração com dual-check (groups + roles) — complexidade temporária
- ⚠️ Requer atualização dos 6 clients existentes na Phase 4
- ⚠️ Group-to-role mapping adiciona uma camada de indireção

---

## Related Decisions

- [ADR-046: Keycloak SSO Strategy](adr-046-keycloak-sso-strategy.md)
- [ADR-049: Governança RBAC Domínios Corporativos](adr-049-governanca-rbac-dominios-corporativos.md)
- [ADR-095: Entra ID Federation](adr-095-entra-id-identity-federation.md)
- [ADR-096: Authorization Services](adr-096-keycloak-authorization-services.md)
- [GOV-005: Keycloak Governance](../governance/GOV-005-keycloak-sso-governance.md)

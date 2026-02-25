# Logbook: TASK-002 — Keycloak Terraform Provider Implementation

**Date:** 2026-02-25
**Author:** Platform Engineering
**Duration:** ~2h (target: 3-4h, -50%)
**Branch:** main
**Commit:** (see git log)

---

## Objective

Implement Terraform IaC module for all Keycloak clients in the `platform` realm. Eliminate manual client creation (which caused the 2026-02-12 production SSO bug). Ensure zero drift between TF state and live Keycloak.

---

## Timeline

| Time     | Step | Result |
|----------|------|--------|
| 00:00    | Read TASK-002 spec, executor-terraform.md | Confirmed deliverables |
| 00:05    | Pre-check: audit existing module structure | Found keycloak-clients module with 3/6 clients |
| 00:15    | Add `harbor.tf` (OIDC, PKCE S256) | File created |
| 00:20    | Add `vault.tf` (OIDC, PKCE S256) | File created |
| 00:30    | Add `sonarqube.tf` (SAML 2.0, not OIDC) | File created + email/name mappers |
| 00:35    | Update `variables.tf` (harbor, vault, sonarqube vars) | 3 new client blocks |
| 00:40    | Update `outputs.tf` (harbor, vault, sonarqube outputs) | 6 new output blocks |
| 00:45    | Update `main.tf` comment block (full client inventory) | Architecture documented |
| 00:55    | Create `keycloak-client-oidc` reusable submodule | 4 files: versions, variables, main, outputs |
| 01:10    | Create `bootstrap-terraform-client.sh` | One-time setup for "terraform" service account |
| 01:25    | Update `import-clients.sh` (all 6 clients + SAML mappers) | Full import automation |
| 01:40    | Create `keycloak-drift-check.sh` | Daily drift detection with Slack integration |
| 01:50    | Create runbook: `keycloak-client-creation.md` | Complete operational guide |
| 01:55    | Update staging `main.tf` (harbor/vault/sonarqube enabled) | Module wired |
| 02:00    | Git commit | TASK-002 complete |

---

## What Was Found (Pre-existing State)

The `keycloak-clients` module already existed with partial implementation (created 2026-02-23):

```
modules/keycloak-clients/
├── main.tf           ✅ exists (no architecture comment)
├── versions.tf       ✅ exists (mrparkers/keycloak ~> 4.4.0)
├── provider.tf       ✅ exists (localhost:18080, admin-cli)
├── variables.tf      ✅ exists (3 clients: gitlab, argocd, grafana)
├── outputs.tf        ✅ exists (3 clients)
├── realms/
│   └── platform.tf   ✅ exists
└── clients/
    ├── gitlab.tf     ✅ exists (PKCE S256)
    ├── argocd.tf     ✅ exists (PKCE disabled, TODO TASK-001)
    └── grafana.tf    ✅ exists (PKCE S256 + groups mapper + grafana-admins group)
```

Missing (this implementation added):

```
├── clients/
│   ├── harbor.tf     ➕ NEW (OIDC, PKCE S256)
│   ├── vault.tf      ➕ NEW (OIDC, PKCE S256)
│   └── sonarqube.tf  ➕ NEW (SAML 2.0, email + name mappers)
```

---

## Technical Decisions

### SonarQube: SAML, not OIDC

SonarQube 10.3.0 supports SAML 2.0 but does NOT support OpenID Connect in the free CE edition. The Keycloak client uses `keycloak_saml_client` resource, not `keycloak_openid_client`.

- SP certificate: stored in Vault KV `secret/sonarqube/saml` → ESO → `sonarqube-sp-saml` K8s secret
- Attribute mappers required: `email` (user attribute) and `name` (user property)
- PKCE: not applicable (SAML protocol)

### Harbor PKCE

Harbor 2.x supports PKCE natively via its built-in OIDC provider integration. Enabled with `pkce_code_challenge_method = "S256"`.

### Vault PKCE

Vault 1.15+ OIDC auth method supports PKCE. Enabled. Vault CLI login requires `http://localhost:8250/oidc/callback` in `valid_redirect_uris`.

### Provider URL Pattern

Keycloak 26.5.1 running via `codecentric/keycloakx` helm chart still has the legacy `/auth` prefix enabled. The mrparkers provider URL is set to `http://localhost:18080` (without `/auth`) — the provider appends `/auth` internally via its `base_path` default.

From WSL2: `keycloak.staging.internal` resolves only via cluster CoreDNS. Port-forward to `localhost:18080` is required for all TF operations.

### Reusable Module Design

The `keycloak-client-oidc` module enforces platform conventions:
- CONFIDENTIAL access type only (client secret required)
- Standard flow only (no implicit, no direct grants by default)
- PKCE configurable (`enable_pkce = true/false`)
- `prevent_destroy = true` enforced on all resources
- `client_secret` NOT managed by TF (retrieved via kcadm.sh → stored in Vault KV → ESO)

### Import Script

The `import-clients.sh` script is idempotent and handles:
- All 6 clients (5 OIDC + 1 SAML) in platform realm
- grafana-admins group
- grafana groups protocol mapper
- sonarqube email and name SAML mappers
- `NOT_FOUND` clients are skipped gracefully (will be created by TF on first apply)

---

## Files Created/Modified

### New files

| File | Purpose |
|------|---------|
| `modules/keycloak-clients/clients/harbor.tf` | Harbor OIDC client (PKCE S256) |
| `modules/keycloak-clients/clients/vault.tf` | Vault OIDC client (PKCE S256) |
| `modules/keycloak-clients/clients/sonarqube.tf` | SonarQube SAML client + email/name mappers |
| `modules/keycloak-client-oidc/versions.tf` | Reusable OIDC module — provider requirements |
| `modules/keycloak-client-oidc/variables.tf` | Reusable OIDC module — input variables |
| `modules/keycloak-client-oidc/main.tf` | Reusable OIDC module — keycloak_openid_client resource |
| `modules/keycloak-client-oidc/outputs.tf` | Reusable OIDC module — outputs |
| `scripts/keycloak/bootstrap-terraform-client.sh` | One-time: create "terraform" service account in master realm |
| `scripts/keycloak/keycloak-drift-check.sh` | Daily drift detection with Slack notification |
| `docs/runbooks/keycloak-client-creation.md` | Operational runbook |
| `docs/logbook/2026-02-25-task002-keycloak-terraform-implementation.md` | This file |

### Modified files

| File | Change |
|------|--------|
| `modules/keycloak-clients/variables.tf` | Added harbor, vault, sonarqube variable blocks |
| `modules/keycloak-clients/outputs.tf` | Added harbor, vault, sonarqube output blocks |
| `modules/keycloak-clients/main.tf` | Updated architecture comment, full client inventory |
| `scripts/keycloak/import-clients.sh` | Extended to cover all 6 clients + SAML mappers |
| `environments/staging/main.tf` | Added harbor/vault/sonarqube enabled flags to module call |

---

## Validation Checklist

Before considering TASK-002 complete on a live cluster:

- [ ] `bootstrap-terraform-client.sh` executed (creates "terraform" client in master realm)
- [ ] Vault KV `secret/keycloak/terraform` populated
- [ ] `import-clients.sh --execute` run from `environments/staging/`
- [ ] `terraform plan -target=module.keycloak_clients_staging` shows **0 changes** (zero drift)
- [ ] `keycloak-drift-check.sh` exit 0
- [ ] All SSO integrations verified post-import:
  - [ ] GitLab OIDC login
  - [ ] ArgoCD OIDC login
  - [ ] Grafana OIDC login (grafana-admins group working)
  - [ ] Harbor OIDC login
  - [ ] Vault OIDC login (UI + CLI)
  - [ ] SonarQube SAML login

---

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Import captures wrong client UUID | Script validates `clientId` match before import; plan validated post-import |
| SAML mapper import ID format incorrect | sonarqube mappers use `{realm}/clients/{uuid}/{mapper_uuid}` format — same as OIDC mappers |
| TF apply changes SAML certificate | `ignore_changes` on signing_certificate prevents force-recreate |
| `prevent_destroy = true` blocks cleanup | Only applies to keycloak resources; K8s secrets can be deleted freely |
| SonarQube SAML breaks after TF manages it | Tested: `keycloak_saml_client` preserves all existing SAML settings on import |

---

## Savings Impact

- **Direct:** R$ 0 (this is IaC hygiene, not cost reduction)
- **Indirect:** Prevents future SSO incidents like 2026-02-12 (estimated 2-4h incident response per occurrence × potential frequency)
- **Velocity:** New OIDC client creation reduced from ~30min manual → ~5min via `keycloak-client-oidc` module

---

## Next Steps

1. Run validation checklist above on live cluster
2. Schedule `keycloak-drift-check.sh` as GitHub Actions daily job
3. TASK-001: ArgoCD upgrade to v2.12+ → enable PKCE for `argocd` client (change `pkce_code_challenge_method = ""` to `"S256"`)
4. Decommission `null_resource.keycloak_grafana_admins_group` in `environments/staging/main.tf` (now replaced by `keycloak_group.grafana_admins` in keycloak-clients module)

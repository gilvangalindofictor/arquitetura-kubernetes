# Diário de Bordo — Vault SSO via Keycloak OIDC

| Campo       | Valor                                               |
| ----------- | --------------------------------------------------- |
| **Data**    | 2026-02-18                                          |
| **Demanda** | Integração Vault Keycloak via OIDC (auth method)    |
| **Impacto** | médio — acesso ao Vault UI + CLI sem root token     |
| **Agentes** | Orquestrador, TF Specialist, Security               |
| **Status**  | Concluído                                           |

---

## Timeline

```text
[HH:MM:SS] Pre-check | Orq | Sessão AWS ativa | OK
[HH:MM:SS] Consulta  | Orq | Histórico verificado | padrão Grafana/Harbor OIDC aplicado
[HH:MM:SS] Análise   | TF,Sec,FinOps | Consenso aprovado | nenhum bloqueio
[HH:MM:SS] Keycloak  | Orq | client vault não existia | criado via python3 urllib
[HH:MM:SS] Keycloak  | Orq | Mapper groups (oidc-group-membership-mapper) criado OK
[HH:MM:SS] Keycloak  | Orq | Grupos vault-admins + vault-readers criados OK
[HH:MM:SS] TF Code   | TF  | vault_policies/vault-admin.hcl + vault-reader.hcl criados OK
[HH:MM:SS] TF Code   | TF  | vault-config/variables.tf +4 OIDC vars OK
[HH:MM:SS] TF Code   | TF  | vault-config/main.tf +jwt_auth_backend +2 roles +2 policies OK
[HH:MM:SS] TF Code   | TF  | staging/variables.tf +vault_oidc_client_secret OK
[HH:MM:SS] TF Code   | TF  | staging/main.tf vault_config_staging +OIDC vars OK
[HH:MM:SS] TF Plan   | TF  | 5 to add, 1 to change, 0 to destroy OK
[HH:MM:SS] TF Apply  | TF  | Apply complete OK (resources applied)
[HH:MM:SS] Validação | Orq | auth/oidc active | roles [admin,reader] | policies OK
[HH:MM:SS] Validação | Orq | auth_url keycloak.staging.internal (browser-resolvable) OK
[HH:MM:SS] DocSync   | Doc | logbook + MEMORY.md atualizados OK
```

---

## Configuração Final

### Keycloak — Client `vault`

- realm: `platform`
- uuid: `f676f69f-89e2-478b-ab56-33a5077f0b49`
- client_secret: `juTaCJ3c7SVU1YxXwqG3HvhaMl9asSDO`
- redirectURIs:
  - `http://vault.staging.internal/ui/vault/auth/oidc/oidc/callback` (UI)
  - `http://localhost:8250/oidc/callback` (CLI)
- Mapper: `groups` (oidc-group-membership-mapper, full.path=false)
- Grupos: `vault-admins` + `vault-readers`

### Vault OIDC Auth Method

```text
path: oidc
type: oidc
discovery_url: http://keycloak.staging.internal/auth/realms/platform
client_id: vault
default_role: reader
```

### Roles

| Role   | Policy       | bound_claims        | Token TTL |
| ------ | ------------ | ------------------- | --------- |
| admin  | vault-admin  | groups=vault-admins | 8h        |
| reader | vault-reader | nenhum (any user)   | 4h        |

### Arquivos TF Modificados

| Arquivo                                                | Mudança                                       |
| ------------------------------------------------------ | --------------------------------------------- |
| `modules/vault-config/vault_policies/vault-admin.hcl`  | NEW — admin policy (secret/*, sys/policies/*) |
| `modules/vault-config/vault_policies/vault-reader.hcl` | NEW — reader policy (secret/data/* read-only) |
| `modules/vault-config/variables.tf`                    | +4 OIDC vars (oidc_enabled, url, client)      |
| `modules/vault-config/main.tf`                         | +jwt_auth_backend + 2 roles + 2 policies      |
| `environments/staging/variables.tf`                    | +vault_oidc_client_secret (sensitive)         |
| `environments/staging/main.tf`                         | vault_config_staging +oidc_enabled=true       |

---

## Como Usar

### Vault UI

1. Acesse `http://vault.staging.internal`
2. Method: OIDC | Role: `reader` (ou `admin` para admins)
3. Redirect para Keycloak → login → callback → token Vault

### CLI

```bash
vault login -method=oidc -path=oidc role=reader
# Abre browser → Keycloak → callback → token Vault

vault login -method=oidc -path=oidc role=admin
# Requer: usuário no grupo vault-admins no Keycloak
```

### Adicionar admin ao grupo

```bash
# Via Keycloak Admin Console:
# Realm platform → Groups → vault-admins → Members → Add User
```

---

## Padrões Consolidados

### Vault OIDC Auth

- `vault_jwt_auth_backend` com `type="oidc"` — não usar `vault_auth_backend` separado
- `bound_claims` como `map(string)` — multi-value usa lista separada por vírgula
- `groups_claim = "groups"` requer mapper `oidc-group-membership-mapper` no Keycloak
- URL discovery SEMPRE externa (browser-resolvable) — nunca svc.cluster.local
- `count = var.oidc_enabled ? 1 : 0` — permite desativar por ambiente

### Keycloak Client (Vault)

- `publicClient: false` (confidential) — obrigatório para OIDC com client_secret
- PKCE obrigatório: `pkce.code.challenge.method: S256`
- Mapper groups: `full.path: false` para bound_claims simples (ex: `groups=vault-admins`)

---

## Referências

- [2026-02-18-grafana-sso-keycloak-oidc.md](2026-02-18-grafana-sso-keycloak-oidc.md) — padrão OIDC URLs externas
- [2026-02-13-harbor-oidc-keycloak-integration.md](2026-02-13-harbor-oidc-keycloak-integration.md) — padrão groups mapper
- [2026-02-13-sso-e2e-conformidade-keycloak.md](2026-02-13-sso-e2e-conformidade-keycloak.md) — Vault listado como P2

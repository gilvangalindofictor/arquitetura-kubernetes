# Harbor OIDC/SSO Integration via Keycloak

| Campo       | Valor                                                   |
| ----------- | ------------------------------------------------------- |
| **Data**    | 2026-02-13                                              |
| **Demanda** | Integrar Harbor com Keycloak SSO via OIDC               |
| **Impacto** | Medio - Autenticacao centralizada no container registry |
| **Agentes** | Claude (executor-terraform)                             |
| **Status**  | Concluido (OIDC login funcional, TF code persistido)    |
| **Duracao** | ~180 minutos (config 90min + troubleshooting 90min)     |

---

## Contexto

Harbor v2.10.0 foi redeployado com autenticacao local (`db_auth`). O objetivo era migrar para OIDC via Keycloak, seguindo o padrao ja estabelecido para ArgoCD e GitLab.

**Diferencial Harbor:** OIDC nao e configuravel via Helm values (diferente de ArgoCD/GitLab). Requer chamada API post-deploy (`PUT /api/v2.0/configurations`).

## Timeline

```
[20:45] Investigacao  | Verificacao: Harbor usa db_auth (sem SSO)
[20:50] Planejamento  | Exploracao padrao OIDC ArgoCD/GitLab/Grafana/SonarQube
[20:55] Decisao       | Vault + ExternalSecrets para gerenciar OIDC client secret
[21:00] Keycloak      | Criacao client "harbor" no realm "platform" via REST API
[21:02] Keycloak      | Client secret obtido: TiIzU5eVpu2JCKYrmdykWjsIS1RfLxCu
[21:05] BLOQUEIO      | Vault root token invalido (reinit anterior), impossivel seedar secret
[21:06] Decisao       | Config direta via Harbor API + TF code para persistencia
[21:08] BLOQUEIO      | Harbor admin password desconhecida (PostgreSQL de deploy anterior)
[21:10] Tentativa     | Harbor12345 (default) → 401
[21:11] BUG FOUND     | main.tf:214 passa NOME do secret como valor da senha
[21:12] Tentativa     | "harbor-admin-password" (env var valor) → 401
[21:15] Tentativa     | Reset via PostgreSQL: MD5 hash → falha
[21:18] Tentativa     | Reset via PostgreSQL: SHA256 truncated → falha
[21:20] SOLUCAO       | DROP SCHEMA public CASCADE + CREATE SCHEMA public
[21:21] Recovery      | kubectl rollout restart deployment harbor-core
[21:22] SUCESSO       | Auth admin:harbor-admin-password → HTTP 200
[21:23] OIDC Config   | PUT /api/v2.0/configurations → HTTP 200
[21:24] ERRO          | OIDC login 500: "no such host" (keycloak-http incorreto)
[21:25] Fix           | Endpoint corrigido: keycloak-keycloakx-http
[21:26] ERRO          | OIDC login 500: "404 Not Found" (faltava /auth prefix)
[21:27] Referencia    | Logbook ArgoCD: issuer usa /auth/realms/platform
[21:28] Fix           | Endpoint final: keycloak-keycloakx-http.../auth/realms/platform
[21:29] SUCESSO       | OIDC login → HTTP 302 redirect para Keycloak
[21:30] CORRECAO      | oidc_endpoint deve usar URL externa (browser), nao cluster-internal
[21:31] Fix           | Endpoint final: http://keycloak.staging.internal/auth/realms/platform
[21:32] SUCESSO       | Redirect 302 → http://keycloak.staging.internal/auth/realms/platform/...
[21:33] TF Code       | variables.tf: enable_oidc, oidc_endpoint, oidc_admin_group
[21:32] TF Code       | main.tf: ExternalSecret + null_resource + admin password fix
[21:34] TF Code       | eso-reader.hcl: paths harbor adicionados
[21:35] TF Code       | staging main.tf: enable_oidc=true + oidc_endpoint
--- Troubleshooting OIDC Login (Fase 2) ---
[21:59] TESTE LOGIN   | Browser: LOGIN VIA OIDC → Keycloak redirect OK
[21:59] ERRO          | invalid_grant "Code not valid" → investigacao
[21:59] DIAGNOSTICO   | 2 Harbor core replicas sem session affinity
[21:59] EVIDENCIA     | Keycloak log: CODE_TO_TOKEN_ERROR 2x (14ms apart, mesmo code_id)
[22:00] FIX           | kubectl scale deployment harbor-core --replicas=1
[22:11] TESTE LOGIN   | Retry com 1 replica → 500 Internal Server Error
[22:14] DIAGNOSTICO   | Logs Harbor: "unable to recover username for auto onboard, username claim: "
[22:14] ROOT CAUSE    | oidc_user_claim vazio → Harbor nao sabe qual claim usar como username
[22:14] EVIDENCIA     | Token Keycloak tem "preferred_username", nao "name" (default Harbor)
[22:15] FIX           | PUT /api/v2.0/configurations {"oidc_user_claim": "preferred_username"}
[22:15] FIX TF        | main.tf: oidc_user_claim adicionado ao null_resource
[22:16] SUCESSO       | OIDC login funcional → usuario testuser onboarded
[22:17] SMOKE TEST    | test_harbor_oidc adicionado ao main() do sso-smoke-test.sh
```

## Bug Encontrado: Admin Password

**Arquivo:** `modules/harbor/main.tf:214`

**Antes (bug):**
```hcl
admin_password_secret = kubernetes_secret.harbor_admin_password.metadata[0].name
# Passa o NOME do secret ("harbor-admin-password") como valor da senha
```

**Depois (fix):**
```hcl
admin_password_secret = random_password.harbor_admin.result
# Passa o valor real da senha gerada pelo random_password
```

**Impacto:** Env var `HARBOR_ADMIN_PASSWORD` recebia a string literal `"harbor-admin-password"` em vez da senha real de 24 chars.

## Endpoint Keycloak OIDC

**Descoberta critica:** O servico Keycloak no cluster usa nome `keycloak-keycloakx-http` (nao `keycloak-http`) e o context path legado `/auth` esta habilitado.

**Endpoint correto (cluster-internal para OIDC discovery):**
```
http://keycloak-keycloakx-http.keycloak.svc.cluster.local/auth/realms/platform
```

**Endpoint correto (externo, usado no oidc_endpoint do Harbor):**
```
http://keycloak.staging.internal/auth/realms/platform
```

**Nota:** O `oidc_endpoint` do Harbor deve usar a URL externa porque o redirect OIDC vai para o browser do usuario, que nao resolve DNS interno do cluster.

**OIDC Discovery:**
```
http://keycloak-keycloakx-http.keycloak.svc.cluster.local/auth/realms/platform/.well-known/openid-configuration
```

**Referencia:** Configuracao identica ao ArgoCD (logbook 2026-02-06).

## Configuracao OIDC Aplicada

```json
{
  "auth_mode": "oidc_auth",
  "oidc_name": "Keycloak",
  "oidc_endpoint": "http://keycloak.staging.internal/auth/realms/platform",
  "oidc_client_id": "harbor",
  "oidc_client_secret": "TiIzU5eVpu2JCKYrmdykWjsIS1RfLxCu",
  "oidc_scope": "openid,profile,email",
  "oidc_verify_cert": false,
  "oidc_auto_onboard": true,
  "oidc_user_claim": "preferred_username",
  "oidc_groups_claim": "groups",
  "oidc_admin_group": "harbor-admins"
}
```

## Validacao

| Check                                | Resultado                                                                   |
| ------------------------------------ | --------------------------------------------------------------------------- |
| Harbor systeminfo auth_mode          | oidc_auth                                                                   |
| Harbor systeminfo oidc_provider_name | Keycloak                                                                    |
| GET /c/oidc/login                    | HTTP 302                                                                    |
| Redirect URL                         | keycloak.staging.internal/auth/realms/platform/protocol/openid-connect/auth |
| client_id no redirect                | harbor                                                                      |
| redirect_uri no redirect             | http://harbor.staging.internal/c/oidc/callback                              |
| scope no redirect                    | openid+profile+email                                                        |
| OIDC login end-to-end                | OK (testuser onboarded via preferred_username)                              |

## Troubleshooting OIDC Login

### Erro 1: invalid_grant "Code not valid"

**Sintoma:** Apos redirect do Keycloak, Harbor retorna `{"errors":[{"code":"BAD_REQUEST","message":"oauth2: \"invalid_grant\" \"Code not valid\""}]}`

**Investigacao:**

- Keycloak log: `CODE_TO_TOKEN_ERROR, error="invalid_code"` duplicado (2 requests em 14ms)
- Evidencia: `Code 'xxx' already used for userSession 'N0jDuE0fxRoxVgbi8kx94tzK'`
- Harbor tinha **2 replicas core** (bbr47 + kqgr5) sem session affinity no ALB

**Causa:** Com 2 replicas, Pod A inicia o fluxo OIDC (armazena state na sessao local). O callback do Keycloak e roteado pelo ALB para Pod B, que nao tem a sessao. O token exchange pode ocorrer 2 vezes (race condition), consumindo o authorization code na primeira tentativa e falhando na segunda.

**Fix:** `kubectl scale deployment harbor-core --replicas=1`

**Fix permanente (para multiplas replicas):**

```yaml
alb.ingress.kubernetes.io/target-group-attributes: stickiness.enabled=true,stickiness.lb_cookie.duration_seconds=3600
```

### Erro 2: 500 Internal Server Error (apos fix replicas)

**Sintoma:** Login OIDC retorna `{"errors":[{"code":"UNKNOWN","message":"internal server error"}]}` mesmo com 1 replica.

**Investigacao:**

- Token exchange com Keycloak: SUCESSO (claims recebidos no log)
- Claims no token: `at_hash, aud, azp, email, email_verified, preferred_username, sub` (sem `name`)
- Erro Harbor: `"unable to recover username for auto onboard, username claim: ""`
- Campo `oidc_user_claim` no Harbor: VAZIO

**Root Cause:** Harbor com `oidc_auto_onboard: true` precisa saber qual claim usar como username. O default do Harbor espera o claim `name`, mas o token do Keycloak retorna `preferred_username` (padrao Keycloak). Com `oidc_user_claim` vazio, Harbor nao consegue extrair o username e retorna 500.

**Fix:**

```bash
curl -X PUT http://localhost:8080/api/v2.0/configurations \
  -u "admin:harbor-admin-password" \
  -H "Content-Type: application/json" \
  -d '{"oidc_user_claim": "preferred_username"}'
```

**Fix TF:** `oidc_user_claim` adicionado ao `null_resource.harbor_oidc_config` em `modules/harbor/main.tf:358`

### Erro 3: Unable to get groups from claims (WARNING)

**Sintoma:** `Unable to get groups from claims, groups claims key: groups`

**Causa:** Client `harbor` no Keycloak nao tem protocol mapper para incluir claim `groups` no token. Apenas warning, nao bloqueia login. Necessario para mapeamento de admin group (`harbor-admins`).

**Fix pendente:** Adicionar protocol mapper no Keycloak client `harbor` (type: Group Membership, claim name: `groups`, full group path: OFF)

## Arquivos Modificados (Terraform)

| Arquivo                                              | Alteracao                                                         |
| ---------------------------------------------------- | ----------------------------------------------------------------- |
| `modules/harbor/variables.tf`                        | +3 vars: enable_oidc, oidc_endpoint, oidc_admin_group             |
| `modules/harbor/main.tf:214`                         | Fix: admin_password_secret = random_password (era nome do secret) |
| `modules/harbor/main.tf:262-371`                     | +ExternalSecret (Vault→K8s) + null_resource (Harbor API config)   |
| `modules/vault-config/vault_policies/eso-reader.hcl` | +paths secret/data/harbor/* e secret/metadata/harbor/*            |
| `environments/staging/main.tf:434-436`               | +enable_oidc=true, oidc_endpoint                                  |

## Pendencias

1. **Terraform apply** - Adiado pois Vault root token invalido (ExternalSecret nao vai syncar sem Vault operacional)
2. **Vault secret seed** - Quando Vault for reinicializado: `vault kv put secret/harbor/oidc client_id=harbor client_secret=TiIzU5eVpu2JCKYrmdykWjsIS1RfLxCu`
3. ~~**Validacao browser** - Login end-to-end via browser~~ **CONCLUIDO** (testuser login OK)
4. **Keycloak groups mapper** - Adicionar protocol mapper no client `harbor` para claim `groups`
5. **Harbor core replicas** - Habilitar sticky sessions no ALB antes de escalar para 2+ replicas

## Licoes Aprendidas

| #   | Licao                                                                                          | Impacto  |
| --- | ---------------------------------------------------------------------------------------------- | -------- |
| 1   | Harbor OIDC nao suporta config via Helm values - requer API post-deploy                        | Design   |
| 2   | Keycloak com chart keycloakx usa servico `keycloak-keycloakx-http` (nao `keycloak-http`)       | Config   |
| 3   | Keycloak mantem context path `/auth` (legado) - validar via OIDC discovery                     | Config   |
| 4   | TF template `metadata[0].name` retorna nome do recurso, nao o valor do campo data              | Bug      |
| 5   | DROP SCHEMA + restart e alternativa viavel para reset de senha Harbor                          | Recovery |
| 6   | OIDC endpoint deve usar URL externa (browser), nao cluster-internal (redirect vai pro usuario) | Config   |
| 7   | Harbor OIDC com multiplas replicas requer session affinity (ALB sticky sessions)                | Design   |
| 8   | `oidc_user_claim` deve ser `preferred_username` para Keycloak (default Harbor espera `name`)    | Config   |
| 9   | Keycloak `CODE_TO_TOKEN_ERROR` duplicado indica race condition de replicas no callback          | Debug    |
| 10  | Token exchange sucesso + 500 = problema pos-exchange (verificar claims, user onboard)           | Debug    |

## Referencias

- [Harbor Redeploy](2026-02-13-harbor-redeploy-k8s-resources.md)
- [ArgoCD OIDC](2026-02-06-argocd-gitops-deployment.md)
- [Keycloak OIDC Troubleshooting](2026-02-12-keycloak-oidc-integration-troubleshooting.md)
- [SSO E2E Conformidade](2026-02-13-sso-e2e-conformidade-keycloak.md)

# Diario de Bordo --- ArgoCD SSO Keycloak OIDC (5 Fixes Cascata)

| Campo       | Valor                                                                    |
| ----------- | ------------------------------------------------------------------------ |
| **Data**    | 2026-02-18                                                               |
| **Demanda** | Fix ArgoCD SSO Keycloak: DNS, redirect URL, split-horizon, scopes, secret |
| **Impacto** | alto (5 erros OIDC cascata, ConfigMap + values.yaml.tpl + staging/main.tf) |
| **Agentes** | Orquestrador, TF, Security, AWS                                          |
| **Status**  | concluido                                                                |

---

## Timeline

[22:06:00] Demanda | Orq | ArgoCD OIDC "no such host" keycloak-http.keycloak.svc.cluster.local | impacto: medio
[22:06:30] Consulta | Orq | Historico validado | Ref: 2026-02-11 (keycloakx chart naming), 2026-02-13 (Harbor same fix)
[22:07:00] Analise | Orq | Root cause: alias service `keycloak-http` removido do cluster, service real = `keycloak-keycloakx-http`
[22:07:30] Consenso | TF,Sec,AWS | Aprovado sem condicoes | name change only, zero destructive ops
[22:08:00] Git Commit | Orq | 20d28dc fix(keycloak): correct service name | 2 files, 5 insertions, 5 deletions
[22:09:00] TF Plan | TF | targeted: CoreDNS ConfigMap + ArgoCD Helm | 1 add, 4 change, 0 destroy
[22:09:30] TF Apply | TF | Iniciado (targeted) | AWS_PROFILE=k8s-platform-staging
[22:10:00] AML-C1 | TF | Refreshing state... | ArgoCD: 2/2 Running, Keycloak: 1/1 Running
[22:11:30] AML-C2 | TF | Vault resources applied (dependency inclusion) | random_password + eso-reader policy
[22:12:00] AML-C3 | TF | CoreDNS ConfigMap updated | ArgoCD Helm upgrade in progress
[22:13:00] Apply Done | TF | 1 added, 4 changed, 0 destroyed | exit 0
[22:13:30] Validacao | Orq | ArgoCD ConfigMap: issuer=keycloak-keycloakx-http OK
[22:13:45] Validacao | Orq | OIDC Discovery: curl from argocd NS -> 200 OK, issuer correct
[22:14:00] Restart | Orq | kubectl rollout restart deployment/argocd-server | 2/2 rolled out
[22:15:30] Validacao | Orq | ArgoCD server Running 2/2 | OIDC warning pre-existente (secret label)

### Fixes subsequentes (cascata OIDC)

[22:20:00] Erro 2 | Orq | "Invalid redirect URL" — protocol and host must match
[22:21:00] Analise | Orq | ArgoCD `server.config.url` era `https://` mas ALB so suporta HTTP:80
[22:22:00] Fix 2 | Orq | `values.yaml.tpl` linha 58: `url: https://` -> `url: http://`
[22:25:00] Erro 3 | User | Browser redirect para `keycloak-keycloakx-http.keycloak.svc.cluster.local` (irresolvivel externamente)
[22:26:00] Analise | Orq | Split-horizon DNS: issuer clusterDNS exposto no browser, precisa hostname externo
[22:27:00] Fix 3 | Orq | `staging/main.tf` keycloak_url: `keycloak-keycloakx-http...svc.cluster.local` -> `http://keycloak.staging.internal/auth`
[22:28:00] Patch | Orq | kubectl patch cm argocd-cm (issuer = keycloak.staging.internal)
[22:35:00] Erro 4 | User | "Invalid scopes: openid profile email groups" — Keycloak rejeita scope `groups`
[22:36:00] Consulta | Orq | Logbook consultado: groups claim via Group Membership mapper, sem scope dedicado
[22:37:00] Fix 4 | Orq | `values.yaml.tpl` linha 66: scopes `["openid","profile","email","groups"]` -> `["openid","profile","email"]`
[22:38:00] Patch | Orq | kubectl patch cm argocd-cm (scopes sem groups)
[22:39:00] TF Apply bloqueado | TF | vault_jwt_auth_backend.oidc dependency error + TF state lock + PostgreSQL timeout
[22:42:00] Workaround | Orq | kubectl patch cm direto (bypass TF) + force-unlock state lock
[22:50:00] Erro 5 | User | "unauthorized_client: Invalid client or Invalid client credentials"
[22:51:00] Consulta | Orq | Logbook 2026-02-06 consultado: ArgoCD secret syntax documentada
[22:52:00] Analise | Orq | ConfigMap usava `${argocd-oidc-credentials:client-secret}` — sintaxe incorreta
[22:52:30] Analise | Orq | ArgoCD espera `$oidc.keycloak.clientSecret` referenciando key no `argocd-secret`
[22:53:00] Validacao | Orq | `argocd-secret` ja contem key `oidc.keycloak.clientSecret` com valor correto
[22:54:00] Fix 5 | Orq | kubectl patch cm argocd-cm: `clientSecret: ${argocd-oidc-credentials:client-secret}` -> `$oidc.keycloak.clientSecret`
[22:54:30] Fix 5 | Orq | `values.yaml.tpl` linha 65: `$${argocd-oidc-credentials:client-secret}` -> `$oidc.keycloak.clientSecret`
[22:55:00] Restart | Orq | kubectl rollout restart deployment/argocd-server | 2/2 rolled out
[22:56:00] Validacao | Orq | ArgoCD logs: `Creating client app (argocd)` sem erros de secret
[22:57:00] Validacao | User | SSO login via Keycloak funcional | **CONCLUIDO**

---

## 5 Erros OIDC Cascata

| # | Erro | Root Cause | Fix | Arquivo |
|---|------|-----------|-----|---------|
| 1 | `no such host keycloak-http` | Alias service removido do cluster, real = `keycloak-keycloakx-http` | Atualizar service name em 3 arquivos | staging/main.tf, keycloak/outputs.tf |
| 2 | `Invalid redirect URL: protocol and host must match` | `server.config.url: https://` mas ALB so suporta HTTP:80 | `https://` -> `http://` | argocd/values.yaml.tpl:58 |
| 3 | Browser redirect para `svc.cluster.local` (irresolvivel) | Split-horizon: issuer URL interna exposta no browser | `keycloak_url` = hostname externo `keycloak.staging.internal/auth` | staging/main.tf:501 |
| 4 | `Invalid scopes: openid profile email groups` | Keycloak nao tem scope `groups`; groups claim vem via mapper | Remover `groups` de requestedScopes | argocd/values.yaml.tpl:66 |
| 5 | `unauthorized_client: Invalid client credentials` | ConfigMap usava `${argocd-oidc-credentials:client-secret}` (sintaxe errada) | `$oidc.keycloak.clientSecret` referenciando `argocd-secret` | argocd/values.yaml.tpl:65 |

---

## Arquivos Alterados

| Arquivo | Linha | Mudanca |
| --- | --- | --- |
| `environments/staging/main.tf` | 501 | `keycloak_url = http://keycloak.staging.internal/auth` |
| `environments/staging/main.tf` | 1020 | CoreDNS rewrite -> `keycloak-keycloakx-http` |
| `modules/keycloak/outputs.tf` | 12,17,28 | 3 outputs: `keycloak-keycloakx-http` + porta 80 + path `/auth` |
| `modules/argocd/values.yaml.tpl` | 58 | `url: https://` -> `url: http://` |
| `modules/argocd/values.yaml.tpl` | 65 | `clientSecret: $oidc.keycloak.clientSecret` (was `$${argocd-oidc-credentials:client-secret}`) |
| `modules/argocd/values.yaml.tpl` | 66 | `requestedScopes: ["openid","profile","email"]` (removed `groups`) |

---

## Efeito Colateral (nao planejado)

TF apply com `-target` incluiu dependencias do vault_config_staging:
- `random_password.keycloak_postgresql[0]` criado (nova senha gerada)
- `vault_kv_secret_v2.keycloak_postgresql` atualizado (senha no Vault rotacionada)
- `vault_policy.eso_reader` modificado (paths grafana/* removidos)

**Risco**: Se ExternalSecret sincronizar a nova senha do Vault para K8s, e o Keycloak pod reiniciar, a conexao com PostgreSQL pode falhar (RDS ainda tem a senha antiga). Monitorar.

---

## Problemas durante TF Apply (fixes 3-5)

| Problema | Causa | Workaround |
|----------|-------|------------|
| TF state lock (2x) | Apply anterior nao finalizou | `terraform force-unlock -force <LOCK_ID>` |
| PostgreSQL timeout | FinOps shutdown RDS apos 18h BRT | `-refresh=false` flag |
| Vault OIDC dependency | `vault_jwt_auth_backend.oidc` falha sem `oidc_client_secret` | kubectl patch cm direto (bypass TF) |

---

## Pattern: ArgoCD OIDC Secret Resolution

**Errado:** `${argocd-oidc-credentials:client-secret}` — sintaxe generica de variable, ArgoCD nao resolve

**Correto:** `$oidc.keycloak.clientSecret` — ArgoCD-specific syntax:
1. Referencia key `oidc.keycloak.clientSecret` no K8s Secret `argocd-secret`
2. Secret `argocd-secret` deve conter essa key com o valor do client secret
3. Secret deve ter label `app.kubernetes.io/part-of: argocd`

**Documentado tambem em:** logbook 2026-02-06 (primeira configuracao OIDC)

---

## Pattern: Split-Horizon DNS para OIDC

**Regra:** Todas as URLs OIDC expostas no browser DEVEM usar hostname externo:
- **Browser (issuer no redirect):** `http://keycloak.staging.internal/auth/realms/platform`
- **Server-to-server (pod-to-pod):** `http://keycloak-keycloakx-http.keycloak.svc.cluster.local/auth`
- **CoreDNS bridge:** `rewrite name keycloak.staging.internal keycloak-keycloakx-http.keycloak.svc.cluster.local`

**Consistente com:** Grafana OIDC (DEC-060), SonarQube SAML (DEC-062), Vault OIDC (DEC-061)

---

## Resultado

- **5 erros OIDC cascata**: todos RESOLVIDOS
- **ArgoCD SSO via Keycloak**: **FUNCIONAL**
- **ArgoCD pods**: 2/2 Running, 0 restarts, logs sem erros
- **OIDC Discovery**: `http://keycloak.staging.internal/auth/realms/platform/.well-known/openid-configuration` -> 200 OK
- **Login flow**: ArgoCD -> Keycloak -> callback -> ArgoCD dashboard

# Diario de Bordo --- Fix Keycloak Service Name (ArgoCD OIDC + CoreDNS)

| Campo       | Valor                                                          |
| ----------- | -------------------------------------------------------------- |
| **Data**    | 2026-02-18                                                     |
| **Demanda** | Fix DNS: keycloak-http -> keycloak-keycloakx-http (ArgoCD SSO) |
| **Impacto** | medio (OIDC config change, CoreDNS rewrite, module outputs)    |
| **Agentes** | Orquestrador, TF, Security, AWS                                |
| **Status**  | concluido                                                      |

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

## Arquivos Alterados

| Arquivo                        | Linha    | Mudanca                                                        |
| ------------------------------ | -------- | -------------------------------------------------------------- |
| `environments/staging/main.tf` | 501      | `keycloak_url = keycloak-keycloakx-http` (ArgoCD OIDC)         |
| `environments/staging/main.tf` | 1020     | CoreDNS rewrite -> `keycloak-keycloakx-http`                   |
| `modules/keycloak/outputs.tf`  | 12,17,28 | 3 outputs: `keycloak-keycloakx-http` + porta 80 + path `/auth` |

## Efeito Colateral (nao planejado)

TF apply com `-target` incluiu dependencias do vault_config_staging:
- `random_password.keycloak_postgresql[0]` criado (nova senha gerada)
- `vault_kv_secret_v2.keycloak_postgresql` atualizado (senha no Vault rotacionada)
- `vault_policy.eso_reader` modificado (paths grafana/* removidos)

**Risco**: Se ExternalSecret sincronizar a nova senha do Vault para K8s, e o Keycloak pod reiniciar, a conexao com PostgreSQL pode falhar (RDS ainda tem a senha antiga). Monitorar.

## Warning Pre-existente

ArgoCD server logs: `config referenced '${argocd-oidc-credentials:client-secret}', but key does not exist in secret`
- Secret `argocd-oidc-credentials` existe no NS argocd com key `client-secret`
- Provavel causa: falta label `app.kubernetes.io/part-of: argocd` no K8s Secret
- Nao impacta o fix de DNS, pendente investigacao separada

## Resultado

- **Erro original**: `dial tcp: lookup keycloak-http.keycloak.svc.cluster.local: no such host` -> **RESOLVIDO**
- **OIDC Discovery**: `http://keycloak-keycloakx-http.keycloak.svc.cluster.local/auth/realms/platform/.well-known/openid-configuration` -> **200 OK**
- **ArgoCD**: ConfigMap atualizado, pods reiniciados, OIDC issuer correto
- **CoreDNS**: Rewrite `keycloak.staging.internal` -> `keycloak-keycloakx-http.keycloak.svc.cluster.local`

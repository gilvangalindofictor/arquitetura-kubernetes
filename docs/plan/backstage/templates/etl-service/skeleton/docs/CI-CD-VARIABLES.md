# Variáveis CI/CD obrigatórias

Configure em **Settings → CI/CD → Variables** no repositório GitLab após o scaffold.

## Obrigatórias

| Variável | Tipo | Protected | Masked | Descrição |
|---|---|---|---|---|
| `KUBECONFIG_STAGING` | File/Var | Sim | Sim | kubeconfig em base64 do cluster EKS staging |
| `VAULT_ADDR` | Variable | Sim | Não | URL do Vault. Ex: `https://vault.staging.internal` |
| `CI_REGISTRY_USER` | Variable | Sim | Não | Harbor robot account username |
| `CI_REGISTRY_PASSWORD` | Variable | Sim | Sim | Harbor robot account token/password |

## Opcionais

| Variável | Tipo | Descrição |
|---|---|---|
| `HARBOR_CA_CERT_B64` | Variable | CA cert do Harbor em base64 (se self-signed) |
| `SONAR_TOKEN` | Variable | Token do SonarQube para quality gate |
| `VAULT_TOKEN` | Variable | Token estático do Vault — **opcional** quando Kubernetes JWT auth está ativo (padrão) |

> **Nota sobre autenticação no Vault:** O pipeline usa `CI_JOB_JWT` para autenticar no Vault via `auth/kubernetes/login`, tornando `VAULT_TOKEN` desnecessário no fluxo padrão. A variável `VAULT_TOKEN` só é necessária em cenários de bootstrap (antes do Kubernetes auth estar configurado) ou debug local.

## Configuração das Credenciais das Originadoras (Vault)

Antes do primeiro push para `staging`, configure as credenciais de cada originadora no Vault:

```bash
# Para cada originadora declarada no template:
vault kv put secret/staging/${{ values.name }}/{secretKeyRef} \
  username="USUARIO_REAL" \
  password="SENHA_REAL"

# Exemplo para aspbras:
vault kv put secret/staging/${{ values.name }}/aspbras \
  username="usuario_aspbras" \
  password="senha_aspbras"
```

## Fluxo de deploy

1. Faça push para branch `staging` (após merge do MR)
2. Pipeline executa: validate → test → build → provision → migrate → deploy
3. O stage `provision` cria automaticamente o namespace, Vault paths para DB/Redis/Keycloak, e aplica o ExternalSecret
4. O stage `deploy` faz `helm upgrade` com a imagem `harbor.staging.internal/data/${{ values.name }}:$CI_COMMIT_SHA`
5. Verifique o deploy: `kubectl get pods -n staging-data-${{ values.name }}`

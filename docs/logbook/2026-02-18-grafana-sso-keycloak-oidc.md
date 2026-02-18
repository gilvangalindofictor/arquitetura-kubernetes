# Diario de Bordo - Grafana SSO via Keycloak OIDC

| Campo       | Valor                                                    |
| ----------- | -------------------------------------------------------- |
| **Data**    | 2026-02-18                                               |
| **Demanda** | Integração Grafana ↔ Keycloak via OIDC (auth.generic_oauth) |
| **Impacto** | médio — plataforma de observabilidade com SSO            |
| **Agentes** | Orquestrador, TF Specialist                              |
| **Status**  | ✅ Concluído                                             |

---

## Diagnóstico Inicial

Verificação da integração SSO Grafana ↔ Keycloak revelou que **não estava implementada**.

| Serviço | SSO Status Pré-Sessão |
| ------- | --------------------- |
| Grafana | `adminPassword` puro — sem OIDC |
| Keycloak client `grafana` | **Já existia** no realm `platform` (redirectUris: localhost:3000 + amazonaws.com) |

---

## Implementação Terraform

### Arquivos Modificados

**1. `modules/kube-prometheus-stack/versions.tf`**
- Adicionado provider `gavinbunney/kubectl ~> 1.14` para suportar `kubectl_manifest`

**2. `modules/kube-prometheus-stack/variables.tf`**
- Adicionadas 4 variáveis OIDC:
  - `grafana_oidc_enabled` (bool, default: false)
  - `grafana_keycloak_url` (string)
  - `grafana_keycloak_client_id` (string, default: "grafana")
  - `grafana_keycloak_client_secret` (string, sensitive)

**3. `modules/kube-prometheus-stack/main.tf`**
- 10 `dynamic "set"` blocks para `auth.generic_oauth` no helm_release
- Recurso `kubectl_manifest.grafana_oidc_externalsecret` para ExternalSecret

**4. `environments/staging/main.tf`**
- Ativado `grafana_oidc_enabled = true`
- `grafana_keycloak_url = "http://keycloak.staging.internal/auth"`

### ExternalSecret criado via Terraform

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: grafana-oidc-credentials
  namespace: monitoring
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: grafana-oidc-credentials
    creationPolicy: Owner
  data:
    - secretKey: client_id
      remoteRef:
        key: secret/data/grafana/oidc
        property: client_id
    - secretKey: client_secret
      remoteRef:
        key: secret/data/grafana/oidc
        property: client_secret
```

---

## Vault — Seed de Credenciais

```bash
# Vault port-forward
kubectl port-forward -n vault-system svc/vault 8200:8200 &

# Seed secret/grafana/oidc
vault kv put secret/grafana/oidc \
  client_id=grafana \
  client_secret=I4wY1xGwxMnTbWjRxVQZ7zk0gIJBUvjB
```

### Vault Policy eso-reader — Atualizada

Adicionados paths para `grafana`:
```hcl
path "secret/data/grafana/*"     { capabilities = ["read"] }
path "secret/metadata/grafana/*" { capabilities = ["list"] }
```

---

## Keycloak — Client grafana Atualizado

Client `grafana` no realm `platform` já existia. Adicionada redirect URI:
```
http://grafana.staging.internal/login/generic_oauth
```

Via API com python3 urllib (curl falha com chars especiais na senha admin `Qq!Tp?Q=xmCmj5zGbzIW>kno`):
```python
import urllib.request, urllib.parse, json

# Get admin token
data = urllib.parse.urlencode({...}).encode()
req = urllib.request.Request('http://localhost:8080/auth/realms/master/protocol/openid-connect/token', data=data)
with urllib.request.urlopen(req) as r:
    token = json.loads(r.read())['access_token']
```

---

## Problemas Encontrados e Soluções

### 1. `assertNoLeakedSecrets` — Helm Chart Block

**Sintoma:** `helm upgrade` falhou com erro sobre `client_secret` em plain values.

**Causa:** kube-prometheus-stack chart bloqueia qualquer campo `*secret*` nos values de `grafana.ini` para evitar vazamento em ConfigMaps.

**Solução:** Usar `envValueFrom` em vez de valor direto na ini section:

```yaml
grafana:
  envValueFrom:
    GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET:
      secretKeyRef:
        name: grafana-oidc-credentials
        key: client_secret
```

A variável de ambiente `GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET` é lida diretamente pelo Grafana como override de `[auth.generic_oauth] client_secret`.

---

### 2. `${client_secret}` — Variável Não Expandida

**Sintoma:** Grafana recebia `${client_secret}` literal na ini, autenticação falhava.

**Causa:** Grafana `grafana.ini` variable expansion requer que o secret esteja acessível via `[section] client_secret = ${ENV_VAR}`, mas o chart intercepta o valor antes.

**Solução:** Usar env var direta `GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET` (formato `GF_<SECTION>_<KEY>` sobrescreve qualquer valor da ini).

---

### 3. Browser recebe URL `svc.cluster.local` — Redirect OIDC Falhou

**Sintoma:**
```
http://keycloak.keycloak.svc.cluster.local/realms/platform/protocol/openid-connect/auth?redirect_uri=...
```
Browser não resolve `.svc.cluster.local` → falha na autenticação.

**Causa:** `auth_url`/`token_url` configurados com endpoint K8s interno (`keycloak.keycloak.svc.cluster.local`). O Grafana usa essas URLs tanto para server-to-server quanto para redirecionar o browser.

**Solução:** Usar hostname externo para TODAS as URLs OIDC:

```yaml
grafana_keycloak_url = "http://keycloak.staging.internal/auth"
# → auth_url:  http://keycloak.staging.internal/auth/realms/platform/protocol/openid-connect/auth
# → token_url: http://keycloak.staging.internal/auth/realms/platform/protocol/openid-connect/token
# → api_url:   http://keycloak.staging.internal/auth/realms/platform/protocol/openid-connect/userinfo
```

> **Padrão geral:** Para qualquer serviço OIDC cujo browser precisa ser redirecionado para o IdP, SEMPRE usar hostname externo (resolvível pelo browser) em ALL OIDC URLs — mesmo que server-to-server poderia usar internal.

---

### 4. PVC ReadWriteOnce — Rolling Update Deadlock

**Sintoma:** Novo pod Grafana ficou em `Init:0/1` indefinidamente. PVC preso no pod antigo.

**Causa:** Grafana usa `updateStrategy: RollingUpdate` com PVC `ReadWriteOnce`. Novo pod não consegue montar o volume enquanto o pod antigo está ativo.

**Solução:**
```bash
kubectl scale deploy kube-prometheus-stack-grafana -n monitoring --replicas=0
kubectl scale deploy kube-prometheus-stack-grafana -n monitoring --replicas=1
```

---

### 5. `--set` Falha com `role_attribute_path` Complexo

**Sintoma:** `helm upgrade --set grafana."grafana\.ini"."auth\.generic_oauth".role_attribute_path=...` falhou.

**Causa:** Valor contém espaços, colchetes e `||` que quebram parsing do `--set`.

**Solução:** Sempre usar `-f /tmp/values.yaml` para valores complexos.

---

### 6. Curl com Senha Especial — Falha de Autenticação

**Sintoma:** `curl` com `--data-urlencode` falhou com chars especiais (`!`, `?`, `=`, `>`).

**Solução:** Usar python3 urllib.request que faz encoding correto automaticamente:
```bash
# Keycloak auth base URL (Quarkus): DEVE incluir /auth (KC_HTTP_RELATIVE_PATH)
# CORRETO: http://localhost:8080/auth/realms/master/...
# ERRADO:  http://localhost:8080/realms/master/...
```

---

## Configuração Final (helm upgrade aplicado)

```yaml
# /tmp/grafana-oidc-values.yaml
grafana:
  envValueFrom:
    GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET:
      secretKeyRef:
        name: grafana-oidc-credentials
        key: client_secret
  grafana.ini:
    server:
      root_url: "http://grafana.staging.internal"
    auth.generic_oauth:
      enabled: true
      name: Keycloak
      client_id: grafana
      scopes: "openid email profile"
      auth_url: "http://keycloak.staging.internal/auth/realms/platform/protocol/openid-connect/auth"
      token_url: "http://keycloak.staging.internal/auth/realms/platform/protocol/openid-connect/token"
      api_url: "http://keycloak.staging.internal/auth/realms/platform/protocol/openid-connect/userinfo"
      role_attribute_path: "contains(groups[*], 'grafana-admins') && 'Admin' || 'Viewer'"
      allow_sign_up: true
```

---

## Validação

```bash
# Pod status
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana
# kube-prometheus-stack-grafana-dfd6dffdc-4tjvp   3/3   Running

# OIDC redirect check
kubectl exec -n monitoring deploy/kube-prometheus-stack-grafana -c grafana -- \
  wget -S --spider http://localhost:3000/login/generic_oauth 2>&1 | grep "Location:"
# Location: http://keycloak.staging.internal/auth/realms/platform/protocol/openid-connect/auth
#   ?client_id=grafana
#   &redirect_uri=http%3A%2F%2Fgrafana.staging.internal%2Flogin%2Fgeneric_oauth
#   &response_type=code
#   &scope=openid+email+profile
```

✅ Redirect URI correto: `http://grafana.staging.internal/login/generic_oauth` (sem porta 3000, sem svc.cluster.local)

---

## Próximos Passos

1. **Criar grupo Keycloak `grafana-admins`**: usuários neste grupo recebem role `Admin` automaticamente
2. **Committar terraform**: modules/kube-prometheus-stack (versions.tf, variables.tf, main.tf) + environments/staging/main.tf

---

## Referências

- [2026-02-13-sso-e2e-conformidade-keycloak.md](2026-02-13-sso-e2e-conformidade-keycloak.md) — padrão svc.cluster.local issue documentado
- [2026-02-13-harbor-oidc-keycloak-integration.md](2026-02-13-harbor-oidc-keycloak-integration.md) — padrão similar Harbor OIDC

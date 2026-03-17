# Runbook: Rotação do Robot Account harbor-registry-secret

**Categoria**: Security / Secrets Management
**Prioridade**: P1
**Componentes**: Harbor, Vault KV, ExternalSecrets Operator
**Última atualização**: 2026-03-17
**Ref. demanda**: docs/demands/2026-03-17-eso-harbor-registry-secret.md

---

## Contexto

O robot account `robot$gitlab-ci` no Harbor é a credencial usada por todos os workloads
para pull de imagens do registry `harbor.staging.internal`. O token é gerenciado centralmente
no Vault KV path `secret/harbor/robot-account` e propagado automaticamente via ExternalSecrets
Operator para os namespaces de aplicação.

**Namespaces com harbor-registry-secret gerenciado por ESO:**

| Namespace | ExternalSecret | Vault path | Status |
|-----------|---------------|-----------|--------|
| staging-platform-backstage | harbor-registry-secret | secret/harbor/robot-account | SecretSynced |
| staging-data-hatch-etl | harbor-registry-secret-sync | secret/staging/hatch-etl/harbor-ci | SecretSynced (robot$hatch-etl-ci — robot separado) |

---

## SOP: Rotação do robot$gitlab-ci

### Pré-condições

- Acesso ao Harbor UI com conta admin
- Acesso ao Vault (root token ou token com permissão `secret/harbor/*` write)
- `kubectl` com contexto apontando para o cluster staging

### Passo 1 — Regenerar token no Harbor

1. Acesse Harbor UI: `https://harbor.staging.internal`
2. Navegue em: **Administration > Robot Accounts**
3. Localize `robot$gitlab-ci`
4. Clique em **...** > **Reset Secret**
5. Copie o novo token (exibido apenas uma vez)

### Passo 2 — Atualizar o Vault

```bash
# Port-forward para o Vault (se necessário)
kubectl port-forward -n staging-security-vault vault-0 8200:8200 &

export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=<token-com-permissao-write>

# Atualizar apenas o campo secret (preservar os demais campos)
vault kv patch secret/harbor/robot-account secret="<NOVO_TOKEN>"

# Verificar
vault kv get secret/harbor/robot-account
```

### Passo 3 — Forçar sync imediato (opcional — ESO sincroniza em até 1h)

```bash
# Para staging-platform-backstage
kubectl annotate externalsecret harbor-registry-secret \
  force-sync=$(date +%s) --overwrite \
  -n staging-platform-backstage

# Aguardar sync (normalmente < 30s)
kubectl get externalsecret harbor-registry-secret \
  -n staging-platform-backstage \
  -o jsonpath='{.status.conditions[0].reason}{" "}{.status.refreshTime}'
```

### Passo 4 — Validar

```bash
# Verificar que o secret foi atualizado
kubectl get secret harbor-registry-secret -n staging-platform-backstage \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | python3 -c "
import json, sys
d = json.load(sys.stdin)
for server, creds in d['auths'].items():
    print('server:', server)
    print('username:', creds.get('username'))
    print('auth present:', bool(creds.get('auth')))
"

# Verificar pods em execução (não devem estar em ImagePullBackOff)
kubectl get pods -n staging-platform-backstage
```

---

## SOP: Diagnóstico de ImagePullBackOff relacionado ao Harbor

### Sintomas

- Pod em estado `ImagePullBackOff` ou `ErrImagePull`
- Mensagem de erro: `unauthorized: authentication required` ou `invalid username/password`

### Diagnóstico rápido

```bash
# 1. Verificar status do ExternalSecret
kubectl get externalsecret harbor-registry-secret -n <NAMESPACE>

# 2. Verificar se o secret tem ownerReference (gerenciado por ESO)
kubectl get secret harbor-registry-secret -n <NAMESPACE> \
  -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}'
# Esperado: ExternalSecret/harbor-registry-secret

# 3. Verificar conteúdo do secret
kubectl get secret harbor-registry-secret -n <NAMESPACE> \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | python3 -m json.tool

# 4. Forçar sync do ESO
kubectl annotate externalsecret harbor-registry-secret \
  force-sync=$(date +%s) --overwrite -n <NAMESPACE>
```

### Se o ExternalSecret estiver com erro (não SecretSynced)

```bash
# Verificar mensagem de erro
kubectl describe externalsecret harbor-registry-secret -n <NAMESPACE>

# Verificar se o Vault path existe e tem as chaves corretas
kubectl exec -n staging-security-vault vault-0 -- \
  env VAULT_ADDR=http://127.0.0.1:8200 \
  vault kv get secret/harbor/robot-account
# Esperado: keys 'name' e 'secret' presentes

# Verificar se ClusterSecretStore está Ready
kubectl get clustersecretstore vault-backend \
  -o jsonpath='{.status.conditions[0].type}{" "}{.status.conditions[0].status}'
# Esperado: Ready True
```

---

## Adicionando novos namespaces

Para adicionar suporte ao `harbor-registry-secret` em um novo namespace:

```bash
# 1. Copiar o manifesto base
cp platform-provisioning/aws/kubernetes/manifests/externalsecrets/harbor-registry-secret-backstage.yaml \
   platform-provisioning/aws/kubernetes/manifests/externalsecrets/harbor-registry-secret-<NOVO-NS>.yaml

# 2. Editar o namespace no arquivo
# Atualizar: metadata.namespace: <NOVO-NS>

# 3. Aplicar
kubectl apply -f platform-provisioning/aws/kubernetes/manifests/externalsecrets/harbor-registry-secret-<NOVO-NS>.yaml

# 4. Aguardar sync
kubectl get externalsecret harbor-registry-secret -n <NOVO-NS> -w
```

---

## Vault path de referência

```
secret/harbor/robot-account:
  name:   robot$gitlab-ci          # username do robot account
  secret: <token-atual-32-chars>   # token gerado pelo Harbor
```

Nota: o path usa `name` e `secret` (não `username`/`password`) — keys definidas
pelo operador ao popular o Vault em 2026-03-17. O template do ExternalSecret mapeia:
- `name` → variável `robotName`
- `secret` → variável `robotSecret`

---

## Histórico de incidentes

| Data | Evento | Resolução |
|------|--------|-----------|
| 2026-03-17 | Token expirado → Backstage ImagePullBackOff | Token regenerado no Harbor, atualizado no Vault, ESO criado |

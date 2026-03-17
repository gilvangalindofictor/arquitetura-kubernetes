# Demanda: ESO Dedicado para harbor-registry-secret

**Data**: 2026-03-17
**Prioridade**: P1
**Tipo**: Security / Infrastructure
**Componentes afetados**: ExternalSecrets Operator, Vault KV, Harbor (robot$gitlab-ci), staging-platform-backstage, demais namespaces com imagePullSecret manual
**Origem**: Mesa Técnica — Sessão de Health Check 2026-03-17
**ADRs relacionados**: ADR-101 (Secrets Migration Vault + ExternalSecrets)

---

## 1. Contexto e Motivação

Em 2026-03-17, o Backstage (namespace `staging-platform-backstage`) ficou com falha de pull de imagens
porque o `harbor-registry-secret` estava com credenciais expiradas. O robot account `robot$gitlab-ci`
no Harbor havia sido regenerado e o secret Kubernetes **não foi atualizado automaticamente** — exigindo
intervenção manual de emergência.

O token foi corrigido manualmente (token: `wIXJr1f2IixiaeGQYM709OfE8T3UBxnr`) e armazenado no Vault
em `secret/harbor/robot-account`. Porém, o `harbor-registry-secret` continua como plain K8s Secret,
sem nenhum ExternalSecret gerenciando sua sincronização.

Adicionalmente, o mesmo padrão de risco pode existir em outros namespaces que utilizam
`harbor-registry-secret` como `imagePullSecret` criado manualmente.

---

## 2. Problema Atual

| Item | Descrição | Risco |
|------|-----------|-------|
| Secret manual | `harbor-registry-secret` em `staging-platform-backstage` é plain K8s Secret | Qualquer rotação do robot$gitlab-ci quebra pulls de imagem silenciosamente |
| Sem owner | Nenhum ExternalSecret como owner do secret | Secret não é recriado automaticamente se deletado ou corrompido |
| Sem sincronização | Rotação no Vault não propaga para o cluster | Operador deve lembrar de atualizar manualmente cada namespace |
| Escopo desconhecido | Outros namespaces podem ter o mesmo `harbor-registry-secret` manual | Auditoria necessária para mapear a superfície total de exposição |
| Sem alerta | Não há PrometheusRule para `harbor-registry-secret` desatualizado ou falha de pull | Falha silenciosa: workloads em `ImagePullBackOff` sem alerta |

O `ClusterSecretStore` `vault-backend` está operacional e já gerencia 15+ ExternalSecrets no cluster.
A infraestrutura de sincronização existe; falta apenas o ExternalSecret específico para o secret de
registry do Harbor.

---

## 3. Solução Proposta

### Fase 1 — Auditoria de namespaces afetados

Identificar todos os namespaces com `harbor-registry-secret` criado manualmente:

```bash
kubectl get secrets --all-namespaces \
  --field-selector type=kubernetes.io/dockerconfigjson \
  -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].kind" \
  | grep harbor-registry
```

Namespaces suspeitos (além de `staging-platform-backstage`):
- `staging-platform-harbor` (exporter)
- `staging-data-hatch-etl`
- `staging-platform-gitlab` (CI runners)
- Qualquer namespace com workloads que pull do Harbor

### Fase 2 — Vault KV consolidado

Garantir que o Vault path `secret/harbor/robot-account` contenha as chaves necessárias para
reconstruir o `.dockerconfigjson`:

```
secret/harbor/robot-account:
  username: "robot$gitlab-ci"
  password: "<token-atual>"
  server:   "harbor.staging.internal"   # ou FQDN do Harbor
```

Política `eso-reader` deve ter permissão de leitura no path `secret/harbor/*`.

### Fase 3 — ExternalSecret por namespace

Criar um ExternalSecret em cada namespace afetado. Template base:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: harbor-registry-secret
  namespace: <NAMESPACE>
  labels:
    app.kubernetes.io/managed-by: external-secrets
    environment: staging
    tier: registry
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: harbor-registry-secret
    creationPolicy: Owner
    deletionPolicy: Retain
    template:
      type: kubernetes.io/dockerconfigjson
      data:
        .dockerconfigjson: |
          {
            "auths": {
              "{{ .server }}": {
                "username": "{{ .username }}",
                "password": "{{ .password }}",
                "auth": "{{ printf "%s:%s" .username .password | b64enc }}"
              }
            }
          }
  data:
    - secretKey: username
      remoteRef:
        key: secret/data/harbor/robot-account
        property: username
    - secretKey: password
      remoteRef:
        key: secret/data/harbor/robot-account
        property: password
    - secretKey: server
      remoteRef:
        key: secret/data/harbor/robot-account
        property: server
```

### Fase 4 — Procedimento de migração (sem downtime)

Para cada namespace:

1. Aplicar o ExternalSecret (`kubectl apply -f harbor-registry-secret-<ns>.yaml`)
2. Aguardar o ESO criar o novo secret com `ownerReference` correto (~30s)
3. Verificar: `kubectl get externalsecret harbor-registry-secret -n <NAMESPACE>`
4. Verificar: `kubectl get secret harbor-registry-secret -n <NAMESPACE> -o json | jq .metadata.ownerReferences`
5. Se o secret já existia manualmente: deletar o plain secret para transferir ownership
   ```bash
   kubectl delete secret harbor-registry-secret -n <NAMESPACE>
   # ESO vai recriar automaticamente via ownerReference
   ```
6. Testar pull de imagem: `kubectl run test --image=harbor.staging.internal/... --restart=Never -n <NAMESPACE>`

### Fase 5 — Procedimento de rotação futura (protocolo)

Com o ESO ativo, a rotação do robot$gitlab-ci passa a ser:

1. Regenerar token no Harbor UI
2. `vault kv put secret/harbor/robot-account password="<novo-token>"`
3. Aguardar `refreshInterval` (1h) ou forçar sync:
   ```bash
   kubectl annotate externalsecret harbor-registry-secret \
     force-sync=$(date +%s) --overwrite -n <NAMESPACE>
   ```
4. Zero intervenção manual nos K8s Secrets

---

## 4. Artefatos a Criar

```
platform-provisioning/aws/kubernetes/manifests/externalsecrets/
  harbor-registry-secret-backstage.yaml          # staging-platform-backstage
  harbor-registry-secret-hatch-etl.yaml          # staging-data-hatch-etl
  harbor-registry-secret-<ns>.yaml               # demais namespaces (pós-auditoria)

docs/runbooks/
  harbor-robot-account-rotation.md               # SOP: rotação do robot$gitlab-ci
```

Vault (não é arquivo, mas é artefato de configuração):
- `secret/harbor/robot-account` com keys: `username`, `password`, `server`
- Policy `eso-reader`: adicionar permissão `secret/harbor/*`

---

## 5. Critérios de Aceite

| Gate | Como verificar |
|------|----------------|
| Auditoria completa | Lista de todos os namespaces com `harbor-registry-secret` levantada e documentada |
| Vault path populado | `vault kv get secret/harbor/robot-account` retorna username, password, server |
| Policy eso-reader atualizada | `vault policy read eso-reader` inclui `secret/harbor/*` com capability `read` |
| ExternalSecret `staging-platform-backstage` | `kubectl get externalsecret harbor-registry-secret -n staging-platform-backstage` → `SecretSynced: True` |
| ownerReference presente | `kubectl get secret harbor-registry-secret -n staging-platform-backstage -o json` → ownerReference aponta para ExternalSecret |
| Zero plain secrets residuais | Nenhum `harbor-registry-secret` sem ownerReference em namespaces de aplicação |
| Rotação validada | Trocar password no Vault → aguardar sync → confirmar novo `.dockerconfigjson` nos secrets |
| Runbook publicado | `docs/runbooks/harbor-robot-account-rotation.md` existente com SOP completo |

---

## 6. Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|--------------|---------|-----------|
| Downtime durante migração se plain secret deletado antes do ESO criar | Média | Alto | Aplicar ESO primeiro, aguardar `SecretSynced: True` ANTES de deletar o plain secret |
| `deletionPolicy: Retain` pode deixar secret orfão se ESO for deletado | Baixa | Médio | Documentar: ao remover ESO, deletar manualmente o secret ou migrar para outro owner |
| Template `.dockerconfigjson` mal formado quebra pull de imagens | Baixa | Alto | Validar template com `kubectl run` em namespace de teste antes de aplicar em produção |
| Vault path `secret/harbor/robot-account` com chaves erradas (key mismatch) | Baixa | Alto | Testar ExternalSecret em staging-platform-backstage primeiro (menor blast radius) |
| Outros namespaces não mapeados na auditoria | Média | Médio | Implementar PrometheusAlert para `ImagePullBackOff` com label de namespace → detectar pós-rotação |
| `eso-reader` policy sem permissão no novo path | Média | Alto | Verificar policy ANTES de aplicar os ExternalSecrets; atualizar via `vault policy write` |

---

## 7. Estimativa de Esforço

| Fase | Complexidade | Horas estimadas |
|------|-------------|----------------|
| Fase 1 — Auditoria de namespaces | Baixa | 0.5h |
| Fase 2 — Vault KV + policy | Baixa | 0.5h |
| Fase 3+4 — ExternalSecrets + migração (por namespace) | Baixa | 0.5h/namespace |
| Fase 5 — Runbook + validação E2E rotação | Baixa | 1h |
| **Total estimado (4 namespaces)** | **Baixa** | **~4h** |

---

## 8. Dependências

| Dependência | Status | Bloqueador? |
|-------------|--------|-------------|
| ClusterSecretStore `vault-backend` operacional | Ativo — SecretSynced True em 15+ ESOs | Não |
| Vault KV v2 engine em `secret/` | Ativo | Não |
| Vault policy `eso-reader` modificável | Disponível via root token (ver CREDENTIALS.md — não versionado) | Não |
| Harbor robot$gitlab-ci token armazenado no Vault | Armazenado em `secret/harbor/robot-account` (2026-03-17) | Não |
| Acesso ao cluster (AWS SSO k8s-platform-prod) | Disponível | Não |
| Janela de manutenção para namespaces críticos | Necessária para staging-platform-gitlab se aplicável | Condicional |

**Pré-requisito de execução**: Nenhum bloqueador técnico. Pode ser executado imediatamente após
abertura de janela de manutenção (baixo risco — sem downtime esperado se procedimento seguido).

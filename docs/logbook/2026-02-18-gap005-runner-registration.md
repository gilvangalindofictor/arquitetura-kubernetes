# GAP-005: GitLab Runner Registration — Authentication Token (2026-02-18)

**Data:** 2026-02-18
**Duração:** ~45min
**Status:** ✅ Completo — Runner `id=115` online
**Agente:** Claude Code (executor-terraform.md framework)

---

## Contexto

GAP-005 estava bloqueado desde 2026-02-13:
- `runner-token`: vazio (precisava de authentication token GitLab 17.x)
- `runner-registration-token`: deprecated no GitLab 17.x (retornava 500)
- `REGISTER_LOCKED=false`: env var incompatível com authentication tokens

## Root Causes Identificados

### 1. Registration Token Deprecated (GitLab 17.x)
```
POST /api/v4/runners → 500 Internal Server Error
```
GitLab 17.x removeu suporte a `runner-registration-token` para registro.
Requer criação de **authentication token** via API/UI.

### 2. REGISTER_LOCKED env var (Helm chart 0.71.0 incompatibility)
```
FATAL: Runner configuration [...] cannot be specified when registering with a
runner authentication token. (--locked, --tag-list, --run-untagged, etc.)
```
O Helm chart (gitlab-runner 0.71.0) gera `REGISTER_LOCKED=false` como env var
por padrão, mesmo quando `runners.locked` não está explicitamente configurado.
GitLab Runner 17.6.0 recusa esses flags ao usar authentication tokens (glrt-*).

## Solução Aplicada

### Step 1: PAT via Rails Runner (admin acesso)
```bash
kubectl port-forward -n gitlab-staging svc/gitlab-webservice-default 18080:8080 &
kubectl exec -n gitlab-staging gitlab-webservice-default-6869cb4ddd-sbpjj -c webservice -- \
  /srv/gitlab/bin/rails runner \
  "token = User.find_by_username('root').personal_access_tokens.create!(
    scopes: ['api','read_user'], name: 'runner-setup-token', expires_at: 7.days.from_now
  ); puts token.token"
# → GITLAB_PAT_REDACTED
```

### Step 2: Runner Authentication Token (GitLab 17.x new workflow)
```bash
PAT="GITLAB_PAT_REDACTED"
curl -X POST "http://localhost:18080/api/v4/user/runners" \
  -H "PRIVATE-TOKEN: ${PAT}" \
  -H "Content-Type: application/json" \
  -d '{"runner_type":"instance_type","description":"k8s-staging-runner",
       "tag_list":"k8s,staging,docker","run_untagged":true,"locked":false}'
# → {"id":115,"token":"glrt-t1_HhPp1xksgJsLFmBJeX_W","token_expires_at":null}
```

### Step 3: Atualizar Secret
```bash
kubectl create secret generic gitlab-gitlab-runner-secret \
  -n gitlab-staging \
  --from-literal=runner-registration-token="" \
  --from-literal=runner-token="glrt-t1_HhPp1xksgJsLFmBJeX_W" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Step 4: Scale Up + Patch REGISTER_LOCKED
```bash
kubectl scale deployment gitlab-gitlab-runner -n gitlab-staging --replicas=1

# Remover REGISTER_LOCKED env var (índice 2 no array de envs)
kubectl patch deployment gitlab-gitlab-runner -n gitlab-staging --type='json' -p='[
  {"op": "remove", "path": "/spec/template/spec/containers/0/env/2"}
]'
```

## Resultado

```
Pod: gitlab-gitlab-runner-5485bdbff6-4dndx — 1/1 Running (0 restarts)

API validation:
  ID:          115
  Name:        k8s-staging-runner
  Status:      online
  Online:      True
  Active:      True
  Runner type: instance_type
  Tags:        ['k8s', 'staging', 'docker']
  Run untagged: True
```

## Fixes Terraform Persistidos

**`modules/gitlab/values.yaml.tpl`:**
- `gitlabUrl`: corrigido namespace `gitlab` → `gitlab-staging`
- `runners.config`: `namespace = "gitlab"` → `namespace = "gitlab-staging"`
- Documentação do workaround REGISTER_LOCKED

## Próximos Passos GAP-005 (restante)

| Item | Esforço | Status |
|------|---------|--------|
| ~~Runner registration~~ | ~~1h~~ | ✅ Done |
| CI/CD variables (Harbor, SonarQube secrets) | 30min | ⏸️ Pendente |
| `.gitlab-ci.yml` templates (build, test, scan, deploy) | 1h | ⏸️ Pendente |
| Runner RBAC least-privilege | 30min | ⏸️ Pendente |
| Validação pipeline end-to-end | 30min | ⏸️ Pendente |

**GAP-005: 40% completo** (registration resolvido, integração CI/CD pendente)

---

## Lições Aprendidas

1. **GitLab 17.x breaking change**: `runners.locked`, `run_untagged`, `tag_list`
   são configurados **server-side** ao criar o runner, não no momento do register.
   O Helm chart 0.71.0 ainda gera esses env vars — workaround: `kubectl patch`.

2. **Rails Runner para PAT admin**: Único método confiável quando OAuth endpoint
   retorna vazio (GitLab com OmniAuth OIDC habilitado bloqueia resource owner flow).

3. **API endpoint novo**: `POST /api/v4/user/runners` (não mais `/api/v4/runners`).

---

_Executado: 2026-02-18 | Duração: ~45min | Runner ID: 115_

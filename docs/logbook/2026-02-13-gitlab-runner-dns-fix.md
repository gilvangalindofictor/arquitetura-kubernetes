# GitLab Runner DNS Fix

**Data**: 2026-02-13
**Tipo**: Quick Fix
**Duração**: 5 minutos
**Status**: ✅ Completo (DNS), ⚠️ Requer authentication token

---

## 📋 Contexto

GitLab Runner estava em CrashLoopBackOff (220 restarts) com erro DNS:
```
dial tcp: lookup gitlab-webservice-default.gitlab.svc.cluster.local on 172.20.0.10:53:
no such host
```

## 🔍 Root Cause

`CI_SERVER_URL` configurado com **namespace incorreto**:
- ❌ Errado: `gitlab-webservice-default.gitlab.svc.cluster.local` (namespace `gitlab`)
- ✅ Correto: `gitlab-webservice-default.gitlab-staging.svc.cluster.local` (namespace `gitlab-staging`)

## ✅ Solução Aplicada

```bash
# Fix CI_SERVER_URL environment variable
kubectl set env deployment/gitlab-gitlab-runner -n gitlab-staging \
  CI_SERVER_URL=http://gitlab-webservice-default.gitlab-staging.svc.cluster.local:8080

# Restart deployment
kubectl rollout restart deployment/gitlab-gitlab-runner -n gitlab-staging
```

**Resultado:**
- ✅ DNS resolution: OK
- ✅ Pod status: Running
- ⚠️ Registration: Falha 500 (expected - registration token deprecated)

## 📊 Status Atual

```
NAME                                    READY   STATUS    RESTARTS   AGE
gitlab-gitlab-runner-687788bcdc-jshft   0/1     Running   0          2m
```

**Erro atual (esperado):**
```
ERROR: Registering runner... failed
status=POST http://gitlab-webservice-default.gitlab-staging.svc.cluster.local:8080/api/v4/runners:
500 Internal Server Error
```

## ⚠️ Próximos Passos

### GitLab 17.x Registration Workflow

GitLab 17.x **deprecou registration tokens**. Requer authentication tokens criados via UI:

1. **Acessar GitLab Admin UI**
   ```bash
   kubectl port-forward -n gitlab-staging svc/gitlab-webservice-default 8080:8080
   # Browser: http://localhost:8080
   ```

2. **Criar Authentication Token**
   - Admin Area → CI/CD → Runners
   - Click "New instance runner"
   - Copy authentication token

3. **Atualizar Secret**
   ```bash
   kubectl create secret generic gitlab-gitlab-runner-secret \
     -n gitlab-staging \
     --from-literal=runner-registration-token="" \
     --from-literal=runner-token="<NEW_AUTH_TOKEN>" \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

4. **Restart Runner**
   ```bash
   kubectl rollout restart deployment/gitlab-gitlab-runner -n gitlab-staging
   ```

## 📝 Documentação

**Referência:** [GitLab Runner Authentication Tokens](https://docs.gitlab.com/ee/ci/runners/new_creation_workflow)

**ADR:** Nenhum (quick fix operacional)

**Logbook GAP-002:** [2026-02-06-gitlab-components-fix.md](2026-02-06-gitlab-components-fix.md)

---

## ✅ GAP-002 Status Final

| Componente | Status | Fix Date |
|------------|--------|----------|
| Gitaly | ✅ Running | 2026-02-06 |
| KAS | ✅ Running | 2026-02-06 |
| Sidekiq | ✅ Running | 2026-02-06 |
| Webservice | ✅ Running | 2026-02-06 |
| Runner (DNS) | ✅ Fixed | 2026-02-13 |
| Runner (Registration) | ⏸️ Deferred to GAP-005 | - |

**GAP-002: ✅ 95% COMPLETO**

Runner registration é parte do **GAP-005 (GitLab CI/CD Integration)** e requer:
- GitLab Admin UI access
- Authentication token creation
- CI/CD variables configuration
- Pipeline templates

---

_Fix aplicado em: 2026-02-13 14:30 BRT | Duração: 5min_

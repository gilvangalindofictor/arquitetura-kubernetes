# GitLab KAS/Runner Recovery - Redis DNS + RDB Persist Fix

**Data:** 2026-02-13 18:00-18:20 BRT
**Duração:** 20 minutos troubleshooting
**Executor:** Orquestrador DevOps
**Cluster:** k8s-platform-prod (EKS 1.34)

---

## 🎯 OBJETIVO

Resolver GitLab KAS (0/1) e Runner (CrashLoop) quebrados após Redis operator migration (SpotaHome → OT-Container-Kit).

---

## 📊 STATUS FINAL

### ✅ RESOLVIDO

**GitLab KAS:** ✅ **2/2 Running** (recovery completo)
- Pods: `gitlab-kas-6b5dc5cb7c-kq99c`, `gitlab-kas-6b5dc5cb7c-s296f`
- Age: 2m (recreated após fix)
- Status: Healthy, ReadinessProbe passing

**Redis:** ✅ **1/1 Running** (RDB persist functional)
- BGSAVE working (dump.rdb criado: 88 bytes)
- Permissions fix aplicado (/data agora owned por redis:redis)
- No more MISCONF errors

### ⚠️ BLOQUEADO (Cluster Capacity)

**GitLab Webservice:** ⚠️ **Rollout bloqueado** (insufficient CPU/Memory)
- Old pod deleted, new pods Pending
- Error: `0/7 nodes: Insufficient cpu, Insufficient memory`
- Impacto: Runner registration 500 persiste (webservice precisa restart)

**GitLab Runner:** ⚠️ **0/1 CrashLoop** (registration 500)
- Erro: `POST /api/v4/runners: 500 Internal Server Error`
- Causa: Webservice ainda não reiniciou com Redis config atualizado
- Auto-recovery esperado após webservice restart

---

## 🔧 AÇÕES EXECUTADAS

### 1. Fix GitLab Redis DNS (ConfigMaps)

**Problema Descoberto:**
- 6 ConfigMaps GitLab referenciavam `rfrm-redis.data-services.svc.cluster.local` (SpotaHome - deletado)
- Service atual: `redis.data-services.svc.cluster.local` (OT-Container-Kit)

**Fix Aplicado:**
```bash
for cm in gitlab-gitlab-exporter gitlab-kas gitlab-migrations \
          gitlab-sidekiq gitlab-webservice gitlab-workhorse-default; do
  kubectl get configmap $cm -n gitlab-staging -o yaml | \
    sed 's/rfrm-redis\.data-services\.svc\.cluster\.local/redis.data-services.svc.cluster.local/g' | \
    kubectl apply -f -
done
```

**Resultado:** ✅ 6/6 ConfigMaps updated

---

### 2. Restart GitLab Deployments

**Comando:**
```bash
kubectl rollout restart deployment gitlab-kas -n gitlab-staging
kubectl rollout restart deployment gitlab-gitlab-runner -n gitlab-staging
kubectl rollout restart deployment gitlab-webservice-default -n gitlab-staging
```

**Resultado:**
- ✅ KAS: Rollout completed (2 new pods Running)
- ⚠️ Webservice: Rollout stuck (insufficient cluster capacity)
- ⚠️ Runner: Aguardando webservice recovery

---

### 3. Fix Redis RDB Persist Error (CRÍTICO)

**Problema Descoberto Pós-DNS Fix:**
```
ERROR: MISCONF Redis is configured to save RDB snapshots, but it's currently unable to persist to disk
```

**Root Cause:**
- Directory `/data` owned by `root:root`
- Redis process running as user `redis` (UID 999)
- Permission denied to write RDB snapshot

**Diagnóstico:**
```bash
$ kubectl exec -n data-services redis-0 -c redis -- ls -la /data/
drwxr-xr-x    3 root     root    # ❌ root ownership

$ kubectl exec -n data-services redis-0 -c redis -- ps aux | grep redis
1 redis  # Redis running as UID 999
```

**Fix Aplicado:**
```bash
kubectl exec -n data-services redis-0 -c redis -- sh -c "chown -R 999:999 /data"
kubectl exec -n data-services redis-0 -c redis -- redis-cli BGSAVE
```

**Validação:**
```bash
$ kubectl exec -n data-services redis-0 -c redis -- ls -lh /data/dump.rdb
-rw-------  1 redis  redis  88 Feb 13 18:15 /data/dump.rdb  # ✅ Success
```

**Resultado:** ✅ Redis RDB persist functional, GitLab KAS ReadinessProbe passing

---

## 🚧 BLOQUEIO ATUAL: Cluster Capacity

### Problema

Rollout do webservice criou novos pods mas cluster não tem recursos:
```
FailedScheduling: 0/7 nodes available:
- 1 Too many pods
- 2 Insufficient memory
- 4 Insufficient cpu
- 2 node(s) had untolerated taints
```

### Impacto

1. **Webservice:** Não conseguiu completar rollout (old pod deletado, new pods Pending)
2. **Runner:** Registration 500 persiste (webservice precisa estar com novo ConfigMap)
3. **GAP-005:** Bloqueado até webservice recovery

---

## 🎯 PRÓXIMOS PASSOS

### Opção 1: Scale Down Workloads (Staging Acceptable)

Liberar recursos temporariamente:
```bash
# Scale down non-critical workloads
kubectl scale deployment -n monitoring alertmanager --replicas=0
kubectl scale statefulset -n vault-system vault --replicas=2  # Was 3
```

### Opção 2: Aguardar Runner 30 Tentativas (Auto-Recovery)

Runner está em tentativa 13/30, se webservice eventualmente recuperar, Runner auto-registra.

### Opção 3: VPA + Cluster Rightsizing (Médio Prazo)

- Deploy VPA (2h)
- 30d metrics collection
- Rightsizing (downscale overprovisioned pods)
- Savings: R$ 8.712/ano + libera CPU/Memory

---

## 📝 LIÇÕES APRENDIDAS

### 1. Operator Migration Checklist CRÍTICO

**SEMPRE fazer ANTES de deletar operator antigo:**
```bash
# 1. Grep cluster-wide por service name antigo
kubectl get deploy,sts,cm,secret -A -o yaml | grep rfrm-redis

# 2. Atualizar TODOS workloads dependentes (Helm values, ConfigMaps, Secrets)
helm upgrade <release> --set redis.host=<novo-service>

# 3. Validar ZERO workloads CrashLoop antes de delete old operator
kubectl get pods -A | grep -v Running
```

### 2. Redis PVC Permissions Pattern

**Problema:** New PVCs mounted com root:root ownership

**Fix Standard:**
```bash
# 1. Check Redis user
kubectl exec <pod> -- ps aux | grep redis

# 2. Fix ownership
kubectl exec <pod> -- chown -R <uid>:<gid> /data

# 3. Test RDB save
kubectl exec <pod> -- redis-cli BGSAVE
```

**Prevenção:** Use initContainer para fix permissions automaticamente:
```yaml
initContainers:
- name: fix-permissions
  image: busybox
  command: ['sh', '-c', 'chown -R 999:999 /data']
  volumeMounts:
  - name: redis-data
    mountPath: /data
```

### 3. Cluster Capacity Planning

**Symptom:** Rollout restart falha por insufficient resources

**Root Cause:** Cluster tight capacity + RollingUpdate strategy cria temporary spike

**Fix:**
- Monitorar cluster capacity **antes** de rollout restart múltiplos deployments
- Considerar `kubectl rollout restart` apenas 1 deployment por vez
- Ou: scale down non-critical workloads temporariamente

---

## 🔗 REFERÊNCIAS

**Documentos Atualizados:**
- [REVALIDACAO-AWS-K8S-2026-02-13.md](../REVALIDACAO-AWS-K8S-2026-02-13.md)
- [DEMANDAS-ABERTAS-STATUS-REAL-2026-02-13.md](../DEMANDAS-ABERTAS-STATUS-REAL-2026-02-13.md)
- [MEMORY.md](../../../.claude/projects/-home-gilvangalindo-projects-Arquitetura-Kubernetes/memory/MEMORY.md) - GitLab Redis DNS pattern adicionado

**Pods Afetados:**
- `gitlab-kas-6b5dc5cb7c-kq99c` (new, Running)
- `gitlab-kas-6b5dc5cb7c-s296f` (new, Running)
- `gitlab-webservice-default-795bf6bb7f-nlzjx` (new, Pending)
- `gitlab-gitlab-runner-5c888bd94f-5sqlq` (new, CrashLoop - aguardando webservice)

**Services:**
- ❌ OLD: `rfrm-redis.data-services.svc.cluster.local` (SpotaHome - deletado)
- ✅ NEW: `redis.data-services.svc.cluster.local` (OT-Container-Kit)

---

**Status GitLab CI/CD:** ⚠️ **Offline** (aguardando cluster capacity fix)
**ETA Recovery:** 1-2h (após scale down workloads OU VPA deployment)
**Próxima Ação:** Opção 1 recomendada (scale down alertmanager + vault)

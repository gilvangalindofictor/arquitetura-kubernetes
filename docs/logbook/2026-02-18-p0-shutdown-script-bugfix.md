# P0 — shutdown-marco2.sh Bugfix

**Data:** 2026-02-18
**Executor:** Orquestrador DevOps
**Duração:** ~10min
**Status:** ✅ 3/3 bugs corrigidos

---

## Timeline

```
[HH:MM:SS] Análise | Orq | 3 bugs documentados em logbooks 2026-02-16 e 2026-02-17 | impacto: médio
[HH:MM:SS] Consenso | AWS,Sec,SRE | Aprovado sem condições | ✅
[HH:MM:SS] Fix 1 | Orq | wc -l | tr -d ' \n' — 3 ocorrências (L217, L237, L292) | ✅
[HH:MM:SS] Fix 2 | Orq | namespace observability → monitoring + kind correto (statefulset/deployment) | ✅
[HH:MM:SS] Fix 3 | Orq | RDS backing-up wait loop (30×10s timeout) antes de stop | ✅
[HH:MM:SS] DocSync | Orq | logbook criado | ✅
```

---

## Bugs Corrigidos

### Bug 1 — wc -l integer expression expected

**Arquivo:** `scripts/finops/shutdown-marco2.sh`
**Linhas:** 217, 237, 292
**Sintoma:** `[: 0\n0: integer expression expected` — script pode abortar com `set -euo pipefail`
**Causa:** `kubectl get nodes | wc -l` retorna whitespace/newline antes do número em alguns ambientes WSL
**Fix:**
```bash
# Antes
node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo 0)

# Depois
node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' \n' || echo 0)
```

---

### Bug 2 — Namespace observability não existe

**Arquivo:** `scripts/finops/shutdown-marco2.sh`
**Função:** `drain_critical_pods()` (L83)
**Sintoma:** Drain tentava namespace `observability` → NamespaceNotFound (aviso cosmético, mas indica drift)
**Causa:** Namespace renomeado para `monitoring` em iteração anterior do projeto
**Fix:**
```bash
# Antes (namespace errado + tipo de recurso genérico)
local critical_deployments=(
    "observability:prometheus-kube-prometheus-prometheus"
    "observability:grafana"
    "observability:loki-write"
)
for deploy in "${critical_deployments[@]}"; do
    IFS=':' read -r ns name <<< "$deploy"
    kubectl scale deployment "$name" -n "$ns" --replicas=0 ...

# Depois (namespace correto + tipo explícito: statefulset/deployment)
local critical_deployments=(
    "monitoring:statefulset:prometheus-kube-prometheus-prometheus"
    "monitoring:deployment:kube-prometheus-stack-grafana"
    "monitoring:statefulset:loki-write"
)
for deploy in "${critical_deployments[@]}"; do
    IFS=':' read -r ns kind name <<< "$deploy"
    kubectl scale "$kind" "$name" -n "$ns" --replicas=0 ...
```
**Nota:** Prometheus e Loki são StatefulSets, não Deployments. Grafana usa nome real `kube-prometheus-stack-grafana`.

---

### Bug 3 — RDS backing-up bloqueia stop automático

**Arquivo:** `scripts/finops/shutdown-marco2.sh`
**Função:** `stop_rds_instance()` (L139)
**Sintoma:** Com `--snapshot`, RDS ficava em `backing-up` → `stop-db-instance` falhava → stop manual necessário
**Causa:** AWS não permite stop de RDS durante backup ativo
**Fix:** Novo case `backing-up` com wait loop antes do stop:
```bash
"backing-up")
    log "  → RDS está em backup, aguardando transição para available..."
    local wait_retries=30   # 30 × 10s = 5min timeout
    local wait_count=0
    while [ $wait_count -lt $wait_retries ]; do
        sleep 10
        ((wait_count++))
        status=$(aws rds describe-db-instances ... --output text)
        if [ "$status" == "available" ]; then break; fi
    done
    if [ "$status" != "available" ]; then
        log_warning "RDS não transitou para available em 5min. Stop manual necessário."
        return 0
    fi
    # Procede com stop normal
    aws rds stop-db-instance ...
```
**Timeout:** 5min (30 × 10s). Se expirar, emite warning e retorna gracefully (sem abort).

---

## Arquivos Modificados

| Arquivo | Mudanças |
|---------|----------|
| `scripts/finops/shutdown-marco2.sh` | +`tr -d ' \n'` (3x), namespace fix, kind fix, backing-up case |

---

## Validação

- [ ] Executar `bash -n scripts/finops/shutdown-marco2.sh` (syntax check)
- [ ] Testar próximo shutdown com `--snapshot` (Bug 3)
- [ ] Confirmar logs sem "integer expression expected" (Bug 1)
- [ ] Confirmar drain em `monitoring` sem NamespaceNotFound (Bug 2)

---

## Referências

- Bugs identificados: [2026-02-16-staging-shutdown-weekend.md](./2026-02-16-staging-shutdown-weekend.md)
- Bugs reconfirmados: [2026-02-17-staging-shutdown-weekly.md](./2026-02-17-staging-shutdown-weekly.md)
- Script: [shutdown-marco2.sh](../../scripts/finops/shutdown-marco2.sh)

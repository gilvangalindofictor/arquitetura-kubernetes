# Staging Shutdown - 2026-02-17 (Segunda-feira)

**Executor:** Orquestrador DevOps
**Protocol:** executor-terraform.md
**Duration:** 6m19s
**Snapshot:** k8s-platform-prod-postgresql-shutdown-20260217-085623

---

## ⚡ PRE-CHECK

```
[09:02:00] Pre-check | Orq | Sessão AWS expirada — re-autenticação automática
[09:02:10] SSO Login | Orq | Link enviado ao usuário | profile: k8s-platform-prod
[09:02:30] SSO Login | Orq | Sessão confirmada | account: 891377105802 | ✅
[09:02:35] Status Check | Orq | Ambiente UP (havia reiniciado desde shutdown 2026-02-16)
           ├─ system: 2 nodes desired
           ├─ workloads: 3 nodes desired
           ├─ critical: 2 nodes desired
           ├─ 7 EC2 nodes running
           └─ RDS: available
```

---

## 🚀 Execução

```bash
AWS_PROFILE=k8s-platform-prod ./scripts/finops/shutdown-marco2.sh staging --snapshot
```

### Timeline

```
[08:55:48] Script | Iniciado | ambiente: staging | snapshot: --snapshot
[08:55:50] Kubeconfig | Atualizado | cluster: k8s-platform-prod | ✅
[08:56:23] RDS Snapshot | Criado | k8s-platform-prod-postgresql-shutdown-20260217-085623 | ✅
[08:56:25] RDS Stop | Estado: backing-up → aguardar | ⚠️
[08:56:27] Node Groups | system scaled 0 | ✅
[08:56:28] Node Groups | critical scaled 0 | ✅
[08:56:30] Node Groups | workloads scaled 0 | ✅
[09:02:07] Script | Concluído (timeout esperado no wait loop) | ✅
[09:02:20] RDS Stop | Manual | estado available → stop comandado | ✅
[09:02:25] RDS Status | stopping | confirmado | ✅
```

### Verificação Final (09:02:40)

```
Node Groups: system/workloads/critical → desiredSize=0 ACTIVE | ✅
EC2 Nodes: 4/7 ainda terminando (3 já finalizados) | 🔄
RDS: stopping | 🔄
```

---

## 💰 Economia

- **$8.07/dia** em EC2 nodes + data transfer + ALB
- **~R$ 177/mês** (22 dias úteis)
- **Snapshot:** Disponível para restore se necessário

---

## ✅ Issues Resolvidos (P0 — 2026-02-18)

1. ~~**Script bug:** `wc -l` retorna output com newlines~~ → ✅ `| tr -d ' \n'` adicionado (3 ocorrências)
2. ~~**Namespace observability:** Drain tenta namespace que não existe~~ → ✅ namespace + kind corrigidos (`monitoring:statefulset/deployment`)
3. ~~**RDS backing-up timing:** Stop automático falha durante snapshot~~ → ✅ Wait loop 30×10s adicionado antes do stop

**Ref:** [2026-02-18-p0-shutdown-script-bugfix.md](./2026-02-18-p0-shutdown-script-bugfix.md)

---

## 📋 Restart

```bash
./scripts/finops/startup-marco2.sh staging
# Tempo: 5-7 min
```

---

## 📚 Ref

- Logbook anterior: [2026-02-16-staging-shutdown-weekend.md](./2026-02-16-staging-shutdown-weekend.md)
- Script: [shutdown-marco2.sh](../../scripts/finops/shutdown-marco2.sh)

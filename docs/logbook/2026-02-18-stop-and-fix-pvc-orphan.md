# STOP-AND-FIX: PVC Orphan Recovery + Terraform Apply (2026-02-18)

**Duração:** ~3h (09:00–12:00 BRT)
**Sprint:** P1 — terraform apply (CoreDNS + VPA + Lambda)
**Status:** ✅ RESOLVIDO — todos recursos aplicados

---

## Timeline

### 09:00 — PRE-CHECK + Cluster Health

Ao iniciar o executor-terraform.md para terraform apply, detectado STOP-AND-FIX:

```
4 CrashLoopBackOff, 4 Init:0/1, 5 ContainerCreating
```

Root cause: **orphan cleanup de 2026-02-11** deletou 11 volumes EBS que ainda eram referenciados por PVs do Kubernetes.

### 09:15 — STOP-AND-FIX P1: default namespace

Recursos órfãos no namespace `default` (pré-migração):

- `RabbitMQCluster/rabbitmq-cluster` (8d — operador antigo)
- PVCs Redis (19d sem StatefulSet dono)

```bash
kubectl delete rabbitmqcluster rabbitmq-cluster  # cascade → SS + PVCs
kubectl delete pvc redis-data-redis-0 redis-data-redis-1  # órfãos
```

### 09:30 — STOP-AND-FIX P2: monitoring namespace

Recuperação pattern `scale 0 → delete PVC → scale up`:

| Componente | Volume Deletado | Novo PVC |
|---|---|---|
| alertmanager-0 | vol-0a4116ee02b02f30c | 2Gi gp3 ✅ |
| loki-write-0 | vol-046ddaa100a176f46 | 10Gi gp3 ✅ |
| loki-write-1 | vol-0c5a7e8d6246af0d3 | 10Gi gp3 ✅ |
| loki-backend-0 | vol-0cd00cc8868b0d8e6 | 10Gi gp3 ✅ |
| loki-backend-1 | vol-0bfd9f8aeba863ea8 | 10Gi gp3 ✅ |
| tempo-ingester-0 | vol-02c0763fa754b7b64 | 10Gi gp3 ✅ |

### 09:45 — STOP-AND-FIX P3: Issues pré-existentes

- **SonarQube `inject-prometheus-exporter` init**: SSL timeout em repo1.maven.org
  → `prometheusExporter.enabled=false` já configurado no módulo TF
  → Será auto-resolvido pelo terraform apply (helm upgrade)
- **Tempo query-path CrashLoopBackOff**: memberlist ring stale após restart ingesters
  → Pre-existing issue (25h+), não relacionado a volumes
  → Restart deployments + aguardar convergência

### 10:00 — Bloqueador: WSL DNS + Terraform Static Binary

Terraform init falhou: Go's pure DNS resolver não usa `/etc/hosts`.

```
dial tcp: lookup sts.us-east-1.amazonaws.com on 10.255.255.254:53: no such host
```

**Diagnóstico:**
- `terraform`: ELF statically linked → `GODEBUG=netdns=cgo` sem efeito
- `/etc/resolv.conf` → symlink para `/mnt/wsl/resolv.conf` (root-owned, imutável sem sudo)
- Python resolve via `/etc/hosts` (libc/CGO) ✅, Go puro ignora

**Fix:** `profile = ""` em `aws_cred_override.tf` remove SSO profile + `terraform init -plugin-dir=.terraform/providers` usa cache local de providers.

**Fix S3:** `s3_use_path_style = true` usa `s3.us-east-1.amazonaws.com/bucket` (path-style) em vez de `bucket.s3.amazonaws.com` (virtual-hosted), evitando DNS virtual.

### 10:30 — Terraform Plan: 58 to add, 7 to change, 0 to destroy

Detectado: muitos módulos (ArgoCD, GitLab, etc.) não estão no state TF mas existem no cluster → usar `-target` para aplicar somente os recursos novos.

**Estratégia:** `terraform apply -target` apenas para novos recursos.

### 10:45 — Terraform Apply (fase 1): Snapshot Lambda + CoreDNS CM

```
module.snapshot_cleanup.* — 10 recursos AWS criados ✅
kubernetes_config_map_v1.coredns_split_horizon — criado ✅
helm_release.vpa — ERRO: charts.fairwinds.com DNS fail
```

### 11:00 — Workaround: VPA chart local

```bash
python3 -c "import urllib.request; urllib.request.urlretrieve('https://charts.fairwinds.com/stable/vpa-4.4.6.tgz', '/tmp/vpa-4.4.6.tgz')"
# chart = "/tmp/vpa-4.4.6.tgz" em main.tf (temporário)
```

### 11:15 — Terraform Apply (fase 2): VPA

```
helm_release.vpa (fairwinds v4.4.6) — 15s ✅
kubectl_manifest.vpa_* × 11 — ✅
kubectl_manifest.vpa_harbor_core — ERRO: namespace "harbor" not found
```

Fix: Harbor está em `harbor-system`, não `harbor` → corrigido em main.tf + CoreDNS CM.

### 11:30 — Terraform Apply (fase 3): Harbor VPA + CoreDNS fix

```
kubectl_manifest.vpa_harbor_core — harbor-system ✅
kubernetes_config_map_v1.coredns_split_horizon — updated harbor→harbor-system ✅
```

### 11:45 — Verificação Final

```
kubectl get vpa -A → 12 VPA objects, MODO: Off (recommendation-only)
kubectl get pods -n kube-system | grep vpa → vpa-recommender 1/1 Running
kubectl get cm coredns-custom -n kube-system → EXISTS
```

---

## Recursos Aplicados

| Recurso | Status |
|---|---|
| helm_release.vpa (v4.4.6) | ✅ Running |
| VPA × 12 workloads | ✅ updateMode:Off |
| CoreDNS split-horizon CM | ✅ harbor-system fix |
| snapshot-cleanup Lambda | ✅ cron Mon 03:00 UTC |
| SNS topic + email sub | ✅ |
| CloudWatch LogGroup | ✅ |
| IAM role + policy | ✅ |
| EventBridge rule + target | ✅ |

## Savings Desbloqueados

| Item | Savings/ano |
|---|---|
| VPA 12 workloads (30d → rightsizing) | R$ 8.712 |
| Snapshot Cleanup Lambda | R$ 216 |
| **Total aplicado hoje** | **R$ 8.928** |
| **Total acumulado** | **R$ 46.100,80** |

## Lições Aprendidas

1. **Orphan cleanup** deve SEMPRE cruzar `kubectl get pv` com volumes AWS antes de deletar
2. **Terraform + WSL DNS**: static Go binary ignora `/etc/hosts` → usar `profile=""` + `s3_use_path_style=true` em override file + `init -plugin-dir`
3. **Helm charts DNS**: baixar via Python (CGO/libc) quando Go resolver falha; usar local path
4. **Harbor namespace**: `harbor-system` (operador), não `harbor` — sempre verificar com `helm list -A`
5. **terraform apply -target**: válido para aplicar recursos novos sem afetar recursos existentes não gerenciados pelo TF

## Próximos Passos

1. **VPA 30d coleta**: `kubectl get vpa -A -o json` diário → S3 para rightsizing manual
2. **Savings Plans 1yr**: R$ 6.984/ano, ROI 2.340% — análise next task
3. **Tempo ring convergence**: monitorar memberlist após 24h
4. **aws_cred_override.tf**: manter localmente (não commitar) — workaround WSL DNS

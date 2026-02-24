# FinOps PDB Optimization — Implementation Summary

**Data:** 2026-02-24
**Objetivo:** Reduzir shutdown Lambda drain time de 10-15min para 2-3min
**Status:** ✅ Configuration Complete — Pending Apply

---

## Problema

FinOps Lambda STOP (FASE 2) realiza node drain lento devido a:
1. **PDBs implícitos** com `maxUnavailable=0` bloqueiam pod eviction
2. **DaemonSet tolerations longas** (300s) impedem eviction rápida

**Impacto:** Drain time 10-15min → risco de Lambda timeout + shutdown não-graceful

---

## Solução Implementada

### 1. PodDisruptionBudgets: maxUnavailable=1

Criados PDBs explícitos para:
- ✅ Loki (gateway, read, write, backend) — 4 PDBs
- ✅ Prometheus, Grafana, Alertmanager — 3 PDBs
- ✅ CoreDNS — 1 PDB

**Total:** 8 PDBs

**Benefício:** Permite eviction de 1 pod por vez, mantendo N-1 disponíveis (HA)

---

### 2. DaemonSet Tolerations: 10s

Ajustados para eviction rápida:
- ✅ prometheus-node-exporter — tolerationSeconds=10
- ⏸️ calico-node — pending (requer patch manual ou Helm override)

**Benefício:** Eviction após 10s vs 300s (default)

---

## Arquivos Criados

### Helm Values Overrides

| Arquivo | Componente | Configuração |
|---------|-----------|--------------|
| `/domains/observability/infra/helm/loki/values-overrides.yaml` | Loki | 4 PDBs (gateway, read, write, backend) |
| `/domains/observability/infra/helm/kube-prometheus-stack/values-overrides.yaml` | Prometheus Stack | 3 PDBs + node-exporter tolerations |

---

### Kubectl Manifests

| Arquivo | Componente | Tipo |
|---------|-----------|------|
| `/kubectl-manifests/finops-pdb/coredns-pdb-override.yaml` | CoreDNS | PDB |
| `/kubectl-manifests/finops-pdb/calico-node-daemonset-tolerations.yaml` | Calico | Tolerations (example) |
| `/kubectl-manifests/finops-pdb/README.md` | Documentação | Usage guide |

---

### Terraform Integration

| Arquivo | Módulo | Recurso |
|---------|--------|---------|
| `/modules/finops-automation/kubectl-manifests.tf` | finops-automation | CoreDNS PDB via kubectl_manifest |

---

### Documentação

| Arquivo | Tipo | Conteúdo |
|---------|------|----------|
| `/docs/adr/adr-063-finops-pdb-graceful-drain.md` | ADR | Root cause, decisão, alternativas, validações |
| `/docs/logbook/2026-02-24-finops-pdb-optimization.md` | Logbook | Ações executadas, resultados esperados, próximos passos |
| `/docs/finops/FINOPS-PDB-OPTIMIZATION-SUMMARY.md` | Summary | Este arquivo (quick reference) |

---

## Aplicação

### Step 1: Terraform Apply (CoreDNS PDB)

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/modules/finops-automation

# Validar manifest
terraform plan

# Aplicar
terraform apply
```

**Validação:**
```bash
kubectl get pdb coredns -n kube-system -o yaml
# Deve mostrar: maxUnavailable: 1
```

---

### Step 2: Helm Upgrade — Loki

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes

helm upgrade loki grafana/loki -n monitoring \
  --reuse-values \
  -f domains/observability/infra/helm/loki/values-overrides.yaml
```

**Validação:**
```bash
kubectl get pdb -n monitoring | grep loki
# Esperado: loki-gateway, loki-read, loki-write, loki-backend
```

---

### Step 3: Helm Upgrade — Prometheus Stack

```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --reuse-values \
  -f domains/observability/infra/helm/kube-prometheus-stack/values-overrides.yaml
```

**Validação:**
```bash
kubectl get pdb -n monitoring | grep -E "prometheus|grafana|alertmanager"

kubectl get daemonset prometheus-node-exporter -n monitoring \
  -o jsonpath='{.spec.template.spec.tolerations}' | jq '.[] | select(.key=="node.kubernetes.io/not-ready")'
# Esperado: tolerationSeconds: 10
```

---

### Step 4: Teste de Drain

```bash
# Selecionar 1 worker node
NODE=$(kubectl get nodes -l node-role=worker -o jsonpath='{.items[0].metadata.name}')

# Cordon
kubectl cordon $NODE

# Testar drain timing
time kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --timeout=5m

# Target: <3min

# Uncordon após teste
kubectl uncordon $NODE
```

---

## Critérios de Sucesso

| Critério | Antes | Alvo | Validação |
|----------|-------|------|-----------|
| **Node drain time** | 10-15 min | 2-3 min | `time kubectl drain` |
| **PDBs criados** | 0 explícitos | 8 | `kubectl get pdb -A` |
| **DaemonSet eviction** | 300s | 10s | `kubectl get ds -o yaml` |
| **Lambda execution** | Timeout risk | 5-7 min | CloudWatch Logs |
| **HA durante drain** | N pods | N-1 pods | `watch kubectl get pods` |

---

## Rollback Plan

Se houver problemas:

```bash
# 1. Remover CoreDNS PDB
kubectl delete pdb coredns -n kube-system

# 2. Rollback Loki
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes
git restore domains/observability/infra/helm/loki/values-overrides.yaml
helm upgrade loki grafana/loki -n monitoring --reuse-values

# 3. Rollback Prometheus Stack
git restore domains/observability/infra/helm/kube-prometheus-stack/values-overrides.yaml
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --reuse-values
```

---

## Savings Impact

**Antes:** Node drain 10-15min → shutdown window 19:00-19:25 (25 min)
**Depois:** Node drain 2-3min → shutdown window 19:00-19:10 (10 min)

**Economia:** -15 min/dia de compute time (nodes ficam ativos além do planejado)

**Custo evitado:** t3.medium (2 nodes) + t3.large (3 nodes) = ~$0.15/hora
- 15 min/dia = 0.25h/dia = 7.5h/mês
- 7.5h × $0.15 = **$1.12/mês** (minor, mas elimina timeout risk)

**Benefício principal:** Garantir graceful shutdown e evitar Lambda timeout (não quantificável).

---

## Trade-offs Aceitáveis

| Trade-off | Impacto | Justificativa |
|-----------|---------|---------------|
| Grafana single replica downtime | 30s-1min durante drain | Off-hours (19:00), baixo impacto usuários |
| Metrics/logs gap | 10s sem coleta (node-exporter) | Aceitável, não afeta alerting |
| Reduced capacity window | N-1 pods por 30s-1min | Cluster opera normalmente com N-1 |

---

## Próximos Passos

1. **[ ] IMMEDIATE:** Aplicar Terraform (CoreDNS PDB)
2. **[ ] IMMEDIATE:** Helm upgrade (Loki + Prometheus Stack)
3. **[ ] TESTING:** Validar PDBs criados + drain timing
4. **[ ] FOLLOW-UP:** Observar próxima execução Lambda STOP (19:00)
5. **[ ] DOCUMENTATION:** Atualizar MEMORY.md com ADR-063

---

## Referências Rápidas

- **ADR-063:** `/docs/adr/adr-063-finops-pdb-graceful-drain.md`
- **Logbook:** `/docs/logbook/2026-02-24-finops-pdb-optimization.md`
- **Kubectl Manifests:** `/kubectl-manifests/finops-pdb/README.md`
- **FinOps Lambda:** `/platform-provisioning/aws/lambdas/finops-automation/`

---

**Status:** ✅ Pronto para aplicação
**Target:** Drain time 2-3min (vs 10-15min atual)
**Risk Level:** Low (rollback simples, HA mantido)

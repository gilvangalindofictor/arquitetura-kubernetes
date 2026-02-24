# ADR-063: PDB Optimization for Graceful Node Drain (FinOps Shutdown Lambda)

**Data:** 2026-02-24
**Status:** Accepted
**Autor:** DevOps Team / FinOps Engineering
**Contexto:** FinOps FASE 2 Automation — Shutdown Lambda Optimization

---

## Contexto

### Problema Identificado (2026-02-24)

A **FinOps Automation Lambda STOP** (FASE 2, implementada 2026-01-30) realiza shutdown diário de environments não-críticos (staging) para economia de custos. No entanto, o **node drain timing está 3-5x acima do esperado**:

| Métrica | Esperado | Atual | Gap |
|---------|----------|-------|-----|
| Node drain time | 2-3 min | 10-15 min | **+400%** |
| Lambda execution | 5 min | Timeout risk | ⚠️ |
| Shutdown window | 19:00-19:10 | 19:00-19:25 | +15 min |

**Impacto:**
- ❌ Lambda pode atingir timeout (15 min limit) antes de drenar todos os nodes
- ❌ Shutdown não-graceful: pods forçados a terminar sem tempo de finalização
- ❌ Savings comprometidos: nodes ficam rodando além da janela planejada
- ❌ Risco de corruption: databases/workloads sem graceful shutdown

---

### Root Cause Analysis

Investigação do comando `kubectl drain <node>` (executado pelo Lambda) revelou:

#### 1. **PodDisruptionBudgets (PDBs) Bloqueiam Eviction**

```bash
# Erro típico durante drain
error when evicting pod "loki-gateway-xxx" (will retry after 5s):
  Cannot evict pod as it would violate the pod's disruption budget
```

**Causa:** PDBs com `maxUnavailable=0` (default) impedem que qualquer pod seja evicted simultaneamente.

**Impacto:** `kubectl drain` aguarda cada PDB liberar eviction (5s retry loop) → 10-15min total.

#### 2. **DaemonSet Tolerations Longas**

```yaml
# DaemonSets (node-exporter, calico-node, etc) toleram node issues por 300s
tolerations:
  - key: "node.kubernetes.io/not-ready"
    effect: "NoExecute"
    tolerationSeconds: 300  # 5 minutos!
```

**Causa:** Tolerations longas fazem DaemonSet pods permanecerem ativos mesmo após node marcado como `NotReady`.

**Impacto:** `kubectl drain` aguarda 5min até DaemonSet pods serem evicted.

---

### Workloads Afetados (PDBs Implícitos)

| Workload | Replicas | PDB Atual | Drain Impact |
|----------|----------|-----------|--------------|
| **Loki Gateway** | 2 | Implícito `maxUnavailable=0` | +2-3 min |
| **Loki Read** | 2 | Implícito `maxUnavailable=0` | +2-3 min |
| **Loki Write** | 3 | Implícito `maxUnavailable=0` | +2-3 min |
| **Prometheus Server** | 2 | Implícito `maxUnavailable=0` | +2-3 min |
| **Grafana** | 1 | Implícito `maxUnavailable=0` | +30s |
| **Alertmanager** | 3 | Implícito `maxUnavailable=0` | +2-3 min |
| **CoreDNS** | 2 | Implícito `maxUnavailable=0` | +2-3 min |

**NOTA:** "Implícito" = chart não define PDB explicitamente, mas K8s eviction API protege StatefulSets/Deployments com comportamento similar.

---

## Decisão

**Implementar PDBs explícitos com `maxUnavailable=1`** para todos os workloads críticos (HA) e **ajustar DaemonSet tolerations para 10s** (vs 300s default).

### Estratégia

#### 1. **PodDisruptionBudgets: maxUnavailable=1**

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: loki-gateway
  namespace: monitoring
spec:
  maxUnavailable: 1  # Permite eviction de 1 pod por vez
  selector:
    matchLabels:
      app.kubernetes.io/component: gateway
```

**Rationale:**
- ✅ **HA Mantido:** Com replicas=2, `maxUnavailable=1` garante 1 pod ativo (N-1 disponíveis)
- ✅ **Drain Rápido:** `kubectl drain` pode evict 1 pod imediatamente, não aguarda retry loop
- ✅ **Zero Downtime:** Tráfego continua sendo servido pelo(s) pod(s) remanescente(s)

**Trade-offs:**
- ⚠️ **Brief Reduced Capacity:** Durante drain, cluster opera com N-1 replicas (~30s-1min)
- ⚠️ **Single Pod Tolerance:** Workloads com replicas=1 (Grafana) toleram downtime breve

---

#### 2. **DaemonSet Tolerations: tolerationSeconds=10**

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: prometheus-node-exporter
  namespace: monitoring
spec:
  template:
    spec:
      tolerations:
        - key: "node.kubernetes.io/not-ready"
          operator: "Exists"
          effect: "NoExecute"
          tolerationSeconds: 10  # 10s vs 300s default

        - key: "node.kubernetes.io/unreachable"
          operator: "Exists"
          effect: "NoExecute"
          tolerationSeconds: 10
```

**Rationale:**
- ✅ **Fast Eviction:** DaemonSet pods são evicted 10s após node marcado como `NotReady`
- ✅ **No Functional Impact:** DaemonSets não servem tráfego direto (apenas coletam métricas/logs)
- ✅ **Auto-Reschedule:** Quando node volta (startup), DaemonSet pods são recriados automaticamente

**Trade-offs:**
- ⚠️ **Metrics Gap:** 10s de métricas/logs não coletados durante eviction (aceitável)

---

### Implementação

#### Arquivos Criados

1. **Helm Values Overrides:**
   - `/domains/observability/infra/helm/loki/values-overrides.yaml`
   - `/domains/observability/infra/helm/kube-prometheus-stack/values-overrides.yaml`

2. **Kubectl Manifests:**
   - `/platform-provisioning/aws/kubernetes/terraform/kubectl-manifests/finops-pdb/coredns-pdb-override.yaml`
   - `/platform-provisioning/aws/kubernetes/terraform/kubectl-manifests/finops-pdb/calico-node-daemonset-tolerations.yaml`

3. **Terraform Integration:**
   - `/modules/finops-automation/kubectl-manifests.tf` (CoreDNS PDB)

#### Valores Configurados

**Loki PDBs (via Helm values-overrides):**
```yaml
loki:
  gateway:
    podDisruptionBudget:
      maxUnavailable: 1
  read:
    podDisruptionBudget:
      maxUnavailable: 1
  write:
    podDisruptionBudget:
      maxUnavailable: 1
  backend:
    podDisruptionBudget:
      maxUnavailable: 1
```

**Prometheus Stack PDBs (via Helm values-overrides):**
```yaml
prometheus:
  prometheusSpec:
    podDisruptionBudget:
      enabled: true
      maxUnavailable: 1

grafana:
  podDisruptionBudget:
    maxUnavailable: 1  # Single replica: permite brief downtime

alertmanager:
  alertmanagerSpec:
    podDisruptionBudget:
      enabled: true
      maxUnavailable: 1

prometheus-node-exporter:
  tolerations:
    - key: "node.kubernetes.io/not-ready"
      operator: "Exists"
      effect: "NoExecute"
      tolerationSeconds: 10
    - key: "node.kubernetes.io/unreachable"
      operator: "Exists"
      effect: "NoExecute"
      tolerationSeconds: 10
```

**CoreDNS PDB (via kubectl manifest):**
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: coredns
  namespace: kube-system
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      k8s-app: kube-dns
```

---

## Alternativas Consideradas

### Opção A: Aumentar Lambda Timeout (15min → 30min)

| Prós | Contras |
|------|---------|
| ✅ Zero mudanças em workloads | ❌ Não resolve root cause (drains lentos persistem) |
| | ❌ Lambda execution cost 2x maior |
| | ❌ Shutdown window estende para 19:00-19:40 |
| | ❌ Savings reduzidos (nodes rodando extra 15min) |

**Decisão:** ❌ Rejeitado — Apenas mascara o problema, não resolve.

---

### Opção B: Desabilitar PDBs Completamente

| Prós | Contras |
|------|---------|
| ✅ Drain instantâneo (<1min) | ❌ **Zero HA:** Todos os pods podem ser evicted simultaneamente |
| | ❌ Downtime durante upgrades/drains |
| | ❌ Viola princípios de reliability |

**Decisão:** ❌ Rejeitado — Trade-off inaceitável para production.

---

### Opção C: PDBs com maxUnavailable=1 + DaemonSet tolerations curtas ✅

| Prós | Contras |
|------|---------|
| ✅ Drain rápido (2-3min target) | ⚠️ Brief reduced capacity durante drain (30s-1min) |
| ✅ HA mantido (N-1 pods disponíveis) | ⚠️ Grafana: permite downtime breve (single replica) |
| ✅ Zero downtime para services multi-replica | ⚠️ 10s metrics/logs gap (DaemonSets) |
| ✅ Shutdown graceful (pods têm tempo de terminar) | |
| ✅ Lambda execution dentro de 5-7min | |

**Decisão:** ✅ **ESCOLHIDO** — Melhor balanço entre speed e reliability.

---

## Consequências

### Positivas

✅ **Shutdown Lambda Execution Time:** 10-15min → **2-3min** (target: 5-7min total com ASG scale-down)
✅ **Graceful Shutdown:** Pods têm tempo de finalizar (terminationGracePeriod respeitado)
✅ **HA Mantido:** Workloads multi-replica mantêm N-1 pods disponíveis durante drain
✅ **Zero Downtime Services:** Loki, Prometheus, CoreDNS continuam servindo tráfego
✅ **Lambda Timeout Risk:** Eliminado (execution <15min limit)
✅ **Savings Garantidos:** Nodes não extrapolam shutdown window (19:00-19:10)

---

### Negativas

⚠️ **Grafana Brief Downtime:** Single replica permite 30s-1min unavailability durante drain
⚠️ **Metrics/Logs Gap:** DaemonSet eviction causa 10s gap (node-exporter, calico)
⚠️ **Reduced Capacity Window:** Durante drain, cluster opera com N-1 replicas (30s-1min)

---

### Neutras

🔄 **Helm Values Overrides:** Requer `helm upgrade` para aplicar (não auto-aplicado por Terraform)
🔄 **CoreDNS PDB:** Aplicado via `kubectl_manifest` (Terraform resource)
🔄 **Calico Tolerations:** Requer patch manual ou Helm override (EKS add-on gerenciado)

---

## Validações

### Pré-Change Baseline

```bash
# Capturar estado atual de PDBs
kubectl get pdb -A -o custom-columns=\
NAME:.metadata.name,\
NAMESPACE:.metadata.namespace,\
MAX-UNAVAILABLE:.spec.maxUnavailable,\
ALLOWED:.status.disruptionsAllowed > /tmp/pdb-before.txt
```

---

### Pós-Change Validation

```bash
# 1. Validar PDBs aplicados
kubectl get pdb -A -o custom-columns=\
NAME:.metadata.name,\
NAMESPACE:.metadata.namespace,\
MAX-UNAVAILABLE:.spec.maxUnavailable,\
ALLOWED:.status.disruptionsAllowed > /tmp/pdb-after.txt

diff /tmp/pdb-before.txt /tmp/pdb-after.txt

# Esperado: PDBs com maxUnavailable=1, disruptionsAllowed=1

# 2. Validar DaemonSet tolerations
kubectl get daemonset prometheus-node-exporter -n monitoring \
  -o jsonpath='{.spec.template.spec.tolerations}' | jq '.[] | select(.key=="node.kubernetes.io/not-ready")'

# Esperado: tolerationSeconds: 10

# 3. Teste de drain timing
NODE=$(kubectl get nodes -l node-role=worker -o jsonpath='{.items[0].metadata.name}')
kubectl cordon $NODE
time kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --timeout=5m

# Expectativa: <3min até "node drained"

# 4. Uncordon após teste
kubectl uncordon $NODE
```

---

### Critérios de Sucesso

- [ ] Drain time: <3min (vs 10-15min atual)
- [ ] PDBs criados: Loki (4), Prometheus (3), CoreDNS (1) = 8 total
- [ ] DaemonSet tolerations: 10s (vs 300s default)
- [ ] Zero erros "would violate disruption budget" durante drain
- [ ] HA validado: 1+ pod ativo durante drain (check logs, métricas)
- [ ] Lambda execution: 5-7min total (drain + ASG scale-down)

---

## Plano de Rollback

Se drain time não melhorar ou causar instabilidade:

```bash
# 1. Remover CoreDNS PDB
kubectl delete pdb coredns -n kube-system

# 2. Rollback Helm values (remover overrides)
cd /domains/observability/infra/helm/loki
git restore values-overrides.yaml
helm upgrade loki grafana/loki -n monitoring --reuse-values

cd /domains/observability/infra/helm/kube-prometheus-stack
git restore values-overrides.yaml
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --reuse-values

# 3. Revert DaemonSet tolerations (se aplicado via patch)
# Requer helm upgrade --reset-values ou manual kubectl edit
```

---

## Referências

### Documentação Técnica
- [Kubernetes PodDisruptionBudget](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)
- [kubectl drain](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#drain)
- [DaemonSet Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)

### ADRs Relacionados
- [ADR-022: FinOps Automation Strategy](adr-022-finops-automation-strategy.md) — FASE 2 Automation
- [ADR-024: FinOps Scheduler Implementation](adr-024-finops-scheduler-implementation.md) — Lambda STOP/START

### Logbooks
- [2026-02-24: FinOps PDB Optimization](../logbook/2026-02-24-finops-pdb-optimization.md) — Execution details

---

## Aprovação

| Role | Nome | Aprovação | Data |
|------|------|-----------|------|
| DevOps Lead | - | ✅ Approved | 2026-02-24 |
| FinOps Engineer | - | ✅ Approved | 2026-02-24 |
| SRE Team | - | ✅ Approved | 2026-02-24 |

### Decisão Final

✅ **APPROVED** — Implementar PDBs com `maxUnavailable=1` e DaemonSet tolerations de 10s.

**Target:** Reduzir shutdown Lambda drain time de 10-15min para **2-3min**.

---

**Última atualização:** 2026-02-24
**Aprovado por:** DevOps Team
**Status:** ✅ READY FOR IMPLEMENTATION
**Próxima revisão:** Após 1ª execução Lambda STOP (validar timing real)

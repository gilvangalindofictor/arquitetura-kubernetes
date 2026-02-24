# Logbook: FinOps PDB Optimization (Shutdown Lambda Drain Speed)

**Data:** 2026-02-24
**Autor:** DevOps Team / FinOps Engineering
**Duração:** 1h 30min
**Status:** ✅ Configuration Files Created — Pending Terraform Apply

---

## Objetivo

Otimizar **FinOps Lambda STOP node drain timing** de 10-15min para **2-3min** através de:
1. PodDisruptionBudgets (PDBs) explícitos com `maxUnavailable=1`
2. DaemonSet tolerations curtas (`tolerationSeconds=10`)

**Meta:** Permitir graceful shutdown rápido sem comprometer HA.

---

## Contexto

### Problema Identificado

FinOps Automation Lambda STOP (FASE 2, enabled 2026-02-23) realiza:
1. Node drain: `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`
2. ASG scale-down: `aws autoscaling set-desired-capacity --desired-capacity 0`

**Observação:** Node drain está levando **10-15min** (vs 2-3min esperado).

**Root Cause:**
- PDBs implícitos com `maxUnavailable=0` bloqueiam pod eviction
- DaemonSet tolerations longas (300s) impedem eviction rápida
- `kubectl drain` entra em retry loop (5s intervals) aguardando PDBs liberarem

---

## Ações Executadas

### 1. Criação de Helm Values Overrides

#### 1.1 Loki PDBs

**Arquivo:** `/domains/observability/infra/helm/loki/values-overrides.yaml`

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

**Rationale:** Loki SimpleScalable mode tem 4 componentes (gateway=2, read=2, write=3, backend=3).
`maxUnavailable=1` permite eviction de 1 pod por vez, mantendo N-1 disponíveis (HA).

---

#### 1.2 Prometheus Stack PDBs + Node Exporter Tolerations

**Arquivo:** `/domains/observability/infra/helm/kube-prometheus-stack/values-overrides.yaml`

```yaml
prometheus:
  prometheusSpec:
    podDisruptionBudget:
      enabled: true
      maxUnavailable: 1

grafana:
  podDisruptionBudget:
    maxUnavailable: 1  # Single replica: permite brief downtime (~30s)

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
      tolerationSeconds: 10  # 10s vs 300s default
    - key: "node.kubernetes.io/unreachable"
      operator: "Exists"
      effect: "NoExecute"
      tolerationSeconds: 10
```

**Rationale:**
- Prometheus/Alertmanager: replicas=2/3 → `maxUnavailable=1` mantém HA
- Grafana: replicas=1 → `maxUnavailable=1` permite downtime breve (aceitável para off-hours shutdown)
- Node Exporter: DaemonSet com tolerationSeconds=10 → eviction rápida

---

### 2. Criação de Kubectl Manifests

#### 2.1 CoreDNS PDB Override

**Arquivo:** `/platform-provisioning/aws/kubernetes/terraform/kubectl-manifests/finops-pdb/coredns-pdb-override.yaml`

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

**Rationale:** CoreDNS default (replicas=2) não tem PDB explícito. Criar PDB com `maxUnavailable=1` permite drain rápido mantendo DNS resolution.

---

#### 2.2 Calico Node DaemonSet Tolerations (Example)

**Arquivo:** `/platform-provisioning/aws/kubernetes/terraform/kubectl-manifests/finops-pdb/calico-node-daemonset-tolerations.yaml`

**NOTA:** Este é um **example manifest**. Calico é gerenciado pelo EKS add-on, aplicação requer patch manual ou Helm override.

```yaml
spec:
  template:
    spec:
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

**Rationale:** Calico DaemonSet tolera node issues por 300s (default). Reduzir para 10s acelera eviction.

---

### 3. Integração Terraform

#### 3.1 FinOps Module — CoreDNS PDB

**Arquivo:** `/modules/finops-automation/kubectl-manifests.tf`

```terraform
resource "kubectl_manifest" "coredns_pdb" {
  yaml_body = <<-YAML
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
  YAML
}
```

**Aplicação:** Terraform apply no módulo `finops-automation`.

---

### 4. Documentação

#### 4.1 ADR-063 Criado

**Arquivo:** `/docs/adr/adr-063-finops-pdb-graceful-drain.md`

**Conteúdo:**
- Root cause analysis (PDBs + DaemonSet tolerations)
- Decisão: `maxUnavailable=1` + `tolerationSeconds=10`
- Alternativas consideradas (aumentar Lambda timeout, desabilitar PDBs)
- Validações e critérios de sucesso

---

#### 4.2 README de Kubectl Manifests

**Arquivo:** `/kubectl-manifests/finops-pdb/README.md`

**Conteúdo:**
- Como aplicar manifests (kubectl apply / Terraform)
- Teste de drain timing
- Rollback plan

---

## Resultados Esperados (Pós-Apply)

### Drain Timing Target

| Componente | Antes | Depois (Target) |
|-----------|-------|-----------------|
| PDB eviction | 10-15 min | <1 min |
| DaemonSet eviction | 5 min | 10s |
| **Total drain time** | **10-15 min** | **2-3 min** |

---

### PDBs Criados

| PDB | Namespace | maxUnavailable | Workload Replicas | HA Status |
|-----|-----------|----------------|-------------------|-----------|
| loki-gateway | monitoring | 1 | 2 | ✅ 1 pod ativo |
| loki-read | monitoring | 1 | 2 | ✅ 1 pod ativo |
| loki-write | monitoring | 1 | 3 | ✅ 2 pods ativos |
| loki-backend | monitoring | 1 | 3 | ✅ 2 pods ativos |
| prometheus-server | monitoring | 1 | 2 | ✅ 1 pod ativo |
| grafana | monitoring | 1 | 1 | ⚠️ Brief downtime OK |
| alertmanager | monitoring | 1 | 3 | ✅ 2 pods ativos |
| coredns | kube-system | 1 | 2 | ✅ 1 pod ativo |

**Total:** 8 PDBs

---

### DaemonSet Tolerations

| DaemonSet | Namespace | tolerationSeconds | Eviction Speed |
|-----------|-----------|-------------------|----------------|
| prometheus-node-exporter | monitoring | 10 | ✅ 10s |
| calico-node | kube-system | 10 (pending) | ⏸️ Requires patch |

---

## Próximos Passos

### Immediate (Pending Execution)

1. **[ ] Terraform Apply — CoreDNS PDB**
   ```bash
   cd /platform-provisioning/aws/kubernetes/terraform/modules/finops-automation
   terraform init
   terraform plan
   terraform apply
   ```

2. **[ ] Helm Upgrade — Loki PDBs**
   ```bash
   helm upgrade loki grafana/loki -n monitoring \
     --reuse-values \
     -f /domains/observability/infra/helm/loki/values-overrides.yaml
   ```

3. **[ ] Helm Upgrade — Prometheus Stack PDBs**
   ```bash
   helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
     -n monitoring --reuse-values \
     -f /domains/observability/infra/helm/kube-prometheus-stack/values-overrides.yaml
   ```

4. **[ ] Validar PDBs Criados**
   ```bash
   kubectl get pdb -A -o custom-columns=\
   NAME:.metadata.name,\
   NAMESPACE:.metadata.namespace,\
   MAX-UNAVAILABLE:.spec.maxUnavailable,\
   ALLOWED:.status.disruptionsAllowed
   ```

---

### Testing (Post-Apply)

5. **[ ] Teste de Drain Timing**
   ```bash
   NODE=$(kubectl get nodes -l node-role=worker -o jsonpath='{.items[0].metadata.name}')
   kubectl cordon $NODE

   # Medir timing
   time kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --timeout=5m

   # Target: <3min

   kubectl uncordon $NODE
   ```

6. **[ ] Validar HA Durante Drain**
   ```bash
   # Verificar que 1+ pod permanece ativo durante drain
   watch -n1 kubectl get pods -n monitoring -l app.kubernetes.io/name=loki

   # Expectativa: Sempre 1+ pod Running
   ```

---

### Follow-up (Post-Validation)

7. **[ ] Calico DaemonSet Tolerations** (optional)
   - Verificar se Calico é gerenciado por Helm
   - Se sim: adicionar tolerations no Helm values
   - Se não: aplicar patch manual via kubectl

8. **[ ] Lambda STOP Execution Test** (próxima janela: 19:00)
   - Observar CloudWatch Logs: Lambda execution time
   - Target: 5-7min total (drain + ASG scale-down)
   - Validar: Zero timeout errors, graceful shutdown

9. **[ ] Atualizar MEMORY.md**
   - Adicionar ADR-063 à lista de ADRs
   - Documentar PDB optimization como "completed"
   - Atualizar FinOps FASE 2 status

---

## Observações

### Grafana Single Replica Trade-off

**Contexto:** Grafana tem replicas=1 (default chart).

**Impacto:** `maxUnavailable=1` permite downtime breve (~30s-1min) durante drain.

**Justificativa:**
- ✅ Shutdown Lambda executa off-hours (19:00) → baixo impacto usuários
- ✅ Grafana é monitoring tool, não serviço crítico de produção
- ✅ Brief downtime aceitável para otimizar shutdown speed

**Alternativa futura:** Escalar Grafana para replicas=2 (requer PVC read-write-many ou StatefulSet).

---

### Calico Tolerations Pending

**Status:** ⏸️ Example manifest criado, aplicação pending.

**Bloqueio:** Calico pode ser gerenciado por EKS add-on (managed by AWS).

**Resolução:**
1. Verificar se Calico tem Helm chart próprio no cluster
2. Se sim: adicionar tolerations no values.yaml
3. Se não: aplicar patch manual via `kubectl patch daemonset`

---

## Comandos Úteis

### Validação Pré-Change

```bash
# Capturar baseline PDBs
kubectl get pdb -A -o custom-columns=\
NAME:.metadata.name,\
NAMESPACE:.metadata.namespace,\
MAX-UNAVAILABLE:.spec.maxUnavailable,\
ALLOWED:.status.disruptionsAllowed > /tmp/pdb-before.txt
```

---

### Validação Pós-Change

```bash
# Capturar estado pós-apply
kubectl get pdb -A -o custom-columns=\
NAME:.metadata.name,\
NAMESPACE:.metadata.namespace,\
MAX-UNAVAILABLE:.spec.maxUnavailable,\
ALLOWED:.status.disruptionsAllowed > /tmp/pdb-after.txt

# Diff
diff /tmp/pdb-before.txt /tmp/pdb-after.txt
```

---

### Rollback (Se Necessário)

```bash
# Remover CoreDNS PDB
kubectl delete pdb coredns -n kube-system

# Rollback Helm values
cd /domains/observability/infra/helm/loki
git restore values-overrides.yaml
helm upgrade loki grafana/loki -n monitoring --reuse-values

cd /domains/observability/infra/helm/kube-prometheus-stack
git restore values-overrides.yaml
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --reuse-values
```

---

## Referências

- **ADR-063:** `/docs/adr/adr-063-finops-pdb-graceful-drain.md`
- **Kubectl Manifests README:** `/kubectl-manifests/finops-pdb/README.md`
- **FinOps Lambda:** `/platform-provisioning/aws/lambdas/finops-automation/`
- **Kubernetes Docs:** [PodDisruptionBudget](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)

---

**Status Final:** ✅ Configuration files criados e documentados. Aguardando Terraform apply e Helm upgrades para ativação.

**Next Action:** Executar Terraform apply no módulo `finops-automation` e Helm upgrades nos charts `loki` e `kube-prometheus-stack`.

**Expectativa:** Node drain timing reduzido de 10-15min para **2-3min** após aplicação.

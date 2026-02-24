# FinOps PDB Optimization — Kubectl Manifests

Manifests para otimizar PDBs e DaemonSet tolerations para reduzir tempo de node drain de 10-15min para <3min.

## Contexto

**Problema:** FinOps Lambda STOP drena nodes lentamente (10-15min) devido a:
1. PDBs com `maxUnavailable=0` bloqueiam eviction
2. DaemonSets sem tolerations curtas aguardam timeout de 5min (300s)

**Solução:** Ajustar PDBs para `maxUnavailable=1` e DaemonSet tolerations para `tolerationSeconds=10`

**Referência:** ADR-025 - Graceful Node Drain Strategy

---

## Manifests

### 1. CoreDNS PDB (`coredns-pdb-override.yaml`)

**Função:** Permite eviction de 1 pod CoreDNS durante drain, mantendo 1 pod ativo (HA)

**Como aplicar:**
```bash
kubectl apply -f coredns-pdb-override.yaml
```

**Validar:**
```bash
kubectl get pdb coredns -n kube-system -o yaml
# Deve mostrar: maxUnavailable: 1, disruptionsAllowed: 1
```

---

### 2. Calico Node DaemonSet Tolerations (`calico-node-daemonset-tolerations.yaml`)

**Função:** Adiciona tolerations curtas (10s) para permitir eviction rápida durante drain

**NOTA:** Este é um **example manifest**. Calico é gerenciado pelo EKS add-on ou Helm.

**Opção A: Aplicar via kubectl patch (one-time)**
```bash
kubectl patch daemonset calico-node -n kube-system --type='json' \
  -p='[
    {"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"node.kubernetes.io/not-ready","operator":"Exists","effect":"NoExecute","tolerationSeconds":10}},
    {"op":"add","path":"/spec/template/spec/tolerations/-","value":{"key":"node.kubernetes.io/unreachable","operator":"Exists","effect":"NoExecute","tolerationSeconds":10}}
  ]'
```

**Opção B: Aplicar via Terraform (persistente)**
```terraform
# modules/calico/tolerations.tf (criar se não existir)
resource "kubernetes_manifest" "calico_node_tolerations" {
  manifest = yamldecode(file("${path.module}/calico-node-daemonset-tolerations.yaml"))
}
```

**Validar:**
```bash
kubectl get daemonset calico-node -n kube-system -o jsonpath='{.spec.template.spec.tolerations}' | jq '.[] | select(.key=="node.kubernetes.io/not-ready")'
# Deve mostrar: tolerationSeconds: 10
```

---

## Aplicação via Terraform

Para persistir esses manifests, adicione ao módulo Terraform:

```terraform
# platform-provisioning/aws/kubernetes/terraform/modules/finops/kubectl-manifests.tf

resource "kubectl_manifest" "coredns_pdb" {
  yaml_body = file("${path.module}/kubectl-manifests/finops-pdb/coredns-pdb-override.yaml")
}

# Calico: aplicar apenas se não gerenciado por Helm/EKS add-on
# resource "kubectl_manifest" "calico_node_tolerations" {
#   yaml_body = file("${path.module}/kubectl-manifests/finops-pdb/calico-node-daemonset-tolerations.yaml")
# }
```

**IMPORTANTE:** Verifique se Calico é gerenciado por Helm antes de aplicar manifest diretamente.

---

## Teste de Drain

Após aplicar as mudanças, testar tempo de drain:

```bash
# 1. Selecionar 1 worker node (não critical)
NODE=$(kubectl get nodes -l node-role=worker -o jsonpath='{.items[0].metadata.name}')

# 2. Marcar como unschedulable (cordon)
kubectl cordon $NODE

# 3. Medir tempo de drain
time kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --timeout=5m

# Expectativa: <3min até "node drained"

# 4. Uncordon após teste
kubectl uncordon $NODE
```

**Critérios de sucesso:**
- Drain completa em <3min
- Zero erros "cannot evict pod as it would violate the pod's disruption budget"
- Pods rescheduleados com sucesso em outros nodes
- CoreDNS mantém 1 pod ativo durante drain (HA)

---

## Rollback

Se houver problemas, remover PDBs:

```bash
# CoreDNS PDB
kubectl delete pdb coredns -n kube-system

# Calico tolerations (se aplicado via patch)
# Requer rollback manual via kubectl edit ou Helm upgrade --reset-values
```

---

## Documentação

- **ADR-025:** `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/adr/adr-025-pdb-graceful-drain.md`
- **Logbook:** `/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/logbook/2026-02-24-finops-pdb-optimization.md`
- **FinOps Lambda:** `/home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/lambdas/finops-automation/`

---

**Autor:** DevOps Team
**Data:** 2026-02-24
**Status:** Ready for Testing

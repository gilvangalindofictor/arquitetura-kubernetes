# GAP-003 — Terraform Import Guide

**Data dos recursos criados manualmente:** 2026-03-05/06  
**Cluster:** k8s-platform-prod (EKS us-east-1, conta 891377105802)  
**State bucket:** `terraform-state-marco0-891377105802`  
**Módulo TF:** `platform-provisioning/aws/kubernetes/terraform/modules/backstage/`

---

## Contexto

4 recursos foram criados manualmente no cluster e não estão no Terraform state.
O próximo `terraform apply` retornará `409 Conflict` sem o import abaixo.

---

## Recursos a Importar

### 1. `kubernetes_namespace.backstage`

- **Namespace:** `staging-platform-backstage`
- **ID de import:** nome do namespace

```bash
terraform import module.backstage.kubernetes_namespace.backstage staging-platform-backstage
```

---

### 2. `kubernetes_cluster_role.backstage_kubernetes_reader`

- **ClusterRole:** `backstage-kubernetes-reader`
- **ID de import:** nome do ClusterRole (recurso cluster-scoped, sem namespace)

```bash
terraform import module.backstage.kubernetes_cluster_role.backstage_kubernetes_reader backstage-kubernetes-reader
```

---

### 3. `kubernetes_pod_disruption_budget_v1.backstage_pdb`

- **Namespace:** `staging-platform-backstage`
- **Nome:** `backstage-pdb`
- **ID de import:** `namespace/name`

```bash
terraform import module.backstage.kubernetes_pod_disruption_budget_v1.backstage_pdb staging-platform-backstage/backstage-pdb
```

---

### 4. `kubectl_manifest.backstage_linkerd_exception`

- **Tipo:** Kyverno `PolicyException` (CRD)
- **Namespace:** `staging-platform-backstage`
- **Nome:** `backstage-linkerd-exception`
- **ID de import:** `apiVersion/kind/namespace/name`

```bash
terraform import module.backstage.kubectl_manifest.backstage_linkerd_exception \
  kyverno.io/v2beta1/PolicyException/staging-platform-backstage/backstage-linkerd-exception
```

---

## Sequência Recomendada

Execute na ordem abaixo para evitar dependências quebradas (namespace deve existir no state antes do PDB e do PolicyException):

```bash
# 1. Namespace (base de tudo)
terraform import module.backstage.kubernetes_namespace.backstage \
  staging-platform-backstage

# 2. ClusterRole (cluster-scoped, sem dependência de namespace no state)
terraform import module.backstage.kubernetes_cluster_role.backstage_kubernetes_reader \
  backstage-kubernetes-reader

# 3. PDB (namespaced, depende do namespace estar no state)
terraform import module.backstage.kubernetes_pod_disruption_budget_v1.backstage_pdb \
  staging-platform-backstage/backstage-pdb

# 4. PolicyException Kyverno (CRD namespaced via kubectl_manifest)
terraform import module.backstage.kubectl_manifest.backstage_linkerd_exception \
  kyverno.io/v2beta1/PolicyException/staging-platform-backstage/backstage-linkerd-exception
```

---

## Pós-Import

Após todos os imports, verifique drift restante:

```bash
terraform plan -target=module.backstage 2>&1 | tail -20
```

Resultado esperado: `No changes. Your infrastructure matches the configuration.`

---

## Troubleshooting

| Erro | Causa | Solução |
|------|-------|---------|
| `Resource already managed by Terraform` | Recurso já está no state | Execute `terraform state list \| grep backstage` para verificar |
| `404 Not Found` | Recurso não existe no cluster | Confirme com `kubectl get <resource> -n staging-platform-backstage` |
| `409 Conflict` | State desatualizado | Execute `terraform refresh -target=module.backstage` antes |
| `Error: Invalid resource address` | Endereço do módulo incorreto | Verifique o nome do módulo em `terraform state list` |

---

## Script Automatizado

Use o script em `scripts/backstage-tf-import.sh` para executar todos os imports de forma automatizada.

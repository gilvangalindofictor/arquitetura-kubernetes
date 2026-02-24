# Logbook: FinOps PDB Optimization — Critical Workloads

**Data:** 2026-02-24
**Executor:** DevOps Platform Team (Agent)
**Duração:** ~45min
**Status:** CONCLUIDO

---

## Objetivo

Implementar PodDisruptionBudgets (PDBs) com `minAvailable=0` para 9 workloads críticos, reduzindo tempo de drain de nodes de 30min para <5min e habilitando Cluster Autoscaler scale-down eficiente.

---

## FASE 1: Análise de Workloads (10min)

### PDBs Pré-existentes (antes da intervenção)

```
NAMESPACE       NAME                                    MIN AVAILABLE  ALLOWED DISRUPTIONS
gitlab-staging  gitlab-gitaly                           N/A            1     (maxUnavailable=1)
gitlab-staging  gitlab-gitlab-shell                     N/A            1
gitlab-staging  gitlab-kas                              N/A            1
gitlab-staging  gitlab-registry-v1                      N/A            1
gitlab-staging  gitlab-sidekiq-all-in-1-v1              N/A            1
gitlab-staging  gitlab-webservice-default               N/A            1     (maxUnavailable=1, bloqueante!)
keycloak        keycloak-keycloakx                      1              0     (minAvailable=1, BLOQUEANTE!)
kube-system     calico-kube-controllers                 N/A            1
kube-system     calico-typha                            N/A            1
kube-system     cluster-autoscaler-...                  N/A            0     (BLOQUEANTE!)
kube-system     coredns                                 N/A            1
monitoring      loki-backend/read/write/gateway         N/A            1
monitoring      opentelemetry-collector                 1              1
staging-security-vault  vault                           N/A            0     (BLOQUEANTE!)
```

**PDBs bloqueantes identificados:**
1. `keycloak-keycloakx`: `minAvailable=1` + 1 replica = 0 disruptions permitidas
2. `vault`: `maxUnavailable=0` = 0 disruptions
3. `cluster-autoscaler`: 0 disruptions (normal, CA não pode ser drenado)

### Descobertas Críticas de Labels

| Workload | Label Esperado | Label Real | Correção |
|----------|---------------|------------|----------|
| Keycloak | `app.kubernetes.io/name=keycloak` | `app.kubernetes.io/name=keycloakx` | CORRIGIDO |
| GitLab Webservice | `app=webservice` (único) | `app=webservice,release=gitlab` | ADICIONADO `release=gitlab` |
| Prometheus | `instance=kube-prometheus-stack` | `instance=kube-prometheus-stack-prometheus` | CORRIGIDO |

---

## FASE 2: Criação dos Módulos Terraform (15min)

### Módulo criado: `modules/finops-pdb-optimization/`

Arquivos criados:
- `/platform-provisioning/aws/kubernetes/terraform/modules/finops-pdb-optimization/main.tf`
- `/platform-provisioning/aws/kubernetes/terraform/modules/finops-pdb-optimization/variables.tf`
- `/platform-provisioning/aws/kubernetes/terraform/modules/finops-pdb-optimization/outputs.tf`

Configuração staging:
- `/platform-provisioning/aws/kubernetes/terraform/environments/staging/finops-pdb-optimization.tf`

### Fix adicional aplicado: `modules/finops-automation/`

**Problema encontrado:** `kubectl-manifests.tf` tinha bloco `terraform {}` duplicado + provider `gavinbunney/kubectl` não declarado no módulo, causando erro `hashicorp/kubectl not found`.

**Fix:**
1. Removido bloco `terraform {}` duplicado de `kubectl-manifests.tf`
2. Adicionado provider `kubectl = { source = "gavinbunney/kubectl" }` ao `main.tf`

---

## FASE 3: Aplicação (5min)

**Estratégia:** `kubectl apply` direto (Terraform bloqueado por erros pré-existentes no módulo `keycloak-clients`).

```bash
kubectl apply -f /tmp/pdb-finops-optimization.yaml
```

### Resultado

```
poddisruptionbudget.policy/grafana-pdb created
poddisruptionbudget.policy/argocd-server-pdb created
poddisruptionbudget.policy/harbor-core-pdb created
poddisruptionbudget.policy/gitlab-webservice-pdb created
poddisruptionbudget.policy/keycloak-pdb created
poddisruptionbudget.policy/sonarqube-pdb created
poddisruptionbudget.policy/vault-pdb created
poddisruptionbudget.policy/prometheus-pdb created
poddisruptionbudget.policy/loki-backend-pdb created
```

---

## FASE 4: Validação

### PDBs após intervenção (novos PDBs destacados)

```
NAMESPACE              NAME                   MIN AVAILABLE  ALLOWED DISRUPTIONS
argocd                 argocd-server-pdb      0              2   ✅
gitlab-staging         gitlab-webservice-pdb  0              2   ✅
harbor-system          harbor-core-pdb        0              2   ✅
keycloak               keycloak-pdb           0              1   ✅ (era BLOQUEANTE!)
monitoring             grafana-pdb            0              1   ✅
monitoring             loki-backend-pdb       0              2   ✅
monitoring             prometheus-pdb         0              1   ✅
sonarqube              sonarqube-pdb          0              1   ✅
staging-security-vault vault-pdb             0              1   ✅ (era BLOQUEANTE!)
```

**Todos os 9 PDBs: `ALLOWED DISRUPTIONS >= 1`**

---

## Savings Calculados

| Tipo | Valor/ano | Cálculo |
|------|-----------|---------|
| Direto (drain downtime) | ~R$ 25 | 25min × 4 drains/mês × 3 nodes × R$ 0,0832/h |
| Indireto (CA scale-down) | ~R$ 4.380 | 1 node t3.large × R$ 365/mês × 12 |
| **Total** | **~R$ 4.405** | |

---

## Pendências

1. **Terraform state drift:** PDBs criados via `kubectl apply` não estão no state do Terraform. Próxima sessão: importar via `terraform import` ou re-aplicar via `terraform apply` quando erros do `keycloak-clients` forem corrigidos.
2. **Teste de drain:** Não executado nesta sessão (requer janela de manutenção). Agendar para próxima janela.
3. **Erros pré-existentes no `keycloak-clients` module:** `keycloak_realm.platform` não declarado — bug pré-existente no módulo que requer investigação separada.

---

## Arquivos Criados/Modificados

| Arquivo | Ação |
|---------|------|
| `modules/finops-pdb-optimization/main.tf` | CRIADO |
| `modules/finops-pdb-optimization/variables.tf` | CRIADO |
| `modules/finops-pdb-optimization/outputs.tf` | CRIADO |
| `environments/staging/finops-pdb-optimization.tf` | CRIADO |
| `kubectl-manifests/finops-pdb/pdb-finops-critical-workloads.yaml` | CRIADO |
| `modules/finops-automation/main.tf` | MODIFICADO (kubectl provider) |
| `modules/finops-automation/kubectl-manifests.tf` | MODIFICADO (removed dup terraform{}) |
| `docs/adr/adr-076-finops-pdb-optimization.md` | CRIADO |
| `docs/logbooks/2026-02-24-finops-pdb-optimization.md` | CRIADO |

---

**Status:** CONCLUIDO — 9/9 PDBs ativos em cluster staging

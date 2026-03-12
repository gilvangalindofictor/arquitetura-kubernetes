# Auditoria de Namespaces — AppProjects ArgoCD
**Data:** 2026-03-12
**GAP:** GAP-SEC-03a
**Status:** IMPLEMENTADO
**Autor:** Platform Team (via Documentation Specialist)

---

## Contexto

A ClusterPolicy `enforce-argocd-appproject-destinations` (GAP-SEC-03) foi criada em modo **Audit**
para não bloquear AppProjects legados que usam namespaces fora do padrão ADR-048.

Esta auditoria identifica os desvios existentes, classifica como legítimos ou de risco, e define
o caminho para transição da policy para **Enforce**.

---

## Resultado por AppProject

### platform.yaml
`/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/modules/argocd/projects/platform.yaml`

| Namespace | Padrão ADR-048? | Na Allowlist? | Classificação | Ação |
| --- | --- | --- | --- | --- |
| `keycloak` | ❌ | ✅ | Namespace de sistema — legítimo | Nenhuma |
| `sonarqube` | ❌ | ✅ | Namespace de sistema — legítimo | Nenhuma |
| `vault-system` | ❌ | ✅ | Namespace de sistema — legítimo | Nenhuma |
| `gitlab` | ❌ | ✅ | Namespace de sistema — legítimo | Nenhuma |
| `harbor` | ❌ | ✅ | Namespace de sistema — legítimo | Nenhuma |
| `monitoring` | ❌ | ✅ | Namespace de sistema — legítimo | Nenhuma |
| `cert-manager` | ❌ | ✅ | Namespace de sistema — legítimo | Nenhuma |
| `external-secrets` | ❌ | ✅ | Namespace de sistema — legítimo | Nenhuma |
| `kube-system` | ❌ | ✅ | Namespace de sistema — legítimo | Nenhuma |

**Resultado platform.yaml:** ✅ **100% CONFORME** — todos os namespaces estão na allowlist de sistema.

---

### applications.yaml
`/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/modules/argocd/projects/applications.yaml`

| Namespace | Padrão ADR-048? | Na Allowlist? | Classificação | Ação |
| --- | --- | --- | --- | --- |
| `default` | ❌ | ✅ | Namespace Kubernetes padrão | Nenhuma |
| `staging` | ❌ | ⚠️ pré-auditoria | Legado pré-ADR-048 — workloads app | Adicionado à allowlist (2026-03-12) |
| `production` | ❌ | ⚠️ pré-auditoria | Legado pré-ADR-048 — workloads app | Adicionado à allowlist (2026-03-12) |
| `development` | ❌ | ⚠️ pré-auditoria | Legado pré-ADR-048 — workloads app | Adicionado à allowlist (2026-03-12) |
| `apps-*` (pattern) | ✅ | ✅ | Conforme ADR-048 | Nenhuma |

**Resultado applications.yaml:** ⚠️ **3 namespaces legados** — adicionados à allowlist Kyverno.
Migração para `staging-apps`, `prod-apps`, `dev-apps` planejada (ver Recomendações).

---

### appproject-data.yaml
`/ETL/Hatch/k8s/argocd/appproject-data.yaml`

| Namespace | Padrão ADR-048? | Na Allowlist? | Classificação | Ação |
| --- | --- | --- | --- | --- |
| `staging-data-*` (pattern) | ✅ | ✅ | Conforme ADR-048 (`staging-{domain}-*`) | Nenhuma |

**Resultado appproject-data.yaml:** ✅ **100% CONFORME** — modelo correto para novos AppProjects.

---

## Kyverno Policy — Ajustes Realizados

**Arquivo:** `domains/platform-core/app-provisioning/templates/kyverno-argocd-governance.yaml`

**Adicionado à allowlist** da rule `validate-destination-namespace-pattern`:
```yaml
# GAP-SEC-03a (2026-03-12): namespaces legados applications.yaml
# Pre-ADR-048 — migração para staging-apps/prod-apps/dev-apps planejada
- "staging"
- "production"
- "development"
```

**Razão:** Namespaces são legítimos (pré-ADR-048), policy em Audit mode. A adição previne
alertas de Audit ruidosos que obscureciam violações reais.

---

## Pré-condições para Audit → Enforce

Antes de mover `enforce-argocd-appproject-destinations` para **Enforce**, as seguintes
condições devem ser satisfeitas:

| # | Condição | Status | Responsável |
| --- | --- | --- | --- |
| 1 | `prod-platform-argocd` namespace provisionado (ADR-105) | ⏳ Pendente | Platform Team |
| 2 | Namespaces `staging`/`production`/`development` migrados para `staging-apps`/`prod-apps`/`dev-apps` | ⏳ Pendente — applications.yaml update + workloads | App Team |
| 3 | Namespaces de sistema (`keycloak`, `vault-system`, etc.) migrados para `staging-platform-*` (ADR-048 completo) | ⏳ Backlog — baixa prioridade | Platform Team |
| 4 | Mesa técnica aprovando transição para Enforce | ⏳ Pendente (após 1-3) | Platform Team |

---

## Recomendações

### Curto prazo (antes de Enforce)
1. **Migrar `applications.yaml` destinations**: `staging` → `staging-apps`, `production` → `prod-apps`, `development` → `dev-apps`
2. Criar namespace `staging-apps` no cluster e migrar workloads de aplicação
3. Após migração e validação, remover `staging`/`production`/`development` da allowlist Kyverno
4. Rodar `kubectl get policy enforce-argocd-appproject-destinations -o yaml` e verificar relatório de Audit antes de promover para Enforce

### Longo prazo (ADR-048 completo)
5. Migrar namespaces de sistema de nomes simples (`keycloak`, `vault-system`, etc.) para `staging-platform-keycloak`, `staging-platform-vault`, etc.
6. Atualizar AppProject `platform.yaml` destinations após migração
7. Mover policy para **Enforce** após confirmação de 0 violações em Audit por 30 dias

---

## Referências

- ADR-048: Naming convention `{env}-{domain}-{product}`
- ADR-105: ArgoCD multi-environment model (OPÇÃO A, 4-0)
- GAP-SEC-03: Kyverno ClusterPolicies ArgoCD (resolvido 2026-03-12)
- GAP-SEC-03a: Este documento (auditoria namespace drift)

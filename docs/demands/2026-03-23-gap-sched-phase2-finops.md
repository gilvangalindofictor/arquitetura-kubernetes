# GAP-SCHED-002 Phase 2 + GAP-FINOPS-002 (2026-03-23)

**Data**: 2026-03-23
**Cluster**: k8s-platform-staging + k8s-platform-prod | Conta: 891377105802 | Região: us-east-1
**Sessão**: Continuação de GAP-SCHED-001 Phase 1 (mesma data)
**Prioridade**: ALTO (GAP-SCHED-002) + MÉDIO (GAP-FINOPS-002)
**Status**: CONCLUÍDA — TF ZERO DRIFT

---

## Objetivo

Migrar StatefulSets identificados em system/critical nodes para o workloads nodegroup, sem
perda de dados e com downtime mínimo. Em seguida, aplicar redução de max_size do system ASG
para capturar saving preventivo.

---

## Contexto

GAP-SCHED-001 Phase 1 (Deployments) concluída na mesma sessão com zero disruption.
Phase 2 foca nos StatefulSets — workloads com PVC ReadWriteOnce que exigem análise de
StorageClass (WaitForFirstConsumer vs Immediate) antes de qualquer migração.

Root cause do GAP-SCHED: system nodes sem taint `CriticalAddonsOnly` — scheduler usa-os como
overflow para workloads sem `nodeSelector` (ver Lição 21 em strategies-consolidado.md).

---

## Entregas

### GAP-SCHED-002 — StatefulSets migrados para workloads nodegroup

| Target | Namespace | De | Para | Downtime | Técnica |
| --- | --- | --- | --- | --- | --- |
| loki-chunks-cache-0 | staging-observability-monitoring | system | workloads | ~30s | rolling update (stateless) |
| loki-write-0/1 | staging-observability-monitoring | critical | workloads | ~2min | rolling update |
| loki-backend-0/1 | staging-observability-monitoring | system | workloads | ~3min | rolling update (gp3 WaitForFirstConsumer) |
| sonarqube-sonarqube-0 | staging-platform-sonarqube | system | workloads us-east-1a | ~5min | scale 0→1, PVC reutilizado |
| vault-prod (x3) | prod-security-vault | workloads (sem selector) | workloads (com selector) | ~8min | rolling restart (KMS auto-unseal) |

**Técnica chave (Lição 22):** PVC `gp3 WaitForFirstConsumer` é zone-pinned, não node-pinned.
A migração de nodeSelector é segura desde que haja nodes workloads na mesma AZ do PVC.
Não é necessário deletar PVC.

### GAP-FINOPS-002 — System ASG max_size redução

| Parâmetro | Antes | Depois |
| --- | --- | --- |
| system nodegroup max_size | 6 | 4 |
| Saving estimado | — | ~$360-720/ano (~R$ 2.160-4.320/ano) |

Arquivo: `environments/staging/node-groups.tf`

---

## Arquivos Modificados

| Arquivo | Mudança |
| --- | --- |
| `modules/loki/main.tf` | nodeSelector set blocks para chunks-cache, backend, write |
| `modules/sonarqube/values.yaml.tpl` | nodeSelector: workloads |
| `modules/vault/variables.tf` | variável node_selector (map(string), default {}) |
| `modules/vault/main.tf` | node_selector passado ao templatefile() |
| `modules/vault/values.yaml.tpl` | bloco condicional nodeSelector (length > 0) |
| `environments/prod/main.tf` | node_selector = {"eks.amazonaws.com/nodegroup" = "workloads"} |
| `environments/staging/node-groups.tf` | max_size 6→4 (system nodegroup) |

---

## TF Zero Drift Confirmado

Módulos com drift zerado nesta sessão:

- `module.tempo`
- `module.finops_automation`
- `module.loki` / `module.loki_staging`
- `module.backstage`
- `module.opentelemetry_collector`

---

## Resultado

- GAP-SCHED-002: CONCLUÍDA — 5 StatefulSets em workloads nodegroup
- GAP-FINOPS-002: CONCLUÍDA — ASG max_size 6→4 aplicado
- TF ZERO DRIFT em todos os módulos
- Vault-prod: rolling restart concluído (KMS auto-unseal confirmado)
- SonarQube: PVC reutilizado sem data loss

---

## Lições Aprendidas

- **Lição 22**: gp3 WaitForFirstConsumer = zone-pinned, não node-pinned. Ver strategies-consolidado.md.
- **TF state note**: `module.loki_staging` é o target correto no TF state (não `module.loki`) quando múltiplos environments usam o mesmo módulo.

---

## Referências

- `docs/demands/2026-03-23-gap-sched-node-affinity.md` — contexto GAP-SCHED Phase 1
- `docs/logbook/strategies-consolidado.md` — Lição 21 (nodeSelector) e Lição 22 (gp3 WaitForFirstConsumer)

# Demanda: IaC Compliance Migration — Eliminar Drift Terraform

**Data:** 2026-03-05
**Prioridade:** HIGH (compliance / governanca)
**Status:** CONCLUIDO
**ADR:** [ADR-100](../adr/adr-100-iac-compliance-terraform-helm-nodegroups.md)
**Agentes:** 5 (Promtail, Velero, Loki, NodeGroups, DocSpecialist)

## Problema

Cluster Audit 2026-03-05 identificou 4 componentes fora do Terraform state:

1. Promtail helm rev 8 — instalado manualmente
2. Velero helm rev 11 — instalado manualmente
3. Loki helm rev 18 — modulo existente mas nao instanciado
4. EKS Node Groups (system, workloads, critical) — criados via AWS CLI

## Scope

| Item | Modulo TF | Import Target | Resultado |
|------|-----------|---------------|-----------|
| Promtail | `modules/promtail/` | `helm_release.promtail` | tf-managed |
| Velero Helm | `modules/velero-helm/` | `helm_release.velero` | tf-managed |
| Loki | `modules/loki` instanciado | `helm_release.loki` | tf-managed |
| Node Group system | `node-groups.tf` | `aws_eks_node_group.system` | tf-managed |
| Node Group workloads | `node-groups.tf` | `aws_eks_node_group.workloads` | tf-managed |
| Node Group critical | `node-groups.tf` | `aws_eks_node_group.critical` | tf-managed |

## Resultado

- Compliance IaC: 100% (zero drift nos componentes auditados)
- Disruption de servico: ZERO (import nao reinicia recursos)
- Enterprise Maturity: 4.4/5.0 mantido (sem regressao)

## IaC Debt Residual

| Item | Descricao | Acao Futura |
|------|-----------|-------------|
| `lifecycle { ignore_changes = [values] }` | Loki e Promtail — values gerenciados externamente | Revisar em 90d; remover se valores estabilizados |
| Node group sizing | Importado com config atual; ajustes via TF apply | VPA report (Day 7) guia rightsizing |
| Velero schedules | CRDs fora do Helm values — comportamento intencional | Documentado como decisao de design |

## Logbook

- [2026-03-05-iac-compliance-migration.md](../logbook/2026-03-05-iac-compliance-migration.md)

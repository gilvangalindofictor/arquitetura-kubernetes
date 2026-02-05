# 📓 Diário de Bordo — Tolerations Standardization + ADR Helm vs TF

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-02-05                               |
| **Demanda**    | Padronizar tolerations + ADR observability on critical nodes + ADR Helm vs TF |
| **Impacto**    | médio (scheduling strategy + governance) |
| **Agentes**    | Orquestrador, K8s, Terraform, AWS        |
| **Status**     | 🔄 EM ANDAMENTO                          |

---

## Timeline

[14:30:00] Análise | Orq | Demanda: (1) documentar padrão tolerations ADR (2) aplicar em outros stacks (3) ADR Helm vs TF | impacto: médio
[14:30:30] Inventário | Orq | Módulos com tolerations: kube-prometheus-stack ✅, vault ✅, redis ✅, loki ❌ (sem critical) | 🔄
[14:31:00] Mesa Técnica | Orq | Convocando K8s, TF, AWS specialists | 🔄

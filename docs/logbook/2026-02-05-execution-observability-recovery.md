# 📓 Diário de Bordo — Observability Stack Recovery

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-02-05                               |
| **Demanda**    | Resolver Prometheus/Alertmanager/Grafana Pending 5+ dias |
| **Impacto**    | médio (observability down afeta visibilidade) |
| **Agentes**    | Orquestrador, K8s, Terraform              |
| **Status**     | ✅ CONCLUÍDO                              |
| **Duração**    | 7min 31s (13:46:01 → 13:53:32)            |

---

## Timeline

[13:46:01] Análise | Orq | Demanda: aplicar tolerations workload=critical em obs stack | impacto: médio
[13:46:25] Consenso | K8s,Orq | Aprovado — Helm upgrade Opção A | ✅
[13:46:40] Validação | K8s | AWS auth OK | Pods: alertmanager 0/2 (5d22h), grafana 0/3 (19h), prometheus 0/2 (19h) | ✅
[13:46:50] Backup | Helm | Salvando current values | ✅
[13:46:47] Helm Upgrade | Helm | Iniciado task bff4dc2 | 🔄
[13:47:30] AML-C3 | Helm | Upgrade failed: nil pointer grafana.operator config | ❌
[13:47:35] Análise | Orq | --reuse-values + --set conflict | Mudando estratégia: values file
[13:48:00] Edição | Orq | Adicionadas 3 tolerations workload=critical ao values.yaml | ✅
[13:48:58] Helm Upgrade v2 | Helm | Iniciado task b99fea9 com values file | 🔄
[13:49:45] Helm Done | Helm | Upgrade v2 completed exit 0 | ✅
[13:49:50] Análise | K8s | Pods recriados mas Pending: nodeSelector=system bloqueando critical nodes | ❌
[13:50:10] Correção | Orq | Removidos 3x nodeSelector, mantidas tolerations | ✅
[13:51:29] Helm Upgrade v3 | Helm | Iniciado task bd01eac sem nodeSelector | 🔄
[13:51:50] Helm Done | Helm | Upgrade v3 completed exit 0, chart 81.4.2 | ✅
[13:52:00] Scheduling | K8s | 3 pods schedulados em critical nodes | ✅
[13:52:30] AML-C4 | K8s | alertmanager 2/2, grafana 2/3, prometheus 1/2 Running | 🔄
[13:53:30] Validação | K8s | Todos 3/3 ou 2/2 Running | ✅ 72s startup
[13:53:32] Tolerations | K8s | Validadas: node-type=system + workload=critical | ✅
[13:53:35] Cleanup | K8s | Pod antigo removido automaticamente | ✅
[13:54:00] DocSync | Orq | architecture.md atualizado (scheduling strategy) | ✅

---

## Sumário Final

**Problema:** Prometheus, Alertmanager, Grafana Pending 5+ dias devido a `nodeSelector: node-type=system` bloqueando scheduling em critical nodes

**Root Cause:** Nodes system (2x t3.medium) sem capacidade; taint `workload=critical` não tolerado

**Solução:**
1. Adicionadas tolerations `workload=critical:NoSchedule` (3 componentes)
2. Removido nodeSelector (permitir scheduler escolher entre system/critical nodes)
3. Helm upgrade v3 com values file completo

**Resultado:**
- Todos pods Running em critical nodes (t3.xlarge com capacidade)
- Alertmanager: ip-10-0-134-10 (critical)
- Grafana + Prometheus: ip-10-0-151-94 (critical)
- Duração recovery: 7min 31s
- Helm release: rev 3, chart 81.4.2

**Docs Atualizados:**
- [architecture.md](../context/architecture.md) — Scheduling strategy section
- [logbook](2026-02-05-execution-observability-recovery.md) — Timeline completa

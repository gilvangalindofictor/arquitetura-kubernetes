# 📓 Diário de Bordo — Harbor RWO PVC + Recreate Strategy

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-02-05                               |
| **Demanda**    | Fix Harbor RollingUpdate deadlock com RWO PVCs |
| **Impacto**    | alto                                     |
| **Agentes**    | Orquestrador, K8s, AWS, Terraform, Security |
| **Status**     | concluído                                |

---

## Timeline

[15:43:34] Análise | Orq | Harbor jobservice/registry RWO PVC + RollingUpdate = deadlock | impacto: alto
[15:43:34] Consenso | K8s,AWS,TF,Sec | Aprovar strategy Recreate p/ jobservice+registry | ✅
[15:43:34] Prep | Orq | Criando logbook + editando values.yaml.tpl | 🔄
[15:43:45] Edit | TF | values.yaml.tpl: strategy Recreate added (jobservice+registry) | ✅
[15:44:15] TF Plan | TF | 0 add, 1 change, 0 destroy | helm_release.harbor status failed→deployed | ✅
[15:46:00] TF Apply | TF | Iniciado background PID 25095 | 🔄
[15:59:00] ERRO | TF | Helm timeout context deadline exceeded após 13m+ | ❌
[15:59:10] Investigação | K8s | Verificando pods/logs/events Harbor | 🔍
[16:00:30] Diagnóstico | K8s | Confirmado: Multi-Attach jobservice+registry, strategy ainda RollingUpdate | ⚠️
[16:00:45] Fix Manual | K8s | Patch deployments → Recreate + delete pods antigos | 🔧
[16:01:00] Patch OK | K8s | Deployments strategy: Recreate confirmado | ✅
[16:01:15] PVC Freed | K8s | PVCs attach successful após delete pods antigos | ✅
[16:01:30] Pods UP | K8s | jobservice 1/1, registry 2/2 Running | ✅
[16:02:00] TF Apply Retry | TF | Novo plan + apply iniciado | 🔄
[16:05:53] Apply Done | TF | 1 changed, exit 0 | ✅ 3m53s
[16:06:00] Validação | K8s | Todos Harbor pods Running | ✅
[16:12:00] Conclusão | Orq | Fix completo: strategy Recreate aplicada, pods healthy | ✅
[16:17:00] DocSync | Orq | decisions.md (ADR-042 updated), logbook | ✅

---

## Sumário Executivo

**Problema:** Harbor jobservice/registry com PVCs RWO + strategy RollingUpdate causava Multi-Attach error durante upgrades (pods stuck ContainerCreating).

**Solução:** Aplicar `strategy: Recreate` em jobservice + registry deployments.

**Resultado:** ✅ Pods Running, PVC attach resolvido, Terraform state consolidado.

**Duração:** 29min (15:43 → 16:12)

**ADR:** ADR-044 - Harbor Recreate Strategy (RWO PVC Compatibility)

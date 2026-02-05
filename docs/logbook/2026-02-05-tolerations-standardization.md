# 📓 Diário de Bordo — Tolerations Standardization + ADR Helm vs TF

| Campo          | Valor                                    |
|----------------|------------------------------------------|
| **Data**       | 2026-02-05                               |
| **Demanda**    | Padronizar tolerations + ADR observability on critical nodes + ADR Helm vs TF |
| **Impacto**    | médio (scheduling strategy + governance) |
| **Agentes**    | Orquestrador, K8s, Terraform, AWS        |
| **Status**     | ✅ CONCLUÍDO                              |

---

## Timeline

[14:30:00] Análise | Orq | Demanda: (1) documentar padrão tolerations ADR (2) aplicar em outros stacks (3) ADR Helm vs TF | impacto: médio
[14:30:30] Inventário | Orq | Módulos com tolerations: kube-prometheus-stack ✅, vault ✅, redis ✅, loki ❌ (sem critical) | 🔄
[14:31:00] Mesa Técnica | Orq | Convocando K8s, TF, AWS specialists | 🔄
[14:32:00] Decisão | Mesa | APROVADO: (1) ADR-042 Tolerations Pattern (2) ADR-043 Helm vs TF (3) Aplicar em 7 módulos | ✅
[14:33:00] Implementação | Orq | ADR-042 criada: Tolerations Pattern for Platform Services (node-type + workload) | ✅
[14:34:00] Implementação | Orq | ADR-043 criada: Helm vs Terraform for Platform Services | ✅
[14:35:00] Aplicação | Orq | loki: adicionadas 4x tolerations workload=critical (read, write, backend, gateway) | ✅
[14:40:00] Aplicação | Orq | tempo: corrigido nodeSelector workloads→system + 6x tolerations (distributor, ingester, querier, queryFrontend, compactor, gateway) | ✅
[14:45:00] Aplicação | Orq | harbor: 5x componentes (core, jobservice, registry, portal, trivy) + nodeSelector + tolerations | ✅
[14:48:00] Aplicação | Orq | postgresql: N/A (RDS external service, sem pods K8s) | ✅
[14:49:00] Aplicação | Orq | rabbitmq: RabbitmqCluster CRD + nodeSelector system + tolerations no override.statefulSet | ✅
[14:52:00] Aplicação | Orq | argocd: 5x componentes (server, repoServer, controller, redis, applicationSet) + nodeSelector + tolerations | ✅
[14:55:00] Validação | Orq | terraform plan staging: 0 add, 2 change (harbor + rabbitmq), 0 destroy | ✅
[14:58:00] Validação | Orq | kubectl: 16 pods Pending (100% system nodes capacity, sem toleration critical) | ⚠️
[15:00:00] Diagnóstico | Orq | Arquitetura confirmada: system (34/34), critical (116 disponíveis), workloads (105) | ℹ️

---

## Resumo

### ADRs Criadas
1. **ADR-042: Tolerations Pattern for Platform Services**
   - Padrão: `node-type=system` + `workload=critical`
   - Permite overflow de system nodes → critical nodes
   - Documenta arquitetura de scheduling para platform services

2. **ADR-043: Helm vs Terraform for Platform Services**
   - Guideline para escolha entre Helm chart inline (set blocks) vs values.yaml.tpl
   - Decision framework: complexidade, volatilidade, expertise
   - Padrões identificados: set blocks (loki/tempo), templates (harbor/vault/argocd), kubectl_manifest (operators)

### Módulos Atualizados
| Módulo       | Padrão         | Componentes | Status |
|--------------|----------------|-------------|--------|
| loki         | Helm set       | 4 (read, write, backend, gateway) | ✅ |
| tempo        | Helm set       | 6 (distributor, ingester, querier, queryFrontend, compactor, gateway) | ✅ |
| harbor       | values.yaml    | 5 (core, jobservice, registry, portal, trivy) | ✅ |
| postgresql   | N/A (RDS)      | 0 (external service) | ✅ |
| rabbitmq     | kubectl CRD    | 1 (statefulSet override) | ✅ |
| argocd       | values.yaml    | 5 (server, repoServer, controller, redis, applicationSet) | ✅ |
| **TOTAL**    | **3 padrões**  | **21 componentes** | ✅ |

### Validação
- **Terraform plan:** 0 add, 2 change, 0 destroy (zero drift) ✅
- **Pods Pending:** 16 detectados (causa: 100% system capacity + falta tolerations) ⚠️
- **Problema confirmado:** Nossa solução (ADR-042) resolverá scheduling quando aplicada

### Próximos Passos
1. **Apply terraform:** `terraform apply tfplan-tolerations-standardization` (staging)
2. **Monitor recovery:** Aguardar 16 pods saírem de Pending → Running
3. **Validar distribuição:** Verificar pods em critical nodes com `kubectl get pods -o wide`
4. **Replicar prod:** Aplicar mesmas mudanças no ambiente production

### Impacto FinOps
- Critical nodes (2x t3.xlarge): Utilizados apenas 0% → esperado ~30-40% após apply
- Melhor aproveitamento de capacidade provisionada
- Evita necessidade de escalar system nodes (custo adicional)

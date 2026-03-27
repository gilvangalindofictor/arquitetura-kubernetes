# ADR-052: PLATFORM-SHARED Deve Usar System Nodes — FinOps Safety

## Status
ACCEPTED

## Contexto
Servicos classificados como PLATFORM-SHARED (Tier 2 — ADR-050) sao consumidos por multiplos ambientes (staging + prod) e possuem blast radius cross-environment. Quando esses servicos executam em workload nodes:
- Lambda FinOps pode escalar workload nodes para zero nos horarios de economia, derrubando servicos compartilhados (Harbor, GitLab, SonarQube)
- Workload pods competem por recursos com servicos de plataforma, causando evictions imprevisiveis
- Sem separacao, nao ha garantia de que servicos criticos sobrevivam a janelas de scale-down

Incidente de referencia: Lambda FinOps com `TARGET_NAMESPACES` incluindo namespaces de plataforma causou disrupcao (GAP-LAMBDA-002, resolvido 2026-03-27).

## Decisao
Todo servico classificado como PLATFORM-SHARED (Tier 2) DEVE executar em nodes com label `node-type=system` usando `nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution`. System nodes NAO sao gerenciados pela Lambda FinOps e possuem taints `node-type=system:NoSchedule`.

### Regras

1. **OBRIGATORIO**: Pods de servicos Tier 2 devem ter `nodeAffinity` para `node-type=system`
2. **OBRIGATORIO**: Pods de servicos Tier 2 devem ter `tolerations` para `node-type=system:NoSchedule`
3. **PROIBIDO**: Lambda FinOps NAO deve incluir system node groups no `TARGET_NODE_GROUPS`
4. **PROIBIDO**: Workloads Tier 4 NAO devem ter tolerations para system nodes

### Servicos Afetados (Tier 2 — ADR-050)

| Servico | Namespace | nodeAffinity system | Status |
|---------|-----------|---------------------|--------|
| GitLab | staging-platform-gitlab | Sim (ADR-051) | Aplicado |
| Harbor | staging-platform-harbor | Sim | Aplicado |
| SonarQube | staging-platform-sonarqube | Sim | Aplicado |
| Vault (prod) | prod-security-vault | Sim | Aplicado |
| ArgoCD (staging) | staging-platform-argocd | Sim | Aplicado |
| ArgoCD (prod) | prod-platform-argocd | Sim | Aplicado |
| ESO | external-secrets | Sim | Aplicado |

### Lambda FinOps — Fronteira de Atuacao

```
LAMBDA FINOPS SCOPE:
  ├─ workload node groups  → SCALE (min=0 weekends/nights)
  ├─ system node groups    → NEVER TOUCH
  └─ TARGET_NAMESPACES     → SOMENTE namespaces Tier 4 (workloads)
```

### Kyverno Policy Futura — Enforcement Automatizado

```yaml
# Planejado — sera implementado como ClusterPolicy
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: validate-tier2-system-node-affinity
spec:
  validationFailureAction: Audit  # Audit primeiro, Enforce apos validacao
  rules:
    - name: require-system-node-affinity
      match:
        any:
          - resources:
              kinds:
                - Deployment
                - StatefulSet
              namespaceSelector:
                matchLabels:
                  s6c.io/tier: platform-shared
      validate:
        message: "Tier 2 (PLATFORM-SHARED) workloads must have nodeAffinity for node-type=system"
        pattern:
          spec:
            template:
              spec:
                affinity:
                  nodeAffinity:
                    requiredDuringSchedulingIgnoredDuringExecution:
                      nodeSelectorTerms:
                        - matchExpressions:
                            - key: node-type
                              operator: In
                              values:
                                - system
```

**Roadmap da policy:**
1. Label `s6c.io/tier=platform-shared` em todos os namespaces Tier 2
2. Deploy policy em modo `Audit` — validar que todos os pods ja estao conformes
3. Migrar para modo `Enforce` apos 2 semanas sem violacoes

## Consequencias
- **Positivo**: Servicos PLATFORM-SHARED protegidos contra scale-to-zero FinOps
- **Positivo**: Isolamento de recursos — system nodes reservados para plataforma, workload nodes para aplicacoes
- **Positivo**: Kyverno policy automatiza enforcement — novos deploys nao-conformes sao bloqueados
- **Negativo**: System nodes precisam de capacidade suficiente para todos os servicos Tier 1 + Tier 2
- **Negativo**: Custo fixo de system nodes nao reduzivel por FinOps (by design)
- **Mitigacao**: Revisao trimestral de right-sizing dos system nodes via metricas Prometheus
- **Mitigacao**: Alertas PrometheusRule para system node capacity > 80%

## Validacao
- `kubectl get nodes -l node-type=system` retorna nodes dedicados
- `kubectl get pods --all-namespaces -o wide | grep system` confirma pods Tier 2 em system nodes
- Lambda FinOps `TARGET_NODE_GROUPS` NAO inclui system node groups
- Kyverno policy em modo Audit sem violacoes

## Referencias
- ADR-050: Classificacao de Servicos do Cluster em 4 Tiers
- ADR-051: GitLab Shared Namespace Staging
- ADR-019: FinOps
- GAP-LAMBDA-002: TARGET_NAMESPACES incluia prod-platform-backstage (resolvido 2026-03-27)

Data: 2026-03-27

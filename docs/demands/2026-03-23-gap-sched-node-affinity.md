# GAP-SCHED — Node Affinity Gaps (2026-03-23)

**Data**: 2026-03-23
**Cluster**: k8s-platform-staging | Conta: 891377105802 | Região: us-east-1
**Detectado por**: Agente PERF durante health check pós-UP
**Prioridade**: URGENTE (GAP-SCHED-001) → ALTO (GAP-SCHED-002) → MÉDIO (GAP-SCHED-003, GAP-FINOPS-002)

---

## Contexto

Detectado durante health check pós-UP de 2026-03-23.

Root cause: workloads sem `nodeSelector` espalharam-se para system nodes (t3.medium, max\_size=6) porque os system nodes **não possuem taint** — o scheduler os usa como overflow para workloads comuns (anti-pattern). Ambos system e workloads ASGs atingiram MAX simultâneamente, deixando o cluster no limite de scheduling. 12 workloads sem nodeSelector identificados em system nodes.

**Cluster Autoscaler:** deployment `cluster-autoscaler-aws-cluster-autoscaler` v1.31.0 (kube-system) escalou workloads ASG de 7→9 nodes durante o health check ao detectar pressão de pods.

---

## GAP-SCHED-001 — Deployments sem nodeSelector em system nodes [URGENTE]

**Status:** Phase 1 em execução (agentes TF ativos — 2026-03-23)
**Impacto:** system nodes (t3.medium) sobrecarregados com workloads que deveriam estar em workloads nodegroup (t3.large)

### Workloads Phase 1 — Deployments (zero disruption, rolling update)

| Namespace | Workload | Réplicas | Fix |
|---|---|---|---|
| staging-platform-gitlab | gitlab-kas | 2 | nodeSelector: workloads |
| staging-platform-gitlab | gitlab-toolbox | 1 | nodeSelector: workloads |
| staging-platform-gitlab | gitlab-runner | 1 | nodeSelector: workloads |
| staging-platform-backstage | backstage | 1 | nodeSelector: workloads |
| staging-governance-kyverno | kyverno-admission-controller | 1 | nodeSelector: workloads |
| staging-governance-kyverno | kyverno-reports-controller | 1 | nodeSelector: workloads |
| staging-observability-monitoring | opentelemetry-collector | 2 | nodeSelector: workloads |
| staging-observability-monitoring | loki-canary | 1 | nodeSelector: workloads |
| staging-observability-monitoring | yace | 1 | nodeSelector: workloads |
| prod-platform-harbor | harbor-prod-exporter | 1 | nodeSelector: workloads |

**nodeSelector a aplicar:**
```yaml
nodeSelector:
  eks.amazonaws.com/nodegroup: workloads
```

**Arquivos TF afetados:**
- `platform-provisioning/aws/kubernetes/terraform/modules/gitlab/` — kas, toolbox, runner
- `platform-provisioning/aws/kubernetes/terraform/modules/backstage/`
- `platform-provisioning/aws/kubernetes/terraform/modules/kyverno/` — admission, reports-controller
- `platform-provisioning/aws/kubernetes/terraform/modules/loki/` — canary
- `platform-provisioning/aws/kubernetes/terraform/environments/staging/main.tf` — yace, otel-collector
- `platform-provisioning/aws/kubernetes/terraform/environments/prod/main.tf` — harbor-prod-exporter

**Gate Phase 1:** Todos os Deployments listados com pods Running em workloads nodes. Zero pods desses workloads em system nodes. Zero drift Terraform.

---

## GAP-SCHED-002 — StatefulSets sem nodeSelector [ALTO — Phase 2]

**Status:** Pendente — requer migração planejada com PVC affinity (ReadWriteOnce)
**Risco:** Perda temporária de serviço durante migração (scale-down obrigatório)

### Workloads Phase 2 — StatefulSets (requerem PVC care)

| Namespace | Workload | Storage | Risco |
|---|---|---|---|
| staging-platform-sonarqube | sonarqube-sonarqube | PVC ReadWriteOnce | Serviço offline durante migração |
| staging-observability-monitoring | loki-backend | PVC | Logs degradados durante migração |
| staging-observability-monitoring | loki-chunks-cache | PVC | Logs degradados durante migração |
| prod-security-vault | vault-prod-2 | PVC (Raft storage) | Quorum reduz para 1/2 durante migração |

### Procedimento Phase 2 (por StatefulSet)

```
1. Verificar node atual do pod: kubectl get pod <pod> -o wide
2. Scale-down StatefulSet: kubectl scale sts/<name> --replicas=0
3. Deletar PVC se ReadWriteOnce e node-bound
4. Adicionar nodeSelector no StatefulSet spec
5. Scale-up: kubectl scale sts/<name> --replicas=1
6. Verificar pod Running no workloads node
7. Codificar no .tf correspondente
8. terraform plan → "No changes" (zero drift)
```

**Gate Phase 2:** Todos os StatefulSets listados com pods Running em workloads nodes. PVC recriados e bounds. Serviços restaurados. Zero drift Terraform.

---

## GAP-SCHED-003 — kube-prometheus-stack em system nodes [MÉDIO]

**Status:** Decisão arquitetural pendente
**Problema:** 4-5 pods do kube-prometheus-stack por system node — intencional (system nodegroup) mas contribui para sobrecarga.

### Opções Arquiteturais

| Opção | Descrição | Custo | Risco |
|---|---|---|---|
| A | Manter em system nodes, aumentar t3.medium → t3.large | Alto | Baixo |
| B | Mover todo monitoring stack para workloads nodegroup | Zero | Médio (DaemonSets node-exporter ficam) |
| C | Dividir: operator+alertmanager em system, demais em workloads | Zero | Baixo |

**Recomendação inicial:** Opção C — manter apenas componentes críticos de sistema (operator, alertmanager, kube-state-metrics) em system nodes; mover Prometheus, Grafana, Loki gateway para workloads nodegroup.

**Decisão:** Pendente — requer aprovação arquitetural antes de execução.

---

## GAP-FINOPS-002 — System ASG max\_size redução [MÉDIO]

**Status:** Aguardando Phase 1 + Phase 2 completion
**Arquivo:** `platform-provisioning/aws/kubernetes/terraform/environments/staging/node-groups.tf`

**Mudança:**
```hcl
# De:
max_size = 6  # system nodegroup
# Para:
max_size = 4  # system nodegroup — após Phase 1+2 completos
```

**Saving calculado:**
- 2x t3.medium On-Demand: ~$0.0416/h × 2 × 720h/mês = ~$60/mês
- **Anual: ~$720/ano (~R$4.320/ano)**

**Gate:** Phase 1 concluída + Phase 2 concluída + cluster health estável por 24h + zero pods de workload em system nodes + `terraform plan` retorna "No changes".

---

## Decisão Arquitetural Pendente — Taint em System Nodes

Após Phase 2 completa, avaliar adicionar taint nos system nodes para prevenção permanente:

```yaml
taints:
  - key: CriticalAddonsOnly
    value: "true"
    effect: NoSchedule
```

**Efeito:** Scheduler ignorará system nodes para workloads comuns. Apenas pods com `tolerations: CriticalAddonsOnly` poderão ser agendados — coredns, aws-node, kube-proxy, cluster-autoscaler, metrics-server.

**Pré-requisito obrigatório:** TODOS os workloads que devem rodar em system nodes precisam de tolerations explícitas antes de aplicar o taint. Aplicar taint prematuramente pode causar eviction em massa.

**ADR:** Criar ADR-XXX "nodeSelector obrigatório para todos os workloads" após Phase 2.

---

## Timeline de Execução

| GAP | Fase | Janela | Dependências |
|---|---|---|---|
| GAP-SCHED-001 | Phase 1 | 2026-03-23 (hoje) | Nenhuma |
| GAP-SCHED-002 | Phase 2 | Próxima sessão | Phase 1 concluída |
| GAP-SCHED-003 | Decisão | Próxima sessão | Phase 2 concluída |
| GAP-FINOPS-002 | Apply | Após Phase 2 | Phase 1+2 + 24h estável |

---

## Referências

- `docs/logbook/strategies-consolidado.md` — Lição 21: nodeSelector obrigatório em clusters com mixed nodegroups
- `platform-provisioning/aws/kubernetes/terraform/environments/staging/node-groups.tf`
- `platform-provisioning/aws/kubernetes/terraform/modules/`

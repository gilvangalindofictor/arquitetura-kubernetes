# Demanda: Revisão de Capacidade e Karpenter Migration

**Data**: 2026-03-17
**Prioridade**: P1
**Tipo**: Infrastructure / FinOps / Performance & Capacity
**Componentes afetados**: EKS Node Groups (system, workloads), Cluster Autoscaler, Karpenter, VPC CNI, Terraform módulo EKS
**Origem**: Mesa Técnica — Sessão de Health Check 2026-03-17
**Agentes**: AWS Specialist, Terraform Specialist, FinOps, Performance & Capacity, Security & Compliance
**ADRs relacionados**: A criar — ADR-XXX (Karpenter Adoption Decision), ADR-XXX (Instance Type Standardization)

---

## 1. Contexto e Motivação

Em 2026-03-17, o cluster EKS staging atingiu colapso de capacidade com os seguintes sintomas:

- **7 nodes ativos** (system: 3x t3.medium, workloads: 4x t3.large)
- **CPU 96-100%** em 4 dos 7 nodes
- **Pod limit de 17 pods/node** atingido nos t3.medium (restrição ENI nativa da AWS)
- **Cluster Autoscaler com réplicas = 0** — scale-out completamente bloqueado
- Toda a stack de plataforma (Backstage, ArgoCD, observabilidade, cert-manager, external-secrets) competindo por slots de pods em nodes com ENI saturado

O fix emergencial aplicado foi:
- Node group `system`: max 3 → 5
- Node group `workloads`: max 9 (já era adequado, problema era o desired)
- Reativar Cluster Autoscaler (réplicas 0 → 1)

Este fix é **paliativo**. A arquitetura atual de node groups com instâncias fixas e Cluster Autoscaler legado apresenta limitações estruturais que impactarão o cluster a cada ciclo de crescimento de workload.

---

## 2. Problema Atual

### 2.1 Restrição de Pod Limit — ENI Default da AWS

A AWS limita o número de pods por node com base no tipo de instância e no número de ENIs (Elastic Network Interfaces):

| Instance Type | ENIs | IPs por ENI | Max Pods (padrão VPC CNI) |
|---|---|---|---|
| t3.medium | 3 | 6 | 17 |
| t3.large | 3 | 12 | 35 |
| m5.large | 3 | 10 | 29 |
| m5.xlarge | 4 | 15 | 58 |
| c5.xlarge | 4 | 15 | 58 |

Com t3.medium no node group `system`, a plataforma está limitada a 17 pods por node — insuficiente para uma stack de platform engineering com mais de 10 componentes críticos.

**Alternativa**: Habilitar `ENABLE_PREFIX_DELEGATION` no VPC CNI, que aumenta o limite para `max(110, 2 * vCPUs + 1)`:

| Instance Type | Max Pods (prefix delegation) |
|---|---|
| t3.medium | 110 |
| t3.large | 110 |
| m5.large | 110 |

### 2.2 Cluster Autoscaler — Limitações Conhecidas

O Cluster Autoscaler (CA) opera com as seguintes limitações estruturais que impactam o cluster atual:

| Limitação | Impacto |
|---|---|
| Reage a pods `Unschedulable` — não é preditivo | Lag de 2-10 min entre necessidade e scale-out |
| Não suporta instâncias Spot nativamente (requer node group separado) | Custo mais alto sem flexibilidade de instância |
| Scale-in conservador — aguarda 10 min de underutilization | Custo de nodes ociosos prolongado |
| Um node group por tipo de instância — sem diversificação automática | Risco de indisponibilidade de tipo no AZ |
| Não gerencia workloads com `topologySpreadConstraints` complexas | Pode causar fragmentação |

### 2.3 FinOps — Custo de Instâncias On-Demand Fixas

O cluster opera 100% com instâncias On-Demand sem nenhum uso de Spot ou Savings Plans:

| Node Group | Tipo | Qtd atual | Custo/mês estimado (On-Demand us-east-1) |
|---|---|---|---|
| system | t3.medium | 3 | ~$105 |
| workloads | t3.large | 4 | ~$240 |
| **Total atual** | | **7 nodes** | **~$345/mês** |

Com Spot Instances para `workloads`, a economia estimada é de 60-70%:

| Cenário | Custo/mês estimado |
|---|---|
| On-Demand puro (atual) | ~$345 |
| System On-Demand + Workloads Spot | ~$180 (-48%) |
| System On-Demand + Workloads Spot + Karpenter bin-packing | ~$140 (-59%) |

---

## 3. Solução Proposta

### 3.1 Avaliação Karpenter vs Cluster Autoscaler

**Recomendação da Mesa Técnica**: Migrar para Karpenter no node group `workloads`. Manter Cluster Autoscaler como fallback durante período de transição.

**Comparativo técnico**:

| Critério | Cluster Autoscaler | Karpenter |
|---|---|---|
| Tempo de resposta (scale-out) | 2-10 min | 30-60 seg |
| Suporte a Spot | Node group separado | Nativo (NodePool) |
| Diversificação de instâncias | Manual (um node group por tipo) | Automático (múltiplos types) |
| Bin-packing | Limitado | Otimizado (consolidation nativo) |
| Integração EKS | Helm chart | EKS Add-on disponível |
| Complexidade de migração | — | Média (requer NodePool + NodeClass CRDs) |
| Suporte AWS | Mantido (legado) | Primeira classe no EKS |

**Decisão recomendada**: Adotar Karpenter para node group `workloads` (workloads não-críticos). Manter CA para node group `system` no curto prazo.

### 3.2 Revisão de Instance Types

**Node Group `system` (plataforma crítica)**:

- Problema atual: t3.medium (17 pods/node — insuficiente)
- Opção A: Habilitar prefix delegation no VPC CNI → t3.medium sobe para 110 pods/node (zero custo adicional)
- Opção B: Migrar para m5.large (2 vCPU, 8GB RAM) → mais memória para Backstage, ArgoCD, cert-manager
- **Recomendação**: Opção A (prefix delegation) como fix imediato + Opção B como meta de médio prazo

**Node Group `workloads` (ETL, dados, jobs)**:

- Hoje: t3.large On-Demand
- Karpenter NodePool com múltiplos tipos: `["t3.large", "t3.xlarge", "m5.large", "m5.xlarge", "c5.large"]`
- Priority: Spot → On-Demand fallback automático

### 3.3 Spot Instances para Workloads Não-Críticos

Workloads candidatos a Spot (tolerante a interrupção):

| Workload | Namespace | Tolerância a Spot |
|---|---|---|
| ETL/Hatch jobs | staging-data-hatch-etl | Alta (jobs idempotentes) |
| Loki | monitoring | Média (buffer no disco) |
| Tempo | monitoring | Alta (stateless) |
| Grafana | monitoring | Alta (stateless) |
| GitLab Runner | gitlab | Alta (jobs reexecutáveis) |
| Backstage | backstage | Baixa (stateful — DB) |
| ArgoCD | argocd | Baixa (crítico) |
| cert-manager | cert-manager | Baixa (crítico) |

Estratégia: `nodeSelector` ou `tolerations` para direcionar workloads tolerantes para nodes Spot via Karpenter NodePool dedicado.

### 3.4 Custom Networking EKS (VPC CNI Prefix Delegation)

Habilitar `ENABLE_PREFIX_DELEGATION` e `ENABLE_IPv4_PREFIX_DELEGATION` no addon `vpc-cni`:

```bash
# Aumenta max pods de 17 para 110 nos t3.medium
kubectl set env daemonset aws-node \
  ENABLE_PREFIX_DELEGATION=true \
  ENABLE_IPv4_PREFIX_DELEGATION=true \
  -n kube-system
```

Este change requer:
1. Codificação no módulo Terraform do EKS (addon `vpc-cni` com env vars)
2. Rolling restart dos nodes (draining + cordon) para renegociar ENI prefixes
3. Atualização do `max-pods` no kubelet via `userdata` do Launch Template

**Impacto no Terraform**: o módulo `terraform-aws-modules/eks` suporta configuração do addon `vpc-cni` via `cluster_addons`.

---

## 4. Artefatos a Criar

| ID | Artefato | Caminho | Responsável |
|----|----------|---------|-------------|
| ART-01 | ADR — Karpenter Adoption Decision | `docs/adr/ADR-XXX-karpenter-adoption.md` | Documentation Specialist |
| ART-02 | ADR — Instance Type Standardization | `docs/adr/ADR-XXX-instance-type-standardization.md` | Documentation Specialist |
| ART-03 | Terraform patch — vpc-cni addon (prefix delegation) | `platform-provisioning/aws/kubernetes/terraform/environments/staging/eks.tf` | Terraform Specialist |
| ART-04 | Terraform — Karpenter Helm chart + IAM role | `platform-provisioning/aws/kubernetes/terraform/modules/karpenter/` | Terraform Specialist |
| ART-05 | Karpenter NodePool — workloads-spot.yaml | `platform-provisioning/helm/karpenter/nodepools/workloads-spot.yaml` | AWS Specialist |
| ART-06 | Karpenter EC2NodeClass — workloads.yaml | `platform-provisioning/helm/karpenter/nodeclasses/workloads.yaml` | AWS Specialist |
| ART-07 | Runbook — Karpenter Migration Playbook | `docs/runbooks/karpenter-migration-playbook.md` | Documentation Specialist |
| ART-08 | FinOps Report — Spot Savings Analysis | `docs/finops/spot-savings-analysis-2026-03-17.md` | FinOps |
| ART-09 | Terraform patch — system node group (t3.medium → m5.large) | `platform-provisioning/aws/kubernetes/terraform/environments/staging/node-groups.tf` | Terraform Specialist |

---

## 5. Critérios de Aceite

| Critério | Método de Verificação |
|---|---|
| VPC CNI com prefix delegation ativo | `kubectl get ds -n kube-system aws-node -o yaml \| grep PREFIX` |
| Max pods em t3.medium ≥ 110 | `kubectl describe node <t3.medium-node> \| grep pods` |
| Karpenter instalado e NodePool ativo | `kubectl get nodepool,ec2nodeclass` |
| Workload ETL/Hatch agendado em node Spot | `kubectl get node -l karpenter.sh/capacity-type=spot` |
| Scale-out de workload em < 90 segundos | Teste: deploy de 20 réplicas com pause → medir tempo até pods Running |
| Custo mensal de nodes reduzido em ≥ 30% | AWS Cost Explorer — comparar semana pré vs pós migração |
| `terraform plan` retorna "No changes" após todos os patches | `terraform plan` no diretório staging |
| Zero downtime para workloads críticos durante migração | Checklist de rolling drain durante node group migration |
| ADRs criados e aprovados pela Mesa Técnica | Documentos em `docs/adr/` com status `Accepted` |

---

## 6. Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| Interrupção Spot durante carga de trabalho ETL crítica | Média | Médio | Só mover jobs idempotentes para Spot; usar `PodDisruptionBudget` |
| Rolling restart dos nodes para prefix delegation causa downtime | Média | Alto | Fazer draining node-by-node com `minAvailable` no PDB; manter 1 node system sempre up |
| Karpenter conflito com Cluster Autoscaler durante coexistência | Alta | Médio | Separar node groups: CA gerencia `system`, Karpenter gerencia `workloads` (labels distintos) |
| Subnet IPs insuficientes para prefix delegation (/28 blocks) | Baixa | Alto | Verificar capacidade da subnet antes de ativar: `aws ec2 describe-subnets` |
| Karpenter IAM permissions incorretas — nodes não provisionam | Média | Alto | Usar módulo Terraform oficial (terraform-aws-modules/karpenter) com IAM mínimo |
| t3.medium → m5.large aumenta custo de node group system | Baixa | Baixo | m5.large On-Demand us-east-1: ~$70/node vs t3.medium ~$35/node — delta $35/node aceitável |
| Terraform state drift após mudanças manuais durante incidente | Alta | Médio | Executar `terraform plan` imediatamente após fix emergencial e codificar as mudanças |

---

## 7. Estimativa de Esforço

### Fase 1 — Quick Wins (1-2 dias)

| Tarefa | Esforço |
|---|---|
| Habilitar prefix delegation VPC CNI + Terraform | 3h |
| Rolling restart nodes system (drain + cordon) | 2h |
| Validação: max pods aumentado sem downtime | 1h |
| `terraform plan` → zero drift | 1h |
| **Subtotal Fase 1** | **7h** |

### Fase 2 — Karpenter Migration (1 semana)

| Tarefa | Esforço |
|---|---|
| ADR Karpenter (análise + decisão + aprovação) | 3h |
| Terraform módulo Karpenter + IAM role + IRSA | 4h |
| NodePool + EC2NodeClass workloads-spot | 3h |
| Migração workloads não-críticos para Karpenter NodePool | 4h |
| Testes de scale-out + interrupção Spot simulada | 3h |
| Runbook migration playbook | 2h |
| **Subtotal Fase 2** | **19h** |

### Fase 3 — FinOps + Instance Types (1 semana)

| Tarefa | Esforço |
|---|---|
| Análise de custos Spot vs On-Demand (FinOps Report) | 2h |
| Terraform: system node group t3.medium → m5.large | 3h |
| Rolling migration system nodes + validação plataforma | 4h |
| ADR Instance Type Standardization | 2h |
| **Subtotal Fase 3** | **11h** |

**Total geral estimado**: ~37h (3 fases em ~2 semanas)

---

## 8. Dependências

| Dependência | Status | Bloqueador? |
|---|---|---|
| Cluster EKS staging operacional | UP após fix (2026-03-17) | Sim |
| Terraform state atualizado (sem drift) | Verificar pós-fix emergencial | Sim (Fase 1) |
| Acesso AWS SSO ativo (perfil k8s-platform-prod) | Ativo (2026-03-17) | Sim |
| Subnets com IPs disponíveis para prefix delegation | A verificar via `aws ec2 describe-subnets` | Sim (Fase 1) |
| IAM permissions para Karpenter (ec2:RunInstances, etc.) | A criar via Terraform | Sim (Fase 2) |
| ADR aprovado pela Mesa Técnica antes de migrar Karpenter | Pendente | Sim (Fase 2) |
| PrometheusRules de capacity (demanda 2026-03-17-observabilidade) | Pendente — demanda paralela | Não (mas recomendado antes da Fase 2) |
| PodDisruptionBudgets para workloads críticos definidos | A verificar | Sim (Fase 2, pré-migration) |

---

## 9. Plano de Execução Sequencial

```
FASE 1 — Quick Wins (sem downtime)
  ├─ [TF Specialist] Codificar prefix delegation no eks.tf
  ├─ [AWS Specialist] Verificar capacidade de IPs nas subnets
  ├─ [TF Specialist] terraform apply + terraform plan → No Changes
  └─ [SRE] Rolling drain nodes system (1 por vez) → validar max pods

FASE 2 — Karpenter (staging only, workloads node group)
  ├─ [Documentation] Redigir ADR Karpenter → Mesa Técnica aprova
  ├─ [TF Specialist] Terraform módulo Karpenter (install + IAM + IRSA)
  ├─ [AWS Specialist] Criar NodePool workloads-spot + EC2NodeClass
  ├─ [SRE] Migrar ETL/Hatch + Loki + Tempo + Grafana para Karpenter NodePool
  ├─ [SRE] Testar interrupção Spot simulada — validar reescalonamento
  └─ [Documentation] Runbook migration playbook

FASE 3 — FinOps + Instance Types
  ├─ [FinOps] Gerar relatório de economia pós-Spot
  ├─ [TF Specialist] Migrar system node group: t3.medium → m5.large
  ├─ [SRE] Rolling migration system nodes
  └─ [Documentation] ADR Instance Type Standardization
```

---

## 10. Referências

- Incidente: Sessão de Health Check 2026-03-17 — colapso de capacidade
- Demanda relacionada: `2026-03-17-observabilidade-capacity-alertas.md`
- Karpenter docs: https://karpenter.sh/docs/
- AWS EKS — Increase pod limits: https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
- Terraform AWS EKS module: https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest
- AWS EC2 instance type pricing: https://aws.amazon.com/ec2/pricing/on-demand/
- Cluster Autoscaler vs Karpenter comparison: https://karpenter.sh/docs/concepts/

# Demanda: Proteção Definitiva do Cluster Autoscaler

**Data**: 2026-03-17
**Prioridade**: P1
**Tipo**: Reliability / Infrastructure
**Componentes afetados**: Cluster Autoscaler (Helm), Deployment `cluster-autoscaler` (namespace `kube-system`), EKS Node Groups (system/workloads/critical), kube-prometheus-stack (alertas), ArgoCD
**Origem**: Mesa Técnica — Sessão de Health Check 2026-03-17
**ADRs relacionados**: ADR-100 (IaC Compliance), ADR-TBD (Cluster Autoscaler Resiliência)

---

## 1. Contexto e Motivação

Em 2026-03-17, o Cluster Autoscaler foi encontrado com `replicas=0` no Deployment
`cluster-autoscaler` no namespace `kube-system`. A causa exata do escalonamento para zero é
desconhecida — candidatos: operação manual acidental, FinOps shutdown schedule, ArgoCD drift
correction, ou `terraform apply` com `ignore_changes` incompleto.

O resultado foi **~35 pods em estado `Pending` por aproximadamente 26 horas**, incluindo workloads
críticos de plataforma:

- Prometheus / Alertmanager (observability cega)
- Grafana (dashboards offline)
- SonarQube (CI/CD quality gate bloqueado)
- GitLab Gitaly (SCM potencialmente degradado)
- Outros pods em namespaces `staging-observability-monitoring`, `staging-platform-gitlab`,
  `staging-platform-sonarqube`

O fix imediato foi aplicado manualmente:
```bash
kubectl scale deployment cluster-autoscaler --replicas=1 -n kube-system
kubectl annotate deployment cluster-autoscaler \
  cluster-autoscaler.kubernetes.io/safe-to-evict="false" \
  -n kube-system --overwrite
```

Porém, **nenhuma proteção estrutural existe** para evitar que o mesmo incidente se repita.

---

## 2. Problema Atual

### 2.1 — Lacunas de proteção identificadas

| Lacuna | Descrição | Risco |
|--------|-----------|-------|
| Sem PodDisruptionBudget | Não há PDB protegendo o pod do Cluster Autoscaler | Eviction acidental pelo próprio autoscaler (irônico) ou durante drenagem de node |
| Sem PrometheusAlert | Não há alerta para `kube_deployment_status_replicas{deployment="cluster-autoscaler"} == 0` | Incidente passa despercebido por horas/dias |
| Sem alerta de pods Pending | Não há alerta para "N pods em Pending por mais de X minutos" | 35 pods Pending por 26h sem alerta |
| `ignore_changes` insuficiente | O `ignore_changes` nos node groups protege `desired_size` mas não o Deployment do autoscaler | Um `terraform apply` que destrua/recrie o Helm release resetaria replicas |
| Causa raiz não identificada | Não se sabe o que zerou as replicas | Sem RCA, o incidente pode se repetir |
| Helm release fora do Terraform state | O Cluster Autoscaler foi instalado via Helm mas pode não estar no TF state | Drift potencial não monitorado |
| Sem RBAC de proteção | Qualquer SA com permissão `kubectl scale` pode zerar o autoscaler | Ausência de controle de acesso granular |

### 2.2 — Impacto do incidente (SLI/SLO)

| Métrica | Valor |
|---------|-------|
| Pods afetados | ~35 |
| Duração do incidente | ~26 horas |
| Namespaces impactados | staging-observability-monitoring, staging-platform-gitlab, staging-platform-sonarqube |
| MTTD (Mean Time to Detect) | Desconhecido — detectado manualmente |
| MTTR (Mean Time to Restore) | ~5 minutos (após detecção) |
| Observability durante incidente | Cega (Prometheus/Grafana Pending) |

---

## 3. Solução Proposta

### Fase 1 — Proteções Imediatas (Kubernetes Manifests)

#### 1a — PodDisruptionBudget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: cluster-autoscaler-pdb
  namespace: kube-system
  labels:
    app.kubernetes.io/managed-by: Helm
    app: cluster-autoscaler
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: cluster-autoscaler
```

Este PDB garante que pelo menos 1 réplica do Cluster Autoscaler permaneça disponível durante
drenagens de node planejadas. Combinado com `safe-to-evict=false`, impede que o próprio autoscaler
evicte seu próprio pod.

#### 1b — Annotation `safe-to-evict=false` via Helm values (codificar o fix manual)

O fix manual aplicado em 2026-03-17 (`safe-to-evict=false`) deve ser codificado permanentemente
no Helm values do Cluster Autoscaler. Verificar se o Helm release está gerenciado via Terraform;
se sim, adicionar ao módulo correspondente.

### Fase 2 — Alertas Prometheus (PrometheusRule)

Criar `PrometheusRule` com os seguintes alertas:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cluster-autoscaler-resilience
  namespace: kube-system
  labels:
    prometheus: kube-prometheus
    role: alert-rules
spec:
  groups:
    - name: cluster-autoscaler.rules
      interval: 30s
      rules:

        # CRITICO: Cluster Autoscaler com zero réplicas
        - alert: ClusterAutoscalerDown
          expr: |
            kube_deployment_status_replicas_available{
              deployment="cluster-autoscaler",
              namespace="kube-system"
            } == 0
          for: 2m
          labels:
            severity: critical
            team: platform
          annotations:
            summary: "Cluster Autoscaler está com 0 réplicas disponíveis"
            description: |
              O Deployment cluster-autoscaler em kube-system tem 0 réplicas disponíveis
              há mais de 2 minutos. Pods pendentes NÃO serão escalonados.
              Ação: kubectl scale deployment cluster-autoscaler --replicas=1 -n kube-system
            runbook_url: "https://docs.internal/runbooks/cluster-autoscaler-recovery"

        # AVISO: Cluster Autoscaler com réplicas esperadas != disponíveis
        - alert: ClusterAutoscalerReplicasMismatch
          expr: |
            kube_deployment_spec_replicas{
              deployment="cluster-autoscaler",
              namespace="kube-system"
            }
            !=
            kube_deployment_status_replicas_available{
              deployment="cluster-autoscaler",
              namespace="kube-system"
            }
          for: 5m
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "Cluster Autoscaler: réplicas spec != available por 5min"
            description: |
              Deployment cluster-autoscaler: spec.replicas != status.availableReplicas.
              Verificar: kubectl describe deployment cluster-autoscaler -n kube-system

        # CRITICO: Pods em Pending por mais de 15 minutos (autoscaler inativo?)
        - alert: KubePodsPendingTooLong
          expr: |
            count(
              kube_pod_status_phase{phase="Pending"}
              * on(pod, namespace) group_left()
              (kube_pod_status_scheduled{condition="false"} == 1)
            ) > 3
          for: 15m
          labels:
            severity: critical
            team: platform
          annotations:
            summary: "Mais de 3 pods Pending não escalonáveis por 15 minutos"
            description: |
              {{ $value }} pods estão em Pending com condition Unschedulable por mais de 15min.
              Causa provável: Cluster Autoscaler inativo ou ASG no limite (max_size).
              Verificar: kubectl get pods --all-namespaces | grep Pending
              Verificar: kubectl logs -n kube-system deployment/cluster-autoscaler

        # AVISO: ASG workloads próximo do limite máximo
        - alert: ClusterAutoscalerASGNearMaxCapacity
          expr: |
            cluster_autoscaler_nodes_count
            / on() group_left()
            cluster_autoscaler_max_nodes_count > 0.85
          for: 10m
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "Cluster Autoscaler: capacidade de nodes acima de 85%"
            description: |
              O cluster está utilizando mais de 85% da capacidade máxima de nodes.
              Considerar aumentar max_size no node group ou revisar workloads.
```

### Fase 3 — Codificar no Terraform (IaC Compliance)

#### 3a — Verificar se Cluster Autoscaler está no Terraform state

```bash
terraform state list | grep autoscaler
```

Se não estiver: criar módulo `modules/cluster-autoscaler/` e importar o Helm release.

#### 3b — Adicionar `replicas` explícito e proteção no módulo Helm

No módulo Terraform do Cluster Autoscaler, garantir:

```hcl
resource "helm_release" "cluster_autoscaler" {
  # ... configurações existentes ...

  set {
    name  = "replicaCount"
    value = "1"
  }

  set {
    name  = "podAnnotations.cluster-autoscaler\\.kubernetes\\.io/safe-to-evict"
    value = "false"
  }

  lifecycle {
    # NUNCA reduzir replicas via Terraform apply
    # O ignore_changes aqui é diferente dos node groups:
    # protege contra resets acidentais de configuração de réplicas
    # via plan/apply que não entendam o estado atual
    prevent_destroy = false  # não impede destroy intencional
    # NÃO usar ignore_changes em replicaCount — queremos que TF SEMPRE
    # mantenha replicas=1 como estado desejado
  }
}
```

**Nota**: Ao contrário dos node groups (onde `ignore_changes` em `desired_size` é necessário
porque o autoscaler altera dinamicamente), o `replicaCount` do próprio Deployment do autoscaler
NÃO deve ter `ignore_changes`. O Terraform deve ser a source of truth: `replicas=1`.

#### 3c — Codificar PDB no módulo Terraform

```hcl
resource "kubernetes_manifest" "cluster_autoscaler_pdb" {
  manifest = {
    apiVersion = "policy/v1"
    kind       = "PodDisruptionBudget"
    metadata = {
      name      = "cluster-autoscaler-pdb"
      namespace = "kube-system"
    }
    spec = {
      minAvailable = 1
      selector = {
        matchLabels = {
          app = "cluster-autoscaler"
        }
      }
    }
  }
}
```

### Fase 4 — RCA e Controle de Acesso

#### 4a — Root Cause Analysis

Investigar a causa exata do escalonamento para zero:

```bash
# Verificar audit logs do Kubernetes (se API audit log estiver habilitado)
# CloudTrail: buscar por "UpdateDeployment" ou "PatchDeployment" em kube-system

# Verificar se FinOps shutdown schedule pode ter afetado
kubectl get cronjobs -A | grep -i shutdown
kubectl get cronjobs -A | grep -i scale

# Verificar histórico do ArgoCD para o Helm release
kubectl get applications -n argocd | grep autoscaler
```

#### 4b — RBAC de proteção (opcional, P2)

Considerar criar um `ClusterRole` restrito que impeça `scale` no Deployment do autoscaler
sem permissão explícita de admin:

```yaml
# Exemplo: negar scale para SAs genéricas via OPA/Kyverno policy
# (a ser avaliado na Mesa Técnica — pode ter side effects no ArgoCD)
```

### Fase 5 — Runbook de Recuperação

Criar `docs/runbooks/cluster-autoscaler-recovery.md` com:
1. Diagnóstico rápido (comandos)
2. Fix imediato (`kubectl scale`)
3. Verificação de pods Pending
4. Procedimento de RCA pós-recuperação
5. Checklist de validação pós-fix

---

## 4. Artefatos a Criar

```
platform-provisioning/aws/kubernetes/manifests/
  pdb/cluster-autoscaler-pdb.yaml                          # PodDisruptionBudget
  prometheus-rules/cluster-autoscaler-resilience.yaml      # PrometheusRule (4 alertas)

platform-provisioning/aws/kubernetes/terraform/modules/cluster-autoscaler/
  main.tf                                                   # Helm release + PDB (novo módulo)
  variables.tf
  outputs.tf

platform-provisioning/aws/kubernetes/terraform/environments/staging/
  cluster-autoscaler.tf                                     # Instância do módulo no staging

docs/runbooks/
  cluster-autoscaler-recovery.md                           # SOP de recuperação de emergência

docs/adr/
  adr-TBD-cluster-autoscaler-resiliencia.md                # ADR formalizando as decisões
```

---

## 5. Critérios de Aceite

| Gate | Como verificar |
|------|----------------|
| PDB ativo | `kubectl get pdb cluster-autoscaler-pdb -n kube-system` → `ALLOWED DISRUPTIONS: 0` quando 1 réplica ativa |
| Annotation safe-to-evict | `kubectl get deployment cluster-autoscaler -n kube-system -o yaml` → annotation presente |
| Alerta ClusterAutoscalerDown funcional | Simular: `kubectl scale deployment cluster-autoscaler --replicas=0 -n kube-system` → alerta dispara em ≤2min → restaurar |
| Alerta KubePodsPendingTooLong funcional | PrometheusRule ativa e visível no Prometheus UI → `kubectl get prometheusrule -n kube-system` |
| Terraform state incluindo autoscaler | `terraform state list | grep autoscaler` retorna o Helm release |
| Terraform plan zero drift | `terraform plan` em staging → "No changes" após aplicar módulo |
| Runbook publicado | `docs/runbooks/cluster-autoscaler-recovery.md` existente com SOP validado |
| RCA documentado | Causa do incidente 2026-03-17 identificada e registrada no logbook |

---

## 6. Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|--------------|---------|-----------|
| PrometheusRule não reconhecida pelo Prometheus Operator (label mismatch) | Média | Médio | Verificar labels do selector do Prometheus CR antes de aplicar; testar com regra simples primeiro |
| PDB impede drenagem de node durante manutenção planejada | Baixa | Baixo | Para manutenção: deletar PDB temporariamente com aprovação, ou usar `kubectl drain --disable-eviction` |
| Terraform import do Helm release causa drift e plan com "changes" | Média | Médio | Usar `terraform plan` antes do `apply`; aceitar mudanças cosméticas no Helm values |
| Alerta de pods Pending muito sensível (falsos positivos em deployments normais) | Alta | Baixo | Ajustar `for: 15m` e threshold `> 3`; usar label filter para excluir pods em `Terminating` |
| Causa raiz não identificada → incidente se repete | Média | Alto | Habilitar API audit log no EKS (se não ativo); checar CloudTrail; revisar FinOps CronJobs |
| `prevent_destroy = false` no Helm release permite remoção acidental | Baixa | Crítico | Documentar explicitamente que remoção do módulo = cluster sem autoscaling |

---

## 7. Estimativa de Esforço

| Fase | Complexidade | Horas estimadas |
|------|-------------|----------------|
| Fase 1 — PDB + annotation manifests | Baixa | 0.5h |
| Fase 2 — PrometheusRule (4 alertas) | Baixa | 1h |
| Fase 3 — Terraform module cluster-autoscaler | Média | 2h |
| Fase 3b — terraform import + plan validation | Média | 1h |
| Fase 4 — RCA + RBAC analysis | Média | 1.5h |
| Fase 5 — Runbook + ADR | Baixa | 1h |
| **Total estimado** | **Média** | **~7h** |

---

## 8. Dependências

| Dependência | Status | Bloqueador? |
|-------------|--------|-------------|
| kube-prometheus-stack operacional (Prometheus Operator) | Ativo — staging-observability-monitoring | Não |
| Alertmanager configurado com webhook Teams | Ativo — alertmanager-teams-webhook ExternalSecret | Não |
| Acesso ao cluster (AWS SSO k8s-platform-prod) | Disponível | Não |
| Terraform state do staging desbloqueado | Disponível | Não |
| Helm release do Cluster Autoscaler identificado | A verificar: `helm list -n kube-system` | Pré-condição Fase 3 |
| API Audit Logs do EKS (para RCA) | Status desconhecido — verificar CloudWatch Logs | Opcional (RCA) |

**Pré-requisito de execução**:
- Fases 1 e 2 (manifests) podem ser aplicadas imediatamente sem janela de manutenção
- Fase 3 (Terraform) requer `terraform plan` validado antes do `apply` — sem janela necessária
- Fase 4 (RCA) deve ser executada em paralelo com as demais

**Nota de urgência**: O Cluster Autoscaler está atualmente com `replicas=1` e `safe-to-evict=false`
aplicados manualmente. As Fases 1 e 2 desta demanda codificam e protegem este estado. Recomenda-se
execução na próxima sprint disponível para evitar regressão.

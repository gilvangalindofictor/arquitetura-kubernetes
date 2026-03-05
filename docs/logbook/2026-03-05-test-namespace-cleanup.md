# 2026-03-05 — Limpeza de Namespaces de Teste

**Executado por:** DevOps automação
**Cluster:** k8s-platform-prod (EKS 1.34, us-east-1)
**Impacto:** Liberação de slots de pods em nós system (t3.medium, 17/17 → headroom para DaemonSets)

---

## O que foi deletado e por quê

### Namespaces removidos

| Namespace | Pods | Nós impactados | Motivo da remoção |
|-----------|------|----------------|-------------------|
| `rollouts-test` | 7 pods (nginx-blue-green-test x4, nginx-canary-test x3) | 5 system nodes (t3.medium) | Recursos de demo criados manualmente sem IaC; ocupando slots críticos em system nodes |
| `tracing-test` | 1 pod (tracing-test-app) | 1 workload node | Recurso de teste manual sem IaC |
| `otel-test` | 1 pod (trace-generator) | 1 workload node | Recurso de teste manual sem IaC |

**Comando executado:**
```bash
kubectl delete namespace rollouts-test tracing-test otel-test --ignore-not-found
# Output: namespace "rollouts-test" deleted | namespace "tracing-test" deleted | namespace "otel-test" deleted
```

### Causa raiz do problema

Os pods de `rollouts-test` foram agendados em system nodes (nodegroup=system, t3.medium) porque não tinham `nodeSelector` ou `tolerations` adequados. Os system nodes estavam saturados em 17/17 pods (limite do t3.medium), bloqueando DaemonSets críticos de plataforma.

---

## Verificacao Terraform (Etapa 0)

**Resultado:** NÃO estavam no Terraform — recursos manuais não gerenciados por IaC.

**Evidência da busca:**
- `rollouts-test`, `tracing-test`, `otel-test`: NENHUMA referência nos arquivos `.tf`
- O módulo `modules/argo-rollouts` existe mas está **comentado/desabilitado** em `main.tf` (linhas 892-933)
- O módulo comentado trata apenas do **controller** do Argo Rollouts, não dos pods de teste nginx
- Os pods nginx-blue-green/nginx-canary eram demos de funcionalidade, criados manualmente via `kubectl apply`

```
# Trecho relevante em main.tf (linha 892):
# TEMPORARILY DISABLED (2026-02-26) — CICD-005 Argo Rollouts Module
# module "argo_rollouts_staging" {
#   source = "../../modules/argo-rollouts"
```

---

## Status dos DaemonSets apos limpeza

### DaemonSets que saíram do Pending (CORRIGIDOS)

| DaemonSet | Namespace | Status antes | Status depois |
|-----------|-----------|-------------|---------------|
| `kube-prometheus-stack-prometheus-node-exporter-pdjj8` | staging-observability-monitoring | Pending (19h) | Running |
| `loki-canary-2svk5` | staging-observability-monitoring | Pending (7h) | Running |
| `loki-canary-qxz9b` | staging-observability-monitoring | Pending (19h) | Running |
| `loki-canary-xfh56` | staging-observability-monitoring | Pending (7h) | Running |
| `linkerd-cni-5jqr7` | linkerd-cni | Pending (19h) | Running |
| `loki-write-0` | staging-observability-monitoring | Pending | Running |

### DaemonSets ainda Pending (pre-existente — system nodes 17/17)

Estes permaneceram Pending porque os system nodes continuam saturados em 17/17 pods (t3.medium max). O cluster autoscaler está provisionando novos nós para resolvê-los:

| Pod | Namespace | Motivo |
|-----|-----------|--------|
| `linkerd-cni-vzwxw` | linkerd-cni | 17/17 + NodeAffinity (aguarda novo system node) |
| `promtail-lzvhj` | staging-observability-monitoring | 17/17 + NodeAffinity |
| `promtail-zz9wj` | staging-observability-monitoring | 17/17 + NodeAffinity |
| `node-agent-79x7c` | velero | 17/17 + NodeAffinity |
| `node-agent-jwhgf` | velero | 17/17 + NodeAffinity |

**Ação complementar recomendada:** Ver `2026-03-05-system-asg-max-increase.md` — o ASG de system nodes pode precisar de aumento do `max_size` para acomodar os DaemonSets.

---

## Resposta à pergunta de Governança: DaemonSets no Terraform?

### DaemonSets GERENCIADOS por Terraform (via Helm module)

| DaemonSet | Helm Release | Terraform Resource | Módulo TF |
|-----------|-------------|-------------------|-----------|
| `prometheus-node-exporter` | `kube-prometheus-stack` | `module.kube_prometheus_stack_staging` | `modules/kube-prometheus-stack` |
| `loki-canary` | `loki` | **NÃO via module — Helm manual** | `modules/loki` (módulo existe mas não é instanciado em staging/main.tf) |
| `promtail` | `promtail` | **NÃO via module — Helm manual** | Sem módulo TF |
| `linkerd-cni` | `linkerd-cni` | `module.linkerd` | `modules/linkerd` |
| `velero node-agent` | `velero` | **NÃO via module — Helm manual** | `modules/velero-dr` (apenas S3/IAM, não o Helm) |

### Resumo de governança

| Componente | No Terraform? | Observação |
|------------|--------------|------------|
| `prometheus-node-exporter` (DaemonSet) | SIM | Via `module.kube_prometheus_stack_staging` → `modules/kube-prometheus-stack` → `helm_release.kube_prometheus_stack` |
| `linkerd-cni` (DaemonSet) | SIM | Via `module.linkerd` → `modules/linkerd` → `helm_release.linkerd_cni` |
| `loki-canary` (DaemonSet via loki Helm) | PARCIAL | Módulo `modules/loki` com `helm_release.loki` existe mas não está instanciado em `staging/main.tf`. Deploy atual é manual via `helm upgrade`. |
| `promtail` (DaemonSet) | NAO | Sem módulo TF. Deploy via `helm upgrade promtail grafana/promtail` manual. |
| `velero node-agent` (DaemonSet via velero Helm) | NAO | `modules/velero-dr` gerencia apenas o S3 bucket e IAM (IRSA). O `helm install velero` foi feito manualmente. |

### Argo Rollouts controller (confirmação)

O controller do Argo Rollouts está **Running** e em namespace correto:

```
staging-platform-argocd   argo-rollouts-757cc6c54d-8nm97   2/2   Running   27h
staging-platform-argocd   argo-rollouts-757cc6c54d-x6bs2   2/2   Running   27h
staging-platform-argocd   argo-rollouts-dashboard-fd8d9b56-mntn7   1/1   Running
```

O módulo `modules/argo-rollouts` está **desabilitado** em `main.tf` por blocker (values.yaml.tpl faltando). Mas o controller foi deployado manualmente em 2026-02-26 e está funcionando. Os pods de TESTE deletados (`nginx-blue-green-test`, `nginx-canary-test`) eram demos criados manualmente, sem relação com o controller.

---

## Recomendações de Governança (IaC compliance)

### Regra para recursos de teste

**Futuramente, recursos de teste devem:**

1. Ser criados via Terraform com flag identificador:
   ```hcl
   resource "kubernetes_namespace" "test_rollouts" {
     metadata {
       name = "rollouts-test"
       labels = {
         "platform.io/is-test-resource" = "true"
         "platform.io/test-owner"        = "team-cicd"
         "platform.io/test-expires"      = "2026-03-15"  # TTL explícito
       }
     }
   }
   ```

2. Incluir `nodeSelector` explícito para **NÃO usar system nodes**:
   ```yaml
   nodeSelector:
     node-type: workloads  # nunca system
   ```

3. Ter TTL documentado — remover após validação (máx. 7 dias)

### Itens de backlog técnico

- [ ] Criar módulo Terraform para `promtail` (atualmente deployado via Helm manual)
- [ ] Instanciar `modules/loki` em `staging/main.tf` (módulo existe, não está sendo usado via TF)
- [ ] Criar módulo Terraform para `velero` Helm (atualmente apenas IRSA/S3 no TF, não o Helm)
- [ ] Re-enable `module.argo_rollouts_staging` após criar `values.yaml.tpl`

---

**Estes recursos foram removidos em 2026-03-05 e NAO devem ser recriados sem cobertura Terraform.**

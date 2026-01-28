# Marco 2 - Fase 6: Cluster Autoscaler Implementation

**Data:** 2026-01-28
**Status:** ✅ CÓDIGO IMPLEMENTADO - AGUARDANDO DEPLOY
**Marco:** Marco 2 - Fase 6 (Auto-scaling)
**ADR:** [ADR-007: Cluster Autoscaler Strategy](../../../../../docs/adr/adr-007-cluster-autoscaler-strategy.md)

---

## 📋 Sumário

- [1. Visão Geral](#1-visão-geral)
- [2. Arquitetura](#2-arquitetura)
- [3. Pré-requisitos](#3-pré-requisitos)
- [4. Deploy Instructions](#4-deploy-instructions)
- [5. Validação](#5-validação)
- [6. Troubleshooting](#6-troubleshooting)
- [7. Rollback](#7-rollback)

---

## 1. Visão Geral

### Objetivo

Implementar **Kubernetes Cluster Autoscaler** para escalar automaticamente o node group "workloads" baseado em demanda de recursos, reduzindo custos durante baixa utilização.

### Componentes Implementados

| Componente | Descrição |
|------------|-----------|
| **Terraform Module** | `modules/cluster-autoscaler/` (4 arquivos) |
| **IAM Role + Policy** | IRSA pattern para permissões AWS |
| **Helm Chart** | `cluster-autoscaler` v9.37.0 |
| **Service Account** | Kubernetes SA com annotation role ARN |
| **ASG Tags** | Tags para discovery automático |

### Economia Esperada

- **Cenário:** Scale-down de 1 node workloads durante 70% do tempo
- **Economia mensal:** ~$31/mês
- **Economia anual:** ~$372/ano
- **Percentual:** ~23% redução em custos de nodes workloads

---

## 2. Arquitetura

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CLUSTER AUTOSCALER ARCHITECTURE                     │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                        KUBERNETES CLUSTER                              │ │
│  │                                                                        │ │
│  │  ┌──────────────────────────────────────────────────────────────┐    │ │
│  │  │  kube-system namespace                                        │    │ │
│  │  │                                                               │    │ │
│  │  │  ┌─────────────────────────────────────────────────────┐    │    │ │
│  │  │  │     Cluster Autoscaler Pod                          │    │    │ │
│  │  │  │                                                      │    │    │ │
│  │  │  │  - Monitors pending pods                            │    │    │ │
│  │  │  │  - Calls AWS APIs (IRSA)                            │    │    │ │
│  │  │  │  - Scales ASGs up/down                              │    │    │ │
│  │  │  │                                                      │    │    │ │
│  │  │  │  Service Account: cluster-autoscaler                │    │    │ │
│  │  │  │  Annotation: eks.amazonaws.com/role-arn             │    │    │ │
│  │  │  └──────────────────┬──────────────────────────────────┘    │    │ │
│  │  │                     │                                        │    │ │
│  │  │                     │ AWS STS AssumeRoleWithWebIdentity      │    │ │
│  │  │                     ▼                                        │    │ │
│  │  └──────────────────────────────────────────────────────────────┘    │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                              AWS IAM                                   │ │
│  │                                                                        │ │
│  │  ┌──────────────────────────────────────────────────────────────┐    │ │
│  │  │  IAM Role: ClusterAutoscalerRole-k8s-platform-prod           │    │ │
│  │  │                                                               │    │ │
│  │  │  Trust Policy: OIDC Provider (EKS)                           │    │ │
│  │  │  Condition: serviceaccount:kube-system:cluster-autoscaler    │    │ │
│  │  │                                                               │    │ │
│  │  │  IAM Policy: ClusterAutoscalerPolicy                         │    │ │
│  │  │  - autoscaling:DescribeAutoScalingGroups                     │    │ │
│  │  │  - autoscaling:SetDesiredCapacity                            │    │ │
│  │  │  - autoscaling:TerminateInstanceInAutoScalingGroup           │    │ │
│  │  │  - ec2:DescribeInstances, DescribeImages                     │    │ │
│  │  │                                                               │    │ │
│  │  │  Condition: Tag = k8s.io/cluster-autoscaler/cluster=owned    │    │ │
│  │  └─────────────────────────┬────────────────────────────────────┘    │ │
│  └────────────────────────────┼───────────────────────────────────────────┘ │
│                                │                                            │
│                                │ AWS API Calls                              │
│                                ▼                                            │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │                     AWS AUTO SCALING GROUPS                            │ │
│  │                                                                        │ │
│  │  ┌────────────────┐    ┌────────────────┐    ┌────────────────┐     │ │
│  │  │ ASG: system    │    │ ASG: workloads │    │ ASG: critical  │     │ │
│  │  │ Min: 2, Max: 4 │    │ Min: 2, Max: 6 │    │ Min: 2, Max: 4 │     │ │
│  │  │ CA: disabled   │    │ CA: enabled    │    │ CA: disabled   │     │ │
│  │  └────────────────┘    └────────────────┘    └────────────────┘     │ │
│  │        Fixed               SCALABLE               Fixed               │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Pré-requisitos

### 3.1 Terraform State e Providers

```bash
cd platform-provisioning/aws/kubernetes/terraform/envs/marco2

# Verificar providers configurados
terraform providers

# Esperado:
# - hashicorp/aws ~> 5.0
# - hashicorp/kubernetes ~> 2.0
# - hashicorp/helm ~> 2.0
```

### 3.2 AWS Credentials

```bash
# SSO Login (recomendado)
aws sso login --profile k8s-platform-prod
export AWS_PROFILE=k8s-platform-prod

# Validar
aws sts get-caller-identity
# Esperado: Account: 891377105802
```

### 3.3 Kubernetes Context

```bash
# Atualizar kubeconfig
aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod

# Verificar conectividade
kubectl cluster-info
kubectl get nodes
# Esperado: 7 nodes Ready
```

### 3.4 Aplicar Tags nos ASGs (Marco 1 PRIMEIRO)

**CRÍTICO:** As tags devem ser aplicadas ANTES de instalar o Cluster Autoscaler.

```bash
cd ../marco1

# Terraform plan para adicionar tags
terraform plan -out=marco1-asg-tags.tfplan

# REVISAR: Deve mostrar apenas adição de tags (aws_autoscaling_group_tag)
# Não deve mostrar replace de node groups!

# Apply
terraform apply marco1-asg-tags.tfplan

# Validar tags
aws autoscaling describe-auto-scaling-groups \
  --query 'AutoScalingGroups[?contains(Tags[?Key==`eks:cluster-name`].Value, `k8s-platform-prod`)].{Name:AutoScalingGroupName,Tags:Tags}' \
  --output json | jq '.[] | {Name, CATags: [.Tags[] | select(.Key | startswith("k8s.io/cluster-autoscaler"))]}'
```

**Esperado:**
- ASG "workloads": `k8s.io/cluster-autoscaler/enabled=true`, `k8s.io/cluster-autoscaler/k8s-platform-prod=owned`
- ASG "system": `k8s.io/cluster-autoscaler/enabled=false`, `k8s.io/cluster-autoscaler/k8s-platform-prod=disabled`
- ASG "critical": `k8s.io/cluster-autoscaler/enabled=false`, `k8s.io/cluster-autoscaler/k8s-platform-prod=disabled`

---

## 4. Deploy Instructions

### 4.1 Backup do State

```bash
cd ../marco2

# Download state atual
aws s3 cp s3://k8s-platform-terraform-state-891377105802/marco2/terraform.tfstate \
    ./backup/terraform.tfstate.$(date +%Y%m%d-%H%M%S)

# Listar recursos atuais
terraform state list | wc -l
# Anotar número para comparação posterior
```

### 4.2 Terraform Init e Validação

```bash
# Inicializar (upgrade providers)
terraform init -upgrade

# Validar sintaxe
terraform validate
# Esperado: Success! The configuration is valid.

# Formatar código
terraform fmt -recursive
```

### 4.3 Terraform Plan

```bash
# Gerar plan
terraform plan -out=fase6-cluster-autoscaler.tfplan

# Salvar plan legível
terraform show fase6-cluster-autoscaler.tfplan > fase6-cluster-autoscaler-plan-review.txt
```

**Recursos Esperados (a serem criados):**

1. `module.cluster_autoscaler.aws_iam_policy.cluster_autoscaler` - IAM Policy
2. `module.cluster_autoscaler.aws_iam_role.cluster_autoscaler` - IAM Role (IRSA)
3. `module.cluster_autoscaler.aws_iam_role_policy_attachment.cluster_autoscaler` - Attach policy
4. `module.cluster_autoscaler.kubernetes_service_account.cluster_autoscaler` - Service Account
5. `module.cluster_autoscaler.helm_release.cluster_autoscaler` - Helm chart

**Checklist de Validação:**
- [ ] Nenhum recurso será destruído (destroy = 0)
- [ ] IAM Role tem trust policy OIDC correto
- [ ] Service Account tem annotation `eks.amazonaws.com/role-arn`
- [ ] Helm chart version = 9.37.0
- [ ] Kubernetes version = 1.31

### 4.4 Terraform Apply

```bash
# Apply com plan salvo
terraform apply fase6-cluster-autoscaler.tfplan

# Monitorar progresso
# 1. Recursos IAM (Policy + Role): ~5-10 segundos
# 2. Helm install: ~1-2 minutos
# Total esperado: ~2-3 minutos
```

**Logs Esperados:**
```
module.cluster_autoscaler.aws_iam_policy.cluster_autoscaler: Creating...
module.cluster_autoscaler.aws_iam_policy.cluster_autoscaler: Creation complete after 3s

module.cluster_autoscaler.aws_iam_role.cluster_autoscaler: Creating...
module.cluster_autoscaler.aws_iam_role.cluster_autoscaler: Creation complete after 2s

module.cluster_autoscaler.aws_iam_role_policy_attachment.cluster_autoscaler: Creating...
module.cluster_autoscaler.aws_iam_role_policy_attachment.cluster_autoscaler: Creation complete after 1s

module.cluster_autoscaler.kubernetes_service_account.cluster_autoscaler: Creating...
module.cluster_autoscaler.kubernetes_service_account.cluster_autoscaler: Creation complete after 2s

module.cluster_autoscaler.helm_release.cluster_autoscaler: Creating...
module.cluster_autoscaler.helm_release.cluster_autoscaler: Still creating... [1m0s elapsed]
module.cluster_autoscaler.helm_release.cluster_autoscaler: Creation complete after 1m34s

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

---

## 5. Validação

### 5.1 Script Automático

```bash
# Executar script de validação
./scripts/validate-cluster-autoscaler.sh

# Este script valida:
# ✅ Deployment Running
# ✅ Pod Running
# ✅ Service Account com IAM Role annotation
# ✅ Logs sem erros IAM
# ✅ ASG tags corretas
# ✅ Prometheus ServiceMonitor
```

### 5.2 Validações Manuais

**5.2.1 - Verificar Deployment**
```bash
kubectl get deployment cluster-autoscaler -n kube-system
# Esperado: 1/1 READY

kubectl get pods -n kube-system -l app.kubernetes.io/name=cluster-autoscaler
# Esperado: 1 pod Running
```

**5.2.2 - Verificar Service Account (IRSA)**
```bash
kubectl describe sa cluster-autoscaler -n kube-system

# Esperado:
# Annotations:
#   eks.amazonaws.com/role-arn: arn:aws:iam::891377105802:role/ClusterAutoscalerRole-k8s-platform-prod
```

**5.2.3 - Verificar Logs**
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=cluster-autoscaler --tail=50

# Buscar:
# ✅ "Starting cluster-autoscaler"
# ✅ "Discovering node groups"
# ✅ "Found X ASG(s)"
# ❌ NÃO deve ter: "Unauthorized", "Access Denied", "Permission"
```

**5.2.4 - Verificar Métricas**
```bash
# Port-forward Prometheus (se não estiver ativo)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Acessar: http://localhost:9090
# Query: cluster_autoscaler_nodes_count{state="ready"}
# Esperado: Métrica disponível com valor = 7 (nodes atuais)
```

---

## 6. Troubleshooting

### 6.1 Pod em CrashLoopBackOff

**Sintoma:**
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=cluster-autoscaler
# NAME                                  READY   STATUS             RESTARTS
# cluster-autoscaler-xxx                0/1     CrashLoopBackOff   3
```

**Diagnóstico:**
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=cluster-autoscaler --tail=100
```

**Causas Comuns:**

1. **IAM Permission Errors:**
   ```
   ERROR: Failed to list autoscaling groups: UnauthorizedOperation
   ```
   - **Solução:** Verificar IAM Role trust policy e policy permissions

2. **ASG Tags Ausentes:**
   ```
   WARNING: No Auto Scaling Groups found with tags
   ```
   - **Solução:** Aplicar tags nos ASGs (Marco 1 - seção 3.4)

3. **Kubernetes Version Mismatch:**
   ```
   ERROR: Unsupported Kubernetes version
   ```
   - **Solução:** Verificar `kubernetes_version` no módulo match EKS version

### 6.2 Scale-Up Não Funciona

**Sintoma:** Pods ficam Pending mas nenhum node é provisionado

**Diagnóstico:**
```bash
# 1. Verificar pending pods
kubectl get pods --all-namespaces | grep Pending

# 2. Verificar eventos
kubectl get events --sort-by='.lastTimestamp' | grep -i scale

# 3. Verificar logs do Cluster Autoscaler
kubectl logs -n kube-system -l app.kubernetes.io/name=cluster-autoscaler --tail=100 | grep -i "scale up"
```

**Causas Comuns:**

1. **ASG já no max size:**
   - Verificar: `aws autoscaling describe-auto-scaling-groups`
   - Solução: Aumentar max_size no Marco 1

2. **Node affinity incompatível:**
   - Pods com `nodeSelector: node-type: workloads`?
   - ASG workloads tem label correto?

3. **IAM permissions:**
   - Cluster Autoscaler pode chamar `autoscaling:SetDesiredCapacity`?

### 6.3 Scale-Down Não Funciona

**Sintoma:** Nodes com baixa utilização não são removidos após 10 minutos

**Diagnóstico:**
```bash
# 1. Verificar utilização de nodes
kubectl top nodes

# 2. Verificar scale_down_enabled
terraform output cluster_autoscaler_configuration

# 3. Verificar logs
kubectl logs -n kube-system -l app.kubernetes.io/name=cluster-autoscaler --tail=100 | grep -i "scale down"
```

**Causas Comuns:**

1. **scale_down_enabled = false:**
   - Verificar variável no `main.tf`

2. **Pods com local storage ou system pods:**
   - Pods com `hostPath`, `emptyDir` ou `DaemonSet` bloqueiam scale-down
   - Logs mostrarão: "node has pods with local storage"

3. **Node ainda dentro do delay window:**
   - Aguardar `scale_down_delay_after_add` (10 minutos)

---

## 7. Rollback

### 7.1 Remover Cluster Autoscaler

```bash
# Destroy apenas o módulo cluster_autoscaler
terraform destroy -target=module.cluster_autoscaler

# Confirmar: yes

# Verificar remoção
kubectl get deployment cluster-autoscaler -n kube-system
# Esperado: Error from server (NotFound)
```

### 7.2 Remover Tags dos ASGs (Opcional)

```bash
cd ../marco1

# Destroy apenas as tags
terraform destroy -target=aws_autoscaling_group_tag.workloads_ca_enabled \
                   -target=aws_autoscaling_group_tag.workloads_ca_cluster

# Confirmar: yes
```

### 7.3 Restaurar State (Último Recurso)

```bash
cd ../marco2

# Listar backups
ls -lh backup/*.tfstate

# Restaurar backup
aws s3 cp backup/terraform.tfstate.YYYYMMDD-HHMMSS \
    s3://k8s-platform-terraform-state-891377105802/marco2/terraform.tfstate

# Pull do state restaurado
terraform state pull > current-state.json
```

---

## 8. Próximos Passos

### Após Deploy (Imediato)
1. ✅ Executar script de validação (`validate-cluster-autoscaler.sh`)
2. ✅ Monitorar logs por 30 minutos
3. ✅ Verificar métricas no Prometheus
4. ✅ Executar teste de scale-up (script oferece opção interativa)

### Monitoramento (7 dias)
5. [ ] Dashboard Grafana com métricas de scaling
6. [ ] Alertas Prometheus para scale-up failures
7. [ ] Análise de economia (Cost Explorer)

### Marco 2 Fase 7 (Próximo)
8. [ ] Deploy de aplicações de teste (nginx, echo-server)
9. [ ] Validação end-to-end (Ingress → ALB → Pods → TLS)

---

**Implementado por:** Claude Sonnet 4.5 (DevOps Sênior)
**Framework:** [executor-terraform.md](../../../../../docs/prompts/executor-terraform.md)
**Referências:**
- [ADR-007](../../../../../docs/adr/adr-007-cluster-autoscaler-strategy.md)
- [Cluster Autoscaler Module README](modules/cluster-autoscaler/README.md)
- [Diário de Bordo](../../../../../docs/plan/aws-execution/00-diario-de-bordo.md)

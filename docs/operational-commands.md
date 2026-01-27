# Comandos Operacionais - Cluster EKS

**Atualizado:** 2026-01-27
**Cluster:** k8s-platform-prod
**Region:** us-east-1

---

## 📋 Operação Diária

### Manhã - Iniciar Cluster
```bash
cd platform-provisioning/aws/kubernetes/terraform/envs/marco1/scripts
./startup-cluster-v2.sh
```

**Tempo:** ~15 minutos
**Ações Automáticas:**
- Cria cluster EKS + 7 nodes
- Configura EBS CSI Driver com IAM Role
- Cria StorageClass gp3
- Valida providers.tf do Marco 2
- Aguarda todos os nodes Ready

---

### Validar Status
```bash
# Status básico (Marco 1)
./status-cluster.sh

# Status completo (Marco 1 + Marco 2)
./status-cluster.sh --detailed
```

**Output:**
- Credenciais AWS
- Status do cluster EKS
- Node Groups e custos
- Pods kube-system
- Validação pré-requisitos
- Status Marco 2 (Prometheus, Grafana, Loki, Fluent Bit)
- Recomendações de próximas ações

---

### Fim do Dia - Desligar Cluster
```bash
# Destruição completa (economia: $18.37/dia)
./shutdown-cluster.sh

# Destruição parcial - mantém cluster (economia: $12.76/dia)
./shutdown-cluster.sh --keep-cluster
```

**Modo Keep-Cluster:**
- Mantém: Cluster EKS (Control Plane), Add-ons
- Destrói: Apenas os 7 nodes EC2
- Benefício: Startup rápido no dia seguinte (~5min vs ~15min)

---

## 🔧 Kubernetes - Comandos Úteis

### Nodes
```bash
# Listar nodes
kubectl get nodes

# Detalhes com labels
kubectl get nodes -L node-type,workload,eks.amazonaws.com/nodegroup

# Descrever node específico
kubectl describe node <node-name>

# Resources (CPU/Memory) por node
kubectl top nodes
```

---

### Pods
```bash
# Pods de todos os namespaces
kubectl get pods -A

# Pods do kube-system
kubectl get pods -n kube-system

# Pods do monitoring
kubectl get pods -n monitoring

# Pods com problemas
kubectl get pods -A --field-selector=status.phase!=Running

# Logs de um pod
kubectl logs -n <namespace> <pod-name>

# Logs follow (streaming)
kubectl logs -n <namespace> <pod-name> -f

# Logs de container específico
kubectl logs -n <namespace> <pod-name> -c <container-name>
```

---

### Namespace Monitoring
```bash
# Todos os recursos do monitoring
kubectl get all -n monitoring

# Helm releases
helm list -n monitoring

# Pods por componente
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
kubectl get pods -n monitoring -l app.kubernetes.io/name=fluent-bit

# DaemonSet Fluent Bit
kubectl get ds fluent-bit -n monitoring

# Status dos PVCs
kubectl get pvc -n monitoring
```

---

## 📊 Grafana e Loki

### Acessar Grafana
```bash
# Port-forward
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Acessar: http://localhost:3000
# User: admin
# Password: K8sPlatform2026!

# Obter senha via comando
kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d && echo
```

---

### Consultar Logs no Loki (via Grafana)
1. Acessar Grafana > Explore
2. Selecionar DataSource: Loki
3. Executar queries LogQL:

```logql
# Todos os logs do namespace kube-system
{namespace="kube-system"}

# Logs do monitoring
{namespace="monitoring"}

# Logs de um pod específico
{namespace="kube-system", pod="coredns-xxxxxxxxx"}

# Logs com filtro de texto
{namespace="kube-system"} |= "error"

# Logs de um componente Loki
{namespace="monitoring", app="loki"}

# Logs do Fluent Bit
{namespace="monitoring", app.kubernetes.io/name="fluent-bit"}

# Contar erros por namespace (últimas 5min)
sum(count_over_time({job="fluent-bit"} |= "error" [5m])) by (namespace)
```

---

### Verificar Loki API (Troubleshooting)
```bash
# Port-forward do Loki Gateway
kubectl port-forward -n monitoring svc/loki-gateway 3100:80

# Query labels disponíveis
curl -G -s "http://localhost:3100/loki/api/v1/labels" | jq

# Query valores de um label
curl -G -s "http://localhost:3100/loki/api/v1/label/namespace/values" | jq

# Query logs
curl -G -s "http://localhost:3100/loki/api/v1/query" \
  --data-urlencode 'query={namespace="kube-system"}' \
  --data-urlencode 'limit=10' | jq
```

---

## 🔍 Prometheus

### Acessar Prometheus UI
```bash
# Port-forward
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Acessar: http://localhost:9090
```

### Queries Úteis (PromQL)
```promql
# CPU por node
sum(rate(container_cpu_usage_seconds_total[5m])) by (node)

# Memory por node
sum(container_memory_working_set_bytes) by (node) / 1024 / 1024 / 1024

# Pods por namespace
count(kube_pod_info) by (namespace)

# Status dos pods
kube_pod_status_phase

# Disk usage por PVC
kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes

# Node status
kube_node_status_condition{condition="Ready"}
```

---

## 🗄️ StorageClass e PVCs

### StorageClass
```bash
# Listar StorageClasses
kubectl get storageclass

# Verificar default
kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}'

# Descrever StorageClass gp3
kubectl describe storageclass gp3
```

---

### PVCs
```bash
# Listar PVCs (todos os namespaces)
kubectl get pvc -A

# PVCs do monitoring
kubectl get pvc -n monitoring

# Descrever PVC
kubectl describe pvc -n monitoring <pvc-name>

# Status de binding
kubectl get pvc -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName
```

---

## 🔐 EBS CSI Driver

### Validar IAM Role
```bash
# Service Account do EBS CSI
kubectl get sa ebs-csi-controller-sa -n kube-system -o yaml

# Obter IAM Role ARN
kubectl get sa ebs-csi-controller-sa -n kube-system \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# Verificar pods do EBS CSI
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

# Logs do controller
kubectl logs -n kube-system -l app=ebs-csi-controller -c ebs-plugin
```

---

### Validar Add-on EKS
```bash
# Via AWS CLI
aws eks describe-addon \
  --cluster-name k8s-platform-prod \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1 \
  --profile k8s-platform-prod
```

---

## 🧹 Troubleshooting

### Pods Stuck em Pending
```bash
# Ver eventos do pod
kubectl describe pod -n <namespace> <pod-name>

# Verificar se é problema de StorageClass
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | grep ProvisioningFailed

# Verificar PVC
kubectl describe pvc -n <namespace> <pvc-name>
```

---

### Helm Release Stuck
```bash
# Listar todos os releases (incluindo failed)
helm list -n <namespace> -a

# Ver histórico de release
helm history -n <namespace> <release-name>

# Rollback
helm rollback -n <namespace> <release-name> <revision>

# Uninstall forçado
helm uninstall -n <namespace> <release-name>

# Se persistir, remover secret do Helm
kubectl delete secret -n <namespace> sh.helm.release.v1.<release-name>.v<version>
```

---

### Terraform State Lock
```bash
# Listar locks no DynamoDB
aws dynamodb scan \
  --table-name terraform-state-lock \
  --region us-east-1 \
  --profile k8s-platform-prod

# Remover lock específico
terraform force-unlock -force <LOCK_ID>

# OU via DynamoDB
aws dynamodb delete-item \
  --table-name terraform-state-lock \
  --key '{"LockID":{"S":"<LOCK_ID>"}}' \
  --region us-east-1 \
  --profile k8s-platform-prod
```

---

### Token Expirado
```bash
# Renovar kubeconfig
aws eks update-kubeconfig \
  --region us-east-1 \
  --name k8s-platform-prod \
  --profile k8s-platform-prod

# Validar autenticação
kubectl auth can-i get pods --all-namespaces
```

---

## 💾 Backup e Restore

### Backup Terraform State
```bash
# Backup manual
cd platform-provisioning/aws/kubernetes/terraform/envs/marco1
terraform state pull > backup-$(date +%Y%m%d_%H%M%S).tfstate

# Backups automáticos em:
ls -lh ~/.terraform-backups/marco1/
```

---

### Backup Grafana Dashboards
```bash
# Export via API (requer port-forward ativo)
curl -u admin:K8sPlatform2026! \
  http://localhost:3000/api/search | jq -r '.[] | .uid' | \
  while read uid; do
    curl -u admin:K8sPlatform2026! \
      "http://localhost:3000/api/dashboards/uid/$uid" | \
      jq . > "dashboard-$uid.json"
  done
```

---

## 📊 Métricas e Custos

### Custos Atualizados via AWS CLI
```bash
# Nodes EC2 ativos
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=k8s-platform-prod" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{Type:InstanceType,State:State.Name}' \
  --profile k8s-platform-prod

# Add-ons instalados
aws eks list-addons \
  --cluster-name k8s-platform-prod \
  --region us-east-1 \
  --profile k8s-platform-prod
```

---

### Resource Usage (kubectl top)
```bash
# Requer metrics-server (incluído no kube-prometheus-stack)
kubectl top nodes
kubectl top pods -A
kubectl top pods -n monitoring --sort-by=cpu
kubectl top pods -n monitoring --sort-by=memory
```

---

## 🚨 Alertas Importantes

### Configurar Alertas Críticos
Dashboards no Grafana com alertas configurados:
- Node CPU > 80%
- Node Memory > 85%
- Pod CrashLoopBackOff
- PVC > 80% utilizado
- EBS CSI Driver falhas de provisionamento

---

## 📞 Contatos e Referências

**Documentação:**
- Scripts v2.0: `docs/scripts-improvements-v2.md`
- Plano Consolidado: `~/.claude/plans/purring-jumping-truffle-consolidated.md`
- Execution Plan: `docs/plan/aws-console-execution-plan.md`

**Terraform Docs:**
- Marco 1: `platform-provisioning/aws/kubernetes/terraform/envs/marco1/README.md`
- Marco 2: `platform-provisioning/aws/kubernetes/terraform/envs/marco2/README.md`

**Helm Charts:**
- Kube-Prometheus-Stack: https://github.com/prometheus-community/helm-charts
- Loki: https://github.com/grafana/loki/tree/main/production/helm/loki
- Fluent Bit: https://github.com/fluent/helm-charts

---

**Última atualização:** 2026-01-27
**Versão Scripts:** v2.0
**Status:** Marco 1 e Marco 2 Completos

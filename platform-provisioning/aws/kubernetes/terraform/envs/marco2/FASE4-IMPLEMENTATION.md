# Marco 2 - Fase 4: Logging (Loki + Fluent Bit)

**Data:** 2026-01-26
**Status:** ✅ Código Implementado - Aguardando Deploy
**Tempo Estimado Deploy:** 10-15 minutos

---

## 📋 Resumo Executivo

Implementação completa do sistema de logging centralizado usando:
- **Loki** (S3 backend) para armazenamento de logs
- **Fluent Bit** (DaemonSet) para coleta de logs
- **Integração Grafana** para visualização
- **CloudWatch** em hold (não implementado)

---

## ✅ O Que Foi Implementado

### 1. ADR-005: Logging Strategy

**Arquivo:** [docs/adr/adr-005-logging-strategy.md](/home/gilvangalindo/projects/Arquitetura/Kubernetes/docs/adr/adr-005-logging-strategy.md)

**Decisão:**
- ✅ Loki como solução primária (cloud-agnostic)
- ⏸️ CloudWatch em hold (documentado, não implementado)
- **Economia:** $15.90/mês (Loki) vs $55/mês (CloudWatch) = **$468/ano saved**

### 2. Módulo Terraform: Loki

**Diretório:** `modules/loki/`

**Arquivos:**
- `main.tf` (330 linhas)
- `variables.tf` (15 variáveis)
- `outputs.tf` (11 outputs)
- `versions.tf`

**Componentes:**
- S3 bucket para logs (`k8s-platform-loki-{ACCOUNT_ID}`)
  - Encryption: AES256
  - Lifecycle: 30 dias
  - Public access blocked
- IAM Role + Policy (IRSA pattern)
  - S3: ListBucket, GetObject, PutObject, DeleteObject
  - Trust relationship com OIDC Provider
- Kubernetes Service Account (annotation eks.amazonaws.com/role-arn)
- Helm release: `grafana/loki` v5.42.0
  - Mode: SimpleScalable
  - Read: 2 replicas
  - Write: 2 replicas
  - Backend: 2 replicas
  - Gateway: 2 replicas (Nginx)

### 3. Módulo Terraform: Fluent Bit

**Diretório:** `modules/fluent-bit/`

**Arquivos:**
- `main.tf` (270 linhas)
- `variables.tf` (10 variáveis)
- `outputs.tf` (6 outputs)
- `versions.tf`

**Componentes:**
- Helm release: `fluent/fluent-bit` v0.43.0
- DaemonSet (roda em todos os nodes)
- Parsers:
  - Docker JSON
  - CRI-O
  - Multiline regex (stack traces)
- Filters:
  - Kubernetes metadata enrichment
  - Namespace filtering (exclude kube-system, etc.)
  - Label extraction
- Output:
  - Loki (http://loki-gateway.monitoring:3100/loki/api/v1/push)
- Resources:
  - Requests: 100m CPU, 128Mi RAM
  - Limits: 200m CPU, 256Mi RAM

### 4. Integration no marco2/main.tf

**Adicionado:**
```terraform
module "loki" {
  source = "./modules/loki"
  # ... configuração completa
}

module "fluent_bit" {
  source = "./modules/fluent-bit"
  # ... configuração completa
}
```

**Outputs adicionados:**
- `loki_s3_bucket`
- `loki_iam_role_arn`
- `loki_gateway_endpoint`
- `loki_push_endpoint`
- `fluent_bit_daemonset`
- `fluent_bit_namespace`

### 5. Script de Validação

**Arquivo:** `scripts/validate-fase4.sh` (300 linhas)

**Validações:**
- Pre-flight checks (AWS CLI, kubectl, terraform)
- AWS credentials
- S3 bucket (existence, lifecycle, encryption)
- IAM role e policies
- Loki pods (8 expected: 2+2+2+2)
- Fluent Bit DaemonSet (7 nodes expected)
- Loki API health
- Grafana datasource

**Uso:**
```bash
cd platform-provisioning/aws/kubernetes/terraform/envs/marco2
./scripts/validate-fase4.sh
```

---

## 🚀 Como Fazer o Deploy

### Passo 1: Configurar Credenciais AWS

```bash
# Opção 1: SSO
aws sso login --profile k8s-platform-prod
export AWS_PROFILE=k8s-platform-prod

# Opção 2: Variáveis de ambiente
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret
export AWS_DEFAULT_REGION=us-east-1

# Validar
aws sts get-caller-identity
```

### Passo 2: Navegar para o Diretório

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/envs/marco2
```

### Passo 3: Terraform Init

```bash
terraform init -upgrade
```

**Output esperado:**
```
Initializing modules...
- aws_load_balancer_controller in modules/aws-load-balancer-controller
- cert_manager in modules/cert-manager
- fluent_bit in modules/fluent-bit  ← NOVO
- kube_prometheus_stack in modules/kube-prometheus-stack
- loki in modules/loki  ← NOVO

Terraform has been successfully initialized!
```

### Passo 4: Terraform Plan

```bash
terraform plan -out=fase4.tfplan
```

**Recursos que serão criados:**
```
Plan: XX to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + fluent_bit_daemonset      = "fluent-bit"
  + fluent_bit_namespace      = "monitoring"
  + loki_gateway_endpoint     = "http://loki-gateway.monitoring:3100"
  + loki_iam_role_arn         = (known after apply)
  + loki_push_endpoint        = "http://loki-gateway.monitoring:3100/loki/api/v1/push"
  + loki_s3_bucket            = "k8s-platform-loki-891377105802"
```

**Revisar:**
- S3 bucket: `k8s-platform-loki-{ACCOUNT_ID}`
- IAM role: `LokiS3Role-k8s-platform-prod`
- IAM policy: `LokiS3Policy-k8s-platform-prod`
- Helm releases: `loki`, `fluent-bit`

### Passo 5: Terraform Apply

```bash
terraform apply fase4.tfplan
```

**Tempo estimado:** 5-10 minutos

**Progresso esperado:**
```
1. Creating S3 bucket (30s)
2. Creating IAM policy (10s)
3. Creating IAM role (10s)
4. Attaching policy to role (5s)
5. Creating Kubernetes Service Account (5s)
6. Installing Loki Helm chart (3-5 min)
   - Creating namespace (if not exists)
   - Creating Loki components
   - Waiting for pods to be Ready
7. Installing Fluent Bit Helm chart (1-2 min)
   - Creating DaemonSet
   - Waiting for pods on all nodes
```

### Passo 6: Validar Deployment

```bash
# Usar o script de validação
./scripts/validate-fase4.sh

# Ou validar manualmente
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
kubectl get daemonset -n monitoring fluent-bit
kubectl get pvc -n monitoring
```

**Output esperado:**
```
NAME                                READY   STATUS    AGE
loki-backend-0                      1/1     Running   5m
loki-backend-1                      1/1     Running   5m
loki-gateway-xxx                    1/1     Running   5m
loki-gateway-yyy                    1/1     Running   5m
loki-read-0                         1/1     Running   5m
loki-read-1                         1/1     Running   5m
loki-write-0                        1/1     Running   5m
loki-write-1                        1/1     Running   5m

NAME         DESIRED   CURRENT   READY   AGE
fluent-bit   7         7         7       5m
```

### Passo 7: Testar Ingestion de Logs

```bash
# 1. Port-forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# 2. Acessar Grafana
# http://localhost:3000
# User: admin
# Password: (obter do AWS Secrets Manager)

# 3. Recuperar senha
aws secretsmanager get-secret-value \
    --secret-id k8s-platform-prod/grafana-admin-password \
    --query SecretString \
    --output text \
    --profile k8s-platform-prod

# 4. No Grafana:
# - Ir para Explore
# - Selecionar datasource: Loki
# - Query: {namespace="monitoring"}
# - Verificar logs aparecem
```

### Passo 8: Validar Correlação Trace↔Log (Opcional)

```bash
# No Grafana:
# 1. Ir para dashboard de Traces (Tempo)
# 2. Clicar em um trace ID
# 3. Procurar botão "Logs for this span"
# 4. Clicar → deve abrir Loki com logs filtrados
```

---

## 🔍 Troubleshooting

### Issue 1: Loki Pods Pending

**Sintoma:**
```
loki-write-0   0/1   Pending
```

**Diagnóstico:**
```bash
kubectl describe pod loki-write-0 -n monitoring
# Procurar: "FailedScheduling" ou "Insufficient resources"
```

**Solução:**
- Verificar nodes disponíveis: `kubectl get nodes`
- Verificar taints: `kubectl describe node <node-name> | grep Taints`
- Verificar PVC bound: `kubectl get pvc -n monitoring`

### Issue 2: S3 Access Denied

**Sintoma:**
```
Error: AccessDenied: Access Denied
```

**Diagnóstico:**
```bash
# Verificar IAM role
aws iam get-role --role-name LokiS3Role-k8s-platform-prod

# Verificar trust policy
aws iam get-role --role-name LokiS3Role-k8s-platform-prod --query 'Role.AssumeRolePolicyDocument'

# Verificar Service Account annotation
kubectl get sa loki -n monitoring -o yaml
```

**Solução:**
- Verificar annotation: `eks.amazonaws.com/role-arn`
- Verificar OIDC provider existe: `aws iam list-open-id-connect-providers`
- Verificar trust policy tem namespace correto

### Issue 3: Fluent Bit Não Enviando Logs

**Sintoma:**
- Grafana Explore → Loki → No logs found

**Diagnóstico:**
```bash
# Ver logs do Fluent Bit
kubectl logs -n monitoring daemonset/fluent-bit --tail=50

# Procurar erros de conexão
# "connection refused", "timeout", "unknown host"
```

**Solução:**
- Verificar Loki Gateway service: `kubectl get svc -n monitoring loki-gateway`
- Verificar endpoint configurado: `kubectl describe daemonset fluent-bit -n monitoring | grep loki`
- Testar conectividade: `kubectl exec -n monitoring -it <fluent-bit-pod> -- curl http://loki-gateway:3100/ready`

### Issue 4: Logs Vazios no Grafana

**Sintoma:**
- Query retorna, mas sem conteúdo

**Diagnóstico:**
```bash
# Verificar se Fluent Bit está coletando
kubectl logs -n monitoring daemonset/fluent-bit | grep "Loki"

# Procurar: "POST /loki/api/v1/push" (sucesso)
```

**Solução:**
- Verificar filtros: namespaces excluídos em `exclude_namespaces`
- Aumentar range de tempo no Grafana (última 1h → último 1d)
- Verificar parsers: logs podem estar sendo dropados

---

## 💰 Custos Estimados

### Novos Recursos (Marco 2 Fase 4)

| Recurso | Quantidade | Unit Cost | Monthly Cost |
|---------|-----------|-----------|--------------|
| **S3 Storage** (logs) | 500GB | $0.023/GB | $11.50 |
| **S3 API Requests** | 1M PUT | $0.005/1k | $5.00 |
| **EBS gp3 Storage** (Loki PVCs) | 20GB (write) + 20GB (backend) | $0.08/GB | $3.20 |
| **IAM Resources** | Role + Policy | Free | $0.00 |
| **EC2 Compute** | Existing nodes | $0.00 | $0.00 |
| **Total Marco 2 Fase 4** | - | - | **$19.70/mês** |

### Comparação CloudWatch

| Solução | Monthly Cost | Annual Cost | Savings |
|---------|--------------|-------------|---------|
| **Loki + S3** | $19.70 | $236.40 | Baseline |
| **CloudWatch** | $55.00 | $660.00 | -$423.60/ano |

**ROI:** Loki economiza ~$423/ano (~64% de economia)

---

## 📚 Arquivos Criados/Modificados

### Novos Arquivos

1. `docs/adr/adr-005-logging-strategy.md` (450 linhas)
2. `modules/loki/main.tf` (330 linhas)
3. `modules/loki/variables.tf` (95 linhas)
4. `modules/loki/outputs.tf` (50 linhas)
5. `modules/loki/versions.tf` (20 linhas)
6. `modules/fluent-bit/main.tf` (270 linhas)
7. `modules/fluent-bit/variables.tf` (60 linhas)
8. `modules/fluent-bit/outputs.tf` (30 linhas)
9. `modules/fluent-bit/versions.tf` (15 linhas)
10. `scripts/validate-fase4.sh` (300 linhas)
11. `FASE4-IMPLEMENTATION.md` (este arquivo)

### Arquivos Modificados

1. `main.tf` (+60 linhas: módulos loki e fluent_bit)
2. `outputs.tf` (+40 linhas: outputs loki e fluent_bit)

**Total Linhas de Código:** ~1,720 linhas (Terraform + Bash + Markdown)

---

## 📖 Referências

### Documentação

- [ADR-005: Logging Strategy](../../../../docs/adr/adr-005-logging-strategy.md)
- [04-observability-stack.md](../../../../docs/plan/aws-execution/04-observability-stack.md) (Linhas 803-1075)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Fluent Bit Documentation](https://docs.fluentbit.io/manual/)

### Terraform Modules

- [Loki Helm Chart](https://grafana.github.io/helm-charts)
- [Fluent Bit Helm Chart](https://fluent.github.io/helm-charts)
- [AWS S3 Terraform Resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket)
- [AWS IAM Role Terraform Resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role)

---

## ✅ Definition of Done

### Fase 4 Completa Quando:

- [x] ADR-005 criado e aprovado
- [x] Módulo Terraform Loki implementado
- [x] Módulo Terraform Fluent Bit implementado
- [x] Integration no marco2/main.tf
- [x] Script de validação criado
- [ ] **Terraform apply executado com sucesso**
- [ ] **S3 bucket criado e configurado**
- [ ] **IAM role e policy criados**
- [ ] **8 pods Loki Running (2+2+2+2)**
- [ ] **7 pods Fluent Bit Running (DaemonSet)**
- [ ] **Logs visíveis no Grafana Explore**
- [ ] **Query LogQL funcionando**
- [ ] **Correlação Trace↔Log testada**
- [ ] Documentação atualizada (DEPLOY-CHECKLIST, diário)

---

## 🎯 Próximos Passos (Após Fase 4)

### Marco 2 - Fase 5: Network Policies

- Calico ou AWS VPC CNI Network Policies
- Isolamento entre namespaces
- Egress rules para APIs externas

### Marco 2 - Fase 6: Cluster Autoscaler / Karpenter

- Auto-scaling de nodes
- Scale-to-zero para node groups não-críticos
- Otimização de custos

### Marco 2 - Fase 7: Aplicações de Teste

- Deploy de aplicação sample (nginx, echo-server)
- Validação end-to-end (Ingress → ALB → Pods)
- Testes de certificados TLS (Let's Encrypt)

---

**Status Atual:** ✅ Implementação Completa - Aguardando Deploy
**Próxima Ação:** Configurar AWS credentials e executar `terraform plan`
**Última Atualização:** 2026-01-26
**Estimativa Deploy:** 10-15 minutos

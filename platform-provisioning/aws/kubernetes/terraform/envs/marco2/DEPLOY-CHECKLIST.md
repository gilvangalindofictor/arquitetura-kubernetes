# Deploy Checklist - Marco 2 Platform Services

**Data:** 2026-01-26
**Sprint:** Marco 2 - Fase 3 (Kube-Prometheus-Stack)
**Status:** ⏸️ PRÉ-DEPLOY (Aguardando validações finais)

---

## 📋 Pré-requisitos

### ✅ Completados

- [x] Marco 0: Backend Terraform funcional (S3 + DynamoDB)
- [x] Marco 1: Cluster EKS com 7 nodes operacionais
- [x] Marco 2 - Fase 1: AWS Load Balancer Controller instalado
- [x] Marco 2 - Fase 2: Cert-Manager instalado
- [x] Secrets migrados para AWS Secrets Manager
- [x] ADR-003 e ADR-004 criados e aprovados
- [x] Código Terraform formatado (terraform fmt)
- [x] Script de validação atualizado

### ⏳ Pendentes

- [ ] Credenciais AWS ativas (`aws sso login --profile k8s-platform-prod`)
- [ ] kubectl configurado e acessando o cluster
- [ ] tfsec instalado (opcional, mas recomendado para scan de segurança)
- [ ] Confirmação do usuário para prosseguir com deploy

---

## 🔧 Instalação de Ferramentas (Opcional)

### tfsec (Security Scanner)

**Por que instalar?**
- Identifica issues de segurança no código Terraform antes do deploy
- Valida best practices (encryption, IAM, secrets, etc.)
- Gera relatórios para auditoria

**Como instalar:**

```bash
# Option 1: Homebrew (macOS/Linux)
brew install tfsec

# Option 2: Go
go install github.com/aquasecurity/tfsec/cmd/tfsec@latest

# Option 3: Download binary
# https://github.com/aquasecurity/tfsec/releases

# Option 4: Docker (sem instalação local)
docker run --rm -it -v "$(pwd):/src" aquasec/tfsec /src
```

**Executar scan:**

```bash
cd platform-provisioning/aws/kubernetes/terraform/envs/marco2
./scripts/security-scan.sh
```

**Resultado esperado:**
- ✅ 0 CRITICAL issues
- ✅ 0 HIGH issues
- ✅ 0 MEDIUM issues
- ⚠️ 2 LOW issues (aceitos e documentados em SECURITY-ANALYSIS.md)

---

## ✅ Validações Pré-Deploy

### 1. Validar Credenciais AWS

```bash
export AWS_PROFILE=k8s-platform-prod
aws sts get-caller-identity
```

**Resultado esperado:**
```json
{
    "UserId": "...",
    "Account": "891377105802",
    "Arn": "arn:aws:sts::891377105802:assumed-role/AWSReservedSSO_AdministratorAccess/gilvan.galindo"
}
```

### 2. Validar Acesso ao Cluster EKS

```bash
aws eks update-kubeconfig --region us-east-1 --name k8s-platform-prod --profile k8s-platform-prod
kubectl get nodes
```

**Resultado esperado:**
```
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-128-205.ec2.internal  Ready    <none>   Xd    v1.31.x
... (7 nodes total)
```

### 3. Executar Script de Validação

```bash
cd domains/observability/infra/validation
./validate.sh
```

**Resultado esperado:**
- ✅ AWS credentials válidas
- ✅ Terraform init successful
- ✅ Terraform validation successful
- ✅ Terraform files properly formatted
- ✅ Terraform plan sem erros

### 4. Validar Terraform Plan (Marco 2)

```bash
cd platform-provisioning/aws/kubernetes/terraform/envs/marco2
terraform init
terraform plan
```

**Recursos a serem criados (esperado):**
- `aws_secretsmanager_secret.grafana_admin_password`
- `aws_secretsmanager_secret_version.grafana_admin_password`
- `module.kube_prometheus_stack.kubernetes_namespace.monitoring`
- `module.kube_prometheus_stack.helm_release.kube_prometheus_stack`

**Recursos já existentes (não devem ser recriados):**
- `aws_iam_openid_connect_provider.eks`
- `module.aws_load_balancer_controller.*`
- `module.cert_manager.*`

---

## 🚀 Deploy - Marco 2 Fase 3

### Passo 1: Aplicar Terraform

```bash
cd platform-provisioning/aws/kubernetes/terraform/envs/marco2

# Exportar credenciais (se necessário)
export AWS_PROFILE=k8s-platform-prod

# Review final
terraform plan -out=marco2-phase3.tfplan

# Aplicar (com confirmação)
terraform apply marco2-phase3.tfplan
```

**Tempo estimado:** 3-5 minutos

**Recursos criados:**
1. AWS Secrets Manager secret (grafana_admin_password)
2. Kubernetes namespace (monitoring)
3. Helm release (kube-prometheus-stack)
4. PersistentVolumeClaims (Prometheus: 20Gi, Grafana: 5Gi, Alertmanager: 2Gi)

### Passo 2: Validar Deployments

```bash
# 1. Verificar namespace
kubectl get namespace monitoring

# 2. Verificar pods (aguardar até todos Running)
kubectl get pods -n monitoring
watch kubectl get pods -n monitoring

# Esperado: Todos os pods Running
# - prometheus-kube-prometheus-stack-prometheus-0 (1/1 Running)
# - kube-prometheus-stack-operator-* (1/1 Running)
# - kube-prometheus-stack-grafana-* (3/3 Running)
# - alertmanager-kube-prometheus-stack-alertmanager-0 (2/2 Running)
# - kube-state-metrics-* (1/1 Running)
# - node-exporter-* (1/1 Running per node - 7 total)

# 3. Verificar PVCs
kubectl get pvc -n monitoring

# Esperado:
# - prometheus-kube-prometheus-stack-prometheus-prometheus-0 (Bound, 20Gi)
# - storage-kube-prometheus-stack-grafana-0 (Bound, 5Gi)
# - alertmanager-kube-prometheus-stack-alertmanager-0 (Bound, 2Gi)

# 4. Verificar Services
kubectl get svc -n monitoring

# 5. Verificar ServiceMonitors
kubectl get servicemonitor -n monitoring
```

### Passo 3: Acessar Grafana

```bash
# Port-forward para acessar Grafana localmente
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Abrir browser: http://localhost:3000
# User: admin
# Password: (recuperar do AWS Secrets Manager)
```

**Recuperar senha do Grafana:**

```bash
aws secretsmanager get-secret-value \
    --secret-id k8s-platform-prod/grafana-admin-password \
    --query SecretString \
    --output text \
    --profile k8s-platform-prod
```

### Passo 4: Validar Dashboards

No Grafana (http://localhost:3000), verificar:

1. **Home → Dashboards**
   - ✅ Kubernetes / Compute Resources / Cluster
   - ✅ Kubernetes / Compute Resources / Namespace (Pods)
   - ✅ Kubernetes / Compute Resources / Node (Pods)
   - ✅ Node Exporter / Nodes
   - ✅ Prometheus / Overview

2. **Explore → Prometheus**
   - Query: `up{job="kubernetes-nodes"}`
   - Esperado: 7 nodes UP (value = 1)

3. **Alerting → Alert Rules**
   - Verificar regras padrão do kube-prometheus-stack
   - Ex: Watchdog, KubeNodeNotReady, KubePodCrashLooping, etc.

---

## 🔍 Troubleshooting

### Issue: Pods Pending (Aguardando PVC)

**Sintoma:**
```
prometheus-kube-prometheus-stack-prometheus-0   0/2   Pending
```

**Diagnóstico:**
```bash
kubectl describe pod prometheus-kube-prometheus-stack-prometheus-0 -n monitoring
# Procurar por: "FailedScheduling" ou "PersistentVolumeClaim is not bound"
```

**Solução:**
- Verificar se EBS CSI Driver está funcionando (Marco 1)
- Verificar se StorageClass `gp3` existe: `kubectl get sc`
- Verificar eventos do PVC: `kubectl describe pvc -n monitoring`

### Issue: Pods CrashLoopBackOff

**Sintoma:**
```
kube-prometheus-stack-grafana-*   2/3   CrashLoopBackOff
```

**Diagnóstico:**
```bash
kubectl logs -n monitoring kube-prometheus-stack-grafana-* --previous
```

**Possíveis causas:**
- Senha do Grafana inválida (verificar Secrets Manager)
- Resource limits muito baixos (aumentar em variables.tf)
- PVC não montado corretamente

### Issue: Terraform Plan quer recriar recursos existentes

**Sintoma:**
```
# module.aws_load_balancer_controller.helm_release.aws_load_balancer_controller must be replaced
```

**Solução:**
- Não aplicar! Verificar se backend state está correto
- Executar: `terraform state list` e comparar com recursos no cluster
- Se necessário: `terraform state rm <resource>` e depois `terraform import`

---

## 📊 Métricas de Sucesso

### Critérios de Aceitação

- [x] **Secrets Management**: Senha Grafana no AWS Secrets Manager
- [x] **Código**: terraform fmt -check passa sem erros
- [x] **Documentação**: ADR-003 e ADR-004 criados
- [x] **Validação**: Script validate.sh atualizado e funcional
- [ ] **Deploy**: Todos os pods Running em < 5 minutos
- [ ] **Acesso**: Grafana acessível via port-forward
- [ ] **Dashboards**: Dashboards padrão funcionando e mostrando métricas
- [ ] **Persistência**: PVCs criados e Bound (Prometheus, Grafana, Alertmanager)

### KPIs

| Métrica | Target | Status |
|---------|--------|--------|
| Pods Running | 100% (13+ pods) | ⏳ Pendente |
| PVCs Bound | 3/3 (Prometheus, Grafana, Alertmanager) | ⏳ Pendente |
| Memory Usage | < 2GB (Prometheus) | ⏳ Pendente |
| Startup Time | < 5 minutos (todos os pods) | ⏳ Pendente |
| Dashboards Funcionais | 5+ dashboards padrão | ⏳ Pendente |

---

## 🎯 Próximas Fases (Marco 2)

### Fase 4: Fluent Bit + CloudWatch (Logging)
- Fluent Bit DaemonSet
- Log aggregation para CloudWatch Logs
- Dashboards de logs no Grafana

### Fase 5: Network Policies
- Calico ou AWS VPC CNI Network Policies
- Isolamento entre namespaces
- Egress rules para APIs externas

### Fase 6: Cluster Autoscaler / Karpenter
- Auto-scaling de nodes
- Scale-to-zero para node groups não-críticos
- Otimização de custos

### Fase 7: Aplicações de Teste
- Deploy de aplicação sample (nginx, echo-server)
- Validação end-to-end (Ingress → ALB → Pods)
- Testes de certificados TLS (Let's Encrypt)

---

## 📝 Checklist Final (Pré-Commit)

Antes de commitar as mudanças:

- [x] ✅ Código Terraform formatado (`terraform fmt -recursive`)
- [x] ✅ Variáveis sensíveis marcadas como `sensitive = true`
- [x] ✅ Secrets migrados para AWS Secrets Manager
- [x] ✅ ADRs criados e documentados
- [x] ✅ Scripts de validação atualizados
- [x] ✅ SECURITY-ANALYSIS.md criado
- [ ] ⏳ tfsec scan executado (0 critical, 0 high, 0 medium)
- [ ] ⏳ Terraform apply executado com sucesso
- [ ] ⏳ Todos os pods Running e healthy
- [ ] ⏳ Grafana acessível e dashboards funcionando
- [ ] ⏳ Documentação no diário de bordo atualizada

---

## 🔗 Referências

- [SECURITY-ANALYSIS.md](SECURITY-ANALYSIS.md) - Análise de segurança completa
- [ADR-003](../../../../docs/adr/adr-003-secrets-management-strategy.md) - Secrets Management Strategy
- [ADR-004](../../../../docs/adr/adr-004-terraform-vs-helm-for-platform-services.md) - Terraform vs Helm
- [Diário Marco 0](../../../../docs/plan/aws-execution/diario-marco0-2026-01-23.md) - Histórico de execução
- [Kube-Prometheus-Stack Docs](https://github.com/prometheus-operator/kube-prometheus)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)

---

**Última atualização:** 2026-01-26
**Revisado por:** DevOps Team
**Status:** ⏸️ PRONTO PARA DEPLOY (aguardando confirmação do usuário)

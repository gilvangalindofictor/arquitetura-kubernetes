# PRE-HOOK: Validação OpenTelemetry Tempo (Antes do Deploy)

**Data:** 2026-01-30
**Projeto:** OpenTelemetry Tempo + Collector (Marco 2 - Fase 8)
**Status:** ✅ **OBRIGATÓRIO** - Executar ANTES de `terraform apply`

---

## 🎯 Objetivo

Validar que todas as **ressalvas obrigatórias** identificadas pelos agentes especialistas foram implementadas antes do deploy.

**Consenso Técnico:** 3 agentes (AWS, Terraform, FinOps) aprovaram com **11 ressalvas** (7 bloqueantes, 4 recomendadas).

---

## ✅ Checklist PRÉ-DEPLOY (Bloqueantes)

### ☁️ AWS Specialist (3 validações bloqueantes)

#### 1. VPC Endpoint S3 - Economia $22.50/mês + Segurança

- [ ] **VPC Endpoint S3 criado**
  - Serviço: `com.amazonaws.us-east-1.s3`
  - VPC: `vpc-0b1396a59c417c1f0`
  - Route Tables: Todas as private subnets
  - **Comando criação:**
    ```bash
    aws ec2 create-vpc-endpoint \
      --vpc-id vpc-0b1396a59c417c1f0 \
      --service-name com.amazonaws.us-east-1.s3 \
      --route-table-ids $(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=vpc-0b1396a59c417c1f0" "Name=tag:Name,Values=*private*" \
        --query 'RouteTables[].RouteTableId' --output text)
    ```
  - **Validação:**
    ```bash
    aws ec2 describe-vpc-endpoints \
      --filters "Name=vpc-id,Values=vpc-0b1396a59c417c1f0" \
                "Name=service-name,Values=com.amazonaws.us-east-1.s3"
    # Esperado: State = "available"
    ```
  - **Economia:** $22.50/mês NAT Gateway data transfer + segurança

---

#### 2. S3 Lifecycle Policy - Delete automático 7 dias

- [ ] **Lifecycle policy configurada no módulo Terraform**
  - **Arquivo:** `modules/tempo/s3.tf`
  - **Policy esperada:**
    ```hcl
    resource "aws_s3_bucket_lifecycle_configuration" "tempo" {
      bucket = aws_s3_bucket.tempo.id

      rule {
        id     = "delete-old-traces-7d"
        status = "Enabled"

        expiration {
          days = 7
        }

        noncurrent_version_expiration {
          noncurrent_days = 1
        }
      }
    }
    ```
  - **Validação pós-apply:**
    ```bash
    aws s3api get-bucket-lifecycle-configuration \
      --bucket k8s-platform-tempo-891377105802 | jq '.Rules'
    # Esperado: Expiration.Days = 7
    ```
  - **Economia:** $4.60/mês (prevenir retention creep)

---

#### 3. Network Policies - 4 novas políticas Calico

- [ ] **Network Policies criadas no módulo Terraform**
  - **Arquivo:** `modules/tempo/network-policies.tf` OU `modules/network-policies/tempo.tf`
  - **Políticas esperadas:**
    1. `allow-otel-collector-ingress` (Apps → OTel Collector:4317,4318)
    2. `allow-otel-to-tempo` (OTel Collector → Tempo distributor:3100)
    3. `allow-grafana-to-tempo` (Grafana → Tempo query-frontend:3100)
    4. `allow-tempo-to-s3` (Tempo → S3 egress:443)
  - **Validação pós-apply:**
    ```bash
    kubectl get networkpolicies -n monitoring | grep -E "otel|tempo"
    # Esperado: 4 policies (allow-otel-collector-ingress, allow-otel-to-tempo, allow-grafana-to-tempo, allow-tempo-to-s3)
    ```

---

### 🌱 Terraform Specialist (2 validações bloqueantes)

#### 4. Chart Correto - tempo-distributed v1.10.x

- [ ] **Helm chart especificado corretamente**
  - **Arquivo:** `modules/tempo/main.tf` → `helm_release.tempo`
  - **Chart:** `grafana/tempo-distributed`
  - **Version:** `>= 1.10.0, < 2.0.0`
  - ❌ **NÃO usar:** `grafana/tempo` (modo monolítico, não production-ready)
  - **Validação:**
    ```bash
    helm search repo grafana/tempo-distributed
    # Esperado: Chart version 1.10.x disponível

    grep -A5 "resource \"helm_release\" \"tempo\"" modules/tempo/main.tf | grep chart
    # Esperado: chart = "tempo-distributed"
    ```

---

#### 5. Deploy 2 Fases - Evitar circular dependency

- [ ] **Strategy 2-phase documentada**
  - **Fase 1:** Deploy Tempo isolado
    ```bash
    terraform apply -target=module.tempo
    ```
  - **Fase 2:** Adicionar Grafana datasource e re-apply
    ```bash
    # Editar modules/kube-prometheus-stack/main.tf
    # Adicionar: grafana.additionalDataSources[1] (Tempo)
    terraform apply
    ```
  - **Reason:** Grafana datasource precisa de Tempo query-frontend endpoint UP
  - **Validação dependency:**
    ```bash
    grep -A10 "module \"tempo\"" envs/marco2/main.tf | grep depends_on
    # Esperado: depends_on = [module.kube_prometheus_stack, module.loki]
    ```

---

### 💰 FinOps Specialist (2 validações bloqueantes)

#### 6. Tail Sampling - 10% normal, 100% erros

- [ ] **OpenTelemetry Collector configurado com tail sampling**
  - **Arquivo:** `modules/opentelemetry-collector/values.yaml` (ou criar módulo)
  - **Config esperada:**
    ```yaml
    config:
      processors:
        tail_sampling:
          decision_wait: 10s
          num_traces: 100
          policies:
            - name: errors-policy
              type: status_code
              status_code:
                status_codes: [ERROR]
            - name: slow-requests-policy
              type: latency
              latency:
                threshold_ms: 1000
            - name: probabilistic-policy
              type: probabilistic
              probabilistic:
                sampling_percentage: 10
      service:
        pipelines:
          traces:
            processors: [memory_limiter, tail_sampling, batch]
    ```
  - **Validação pós-deploy:**
    ```bash
    kubectl get configmap -n monitoring opentelemetry-collector -o yaml | grep -A15 tail_sampling
    # Esperado: policies com probabilistic_sampling 10%
    ```
  - **Economia:** $3.65/mês (80% redução custos traces)

---

#### 7. Reduzir EBS Volumes - 20GB → 10GB

- [ ] **PVC size configurado corretamente no Helm values**
  - **Arquivo:** `modules/tempo/main.tf` → `helm_release.tempo` values
  - **Configuração esperada:**
    ```hcl
    set {
      name  = "ingester.persistence.size"
      value = "10Gi"
    }

    set {
      name  = "compactor.persistence.size"
      value = "10Gi"
    }
    ```
  - **Validação pós-apply:**
    ```bash
    kubectl get pvc -n monitoring -l app.kubernetes.io/name=tempo
    # Esperado: 2 PVCs com CAPACITY = 10Gi (ingester, compactor)
    ```
  - **Economia:** $1.60/mês (50% redução EBS costs)

---

## 💡 Recomendações (Não-Bloqueantes - Implementar Semana 1 pós-deploy)

### 8. CloudWatch Alarms - Custo inesperado

- [ ] **Alarmes criados para monitorar custos**
  - **Arquivo:** `modules/tempo/cloudwatch-alarms.tf`
  - **Alarmes esperados:**
    1. `tempo-s3-storage-high` (S3 storage > 5 GB)
    2. `tempo-s3-requests-high` (S3 API requests > 500K/mês)
  - **Comando criação:**
    ```bash
    aws cloudwatch put-metric-alarm \
      --alarm-name tempo-s3-storage-high \
      --alarm-description "Tempo S3 storage exceeded 5GB" \
      --metric-name BucketSizeBytes \
      --namespace AWS/S3 \
      --statistic Average \
      --period 86400 \
      --threshold 5368709120 \
      --comparison-operator GreaterThanThreshold \
      --dimensions Name=BucketName,Value=k8s-platform-tempo-891377105802 Name=StorageType,Value=StandardStorage
    ```

---

### 9. Grafana Dashboard FinOps - Custo estimado Tempo

- [ ] **Dashboard criado com métricas de custo**
  - **Painel 1:** Volume traces/dia (spans ingested)
  - **Painel 2:** S3 storage usado (GB)
  - **Painel 3:** Custo estimado (storage + requests)
  - **Formula:** `(s3_storage_gb * 0.023) + (s3_requests / 1000 * 0.005)`

---

### 10. ServiceMonitor Selector - Validar label release

- [ ] **Prometheus ServiceMonitor selector validado**
  - **Comando:**
    ```bash
    kubectl get prometheus -n monitoring kube-prometheus-stack-prometheus \
      -o jsonpath='{.spec.serviceMonitorSelector}' | jq
    # Esperado: {} (match all) OU {matchLabels: {release: "kube-prometheus-stack"}}
    ```
  - **Validação Tempo ServiceMonitor:**
    ```bash
    kubectl get servicemonitor -n monitoring tempo \
      -o jsonpath='{.metadata.labels.release}'
    # Esperado: "kube-prometheus-stack" (se selector configurado)
    ```

---

### 11. IRSA Session Duration - 1h → 12h

- [ ] **IAM Role session duration aumentado**
  - **Comando:**
    ```bash
    aws iam update-role \
      --role-name TempoS3Role-k8s-platform-prod \
      --max-session-duration 43200
    # 43200 seconds = 12 hours
    ```
  - **Reason:** Compaction jobs podem demorar > 1h
  - **Validação:**
    ```bash
    aws iam get-role --role-name TempoS3Role-k8s-platform-prod \
      --query 'Role.MaxSessionDuration'
    # Esperado: 43200
    ```

---

## 🚦 Aprovação Final

**Critérios para Proceder com Deploy:**

1. ✅ **7 validações bloqueantes** marcadas como completas
2. ✅ **Terraform plan** executado sem erros
3. ✅ **Terraform plan preview** revisado (nenhuma deletion inesperada de Prometheus/Loki)
4. ✅ **Stakeholder approval** documentada

**Assinaturas Requeridas:**

- [ ] **DevOps Lead:** ___________________________ Data: __________
- [ ] **FinOps Team:** ___________________________ Data: __________
- [ ] **Platform Team:** _________________________ Data: __________

---

## 📋 Comandos de Validação Consolidados

**Executar na sequência para validar checklist:**

```bash
cd /home/gilvangalindo/projects/Arquitetura/Kubernetes/platform-provisioning/aws/kubernetes/terraform/envs/marco2

# ===== PRÉ-REQUISITOS =====

# 1. Validar VPC Endpoint S3 existe
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=vpc-0b1396a59c417c1f0" \
            "Name=service-name,Values=com.amazonaws.us-east-1.s3" \
  --query 'VpcEndpoints[0].State'
# Esperado: "available"

# 2. Validar OIDC Provider EKS
aws eks describe-cluster --name k8s-platform-prod \
  --query 'cluster.identity.oidc.issuer' --output text
# Esperado: https://oidc.eks.us-east-1.amazonaws.com/id/...

# 3. Validar Prometheus Operator instalado
kubectl get crd servicemonitors.monitoring.coreos.com
# Esperado: NAME = servicemonitors.monitoring.coreos.com

# 4. Validar Grafana deployado
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana
# Esperado: STATUS = Running

# 5. Validar Loki operacional
kubectl get svc -n monitoring loki-gateway
# Esperado: TYPE = ClusterIP, PORT = 3100

# 6. Validar Calico CNI ativo
kubectl get pods -n kube-system -l k8s-app=calico-node
# Esperado: 7/7 Running (1 por node)

# ===== TERRAFORM =====

# 7. Validar módulo Tempo existe
ls -lh modules/tempo/
# Esperado: main.tf, variables.tf, outputs.tf, versions.tf

# 8. Terraform validate
terraform validate
# Esperado: "Success! The configuration is valid."

# 9. Terraform plan (target Tempo)
terraform plan -target=module.tempo -out=fase8-tempo.tfplan

# 10. Review plan (MANUAL - verificar):
# ✅ S3 bucket será CRIADO (não recreated)
# ✅ IAM Role com trust policy OIDC correto
# ✅ Helm release chart = "tempo-distributed"
# ✅ Network Policies (4 novas)
# ✅ PVC size = 10Gi (ingester, compactor)
# ✅ NO "destroy" de Prometheus/Loki/Grafana
terraform show fase8-tempo.tfplan | less

# 11. Verificar chart version
helm search repo grafana/tempo-distributed
# Esperado: VERSION >= 1.10.0

# 12. Verificar sampling config (se módulo OTel Collector criado)
grep -A20 "tail_sampling" modules/opentelemetry-collector/values.yaml
# Esperado: sampling_percentage: 10

# ===== STATE BACKUP =====

# 13. Backup state atual
aws s3 cp s3://k8s-platform-terraform-state-891377105802/marco2/terraform.tfstate \
  ./backup-state-pre-fase8-$(date +%Y%m%d-%H%M%S).tfstate

# 14. Habilitar versioning S3 (se não habilitado)
aws s3api put-bucket-versioning \
  --bucket k8s-platform-terraform-state-891377105802 \
  --versioning-configuration Status=Enabled
```

---

## 🔄 Rollback Plan

**Se alguma validação bloqueante falhar:**

1. **NÃO executar `terraform apply`**
2. Corrigir a ressalva pendente
3. Re-executar validação completa
4. Documentar correção no diário de bordo

**Em caso de deploy com falha (pós-apply):**

```bash
# Rollback Terraform (target específico)
terraform workspace select marco2
terraform destroy -target=module.tempo

# Restaurar state backup (se necessário)
aws s3 cp ./backup-state-pre-fase8-YYYYMMDD-HHMMSS.tfstate \
  s3://k8s-platform-terraform-state-891377105802/marco2/terraform.tfstate

# Validar rollback
kubectl get pods -n monitoring | grep tempo
# Esperado: (vazio - pods Tempo removidos)
```

---

## 💰 Custo Final Aprovado

| Componente | Custo/Mês | Observação |
|------------|-----------|------------|
| S3 Storage (0.10 GB) | $0.00 | Abaixo de mínimo faturável |
| S3 API Requests | $0.07 | Tail sampling 10% |
| EBS Ingester (10GB) | $0.80 | Reduzido de 20GB |
| EBS Compactor (10GB) | $0.80 | Reduzido de 20GB |
| CloudWatch Logs | $0.80 | Log level WARN |
| **TOTAL STAGING Otimizado** | **$2.47/mês** | ✅ Aprovado FinOps |

**Custo PROD Estimado (10× tráfego):** $4.03/mês (com sampling 10%)

**Budget Impact Marco 2:**
- Marco 2 Atual: $666.00/mês
- **Marco 2 + Tempo:** **$668.47/mês** (+0.4%)

---

## 📊 Próximos Passos (Após Aprovação)

**IMEDIATO (Hoje 2026-01-30):**
1. ✅ Criar módulo Terraform `modules/tempo/`
2. ✅ Implementar OpenTelemetry Collector com tail sampling
3. ✅ Configurar Network Policies
4. ✅ Executar `terraform plan -target=module.tempo`

**DEPLOY (Fase 1):**
5. ✅ Executar `terraform apply -target=module.tempo` (15 minutos)
6. ✅ Validar pods Tempo Running (5 minutos)
7. ✅ Testar trace de teste via OTel Collector (5 minutos)

**INTEGRAÇÃO GRAFANA (Fase 2):**
8. ✅ Adicionar datasource Tempo no kube-prometheus-stack (10 minutos)
9. ✅ Executar `terraform apply` (5 minutos)
10. ✅ Validar datasource Grafana Explore (5 minutos)

**VALIDAÇÃO (Semana 1 pós-deploy):**
11. ✅ Monitorar logs CloudWatch (erros, warnings)
12. ✅ Verificar S3 storage usage (< 5 GB esperado)
13. ✅ Confirmar economia FinOps (Cost Explorer)
14. ✅ Criar CloudWatch Alarms (Recomendação #8)
15. ✅ Criar Grafana Dashboard FinOps (Recomendação #9)

---

**Data Execução PRE-HOOK:** __________
**Responsável Validação:** ___________________________
**Status Final:** [ ] ✅ APROVADO | [ ] ❌ BLOQUEADO

**Próximo Passo:** Implementar módulo Terraform `tempo/` (somente se aprovado)

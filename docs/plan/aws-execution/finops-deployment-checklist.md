# PRE-HOOK: Validação FinOps Automation (Antes do Deploy)

**Data:** 2026-01-30
**Projeto:** Automação FinOps STAGING (EventBridge + Lambda)
**Status:** ✅ **OBRIGATÓRIO** - Executar ANTES de `terraform apply`

---

## 🎯 Objetivo

Validar que todas as **ressalvas obrigatórias** identificadas pelos agentes especialistas foram implementadas antes do deploy.

**Consenso Técnico:** 4 agentes (AWS, Terraform, FinOps, Security) aprovaram com **11 ressalvas obrigatórias**.

---

## ✅ Checklist PRÉ-DEPLOY (Bloqueantes)

### 🌩️ AWS Specialist (3 validações)

- [ ] **RDS 7-Day Auto-Start Check**
  - Lambda valida `last_stop_time` no DynamoDB
  - Re-stop automático se RDS > 7 dias stopped
  - **Arquivo:** `lambda/health_checks.py` linha 45

- [ ] **ASG Scale-In Protection**
  - Pods non-critical com `terminationGracePeriodSeconds: 30`
  - PodDisruptionBudgets validados
  - **Comando:** `kubectl get pdb -n staging`

- [ ] **CloudWatch Alarms**
  - Alarme `finops-staging-startup-duration-high` criado
  - Threshold: 10 min
  - **Arquivo:** `terraform/modules/finops-automation/cloudwatch-alarms.tf`

---

### 🌱 Terraform Specialist (3 validações)

- [ ] **Lambda Deployment Package**
  - `archive_file` data source configurado
  - ZIP gerado automaticamente
  - **Arquivo:** `terraform/modules/finops-automation/lambda.tf`
  ```hcl
  data "archive_file" "lambda" {
    type        = "zip"
    source_dir  = "${path.module}/lambda"
    output_path = "${path.module}/lambda.zip"
  }
  ```

- [ ] **DynamoDB Destroy Protection**
  - `prevent_destroy = true` adicionado
  - **Arquivo:** `terraform/modules/finops-automation/dynamodb.tf`
  ```hcl
  lifecycle {
    prevent_destroy = true
  }
  ```

- [ ] **Terraform Workspaces**
  - Workspaces `staging` e `production` criados
  - **Comando:** `terraform workspace list`
  - Workspace ativo: `staging`

---

### 💰 FinOps (2 validações)

- [ ] **Hidden Costs Documentados**
  - Custos NAT Gateway + Data Transfer documentados em costs.md
  - Custo operacional: $2.43/mês (vs $2.00 estimado)
  - **Arquivo:** `docs/context/costs.md` seção "Custos Operacionais Detalhados"

- [ ] **Dashboard Cost Tracking**
  - Cost Explorer dashboard "FinOps Savings Real vs Projected" criado
  - Métrica: economia mensal real vs R$ 360 target
  - **AWS Console:** Cost Explorer → Dashboards

---

### 🔐 Security (3 validações)

- [ ] **DynamoDB Encryption at Rest**
  - KMS key criada
  - `server_side_encryption` habilitado
  - **Arquivo:** `terraform/modules/finops-automation/dynamodb.tf`
  ```hcl
  server_side_encryption {
    enabled     = true
    kms_key_id  = aws_kms_key.dynamodb_finops.id
  }
  ```
  - **Custo adicional:** +$1/mês (já incorporado em ROI ajustado)

- [ ] **Lambda VPC Validation**
  - Lambda SEM VPC (default) OU
  - Lambda em VPC com NAT Gateway validado
  - **Comando:** `terraform state show aws_lambda_function.finops_scheduler_staging | grep vpc_config`
  - **Resultado esperado:** Vazio (sem VPC) ou subnet com rota internet

- [ ] **Security Tags Aplicadas**
  - Todos os recursos com tags obrigatórias:
    - `Project`, `Environment`, `SecurityReview`, `Compliance`
    - `DataClassification`, `CriticalityTier`, `Owner`, `CostCenter`
  - **Arquivo:** `terraform/modules/finops-automation/variables.tf` (locals.security_tags)

---

## 💡 Recomendações (Não-Bloqueantes)

**Implementar se houver tempo disponível:**

- [ ] Cost Anomaly Detection (AWS native)
- [ ] Terraform Output Exports (ARNs Lambda/EventBridge)
- [ ] IAM Policy Versioning (`-v1` suffix)
- [ ] VPC Endpoint para S3 (best practice)

---

## 🚦 Aprovação Final

**Critérios para Proceder com Deploy:**

1. ✅ **Todas as 11 validações obrigatórias** marcadas como completas
2. ✅ **Terraform plan** executado sem erros
3. ✅ **Terraform plan preview** revisado (nenhuma deletion inesperada)
4. ✅ **Stakeholder approval** documentada

**Assinaturas Requeridas:**

- [ ] **DevOps Lead:** ___________________________ Data: __________
- [ ] **FinOps Team:** ___________________________ Data: __________
- [ ] **Security Team:** _________________________ Data: __________
- [ ] **Tech Lead:** ____________________________ Data: __________

---

## 📋 Comandos de Validação

**Executar na sequência para validar checklist:**

```bash
# 1. Verificar workspace
terraform workspace list
# Esperado: * staging

# 2. Validar Terraform
terraform validate
terraform plan -out=tfplan

# 3. Preview plan (verificar deletions)
terraform show -json tfplan | jq '.resource_changes[] | select(.change.actions[] | contains("delete"))'
# Esperado: Vazio ou apenas recursos esperados

# 4. Verificar Lambda ZIP
ls -lh terraform/modules/finops-automation/lambda.zip
# Esperado: Arquivo existe, tamanho > 1KB

# 5. Verificar DynamoDB encryption
terraform state show aws_dynamodb_table.finops_state | grep encryption
# Esperado: enabled = true

# 6. Verificar Lambda VPC
terraform state show aws_lambda_function.finops_scheduler_staging | grep vpc_config
# Esperado: Vazio (sem VPC) ou subnet_ids presente

# 7. Verificar tags
terraform state show aws_lambda_function.finops_scheduler_staging | grep -A 10 tags
# Esperado: SecurityReview = "2026-01-30", Compliance = "LGPD-OK"

# 8. Validar CloudWatch Alarm
aws cloudwatch describe-alarms --alarm-names finops-staging-startup-duration-high
# Esperado: AlarmName presente, Threshold = 600 (10 min)

# 9. Verificar pods terminationGracePeriod
kubectl get pods -n staging -o jsonpath='{.items[*].spec.terminationGracePeriodSeconds}' | tr ' ' '\n' | sort | uniq
# Esperado: 30 (ou valores razoáveis < 60s)

# 10. Validar Cost Explorer dashboard
aws ce get-cost-and-usage --time-period Start=2026-01-01,End=2026-01-31 --granularity MONTHLY --metrics BlendedCost
# Esperado: Comando executado sem erro (dashboard existe)
```

---

## 🔄 Rollback Plan

**Se alguma validação falhar:**

1. **NÃO executar `terraform apply`**
2. Corrigir a ressalva pendente
3. Re-executar validação completa
4. Documentar correção no diário de bordo

**Em caso de deploy com falha:**

```bash
# Rollback Terraform
terraform workspace select staging
terraform destroy -target=aws_lambda_function.finops_scheduler_staging
terraform destroy -target=aws_cloudwatch_event_rule.finops_startup_staging
terraform destroy -target=aws_cloudwatch_event_rule.finops_shutdown_staging

# Manter DynamoDB (prevent_destroy ativo)
# Manter KMS key (custo negligível, reutilizável)
```

---

**Data Execução PRE-HOOK:** __________
**Responsável Validação:** ___________________________
**Status Final:** [ ] ✅ APROVADO | [ ] ❌ BLOQUEADO

**Próximo Passo:** `terraform apply` (somente se aprovado)

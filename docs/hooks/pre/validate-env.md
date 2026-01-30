# 🔧 PRE-HOOK: Validate Environment

**Objetivo:** Garantir que ambiente de execução está pronto antes de terraform apply

**Executado por:** Terraform Specialist + AWS Specialist

---

## ✅ Checklist de Validação

### 1. Terraform Version

- [ ] **Terraform versão compatível**
  - Versão >= 1.6.0 (conforme terraform.required_version)
  - Provider AWS ~> 5.0 disponível
  - Plugins necessários instalados

**Comando:**
```bash
terraform version
terraform providers
```

---

### 2. AWS Credentials

- [ ] **Credenciais AWS válidas**
  - AWS CLI configurado
  - Perfil correto (staging, production, sandbox)
  - Permissões IAM suficientes (terraform plan test)
  - MFA habilitado (quando aplicável)

**Comando:**
```bash
aws sts get-caller-identity
aws iam get-user
```

**Output esperado:**
```json
{
  "UserId": "AIDAXXXXXXXXXX",
  "Account": "123456789012",
  "Arn": "arn:aws:iam::123456789012:user/terraform-deploy"
}
```

---

### 3. Backend State

- [ ] **S3 backend configurado**
  - Bucket S3 existe e tem encryption
  - DynamoDB table para locking existe
  - Workspace correto (staging vs production)
  - State não corrompido (terraform state list)

**Comando:**
```bash
terraform init
terraform workspace list
terraform state list
```

---

### 4. Network Connectivity

- [ ] **Conectividade com AWS**
  - Acesso aos endpoints AWS (S3, EC2, RDS, EKS)
  - VPN ou bastion configurado (se aplicável)
  - DNS resolution funcionando

**Comando:**
```bash
aws s3 ls
aws ec2 describe-vpcs --region us-east-1 --max-items 1
```

---

### 5. Dependencies Check

- [ ] **Recursos dependentes existentes**
  - VPC e subnets criadas
  - Security Groups base configurados
  - KMS keys disponíveis (se encryption habilitado)
  - IAM roles para IRSA criados (se EKS)

**Comando:**
```bash
terraform show | grep "resource \"aws_vpc\""
aws kms list-keys --region us-east-1
```

---

### 6. Terraform Validate

- [ ] **Código Terraform válido**
  - terraform validate sem erros
  - terraform fmt -check OK
  - No provider version conflicts
  - Variables definidas (sem missing vars)

**Comando:**
```bash
terraform validate
terraform fmt -check
terraform plan -input=false
```

---

### 7. Cost Estimation (opcional)

- [ ] **Estimativa de custo realizada**
  - Infracost executado (se disponível)
  - Comparação com budget aprovado
  - Alertas de custo excessivo

**Comando (se Infracost instalado):**
```bash
infracost breakdown --path .
```

---

## 🚫 Critérios de Bloqueio

**Bloquear execução Terraform se:**

1. **Terraform version incompatível** (< 1.6.0 ou provider AWS < 5.0)
2. **Credenciais AWS inválidas** ou permissões insuficientes
3. **State backend inacessível** (S3 bucket não existe, DynamoDB lock falha)
4. **Workspace incorreto** (staging code rodando em production workspace)
5. **terraform validate FAIL** (syntax errors, missing variables)
6. **Dependencies faltando** (VPC não criada, KMS key ausente)

---

## 🔍 Validação de Segurança Adicional

### Security Specialist Review

- [ ] **Secrets não hardcoded** (grep -r "aws_access_key" .)
- [ ] **Encryption habilitado** para recursos sensíveis (RDS, DynamoDB, S3)
- [ ] **Security Groups não expostos** (0.0.0.0/0 apenas onde necessário)
- [ ] **IAM policies least privilege** (resource-specific ARNs)

**Comando:**
```bash
grep -r "aws_access_key_id" . --exclude-dir=.terraform
grep -r "password\s*=" . --exclude-dir=.terraform | grep -v "random_password"
```

---

## ✅ Aprovação

**Responsável:** Terraform Specialist + AWS Specialist
**Data:** _______
**Status:** [ ] APROVADO | [ ] BLOQUEADO

**Comentários:**
```
[Espaço para observações sobre problemas encontrados]
```

---

**Criado:** 2026-01-30
**Versão:** 1.0
**Próxima Revisão:** Antes de cada terraform apply

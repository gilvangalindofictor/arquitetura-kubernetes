# 🔐 Agente Security & Compliance

**Função:** Validar least privilege, compliance, superfícies de ataque
**Expertise:** IAM Policies, Encryption, Network Security, LGPD, ISO 27001, SOC2

---

## 🎯 Responsabilidades

1. **Least Privilege**
   - IAM policies com permissões mínimas
   - Resource-specific ARNs (não usar `*`)
   - Condition clauses para contexto
   - Princípio "deny by default"

2. **Compliance**
   - ISO 27001 (quando aplicável)
   - SOC2 Type II (quando aplicável)
   - LGPD (verificar dados pessoais)
   - Audit trail (CloudTrail, CloudWatch Logs)

3. **Análise de Superfícies de Ataque**
   - Security Groups 0.0.0.0/0 expostos
   - S3 buckets públicos
   - Secrets em plaintext
   - IAM users vs Roles

4. **Encryption**
   - Encryption at rest (KMS)
   - Encryption in transit (TLS 1.2+)
   - Secrets Manager vs plaintext
   - Key rotation policies

5. **Revisão de Mudanças Críticas**
   - IAM policy changes
   - Security Group modifications
   - Network topology changes
   - Encryption configuration

---

## 📋 Checklist PRE-HOOK Security

- [ ] IAM policies least privilege (resource-specific)
- [ ] Nenhum Access Key hardcoded
- [ ] KMS encryption habilitado para dados sensíveis
- [ ] Security Groups sem 0.0.0.0/0 desnecessário
- [ ] S3 buckets não públicos (sem AllUsers)
- [ ] Secrets Manager para credentials
- [ ] CloudTrail habilitado (audit trail)
- [ ] Tags de compliance aplicadas
- [ ] Network ACLs validadas
- [ ] VPC Flow Logs habilitados (se aplicável)

---

## 📋 Checklist POST-HOOK Security

- [ ] IAM policies ativas sem wildcard `*` desnecessário
- [ ] Encryption validada (KMS keys ativas)
- [ ] Security Groups auditados (sem exposição crítica)
- [ ] CloudTrail logs sendo coletados
- [ ] Access Analyzer findings = 0 (aws accessanalyzer)
- [ ] GuardDuty findings = 0 (se habilitado)
- [ ] Secrets rotacionados (se aplicável)
- [ ] Compliance tags verificadas

---

## 🔍 Análise FinOps STAGING (2026-01-30)

### Aprovações

✅ **IAM Least Privilege** - Resource-specific ARNs, staging-only permissions
✅ **Secrets Management** - BrasilAPI público (sem credentials), IAM roles (não API keys)
✅ **Audit Trail** - CloudWatch Logs 30d retention, compliance LGPD OK (não processa dados pessoais)

### Ressalvas

⚠️ **DynamoDB Encryption at Rest** - Circuit breaker state em plaintext
**Solução:** KMS encryption habilitado (+$1/mês)
```hcl
server_side_encryption {
  enabled    = true
  kms_key_id = aws_kms_key.dynamodb_finops.id
}
```

⚠️ **Lambda VPC Configuration** - Lambda precisa internet para BrasilAPI
**Solução:** Lambda SEM VPC (default, custo $0) vs VPC+NAT ($32/mês)
**Decisão:** Lambda sem VPC = configuração correta

⚠️ **IAM Policy Versioning** - Mudanças não versionadas (dificulta rollback)
**Solução:** Sufixo `-v1` no policy name (não-bloqueante)

### Security Tags Obrigatórias

```hcl
tags = {
  Project            = "FinOps-Automation"
  Environment        = "staging"
  SecurityReview     = "2026-01-30"
  Compliance         = "LGPD-OK"
  DataClassification = "Internal"
  CriticalityTier    = "Medium"
  Owner              = "DevOps-Team"
}
```

### Decisão Final

✅ **APROVADO COM 2 RESSALVAS OBRIGATÓRIAS** (DynamoDB encryption + Lambda VPC validation)

---

**Última Análise:** 2026-01-30
**Próxima Revisão:** Pós-deploy (validar encryption ativa, security tags 100%)
